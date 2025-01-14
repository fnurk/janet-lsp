(use judge)

(defn- no-side-effects # This seems to always only return true no matter what?
  `Check if form may have side effects. If returns true, then the src
  must not have side effects, such as calling a C function.`
  [src]
  (cond
    (tuple? src) (if (= (tuple/type src) :brackets)
                   (all no-side-effects src))
    (array? src) (all no-side-effects src)
    (dictionary? src) (and (all no-side-effects (keys src))
                           (all no-side-effects (values src)))
    true))

(defn- is-safe-def [x]
  (no-side-effects (last x)))

(def- safe-forms {'defn true 'varfn true 'defn- true 'defmacro true 'defmacro- true
                  'def is-safe-def 'var is-safe-def 'def- is-safe-def 'var- is-safe-def
                  'defglobal is-safe-def 'varglobal is-safe-def})

(def- importers {'import true 'import* true 'dofile true 'require true})

(defn- use-2 [evaluator args]
  (each a args (import* (string a) :prefix "" :evaluator evaluator)))

(defn- flycheck-evaluator
  ``An evaluator function that is passed to `run-context` that lints (flychecks) code.
  This means code will parsed and compiled, macros executed, but the code will not be run.
  Used by `flycheck`.``
  [thunk source env where]
    
  (when (tuple? source)
    (let [head (source 0)
          safe-check (or (safe-forms head)
                         (when (and (symbol? head) (string/has-prefix? "define-" head))
                           is-safe-def))] 
      (cond
        # Sometimes safe form
        (function? safe-check) (if (safe-check source) (thunk))
        # Always safe form
        safe-check (thunk)
        # Use
        (= 'use head) (use-2 flycheck-evaluator (tuple/slice source 1))
        # Import-like form
        (importers head) (let [[l c] (tuple/sourcemap source) 
                               newtup (tuple/setmap (tuple ;source :evaluator flycheck-evaluator) l c)] 
                           ((compile newtup env where)))))))

(defn eval-buffer [str]
  (var state (string str))
  (defn chunks [buf _]
    (def ret state)
    (set state nil)
    (when ret
      (buffer/push-string buf str)
      (buffer/push-string buf "\n")))

  (var returnval :ok)

  (try
    (run-context {:chunks chunks
                  :on-compile-error (fn compile-error [msg errf where line col]
                                      (set returnval [:error {:message msg
                                                              :location [line col]}]))
                  :on-parse-error (fn parse-error [p x]
                                    (set returnval [:error {:message (parser/error p)
                                                            :location (parser/where p)}]))
                  :evaluator flycheck-evaluator
                  :fiber-flags :i
                  :source :eval-buffer})
    ([err]
     (set returnval [:error {:message err
                             :location [0 0]}])))

  returnval)

# tests

(deftest "test eval-buffer: (+ 2 2)"
  (test (eval-buffer "(+ 2 2)") :ok))

(deftest "test eval-buffer: (2)"
  (test (eval-buffer "(2)")
    [:error
     {:location [1 1]
      :message "2 expects 1 argument, got 0"}]))

(deftest "test eval-buffer: (+ 2 2"
  (test (eval-buffer "(+ 2 2")
    [:error
     {:location [2 0]
      :message "unexpected end of source, ( opened at line 1, column 1"}]))

# check for side effects
(deftest "test eval-buffer: (pp 42)"
  (test (eval-buffer "(pp 42)") :ok))

(deftest "test eval-buffer: ()"
  (test (eval-buffer "()")
    [:error
     {:location [0 0]
      :message "expected integer key for tuple in range [0, 0), got 0"}]))