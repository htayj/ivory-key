;;;; SPDX-License-Identifier: GPL-3.0-or-later

(in-package #:ivory-key.cli)

(defun print-diagnostic (diagnostic &optional (stream *error-output*))
  (format stream "~A~@[ at ~A~]: ~A~%"
          (ivory-key.conditions:diagnostic-code diagnostic)
          (let ((span (ivory-key.conditions:diagnostic-span diagnostic)))
            (and span (ivory-key.source:source-span-location-string span)))
          (ivory-key.conditions:diagnostic-message diagnostic))
  (when (ivory-key.conditions:diagnostic-hint diagnostic)
    (format stream "  hint: ~A~%"
            (ivory-key.conditions:diagnostic-hint diagnostic))))

(defun check-files (pathnames)
  (let ((failed nil))
    (dolist (pathname pathnames)
      (let ((result (ivory-key.syntax:parse-file pathname)))
        (dolist (diagnostic
                 (ivory-key.syntax:syntax-parse-result-diagnostics result))
          (print-diagnostic diagnostic)
          (when (eq :error
                    (ivory-key.conditions:diagnostic-severity diagnostic))
            (setf failed t)))))
    (if failed 1 0)))

(defun format-files (arguments)
  (let* ((check-only (and arguments (string= (first arguments) "--check")))
         (pathnames (if check-only (rest arguments) arguments))
         (different nil)
         (invalid nil))
    (dolist (pathname pathnames)
      (let* ((result (ivory-key.syntax:parse-file pathname))
             (diagnostics
               (ivory-key.syntax:syntax-parse-result-diagnostics result)))
        (if diagnostics
            (progn
              (setf invalid t)
              (mapc #'print-diagnostic diagnostics))
            (let* ((formatted (ivory-key.syntax:format-parse-result result))
                   (original (uiop:read-file-string pathname)))
              (unless (string= original formatted)
                (setf different t)
                (if check-only
                    (format *error-output* "Would reformat ~A~%" pathname)
                    (with-open-file (stream pathname
                                            :direction :output
                                            :if-exists :supersede
                                            :if-does-not-exist :create)
                      (write-string formatted stream))))))))
    (if (or invalid (and check-only different)) 1 0)))

(defun inventory-command (arguments)
  (unless (= (length arguments) 1)
    (error "inventory requires exactly one Manna Cadet root directory"))
  (ivory-key.migration:write-inventory-report
   (ivory-key.migration:inventory-manna-cadet (first arguments))
   *standard-output*)
  0)

(defun command-options (arguments allowed)
  "Parse value-taking long options without treating paths as shell syntax.

The command entry point receives an argument vector from UIOP; it never builds
or evaluates a shell command.  Repeated options are rejected so a later value
cannot silently override an earlier safety-relevant path.
"
  (let ((options nil))
    (loop while arguments
          for option = (pop arguments) do
            (unless (member option allowed :test #'string=)
              (error "Unknown option ~A." option))
            (unless arguments
              (error "Option ~A requires a value." option))
            (when (assoc option options :test #'string=)
              (error "Option ~A was supplied more than once." option))
            (let ((value (pop arguments)))
              (when (and (>= (length value) 2)
                         (string= value "--" :end1 2 :end2 2))
                (error "Option ~A requires a path or stage, not another option." option))
              (push (cons option value) options)))
    (nreverse options)))

(defun required-option (options name)
  (or (cdr (assoc name options :test #'string=))
      (error "Missing required option ~A." name)))

(defun optional-option (options name)
  (cdr (assoc name options :test #'string=)))

(defun project-option-values (options command)
  "Return PROJECT and COMPOSITION together, or reject a partial project mode.

The project loader owns import traversal and source-root confinement.  A
command must therefore choose either its historic independent source files or
one root project composition; mixing the two would make the selected meaning
and physical mappings ambiguous.
"
  (let ((project (optional-option options "--project"))
        (composition (optional-option options "--composition")))
    (cond ((and project composition) (values project composition))
          ((or project composition)
           (error "~A requires --project and --composition together." command))
          (t (values nil nil)))))

(defun reject-mixed-project-options (project direct-options command)
  (when (and project (some #'identity direct-options))
    (error "~A cannot mix --project/--composition with explicit source files."
           command)))

(defun typed-layout-dump-string (unit)
  "Show the typed, pre-normalization model without depending on object printing."
  (let ((layout (compiler-unit-layout unit)))
    (with-output-to-string (stream)
      (format stream "typed-layout ~A~%"
              (ivory-key.model:identifier-name (ivory-key.model:layout-name layout)))
      (format stream "topology ~A~%"
              (ivory-key.model:identifier-name
               (ivory-key.model:topology-name (ivory-key.model:layout-topology layout))))
      (format stream "axes: ~{~A~^ ~}~%"
              (mapcar (lambda (axis)
                        (ivory-key.model:identifier-name (ivory-key.model:axis-name axis)))
                      (ivory-key.model:layout-axes layout)))
      (format stream "bindings: ~{~A~^ ~}~%"
              (mapcar (lambda (binding)
                        (ivory-key.model:identifier-name
                         (ivory-key.model:binding-position binding)))
                      (ivory-key.model:layout-bindings layout)))
      (format stream "interactions: ~{~A~^ ~}~%"
              (mapcar (lambda (interaction)
                        (ivory-key.model:identifier-name
                         (ivory-key.model:interaction-name interaction)))
                      (ivory-key.model:layout-interactions layout))))))

(defun dump-ir-command (arguments)
  (let* ((options (command-options arguments
                                   '("--stage" "--layout" "--topology"
                                     "--project" "--composition")))
         (stage (required-option options "--stage"))
         (layout-path (optional-option options "--layout"))
         (topology-path (optional-option options "--topology")))
    (multiple-value-bind (project-path composition-name)
        (project-option-values options "dump-ir")
      (reject-mixed-project-options project-path (list layout-path topology-path)
                                    "dump-ir")
      (cond
        (project-path
         (when (string= stage "parsed")
           ;; The project loader intentionally does not expose raw parser
           ;; values as a public registry.  Do not bypass it by reparsing an
           ;; arbitrary imported file merely to satisfy this inspection mode.
           (error "dump-ir --project supports typed or normalized stages, not parsed."))
         (unless (or (string= stage "typed") (string= stage "normalized"))
           (error "Unknown IR stage ~A; expected typed or normalized." stage))
         (multiple-value-bind (unit)
             (load-project-composition-for-compilation project-path composition-name)
           (write-string (if (string= stage "typed")
                             (typed-layout-dump-string unit)
                             (normalized-layout-dump-string
                              (compiler-unit-normalized unit)))
                         *standard-output*)))
        ((string= stage "parsed")
         (let ((parsed (%parse-required-file
                        (required-option options "--layout") "layout")))
           (dolist (form (%parsed-values parsed))
             (write form :stream *standard-output* :escape t)
             (terpri))))
        ((or (string= stage "typed") (string= stage "normalized"))
         (let ((unit (load-layout-for-compilation
                      (required-option options "--layout")
                      :topology-path topology-path)))
           (write-string (if (string= stage "typed")
                             (typed-layout-dump-string unit)
                             (normalized-layout-dump-string
                              (compiler-unit-normalized unit)))
                         *standard-output*)))
        (t (error "Unknown IR stage ~A; expected parsed, typed, or normalized." stage)))
      0)))

(defun levels-command (arguments)
  (let* ((options (command-options arguments
                                   '("--layout" "--topology"
                                     "--project" "--composition")))
         (layout-path (optional-option options "--layout"))
         (topology-path (optional-option options "--topology")))
    (multiple-value-bind (project-path composition-name)
        (project-option-values options "levels")
      (reject-mixed-project-options project-path (list layout-path topology-path)
                                    "levels")
      (let ((unit (if project-path
                      (load-project-composition-for-compilation
                       project-path composition-name)
                      (load-layout-for-compilation
                       (required-option options "--layout")
                       :topology-path topology-path))))
        (write-string (level-report-string (compiler-unit-normalized unit))
                      *standard-output*)
        0))))

(defun explain-command (arguments)
  (let* ((options (command-options arguments
                                   '("--layout" "--topology" "--device" "--realization"
                                     "--project" "--composition"))))
    (multiple-value-bind (project-path composition-name)
        (project-option-values options "explain")
      (reject-mixed-project-options
       project-path
       (list (optional-option options "--layout")
             (optional-option options "--topology")
             (optional-option options "--device")
             (optional-option options "--realization"))
       "explain")
      (let ((result (if project-path
                        (explain-project-source project-path composition-name
                                                :stream *standard-output*)
                        (explain-layout-source
                         (required-option options "--layout")
                         :topology-path (optional-option options "--topology")
                         :device-path (required-option options "--device")
                         :realization-path (required-option options "--realization")
                         :stream *standard-output*))))
        ;; EXPLAIN succeeds only when the planner found an all-exact request.  A
        ;; report of unsupported features is useful evidence, but is not a compile
        ;; success and has a non-zero status for scripts.
        (if result 0 1)))))

(defun compile-command (arguments)
  (let* ((options (command-options arguments
                                   '("--layout" "--topology" "--device" "--realization" "--output"
                                     "--project" "--composition")))
         (output (required-option options "--output")))
    (multiple-value-bind (project-path composition-name)
        (project-option-values options "compile")
      (reject-mixed-project-options
       project-path
       (list (optional-option options "--layout")
             (optional-option options "--topology")
             (optional-option options "--device")
             (optional-option options "--realization"))
       "compile")
      (let ((result (if project-path
                        (compile-project-source project-path composition-name
                                                :output-directory output)
                        (compile-layout-source
                         (required-option options "--layout")
                         :topology-path (optional-option options "--topology")
                         :device-path (required-option options "--device")
                         :realization-path (required-option options "--realization")
                         :output-directory output))))
        (format *standard-output* "Emitted new build directory ~A.~%" output)
        (format *standard-output* "Tool validation was not run; use validate-build for that evidence.~%")
        (dolist (artifact (ivory-key.backend:pipeline-result-artifacts result))
          (format *standard-output* "  ~A~%"
                  (ivory-key.backend:pipeline-artifact-relative-path artifact)))
        0))))

(defun validate-build-command (arguments)
  (unless (= (length arguments) 1)
    (error "validate-build requires exactly one build directory"))
  (let ((results (validate-build-directory (first arguments)))
        (failed nil)
        (unavailable nil))
    (dolist (result results)
      (let ((kind (getf result :kind))
            (status (getf result :status)))
        (format *standard-output* "~(~A~): ~(~A~)~%" kind status)
        (case status
          (:passed nil)
          (:unavailable
           (setf unavailable t)
           (format *standard-output* "  validator unavailable: ~A~%"
                   (getf result :program)))
          (otherwise
           (setf failed t)
           (when (getf result :output)
             (format *standard-output* "  ~A~%" (getf result :output)))))))
    (cond (failed 1) (unavailable 2) (t 0))))

(defun simulate-command (arguments)
  (declare (ignore arguments))
  ;; The public simulator accepts already compiled simulator interactions, but
  ;; the model-to-simulator adapter is not public and intentionally does not
  ;; dispatch ordinary bindings.  Calling internal adapter symbols would make
  ;; this CLI promise a model simulation it cannot faithfully provide.
  (format *error-output*
          "simulate [simulation-adapter-unavailable]: the public adapter cannot simulate a complete layout yet.~%")
  2)

(defun print-usage (&optional (stream *standard-output*))
  (format stream "Usage: ivory-key COMMAND [ARGUMENTS...]~%~%")
  (format stream "Commands:~%")
  (format stream "  check FILE...       Parse and validate safe syntax~%")
  (format stream "  fmt [--check] FILE...  Canonically format source~%")
  (format stream "  inventory ROOT      Inventory a Manna Cadet checkout~%")
  (format stream "  dump-ir --stage parsed|typed|normalized --layout FILE [--topology FILE]~%")
  (format stream "          or --stage typed|normalized --project FILE --composition NAME~%")
  (format stream "  levels --layout FILE [--topology FILE] | --project FILE --composition NAME~%")
  (format stream "  simulate --layout FILE --events FILE  (reports adapter availability)~%")
  (format stream "  explain --layout FILE --device FILE --realization FILE [--topology FILE]~%")
  (format stream "          or --project FILE --composition NAME~%")
  (format stream "  compile --layout FILE --device FILE --realization FILE --output DIR [--topology FILE]~%")
  (format stream "          or --project FILE --composition NAME --output DIR~%")
  (format stream "  validate-build DIR  Run optional XKB/Kanata validators~%"))

(defun main (&optional (arguments (uiop:command-line-arguments)))
  (handler-case
      (if (null arguments)
          (progn (print-usage *error-output*) 2)
          (let ((command (first arguments))
                (rest (rest arguments)))
            (cond
              ((string= command "check") (check-files rest))
              ((string= command "fmt") (format-files rest))
              ((string= command "inventory") (inventory-command rest))
              ((string= command "dump-ir") (dump-ir-command rest))
              ((string= command "levels") (levels-command rest))
              ((string= command "simulate") (simulate-command rest))
              ((string= command "explain") (explain-command rest))
              ((string= command "compile") (compile-command rest))
              ((string= command "validate-build") (validate-build-command rest))
              ((or (string= command "help") (string= command "--help"))
               (print-usage)
               0)
              (t
               (format *error-output* "Unknown command ~A.~%" command)
               (print-usage *error-output*)
               2))))
    (error (condition)
      (format *error-output* "ivory-key: ~A~%" condition)
      1)))
