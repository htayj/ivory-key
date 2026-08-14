;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Declarative event-stream decoder and CLI simulation contracts.

(in-package #:ivory-key.tests)

(defun simulation-source-decode (source)
  (ivory-key.simulate::decode-simulation-event-stream-forms
   (ivory-key.syntax:parse-string source :name "<simulation-source-test>")))

(defun simulation-source-error-code-from (thunk)
  (handler-case
      (progn (funcall thunk)
             (error "Expected a simulation event source error."))
    (ivory-key.simulate::simulation-event-source-error (condition)
      (ivory-key.simulate::simulation-event-source-error-code condition))))

(defun simulation-source-normalized-layout ()
  (let* ((case-axis (ivory-key.model::make-context-axis
                     "case" '("plain" "shifted")))
         (latch-axis (ivory-key.model::make-context-axis
                      "shift-latch" '("plain" "latch") :resolution :behavioral))
         (topology (ivory-key.model::make-topology
                    "source-test" (list (ivory-key.model::make-logical-position "q"))))
         (binding
           (ivory-key.model::make-binding
            "q"
            (ivory-key.model::make-axis-choice-behavior
             "case"
             (list (cons "plain" (ivory-key.model::make-text-output "q"))
                   (cons "shifted" (ivory-key.model::make-text-output "Q")))))))
    (ivory-key.model::normalize-layout
     (ivory-key.model::make-layout "source-test" topology
                                   (list case-axis latch-axis) nil
                                   :bindings (list binding)))))

(deftest simulation-source-decodes-canonical-context-and-drives-layout
  (let* ((stream
           (simulation-source-decode
            "(ivory-key 1)
(simulation
  (axis CASE SHIFTED)
  (latch SHIFT-LATCH LATCH)
  (until 10)
  (event 0 down Q)
  (event 10 up q))"))
         (events (ivory-key.simulate::simulation-event-stream-events stream))
         (result
           (ivory-key.simulate::simulate-normalized-layout-event-stream
            (simulation-source-normalized-layout) stream)))
    (is-equal '(("case" . "shifted"))
              (ivory-key.simulate::simulation-event-stream-axes stream))
    (is-equal '(("shift-latch" . "latch"))
              (ivory-key.simulate::simulation-event-stream-latches stream))
    (is-equal 10 (ivory-key.simulate::simulation-event-stream-until stream))
    (is-equal '(0 10) (mapcar #'ivory-key.simulate:timed-event-time events))
    (is-equal '(:down :up) (mapcar #'ivory-key.simulate:timed-event-kind events))
    (is-equal '("q" "q") (mapcar #'ivory-key.simulate:timed-event-position events))
    (is-equal '((:text "Q")) (ivory-key.simulate:simulation-result-outputs result))
    ;; The binding did not consult SHIFT-LATCH, so preserving it verifies that
    ;; source-declared latches remain subject to the machine's consumption rule.
    (is-equal '(("shift-latch" . "latch"))
              (ivory-key.simulate:simulation-result-latches result))))

(deftest simulation-source-refuses-closed-vocabulary-and-time-violations
  (flet ((code (source)
           (simulation-source-error-code-from
            (lambda () (simulation-source-decode source)))))
    (is-equal :unknown-event-stream-top-level
              (code "(ivory-key 1) (unrelated)") )
    (is-equal :duplicate-event-stream-context
              (code "(ivory-key 1) (simulation (axis mode a) (axis MODE b) (event 0 down q))"))
    (is-equal :malformed-event-stream-form
              (code "(ivory-key 1) (simulation (event 0 down))"))
    (is-equal :generated-deadline-event
              (code "(ivory-key 1) (simulation (event 0 deadline q))"))
    (is-equal :decreasing-event-time
              (code "(ivory-key 1) (simulation (event 4 down q) (event 3 up q))"))
    (is-equal :until-before-last-event
              (code "(ivory-key 1) (simulation (until 2) (event 3 down q))"))
    (is-equal :unknown-event-stream-form
              (code "(ivory-key 1) (simulation (mystery q) (event 0 down q))"))))

(deftest simulation-source-never-reads-evaluates-or-interns-fixture-forms
  (let ((name "event-source-must-not-intern-this")
        (package (find-package '#:ivory-key.simulate)))
    (is (null (find-symbol "EVENT-SOURCE-MUST-NOT-INTERN-THIS" package)))
    (simulation-source-decode
     "(ivory-key 1)
(simulation (event 0 down event-source-must-not-intern-this))")
    (is (null (find-symbol (string-upcase name) package)))
    ;; The lexer treats #. as invalid input, so the payload remains source text
    ;; and the error it contains can never be evaluated by a host reader.
    (let ((signalled nil))
      (handler-case
          (simulation-source-decode
           "(ivory-key 1)
(simulation (event 0 down event-source-must-not-intern-this)
            #.(error \"must never evaluate\"))")
        (ivory-key.conditions:ivory-key-syntax-error ()
          (setf signalled t)))
      (is signalled))
    (is (null (find-symbol (string-upcase name) package)))))

(deftest simulation-source-dispatches-supported-whole-layout-overlay
  (let* ((patch-axis (ivory-key.model::make-context-axis
                      "overlay" '("base" "active") :resolution :patch))
         (topology (ivory-key.model::make-topology
                    "overlay-test" (list (ivory-key.model::make-logical-position "q"))))
         (overlay (ivory-key.model::make-overlay-patch
                   "special" "overlay" "active"
                   (list (ivory-key.model::make-patch-binding
                          "q" (ivory-key.model::make-text-output "Q")))
                   :precedence 1))
         (layout
           (ivory-key.model::normalize-layout
            (ivory-key.model::make-layout
             "overlay-test" topology (list patch-axis) nil
             :bindings (list (ivory-key.model::make-binding
                              "q" (ivory-key.model::make-text-output "q")))
             :overlays (list overlay))))
         (stream (simulation-source-decode
                  "(ivory-key 1) (simulation (axis overlay active) (event 0 down q))"))
         (result
           (ivory-key.simulate::simulate-normalized-layout-event-stream layout stream)))
    (is-equal '((:text "Q"))
              (ivory-key.simulate:simulation-result-outputs result))
    (is (some (lambda (entry)
                (equal '(:overlay-selection "special" :position "q")
                       (ivory-key.simulate::simulation-trace-entry-details entry)))
              (ivory-key.simulate:simulation-result-trace result)))))

(deftest simulation-source-dump-refuses-host-object-printing
  (is-equal
   :unsupported-simulation-dump-value
   (simulation-source-error-code-from
    (lambda ()
      (ivory-key.simulate::simulation-result-dump-string
       (ivory-key.simulate:make-simulation-result
        :outputs (list (make-hash-table))))))))

(defun simulation-source-test-directory ()
  (let ((directory
          (merge-pathnames
           (format nil "ivory-key-simulation-source-~A/" (symbol-name (gensym "TEST-")))
           (uiop:temporary-directory))))
    (ensure-directories-exist (merge-pathnames "placeholder" directory))
    directory))

(defun simulation-source-test-write (directory name content)
  (let ((pathname (merge-pathnames name directory)))
    (with-open-file (stream pathname :direction :output :if-exists :error
                                     :if-does-not-exist :create
                                     :external-format :utf-8)
      (write-string content stream))
    pathname))

(defmacro with-simulation-source-test-directory ((directory) &body body)
  `(let ((,directory (simulation-source-test-directory)))
     (unwind-protect
          (progn ,@body)
       (when (probe-file ,directory)
         (delete-test-directory-tree ,directory)))))

(deftest simulation-cli-renders-deterministic-result-and-refuses-semantic-loss
  (with-simulation-source-test-directory (directory)
    (let* ((layout
             (simulation-source-test-write
              directory "layout.ivory"
              "(ivory-key 1)
(define-layout simulated
  (axis case (:states plain shifted) (:resolution product))
  (binding q
    (at (plain) (unicode \"q\"))
    (at (shifted) (unicode \"Q\"))))"))
           (events
             (simulation-source-test-write
              directory "events.ivory"
              "(ivory-key 1)
(simulation (axis case shifted) (event 0 down q) (event 10 up q))"))
           (unsafe-layout
             (simulation-source-test-write
              directory "unsafe-layout.ivory"
              "(ivory-key 1)
(define-layout unsafe
  (axis overlay (:states base active) (:resolution patch))
  (binding f (latch-axis-state overlay active))
  (binding q (unicode \"q\"))
  (overlay special
    (axis overlay) (state active) (precedence 1)
    (binding q (unicode \"Q\"))))"))
           (output (make-string-output-stream))
           (errors (make-string-output-stream)))
      (let ((*standard-output* output)
            (*error-output* errors))
        (is-equal 0
                  (ivory-key.cli:main
                   (list "simulate" "--layout" (namestring layout)
                         "--events" (namestring events))))
        (is-equal 1
                  (ivory-key.cli:main
                   (list "simulate" "--layout" (namestring unsafe-layout)
                         "--events" (namestring events)))))
      (let ((rendered (get-output-stream-string output))
            (reported (get-output-stream-string errors)))
        (is (search (format nil "simulation-result~%outputs~%  (:text \"Q\")~%trace~%")
                    rendered))
        (is (search "0 event event=(:down \"q\" nil)" rendered))
        (is (search "UNSUPPORTED-OVERLAY-LATCH-TRANSITION" reported))))))

(deftest simulation-cli-loads-project-composition-without-backend-lowering
  "Project simulation selects one resolved layout; it does not compile its profile."
  (with-simulation-source-test-directory (directory)
    (let* ((project
             (simulation-source-test-write
              directory "project.ivory"
              "(ivory-key 1)
(import \"topology.ivory\")
(import \"layout.ivory\")
(import \"device.ivory\")
(import \"realization.ivory\")
(import \"composition.ivory\")"))
           (layout
             (simulation-source-test-write
              directory "layout.ivory"
              "(ivory-key 1)
(define-layout project-sim (uses-topology keyboard)
  (binding q (unicode \"q\")))"))
           (events
             (simulation-source-test-write
              directory "events.ivory"
              "(ivory-key 1)
(simulation (event 0 down q) (event 10 up q))"))
           (output (make-string-output-stream))
           (errors (make-string-output-stream)))
      (simulation-source-test-write
       directory "topology.ivory"
       "(ivory-key 1)
(define-topology keyboard
  (position q (:row 1) (:column 1) (:hand left) (:finger pinky)))")
      (simulation-source-test-write
       directory "device.ivory"
       "(ivory-key 1)
(define-device project-board (uses-topology keyboard)
  (place q (:xkb AD01) (:kanata q)))")
      ;; UNSUPPORTED is valid project policy but intentionally refused by the
      ;; compiler's exact bootstrap bridge.  A successful simulation therefore
      ;; proves project mode stays in the resolved layout path.
      (simulation-source-test-write
       directory "realization.ivory"
       "(ivory-key 1)
(define-realization simulation-context
  (pipeline future-backend)
  (allow-grades unsupported)
  (forbid-shell-actions yes))")
      (simulation-source-test-write
       directory "composition.ivory"
       "(ivory-key 1)
(realize project-simulation
  (:layout project-sim)
  (:device project-board)
  (:profile simulation-context))")
      (let ((*standard-output* output)
            (*error-output* errors))
        (is-equal 0
                  (ivory-key.cli:main
                   (list "simulate" "--project" (namestring project)
                         "--composition" "project-simulation"
                         "--events" (namestring events))))
        (is-equal 1
                  (ivory-key.cli:main
                   (list "simulate" "--project" (namestring project)
                         "--composition" "missing-composition"
                         "--events" (namestring events))))
        (is-equal 1
                  (ivory-key.cli:main
                   (list "simulate" "--project" (namestring project)
                         "--composition" "project-simulation"
                         "--layout" (namestring layout)
                         "--events" (namestring events))))
        (is-equal 1
                  (ivory-key.cli:main
                   (list "simulate" "--project" (namestring project)
                         "--events" (namestring events))))
        (is-equal 1
                  (ivory-key.cli:main
                   (list "simulate" "--project" (namestring project)
                         "--project" (namestring project)
                         "--composition" "project-simulation"
                         "--events" (namestring events))))
        (is-equal 1
                  (ivory-key.cli:main
                   (list "simulate" "--project" (namestring project)
                         "--composition" "project-simulation"))))
      (let ((rendered (get-output-stream-string output))
            (reported (get-output-stream-string errors)))
        (is (search (format nil "simulation-result~%outputs~%  (:text \"q\")~%trace~%")
                    rendered))
        (is (search "Project has no COMPOSITION named missing-composition." reported))
        (is (search "simulate cannot mix --project/--composition with explicit source files."
                    reported))
        (is (search "simulate requires --project and --composition together." reported))
        (is (search "Option --project was supplied more than once." reported))
        (is (search "Missing required option --events." reported))))))
