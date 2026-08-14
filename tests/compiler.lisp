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

(defparameter +compiler-test-composition+
  "(ivory-key 1)
(realize direct-build (:layout direct) (:device test-device) (:profile direct-linux))
")

(defun write-compiler-test-project (directory)
  (compiler-test-write
   directory "project.ivory"
   "(ivory-key 1)
(import \"topology.ivory\")
(import \"layout.ivory\")
(import \"device.ivory\")
(import \"realization.ivory\")
(import \"composition.ivory\")
")
  (compiler-test-write directory "topology.ivory" +compiler-test-topology+)
  (compiler-test-write directory "layout.ivory" +compiler-test-layout+)
  (compiler-test-write directory "device.ivory" +compiler-test-device+)
  (compiler-test-write directory "realization.ivory" +compiler-test-realization+)
  (compiler-test-write directory "composition.ivory" +compiler-test-composition+)
  (merge-pathnames "project.ivory" directory))

(defun compiler-project-error-code-from (thunk)
  (handler-case
      (progn (funcall thunk)
             (error "Expected IVORY-KEY.PROJECT:PROJECT-ERROR."))
    (ivory-key.project:project-error (condition)
      (ivory-key.project:project-error-code condition))))

(defun compiler-stage-code-from (thunk)
  (handler-case
      (progn (funcall thunk)
             (error "Expected IVORY-KEY.CLI:COMPILER-STAGE-ERROR."))
    (ivory-key.cli:compiler-stage-error (condition)
      (ivory-key.cli:compiler-stage-error-code condition))))

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

(deftest compiler-project-composition-compiles-without-reparsing-components
  (with-compiler-test-directory (directory)
    (let* ((project (write-compiler-test-project directory))
           (output (merge-pathnames "project-build/" directory)))
      (multiple-value-bind (unit placement realization composition project-result)
          (ivory-key.cli:load-project-composition-for-compilation
           project "direct-build")
        (is (null (ivory-key.cli::compiler-unit-parsed unit)))
        (is-equal "direct" (ivory-key.model:identifier-name
                             (ivory-key.model:layout-name
                              (ivory-key.cli::compiler-unit-layout unit))))
        (is-equal "test-device" (ivory-key.cli::compiler-placement-name placement))
        (is-equal "direct-linux" (ivory-key.cli::compiler-realization-name realization))
        (is-equal "direct-build"
                  (ivory-key.project:project-realization-composition-name composition))
        (is (ivory-key.project:project-composition project-result "direct-build")))
      (let ((pipeline (ivory-key.cli:compile-project-source
                       project "direct-build" :output-directory output)))
        (is pipeline)
        (is (probe-file (merge-pathnames "keymap.xkb" output)))
        (is (probe-file (merge-pathnames "layout.kbd" output)))
        (is (probe-file (merge-pathnames "REPORT.txt" output)))))))

(deftest compiler-project-composition-refuses-an-unknown-name
  (with-compiler-test-directory (directory)
    (let ((project (write-compiler-test-project directory)))
      (is-equal :unknown-project-definition
                (compiler-project-error-code-from
                 (lambda ()
                   (ivory-key.cli:load-project-composition-for-compilation
                    project "does-not-exist")))))))

(deftest compiler-cli-inspects-and-explains-a-project-composition
  (with-compiler-test-directory (directory)
    (let* ((project (write-compiler-test-project directory))
           (output (merge-pathnames "cli-project-build/" directory))
           (standard-output (make-string-output-stream))
           (error-output (make-string-output-stream)))
      (let ((*standard-output* standard-output)
            (*error-output* error-output))
        (is-equal 0
                  (ivory-key.cli:main
                   (list "dump-ir" "--stage" "normalized" "--project"
                         (namestring project) "--composition" "direct-build")))
        (is-equal 0
                  (ivory-key.cli:main
                   (list "levels" "--project" (namestring project)
                         "--composition" "direct-build")))
        (is-equal 0
                  (ivory-key.cli:main
                   (list "explain" "--project" (namestring project)
                         "--composition" "direct-build")))
        (is-equal 0
                  (ivory-key.cli:main
                   (list "compile" "--project" (namestring project)
                         "--composition" "direct-build" "--output"
                         (namestring output)))))
      (let ((output (get-output-stream-string standard-output)))
        (is (search "normalized-layout direct" output))
        (is (search "levels for direct" output))
        (is (search "Fidelity: exact" output))
        (is (search "Emitted new build directory" output)))
      (is (probe-file (merge-pathnames "keymap.xkb" output)))
      (is (probe-file (merge-pathnames "layout.kbd" output)))
      (is-equal "" (get-output-stream-string error-output)))))

(deftest compiler-project-composition-preserves-source-root-refusal
  (with-compiler-test-directory (directory)
    (let* ((root (merge-pathnames "root/" directory))
           (entry nil))
      (ensure-directories-exist (merge-pathnames "placeholder" root))
      (setf entry (compiler-test-write root "project.ivory"
                                       "(ivory-key 1) (import \"../outside.ivory\")"))
      (compiler-test-write directory "outside.ivory" "(ivory-key 1)")
      (is-equal :import-outside-source-root
                (compiler-project-error-code-from
                 (lambda ()
                   (ivory-key.cli:load-project-composition-for-compilation
                    entry "unreachable")))))))

(deftest compiler-cli-project-mode-resolves-relative-entry-from-captured-cwd
  (with-compiler-test-directory (directory)
    (let* ((project (write-compiler-test-project directory))
           (output (merge-pathnames "relative-project-build/" directory))
           (standard-output (make-string-output-stream))
           (error-output (make-string-output-stream)))
      (declare (ignore project))
      (uiop:with-current-directory (directory)
        ;; Both the entry and explicit source root are relative.  This is the
        ;; command-line shape that used to depend on NIL/default pathname state.
        (is (ivory-key.project:load-project "project.ivory" :source-roots '(".")))
        (let ((*standard-output* standard-output)
              (*error-output* error-output))
          (is-equal 0
                    (ivory-key.cli:main
                     (list "compile" "--project" "project.ivory"
                           "--composition" "direct-build" "--output"
                           (namestring output))))))
      (is (probe-file (merge-pathnames "keymap.xkb" output)))
      (is-equal "" (get-output-stream-string error-output)))))

(deftest project-loader-accepts-entry-beneath-a-symlinked-source-root
  ;; Symlink construction is deliberately an optional Unix adversarial check;
  ;; the loader behavior itself remains portable Common Lisp.
  (when (uiop:os-unix-p)
    (with-compiler-test-directory (directory)
      (let* ((real-root (merge-pathnames "real-root/" directory))
             (link-path (merge-pathnames "source-root-link" directory))
             (link-root (uiop:ensure-directory-pathname link-path)))
        (ensure-directories-exist (merge-pathnames "placeholder" real-root))
        (write-compiler-test-project real-root)
        (unwind-protect
             (progn
               (uiop:run-program (list "ln" "-s" (namestring real-root)
                                       (namestring link-path)))
               (is (ivory-key.project:load-project
                    (merge-pathnames "project.ivory" link-root)
                    :source-roots (list link-root))))
          ;; LINK-PATH has no trailing slash, so DELETE-FILE removes the link
          ;; itself rather than treating it as a directory pathname.
          (ignore-errors (delete-file link-path)))))))

(deftest compiler-emission-requires-an-existing-trusted-output-parent
  (with-compiler-test-directory (directory)
    (let* ((project (write-compiler-test-project directory))
           (output (merge-pathnames "not-created/build/" directory)))
      (is-equal :missing-output-parent
                (compiler-stage-code-from
                 (lambda ()
                   (ivory-key.cli:compile-project-source
                    project "direct-build" :output-directory output)))))))

(deftest compiler-emission-does-not-use-predictable-temporary-siblings
  (with-compiler-test-directory (directory)
    (let* ((project (write-compiler-test-project directory))
           (output (merge-pathnames "build/" directory))
           (old-temporary (merge-pathnames ".build.ivory-key-tmp-0/" directory)))
      (ensure-directories-exist (merge-pathnames "placeholder" old-temporary))
      (compiler-test-write old-temporary "sentinel.txt" "must remain untouched")
      (is (ivory-key.cli:compile-project-source
           project "direct-build" :output-directory output))
      (with-open-file (stream (merge-pathnames "sentinel.txt" old-temporary)
                              :direction :input :external-format :utf-8)
        (is-equal "must remain untouched"
                  (let ((text (make-string (file-length stream))))
                    (read-sequence text stream)
                    text))))))

(deftest compiler-emission-refuses-a-visible-dangling-symlink-target
  ;; DIRECTORY exposes dangling links on the supported Unix hosts.  On other
  ;; hosts the documented trusted-parent precondition remains the fail-closed
  ;; boundary because portable Common Lisp has no LSTAT operation.
  (when (uiop:os-unix-p)
    (with-compiler-test-directory (directory)
      (let* ((project (write-compiler-test-project directory))
             (output (merge-pathnames "build/" directory))
             (link-path (merge-pathnames "build" directory)))
        (unwind-protect
             (progn
               (uiop:run-program (list "ln" "-s" "nowhere" (namestring link-path)))
               (is-equal :output-already-exists
                         (compiler-stage-code-from
                          (lambda ()
                            (ivory-key.cli:compile-project-source
                             project "direct-build" :output-directory output)))))
          (ignore-errors (delete-file link-path)))))))
