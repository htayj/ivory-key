;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;;
;;;; Tagged external-validation probe; deliberately not an ASDF test component.
;;;;
;;;; Invoke from the checkout root with, for example:
;;;;   sbcl --script tests/external/xkb-kanata.lisp
;;;;
;;;; This test only proves that the installed XKB and Kanata parsers accept one
;;;; exact, direct pipeline request.  It does not simulate either backend or
;;;; claim differential equivalence with the reference simulator.

(require "asdf")

(defpackage #:ivory-key.external-xkb-kanata-validation
  (:use #:cl))

(in-package #:ivory-key.external-xkb-kanata-validation)

(defparameter +external-validation-tag+ :external-xkb-kanata)

(defun repository-root ()
  "Return the checkout root from this script's stable load pathname."
  (let* ((script (or *load-pathname* *compile-file-pathname*
                     (error "External validation needs a load pathname.")))
         (external-directory
           (uiop:pathname-directory-pathname (truename script)))
         (tests-directory
           (uiop:pathname-parent-directory-pathname external-directory)))
    (uiop:pathname-parent-directory-pathname tests-directory)))

(defun load-ivory-key ()
  "Load exactly the checked-out core system, without registering this probe.

The external test is intentionally outside the hermetic ASDF suite, so tool
availability changes neither its dependency graph nor its result count.
"
  (let ((root (repository-root)))
    (asdf:load-asd (merge-pathnames "ivory-key.asd" root))
    (asdf:load-system "ivory-key")))

;; LOAD reads one top-level form at a time.  Bootstrap the core before it reads
;; the later IVORY-KEY.BACKEND package-qualified forms in this external script.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (load-ivory-key))

(defun tool-available-p (program)
  "Check PROGRAM with an argument vector, never a shell command.

The version probe is only a capability test.  A tool which is present but later
rejects a generated artifact remains a test failure.
"
  (handler-case
      (progn
        (uiop:run-program (list program "--version")
                          :output :string :error-output :output
                          :ignore-error-status t)
        t)
    (error () nil)))

(defun external-test-directory ()
  (let ((directory
          (merge-pathnames
           (format nil "ivory-key-external-xkb-kanata-~A/"
                   (symbol-name (gensym "VALIDATION-")))
           (uiop:temporary-directory))))
    (ensure-directories-exist (merge-pathnames "placeholder" directory))
    directory))

(defun write-external-source (directory name contents)
  (let ((pathname (merge-pathnames name directory)))
    (with-open-file (stream pathname :direction :output :if-exists :error
                                     :if-does-not-exist :create
                                     :external-format :utf-8)
      (write-string contents stream))
    pathname))

(defun compile-real-pipeline (directory)
  "Compile a small static source layout through the public compiler bridge.

This reaches normalization, the conservative exact-only bridge, combined
pipeline lowering, fresh output emission, and the generated-output contract.
Timed interactions, carrier allocation, and selector semantics are deliberately
absent: neither emitter has backend differential proof for them yet.
"
  (let ((layout
          (write-external-source
           directory "layout.ivory"
           "(ivory-key 1)
(define-layout external-validator
  (uses-topology external-topology)
  (binding q (unicode \"q\"))
  (binding w (unicode \"w\")))
"))
        (topology
          (write-external-source
           directory "topology.ivory"
           "(ivory-key 1)
(define-topology external-topology
  (position q)
  (position w))
"))
        (device
          (write-external-source
           directory "device.ivory"
           "(ivory-key 1)
(define-device external-device
  (uses-topology external-topology)
  (place q (:xkb AD01) (:kanata q))
  (place w (:xkb AD02) (:kanata w)))
"))
        (realization
          (write-external-source
           directory "realization.ivory"
           "(ivory-key 1)
(define-realization external-linux
  (pipeline kanata xkb)
  (allow-grades exact emulated)
  (forbid-shell-actions yes))
"))
        (output (merge-pathnames "build/" directory)))
    (values
     (ivory-key.cli:compile-layout-source
      layout :topology-path topology :device-path device
      :realization-path realization :output-directory output)
     output)))

(defun validation-for-kind (validations kind)
  (or (find kind validations :key (lambda (validation) (getf validation :kind)))
      (error "Pipeline validation did not report ~S." kind)))

(defun require-successful-validator (validations kind expected-arguments)
  (let ((validation (validation-for-kind validations kind)))
    (unless (equal expected-arguments (getf validation :arguments))
      (error "~S validator did not receive the expected argument vector: ~S"
             kind (getf validation :arguments)))
    (unless (getf validation :success)
      (error "Installed ~S validator rejected generated artifact:~%~A"
             kind (getf validation :output)))
    validation))

(defun run-external-xkb-kanata-validation ()
  "Run the explicitly tagged XKB/Kanata parser validation.

Returns :SKIPPED with a visible capability disposition when one or both tools
are unavailable, and otherwise errors on either rejection.
"
  (let ((missing (remove-if #'tool-available-p '("xkbcli" "kanata"))))
    (when missing
      (format t "EXTERNAL-VALIDATION ~S: SKIPPED (missing tool~:P ~{~A~^, ~}).~%"
              +external-validation-tag+ (length missing) missing)
      (return-from run-external-xkb-kanata-validation :skipped))
    (let ((directory (external-test-directory)))
      (unwind-protect
           (multiple-value-bind (pipeline output-directory)
               (compile-real-pipeline directory)
             (let* ((written pipeline)
                    (validations
                      (ivory-key.backend:validate-pipeline-result
                       written output-directory))
                    (xkb (merge-pathnames "keymap.xkb" output-directory))
                    (kanata (merge-pathnames "layout.kbd" output-directory)))
               ;; The backend methods construct these literal lists, making this
               ;; an executable regression against accidentally introducing shell
               ;; invocation or changing the real validator command contract.
               (require-successful-validator
                validations :xkb
                (list "xkbcli" "compile-keymap" "--keymap" (namestring xkb)))
               (require-successful-validator
                validations :kanata
                (list "kanata" "--check" "-c" (namestring kanata)))
               (format t "EXTERNAL-VALIDATION ~S: PASSED (xkbcli and kanata accepted generated artifacts).~%"
                       +external-validation-tag+)
               :passed))
        (when (probe-file directory)
          (uiop:delete-directory-tree directory :validate t))))))

(handler-case
    (progn
      (run-external-xkb-kanata-validation)
      (uiop:quit 0))
  (error (condition)
    (format *error-output* "EXTERNAL-VALIDATION ~S: FAILED~%~A~%"
            +external-validation-tag+ condition)
    (uiop:quit 1)))
