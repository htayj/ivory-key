;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Optional integration evidence.  These helpers never make external tools
;;;; a prerequisite for the hermetic unit suite.

(in-package #:ivory-key.tests)

(defun ivory-key-project-root ()
  "Return the loaded Ivory Key system's source directory."
  (uiop:ensure-directory-pathname
   (asdf:system-source-directory "ivory-key")))

(defun ivory-fixture-pathnames ()
  "Return every checked-in .ivory fixture in deterministic pathname order."
  (let ((root (ivory-key-project-root)))
    (sort
     (append (list (merge-pathnames "manna-cadet-project.ivory" root))
             (loop for directory-name in '("layouts/" "topologies/" "devices/" "realizations/")
                   append (directory (merge-pathnames "*.ivory"
                                                       (merge-pathnames directory-name root)))))
     #'string< :key #'namestring)))

(defun parse-every-ivory-fixture ()
  "Return (PATHNAME . PARSE-RESULT) pairs for all checked-in fixtures."
  (mapcar (lambda (pathname)
            (cons pathname (ivory-key.syntax:parse-file pathname)))
          (ivory-fixture-pathnames)))

(defun assert-every-ivory-fixture-parses ()
  "Signal with fixture-specific context when any fixture has syntax diagnostics."
  (dolist (entry (parse-every-ivory-fixture) t)
    (let ((pathname (car entry))
          (result (cdr entry)))
      (unless (and (ivory-key.syntax:syntax-parse-result-complete-p result)
                   (null (ivory-key.syntax:syntax-parse-result-diagnostics result)))
        (error "Fixture ~A did not parse cleanly: ~S" pathname
               (ivory-key.syntax:syntax-parse-result-diagnostics result))))))

(defun backend-validation-program-available-p (backend)
  "Whether BACKEND's optional validation executable is discoverable."
  (let ((program (ivory-key.backend:capability-validation-program
                  (ivory-key.backend:capabilities backend))))
    ;; UIOP does not expose one portable executable-discovery function across
    ;; all ASDF versions supported by the project.  These validation programs
    ;; both support --version, so a harmless argument-vector probe is clearer
    ;; than using a non-portable implementation helper.
    (and program
         (handler-case
             (progn
               (uiop:run-program (list program "--version")
                                 :output :string :error-output :output)
               t)
           (error () nil)))))

(defun validate-artifacts-when-tools-exist (pipeline-result output-directory)
  "Validate artifacts whose backend executable is installed.

Return one property list per artifact.  A missing executable yields :SKIPPED
rather than a success claim; an installed executable's failure is preserved as
:FAILURE with the backend output and argument vector."
  (loop for artifact in (ivory-key.backend:pipeline-result-artifacts pipeline-result)
        for kind = (ivory-key.backend:pipeline-artifact-kind artifact)
        for pathname =
          (merge-pathnames (ivory-key.backend:pipeline-artifact-relative-path artifact)
                           (uiop:ensure-directory-pathname output-directory))
        for backend = (ecase kind
                        (:xkb (ivory-key.backend:make-xkb-backend))
                        (:kanata (ivory-key.backend:make-kanata-backend)))
        collect
        (if (backend-validation-program-available-p backend)
            (multiple-value-bind (success output arguments)
                (ivory-key.backend:validate-artifact backend pathname)
              (list :kind kind :status (if success :passed :failed)
                    :output output :arguments arguments))
            (list :kind kind :status :skipped
                  :reason "validation executable is not installed"))))

(deftest integration-all-ivory-fixtures-parse
  (is (assert-every-ivory-fixture-parses)))

(deftest integration-manna-project-graph-loads
  (let* ((entry (merge-pathnames "manna-cadet-project.ivory"
                                 (ivory-key-project-root)))
         (project (ivory-key.project:load-project entry)))
    (dolist (expected '(("manna-cadet-linux" . "kinesis-advantage2")
                        ("manna-cadet-advantage360-linux" . "kinesis-advantage360")))
      (let ((composition
              (ivory-key.project:project-composition project (car expected) :errorp t)))
        (is-equal (car expected)
                  (ivory-key.project:project-realization-composition-name composition))
        (is-equal (cdr expected)
                  (ivory-key.model:identifier-name
                   (ivory-key.model:placement-name
                    (ivory-key.project:project-realization-composition-device
                     composition))))))))
