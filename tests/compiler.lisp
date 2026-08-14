;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Focused regression tests for the source-to-bootstrap-pipeline bridge.

(in-package #:ivory-key.tests)

(defun compiler-test-directory ()
  (let ((directory
          (merge-pathnames
           (format nil "ivory-key-compiler-~A/" (symbol-name (gensym "TEST-")))
           (uiop:temporary-directory))))
    (ensure-directories-exist (merge-pathnames "placeholder" directory))
    directory))

(defun compiler-test-write (directory name content)
  (let ((pathname (merge-pathnames name directory)))
    (with-open-file (stream pathname :direction :output :if-exists :error
                                     :if-does-not-exist :create
                                     :external-format :utf-8)
      (write-string content stream))
    pathname))

(defmacro with-compiler-test-directory ((directory) &body body)
  `(let ((,directory (compiler-test-directory)))
     (unwind-protect
          (progn ,@body)
       (when (probe-file ,directory)
         (uiop:delete-directory-tree ,directory :validate t)))))

(defparameter +compiler-test-layout+
  "(ivory-key 1)
(define-layout direct
  (uses-topology one)
  (binding q (unicode \"q\")))
")

(defparameter +compiler-test-topology+
  "(ivory-key 1)
(define-topology one
  (position q))
")

(defparameter +compiler-test-device+
  "(ivory-key 1)
(define-device test-device
  (uses-topology one)
  (place q (:xkb AD01) (:kanata q)))
")

(defparameter +compiler-test-realization+
  "(ivory-key 1)
(define-realization direct-linux
  (pipeline kanata xkb)
  (allow-grades exact emulated)
  (forbid-shell-actions yes))
")

(deftest compiler-bridge-runs-every-front-end-stage-and-emits-new-build
  (with-compiler-test-directory (directory)
    (let* ((layout (compiler-test-write directory "layout.ivory" +compiler-test-layout+))
           (topology (compiler-test-write directory "topology.ivory" +compiler-test-topology+))
           (device (compiler-test-write directory "device.ivory" +compiler-test-device+))
           (realization (compiler-test-write directory "realization.ivory"
                                             +compiler-test-realization+))
           (output (merge-pathnames "build/" directory))
           (unit (ivory-key.cli::load-layout-for-compilation
                  layout :topology-path topology))
           (placement (ivory-key.cli::decode-device-source device)))
      (is-equal "direct"
                (ivory-key.model:identifier-name
                 (ivory-key.model:normalized-layout-name
                  (ivory-key.cli::compiler-unit-normalized unit))))
      (multiple-value-bind (request issues)
          (ivory-key.cli::analyze-normalized-layout
           (ivory-key.cli::compiler-unit-normalized unit) placement)
        (is request)
        (is (null issues))
        (is-equal '("U71")
                  (ivory-key.backend:key-entry-outputs-for
                   (first (ivory-key.backend:lowering-request-entries request)) :xkb)))
      (let ((pipeline (ivory-key.cli::compile-layout-source
                       layout :topology-path topology :device-path device
                       :realization-path realization :output-directory output)))
        (is pipeline)
        (is (probe-file (merge-pathnames "keymap.xkb" output)))
        (is (probe-file (merge-pathnames "layout.kbd" output)))
        (is (probe-file (merge-pathnames "REPORT.txt" output)))
        ;; A second call never supersedes a previously emitted good build.
        (signals error
          (ivory-key.cli::compile-layout-source
           layout :topology-path topology :device-path device
           :realization-path realization :output-directory output))))))

(deftest compiler-bridge-refuses-unproven-context-selection-before-emission
  (with-compiler-test-directory (directory)
    (let* ((layout
             (compiler-test-write
              directory "levels.ivory"
              "(ivory-key 1)
(define-layout levels
  (uses-topology one)
  (axis case (:states plain shifted) (:resolution product))
  (binding q
    (at (plain) (unicode \"q\"))
    (at (shifted) (unicode \"Q\"))))
"))
           (topology (compiler-test-write directory "topology.ivory" +compiler-test-topology+))
           (device (compiler-test-write directory "device.ivory" +compiler-test-device+))
           (unit (ivory-key.cli::load-layout-for-compilation
                  layout :topology-path topology))
           (placement (ivory-key.cli::decode-device-source device)))
      (multiple-value-bind (request issues)
          (ivory-key.cli::analyze-normalized-layout
           (ivory-key.cli::compiler-unit-normalized unit) placement)
        (is (null request))
        (is-equal 1 (length issues))
        (is-equal :unsupported-context-selection
                  (ivory-key.cli::compiler-fidelity-issue-code (first issues)))))))

(deftest compiler-cli-inspection-and-adapter-disposition-are-explicit
  (with-compiler-test-directory (directory)
    (let* ((layout (compiler-test-write directory "layout.ivory" +compiler-test-layout+))
           (topology (compiler-test-write directory "topology.ivory" +compiler-test-topology+))
           (standard-output (make-string-output-stream))
           (error-output (make-string-output-stream)))
      (let ((*standard-output* standard-output)
            (*error-output* error-output))
        (is-equal 0 (ivory-key.cli:main
                     (list "dump-ir" "--stage" "normalized" "--layout"
                           (namestring layout) "--topology" (namestring topology))))
        (is-equal 0 (ivory-key.cli:main
                     (list "levels" "--layout" (namestring layout)
                           "--topology" (namestring topology))))
        (is-equal 2 (ivory-key.cli:main (list "simulate" "--layout"
                                             (namestring layout) "--events" "unused.ivory"))))
      (is (search "normalized-layout direct" (get-output-stream-string standard-output)))
      (is (search "simulation-adapter-unavailable" (get-output-stream-string error-output))))))

(deftest compiler-topology-decoder-accepts-distinct-multiple-positions
  (with-compiler-test-directory (directory)
    (let* ((pathname
             (compiler-test-write
              directory "topology.ivory"
              "(ivory-key 1)\n(define-topology two (position q) (position t))\n"))
           (topology (ivory-key.cli::decode-topology-source pathname)))
      (is-equal '("q" "t")
                (mapcar (lambda (position)
                          (ivory-key.model:identifier-name
                           (ivory-key.model:position-name position)))
                        (ivory-key.model:topology-positions topology))))))
