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
         (delete-test-directory-tree ,directory)))))

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

(defparameter +compiler-test-planner-layout+
  "(ivory-key 1)
(define-layout planner
  (uses-topology two)
  (axis case (:states plain shifted) (:resolution product))
  (modifiers meta)
  (binding q
    (at (plain) (unicode \"q\"))
    (at (shifted) (unicode \"Q\")))
  (binding t (named-symbol theta)))
")

(defparameter +compiler-test-planner-topology+
  "(ivory-key 1)
(define-topology two
  (position q)
  (position t))
")

(defparameter +compiler-test-planner-device+
  "(ivory-key 1)
(define-device planner-device
  (uses-topology two)
  (place q (:xkb AD01) (:kanata q))
  (place t (:xkb AD02) (:kanata t)))
")

(defparameter +compiler-test-planner-composition+
  "(ivory-key 1)
(realize planner-build (:layout planner) (:device planner-device) (:profile direct-linux))
")

(defun compiler-test-twenty-level-layout ()
  (with-output-to-string (stream)
    (format stream "(ivory-key 1)~%(define-layout twenty~%  (uses-topology one)~%")
    (format stream "  (axis plane (:states")
    (loop for number from 1 to 20 do
      (format stream " s~2,'0D" number))
    (format stream ") (:resolution product))~%  (binding q~%")
    (loop for number from 1 to 20 do
      (format stream "    (at (s~2,'0D) (unicode \"a\"))~%" number))
    (format stream "  ))~%")))

(defun compiler-test-forty-level-layout ()
  (with-output-to-string (stream)
    (format stream "(ivory-key 1)~%(define-layout forty~%  (uses-topology one)~%")
    (format stream "  (axis plane (:states")
    (loop for number from 1 to 40 do
      (format stream " s~2,'0D" number))
    (format stream ") (:resolution product))~%  (binding q~%")
    (loop for number from 1 to 40 do
      (format stream "    (at (s~2,'0D) (unicode \"a\"))~%" number))
    (format stream "  ))~%")))

(defun write-compiler-test-project (directory &key
                                               (layout-source +compiler-test-layout+)
                                               (topology-source +compiler-test-topology+)
                                               (device-source +compiler-test-device+)
                                               (realization-source +compiler-test-realization+)
                                               (composition-source +compiler-test-composition+))
  (compiler-test-write
   directory "project.ivory"
   "(ivory-key 1)
(import \"topology.ivory\")
(import \"layout.ivory\")
(import \"device.ivory\")
(import \"realization.ivory\")
(import \"composition.ivory\")
")
  (compiler-test-write directory "topology.ivory" topology-source)
  (compiler-test-write directory "layout.ivory" layout-source)
  (compiler-test-write directory "device.ivory" device-source)
  (compiler-test-write directory "realization.ivory" realization-source)
  (compiler-test-write directory "composition.ivory" composition-source)
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
        (dolist (name '("manifest.json" "allocations.json" "source-map.json" "REPORT.md"))
          (is (probe-file (merge-pathnames name output))))
        (let ((manifest (uiop:read-file-string (merge-pathnames "manifest.json" output))))
          (dolist (identity '("layout" "topology" "device" "realization"))
            (is (search (format nil "\"path\":\"~A\"" identity) manifest)))
          ;; The source digest is of these on-disk bytes, but their physical
          ;; checkout paths must never be published in a generated contract.
          (is (not (search (uiop:native-namestring (truename layout)) manifest)))
          (is (search "\"input_coverage\":[{\"disposition\":\"physical\",\"position\":\"q\"}]"
                      manifest)))
        ;; A second call never supersedes a previously emitted good build.
        (signals error
          (ivory-key.cli::compile-layout-source
           layout :topology-path topology :device-path device
           :realization-path realization :output-directory output))))))

(deftest compiler-device-coverage-is-explicit-for-completeness-and-lowering
  ;; A structurally complete topology may contain an unused, intentionally
  ;; unreachable position.  It is retained in the successful build contract.
  (with-compiler-test-directory (directory)
    (let* ((layout (compiler-test-write
                    directory "layout.ivory"
                    "(ivory-key 1)
(define-layout direct (uses-topology two) (binding q (unicode \"q\")))"))
           (topology (compiler-test-write
                      directory "topology.ivory"
                      "(ivory-key 1)
(define-topology two (position q) (position t))"))
           (device (compiler-test-write
                    directory "device.ivory"
                    "(ivory-key 1)
(define-device covered (uses-topology two)
  (place q (:xkb AD01) (:kanata q))
  (unreachable t))"))
           (realization (compiler-test-write directory "realization.ivory"
                                             +compiler-test-realization+))
           (unit (ivory-key.cli::load-layout-for-compilation
                  layout :topology-path topology))
           (placement (ivory-key.cli::decode-device-source device))
           (output (merge-pathnames "covered-build/" directory)))
      (multiple-value-bind (request issues)
          (ivory-key.cli::analyze-normalized-layout
           (ivory-key.cli::compiler-unit-normalized unit) placement)
        (is request)
        (is (null issues)))
      (ivory-key.cli::compile-layout-source
       layout :topology-path topology :device-path device
       :realization-path realization :output-directory output)
      (let ((manifest (uiop:read-file-string (merge-pathnames "manifest.json" output))))
        (is (search "\"input_coverage\":[{\"disposition\":\"physical\",\"position\":\"q\"},{\"disposition\":\"unreachable\",\"position\":\"t\"}]"
                    manifest)))
      (let ((report (with-output-to-string (stream)
                      (ivory-key.cli::explain-layout-source
                       layout :topology-path topology :device-path device
                       :realization-path realization :stream stream))))
        (is (search "Input coverage:" report))
        (is (search "q: physical" report))
        (is (search "t: unreachable" report)))))
  ;; A missing record is never inferred from an absent mapping, including for
  ;; an otherwise unused topology position in a selected composition.
  (with-compiler-test-directory (directory)
    (let* ((layout (compiler-test-write
                    directory "layout.ivory"
                    "(ivory-key 1)
(define-layout partial (uses-topology two) (binding q (unicode \"q\")))"))
           (topology (compiler-test-write
                      directory "topology.ivory"
                      "(ivory-key 1)
(define-topology two (position q) (position t))"))
           (device (compiler-test-write
                    directory "device.ivory"
                    "(ivory-key 1)
(define-device partial-device (uses-topology two)
  (place q (:xkb AD01) (:kanata q)))"))
           (unit (ivory-key.cli::load-layout-for-compilation
                  layout :topology-path topology))
           (placement (ivory-key.cli::decode-device-source device)))
      (multiple-value-bind (request issues)
          (ivory-key.cli::analyze-normalized-layout
           (ivory-key.cli::compiler-unit-normalized unit) placement)
        (is request)
        (is-equal '(:missing-device-coverage)
                  (mapcar #'ivory-key.cli::compiler-fidelity-issue-code issues)))
      (is-equal :missing-device-coverage
                (compiler-stage-code-from
                 (lambda ()
                   (ivory-key.cli::make-lowering-request-from-normalized-layout
                    (ivory-key.cli::compiler-unit-normalized unit) placement))))))
  ;; An explicitly unreachable input is structurally declared but cannot be
  ;; omitted from a real ordinary binding.
  (with-compiler-test-directory (directory)
    (let* ((layout (compiler-test-write directory "layout.ivory" +compiler-test-layout+))
           (topology (compiler-test-write directory "topology.ivory" +compiler-test-topology+))
           (device (compiler-test-write
                    directory "device.ivory"
                    "(ivory-key 1)
(define-device unreachable-device (uses-topology one) (unreachable q))"))
           (unit (ivory-key.cli::load-layout-for-compilation
                  layout :topology-path topology))
           (placement (ivory-key.cli::decode-device-source device)))
      (multiple-value-bind (request issues)
          (ivory-key.cli::analyze-normalized-layout
           (ivory-key.cli::compiler-unit-normalized unit) placement)
        (is request)
        (is-equal '(:unreachable-device-position)
                  (mapcar #'ivory-key.cli::compiler-fidelity-issue-code issues)))))
  ;; Timed interaction participants are physical inputs too.  A generic timed
  ;; lowering remains refused for its own reason, but coverage is reported
  ;; independently instead of being hidden behind that broader refusal.
  (with-compiler-test-directory (directory)
    (let* ((layout (compiler-test-write
                    directory "layout.ivory"
                    "(ivory-key 1)
(define-layout interaction-only
  (uses-topology one)
  (interaction q-tap
    (:participants q)
    (case tap
      (:match (sequence (down q) (up q)))
      (:commit (up q))
      (:do (unicode \"q\")))))"))
           (topology (compiler-test-write directory "topology.ivory" +compiler-test-topology+))
           (device (compiler-test-write
                    directory "device.ivory"
                    "(ivory-key 1)
(define-device interaction-device (uses-topology one) (unreachable q))"))
           (unit (ivory-key.cli::load-layout-for-compilation
                  layout :topology-path topology))
           (placement (ivory-key.cli::decode-device-source device)))
      (multiple-value-bind (request issues)
          (ivory-key.cli::analyze-normalized-layout
           (ivory-key.cli::compiler-unit-normalized unit) placement)
        (is request)
        (is (member :unreachable-device-position
                    (mapcar #'ivory-key.cli::compiler-fidelity-issue-code issues)))))))

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
        ;; Inspection retains an exact static-table proposal, but the public
        ;; compile gate still refuses it because no selector realization has
        ;; been selected.
        (is request)
        (is-equal 1 (length issues))
        (is-equal :unsupported-context-selection
                  (ivory-key.cli::compiler-fidelity-issue-code (first issues)))
        (is-equal '("U71" "U51")
                  (ivory-key.backend:key-entry-outputs-for
                   (first (ivory-key.backend:lowering-request-entries request))
                   :xkb))))))

(deftest compiler-cli-inspection-and-adapter-disposition-are-explicit
  (with-compiler-test-directory (directory)
    (let* ((layout (compiler-test-write directory "layout.ivory" +compiler-test-layout+))
           (topology (compiler-test-write directory "topology.ivory" +compiler-test-topology+))
           (events (compiler-test-write directory "events.ivory"
                                        "(ivory-key 1)
(simulation (event 0 down q) (event 10 up q))
"))
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
        (is-equal 0 (ivory-key.cli:main (list "simulate" "--layout"
                                             (namestring layout) "--topology"
                                             (namestring topology) "--events"
                                             (namestring events)))))
      (let ((captured-standard-output (get-output-stream-string standard-output)))
        (is (search "normalized-layout direct" captured-standard-output))
        (is (search "simulation-result" captured-standard-output)))
      (is (zerop (length (get-output-stream-string error-output)))))))

(deftest compiler-explain-reports-planner-obligations-without-relaxing-emission
  (with-compiler-test-directory (directory)
    (let* ((project (write-compiler-test-project
                     directory
                     :layout-source +compiler-test-planner-layout+
                     :topology-source +compiler-test-planner-topology+
                     :device-source +compiler-test-planner-device+
                     :composition-source +compiler-test-planner-composition+))
           (layout (merge-pathnames "layout.ivory" directory))
           (topology (merge-pathnames "topology.ivory" directory))
           (device (merge-pathnames "device.ivory" directory))
           (realization (merge-pathnames "realization.ivory" directory))
           (direct-result nil)
           (project-result nil)
           (direct-report
             (with-output-to-string (stream)
               (setf direct-result
                     (ivory-key.cli::explain-layout-source
                      layout :topology-path topology :device-path device
                      :realization-path realization :stream stream))))
           (project-report
             (with-output-to-string (stream)
               (setf project-result
                     (ivory-key.cli:explain-project-source
                      project "planner-build" :stream stream)))))
      ;; The target-neutral planner reports capacity and obligations for both
      ;; source-loading modes, even though the direct emitter cannot lower the
      ;; selector, semantic modifier, or abstract named symbol.
      (is (null direct-result))
      (is (null project-result))
      (dolist (report (list direct-report project-report))
        (is (search "Planner static tables (canonical normalized entry counts)" report))
        (is (search "q: 2 entries; XKB grade exact" report))
        ;; <=8 remains a one-bank plan, so existing inspection output does not
        ;; gain a speculative bank-selection section.
        (is (not (search "Planner multi-bank partitions" report)))
        (is (not (search "Planner bank-selector/carrier obligations" report)))
        (is (search "Planner selector obligations" report))
        (is (search "case [product] states: plain shifted; default: plain; positions: q"
                    report))
        (is (search "Planner semantic-modifier obligations" report))
        (is (search "  meta" report))
        (is (search "Planner resource obligations" report))
        (is (search "selector case:" report))
        (is (search "semantic-modifier meta:" report))
        (is (search "named-symbol theta:" report))
        (is (search "Fidelity: unsupported" report))
        (is (search "[UNSUPPORTED-CONTEXT-SELECTION]" report))
        ;; Named symbols stay semantic requirements; the bootstrap emitter
        ;; must still refuse rather than fabricate an XKB/Kanata spelling.
        (is (search "[UNMAPPED-NAMED-SYMBOL]" report))))))

(deftest compiler-explain-retains-twenty-level-table-and-refuses-emission
  (with-compiler-test-directory (directory)
    (let* ((project (write-compiler-test-project
                     directory
                     :layout-source (compiler-test-twenty-level-layout)
                     :composition-source
                     "(ivory-key 1)
(realize direct-build (:layout twenty) (:device test-device) (:profile direct-linux))
"))
           (layout (merge-pathnames "layout.ivory" directory))
           (topology (merge-pathnames "topology.ivory" directory))
           (device (merge-pathnames "device.ivory" directory))
           (realization (merge-pathnames "realization.ivory" directory))
           (direct-result nil)
           (project-result nil)
           (direct-report
             (with-output-to-string (stream)
               (setf direct-result
                     (ivory-key.cli::explain-layout-source
                      layout :topology-path topology :device-path device
                      :realization-path realization :stream stream))))
           (project-report
             (with-output-to-string (stream)
               (setf project-result
                     (ivory-key.cli:explain-project-source
                      project "direct-build" :stream stream)))))
      (is (null direct-result))
      (is (null project-result))
      (dolist (report (list direct-report project-report))
        (is (search "q: 20 entries; XKB grade unsupported" report))
        (is (search "Planner multi-bank partitions" report))
        (is (search "q: 3 banks; native level capacity: 8; advertised bank capacity: 4 (within capacity)"
                    report))
        (is (search "bank sizes: 1=8 2=8 3=4" report))
        (is (search "plane=s01 -> bank 1 level 1" report))
        (is (search "plane=s08 -> bank 1 level 8" report))
        (is (search "plane=s09 -> bank 2 level 1" report))
        (is (search "plane=s20 -> bank 3 level 4" report))
        (is (search "Planner bank-selector/carrier obligations" report))
        (is (search "q: select 3 banks; requires 3 distinguishable carrier values; lowering unproved"
                    report))
        (is (search "bank-selector q:" report))
        (is (search "bank-carrier q x3:" report))
        (is (search "requires a separately proven emulation or another target" report))
        ;; The planner has not made a future emulation claim, and it does not
        ;; relax the emitter's independent refusal of context selection.
        (is (search "Fidelity: unsupported" report))
        (is (search "[UNSUPPORTED-CONTEXT-SELECTION]" report))))))

(deftest compiler-explain-shows-bank-capacity-overflow-without-emission
  (with-compiler-test-directory (directory)
    (let* ((project (write-compiler-test-project
                     directory
                     :layout-source (compiler-test-forty-level-layout)
                     :composition-source
                     "(ivory-key 1)
(realize direct-build (:layout forty) (:device test-device) (:profile direct-linux))
"))
           (layout (merge-pathnames "layout.ivory" directory))
           (topology (merge-pathnames "topology.ivory" directory))
           (device (merge-pathnames "device.ivory" directory))
           (realization (merge-pathnames "realization.ivory" directory))
           (direct-result nil)
           (project-result nil)
           (direct-report
             (with-output-to-string (stream)
               (setf direct-result
                     (ivory-key.cli::explain-layout-source
                      layout :topology-path topology :device-path device
                      :realization-path realization :stream stream))))
           (project-report
             (with-output-to-string (stream)
               (setf project-result
                     (ivory-key.cli:explain-project-source
                      project "direct-build" :stream stream)))))
      (is (null direct-result))
      (is (null project-result))
      (dolist (report (list direct-report project-report))
        (is (search "q: 40 entries; XKB grade unsupported" report))
        (is (search "q: 5 banks; native level capacity: 8; advertised bank capacity: 4 (exceeded; 5 required)"
                    report))
        (is (search "bank sizes: 1=8 2=8 3=8 4=8 5=8" report))
        (is (search "plane=s01 -> bank 1 level 1" report))
        (is (search "plane=s40 -> bank 5 level 8" report))
        (is (search "q: select 5 banks; requires 5 distinguishable carrier values; lowering unproved"
                    report))
        (is (search "bank-carrier q x5:" report))
        ;; The direct bridge receives no multi-bank lowering request.
        (is (search "Fidelity: unsupported" report))
        (is (search "[UNSUPPORTED-CONTEXT-SELECTION]" report))))))

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

(deftest compiler-project-placement-conversion-refuses-malformed-programmatic-coverage
  "COMPILER-PLACEMENT-FROM-MODEL revalidates model instances that bypass source."
  (let* ((topology
           (ivory-key.model:make-topology
            "programmatic-coverage"
            (list (ivory-key.model:make-logical-position "q"))))
         (q (ivory-key.model:make-identifier "q"))
         (unknown (ivory-key.model:make-identifier "not-on-topology"))
         (device
           ;; MAKE-INSTANCE intentionally bypasses MAKE-DEVICE-PLACEMENT's
           ;; eager validation, simulating an embedding caller with malformed
           ;; constructed data.  No backend metadata should be trusted first.
           (make-instance
            'ivory-key.model:device-placement
            :name (ivory-key.model:make-identifier "bad-programmatic-device")
            :topology topology
            :mappings (list (cons "P01" q) (cons "P02" unknown))
            :position-coverage
            (list (ivory-key.model:make-device-position-coverage q :physical))
            :metadata nil)))
    (is-equal :unknown-device-placement-position
              (compiler-stage-code-from
               (lambda ()
                 (ivory-key.cli::compiler-placement-from-model device))))))

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
        (dolist (name '("manifest.json" "allocations.json" "source-map.json" "REPORT.md"))
          (is (probe-file (merge-pathnames name output))))))))

(deftest compiler-project-build-contract-hashes-header-only-imports
  (with-compiler-test-directory (directory)
    (let* ((project (write-compiler-test-project directory))
           (header (compiler-test-write directory "header-only.ivory"
                                        (format nil "(ivory-key 1)~%")))
           (output (merge-pathnames "contract-project-build/" directory)))
      ;; This legal module supplies no definition, so source provenance must
      ;; come from the project loader's complete loaded graph rather than its
      ;; definition registry.
      (with-open-file (stream project :direction :output :if-exists :supersede
                                      :if-does-not-exist :error
                                      :external-format :utf-8)
        (write-string
         "(ivory-key 1)
(import \"header-only.ivory\")
(import \"topology.ivory\")
(import \"layout.ivory\")
(import \"device.ivory\")
(import \"realization.ivory\")
(import \"composition.ivory\")
"
         stream))
      (is (ivory-key.cli:compile-project-source
           project "direct-build" :output-directory output))
      (let ((manifest (uiop:read-file-string (merge-pathnames "manifest.json" output)))
            (report (uiop:read-file-string (merge-pathnames "REPORT.md" output)))
            (header-hash (ivory-key.build-contract:sha256-hex header)))
        (is (search "\"path\":\"header-only.ivory\"" manifest))
        (is (search header-hash manifest))
        (is (search "\"profile\":\"direct-linux\"" manifest))
        ;; Compilation did not run a validator, so the contract must state
        ;; that fact in prose but must not fabricate a machine tool record.
        (is (not (search "\"validation\"" manifest)))
        (is (search "No external validation ran during compilation" report))))))

(deftest compiler-project-build-contract-is-relocatable
  (with-compiler-test-directory (directory)
    (let* ((left (merge-pathnames "left/" directory))
           (right (merge-pathnames "right/" directory))
           (left-project-root (merge-pathnames "project/" left))
           (left-library-root (merge-pathnames "library/" left))
           (right-project-root (merge-pathnames "project/" right))
           (right-library-root (merge-pathnames "library/" right)))
      (dolist (root (list left-project-root left-library-root
                          right-project-root right-library-root))
        (ensure-directories-exist (merge-pathnames "placeholder" root)))
      (let ((left-project (write-compiler-test-project left-project-root))
            (right-project (write-compiler-test-project right-project-root))
            (left-output (merge-pathnames "build/" left-project-root))
            (right-output (merge-pathnames "build/" right-project-root)))
        ;; The second source root supplies a header-only module.  Its source
        ;; hash must follow the build, but neither source root's host pathname
        ;; or order may enter generated output.
        (dolist (library-root (list left-library-root right-library-root))
          (compiler-test-write library-root "header-only.ivory"
                               (format nil "(ivory-key 1)~%")))
        (dolist (project (list left-project right-project))
          (with-open-file (stream project :direction :output :if-exists :supersede
                                           :if-does-not-exist :error
                                           :external-format :utf-8)
            (write-string
             "(ivory-key 1)
(import \"../library/header-only.ivory\")
(import \"topology.ivory\")
(import \"layout.ivory\")
(import \"device.ivory\")
(import \"realization.ivory\")
(import \"composition.ivory\")
"
             stream)))
        (is (ivory-key.cli:compile-project-source
             left-project "direct-build"
             :source-roots (list left-project-root left-library-root)
             :output-directory left-output))
        (is (ivory-key.cli:compile-project-source
             right-project "direct-build"
             :source-roots (list right-project-root right-library-root)
             :output-directory right-output))
        (is (search "\"path\":\"header-only.ivory\""
                    (uiop:read-file-string (merge-pathnames "manifest.json" left-output))))
        (dolist (name '("manifest.json" "allocations.json" "source-map.json" "REPORT.md"))
          (is-equal (uiop:read-file-string (merge-pathnames name left-output))
                    (uiop:read-file-string (merge-pathnames name right-output))))))))

(deftest compiler-build-contract-refuses-ambiguous-source-identities
  (with-compiler-test-directory (directory)
    (let ((first (compiler-test-write directory "first.ivory" "first"))
          (second (compiler-test-write directory "second.ivory" "second")))
      ;; A duplicate logical label could conceal one physical source behind
      ;; another in a manifest, even if the bytes happen to match.  It is
      ;; therefore an emission refusal, never a de-duplication shortcut.
      (is-equal :ambiguous-contract-source-identity
                (compiler-stage-code-from
                 (lambda ()
                   (ivory-key.cli::%source-hash-records-for-pathnames
                    (list (cons "same-source" first)
                          (cons "same-source" second)))))))))

(deftest compiler-project-contract-refuses-duplicate-relative-source-identities
  (with-compiler-test-directory (directory)
    (let* ((left-root (merge-pathnames "left/" directory))
           (right-root (merge-pathnames "right/" directory)))
      (dolist (root (list left-root right-root))
        (ensure-directories-exist (merge-pathnames "placeholder" root)))
      (let ((project (write-compiler-test-project left-root))
            (output (merge-pathnames "build/" left-root)))
        (dolist (root (list left-root right-root))
          (compiler-test-write root "header-only.ivory" (format nil "(ivory-key 1)~%")))
        (with-open-file (stream project :direction :output :if-exists :supersede
                                         :if-does-not-exist :error
                                         :external-format :utf-8)
          (write-string
           "(ivory-key 1)
(import \"header-only.ivory\")
(import \"../right/header-only.ivory\")
(import \"topology.ivory\")
(import \"layout.ivory\")
(import \"device.ivory\")
(import \"realization.ivory\")
(import \"composition.ivory\")
"
           stream))
        ;; The same root-relative label from two separate roots cannot be
        ;; made unambiguous by leaking root names into the contract.
        (is-equal :ambiguous-contract-source-identity
                  (compiler-stage-code-from
                   (lambda ()
                     (ivory-key.cli:compile-project-source
                      project "direct-build" :source-roots (list left-root right-root)
                      :output-directory output))))))))

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
               (make-test-symbolic-link real-root link-path)
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
               (make-test-symbolic-link #p"nowhere" link-path)
               (is-equal :output-already-exists
                         (compiler-stage-code-from
                          (lambda ()
                            (ivory-key.cli:compile-project-source
                             project "direct-build" :output-directory output)))))
          (ignore-errors (delete-file link-path)))))))

;;; Realization-owned output vocabularies -----------------------------------

(defun write-compiler-vocabulary-project (directory layout-source vocabulary-source)
  "Write a synthetic project whose selected profile owns VOCABULARY-SOURCE.

All backend spellings in these fixtures are deliberately synthetic.  Their
only claim is that the existing conservative adapters either accept or reject
their opaque atom grammar; they do not document a real keyboard profile.
"
  (compiler-test-write
   directory "project.ivory"
   "(ivory-key 1)
(import \"topology.ivory\")
(import \"layout.ivory\")
(import \"device.ivory\")
(import \"vocabulary.ivory\")
(import \"realization.ivory\")
(import \"composition.ivory\")
")
  (compiler-test-write directory "topology.ivory" +compiler-test-topology+)
  (compiler-test-write directory "layout.ivory" layout-source)
  (compiler-test-write directory "device.ivory" +compiler-test-device+)
  (compiler-test-write directory "vocabulary.ivory" vocabulary-source)
  (compiler-test-write
   directory "realization.ivory"
   "(ivory-key 1)
(define-realization vocabulary-linux
  (pipeline kanata xkb)
  (uses-output-vocabulary synthetic-output)
  (allow-grades exact emulated)
  (forbid-shell-actions yes))
")
  (compiler-test-write
   directory "composition.ivory"
   "(ivory-key 1)
(realize vocabulary-build
  (:layout vocabulary-layout)
  (:device test-device)
  (:profile vocabulary-linux))
")
  (merge-pathnames "project.ivory" directory))

(defun compiler-vocabulary-layout (behavior)
  (format nil
          "(ivory-key 1)~%(define-layout vocabulary-layout~%  (uses-topology one)~%  (binding q ~A))~%"
          behavior))

(defun compiler-vocabulary-source (backends mappings)
  (format nil
          "(ivory-key 1)~%(define-output-vocabulary synthetic-output~%  (backends ~A)~%~{  ~A~%~})~%"
          backends mappings))

(defun compiler-test-read-file (pathname)
  (with-open-file (stream pathname :direction :input :external-format :utf-8)
    (let ((content (make-string (file-length stream))))
      (read-sequence content stream)
      content)))

(deftest compiler-project-vocabulary-lowers-named-outputs-through-backend-adapters
  (with-compiler-test-directory (directory)
    (let* ((project
             (write-compiler-vocabulary-project
              directory
              (compiler-vocabulary-layout "(named-symbol synthetic-symbol)")
              (compiler-vocabulary-source
               "xkb kanata"
               '("(map-output named-symbol synthetic-symbol (:xkb \"F13\") (:kanata \"f13\"))"))))
           (output (merge-pathnames "vocabulary-build/" directory)))
      (multiple-value-bind (unit placement realization)
          (ivory-key.cli:load-project-composition-for-compilation
           project "vocabulary-build")
        (is (typep (ivory-key.cli::compiler-realization-vocabulary realization)
                   'ivory-key.model:output-vocabulary))
        (multiple-value-bind (request issues)
            (ivory-key.cli::analyze-normalized-layout
             (ivory-key.cli::compiler-unit-normalized unit) placement
             :vocabulary (ivory-key.cli::compiler-realization-vocabulary realization))
          (is request)
          (is (null issues))
          (let ((entry (first (ivory-key.backend:lowering-request-entries request))))
            (is-equal '("F13")
                      (ivory-key.backend:key-entry-outputs-for entry :xkb))
            (is-equal '("f13")
                      (ivory-key.backend:key-entry-outputs-for entry :kanata)))))
      ;; This passes through COMPILE-XKB-KANATA-REQUEST, which invokes both
      ;; adapter safety checks before WRITE-NEW-PIPELINE-RESULT can emit.
      (is (ivory-key.cli:compile-project-source
           project "vocabulary-build" :output-directory output))
      (is (search "F13"
                  (compiler-test-read-file (merge-pathnames "keymap.xkb" output))))
      (is (search "f13"
                  (compiler-test-read-file (merge-pathnames "layout.kbd" output)))))))

(deftest compiler-project-without-vocabulary-keeps-static-named-key-lowering
  (with-compiler-test-directory (directory)
    (let ((project
            (write-compiler-test-project
             directory
             :layout-source
             "(ivory-key 1)
(define-layout direct
  (uses-topology one)
  (binding q (named-key return)))
")))
      (multiple-value-bind (unit placement realization)
          (ivory-key.cli:load-project-composition-for-compilation project "direct-build")
        (is (null (ivory-key.cli::compiler-realization-vocabulary realization)))
        (multiple-value-bind (request issues)
            (ivory-key.cli::analyze-normalized-layout
             (ivory-key.cli::compiler-unit-normalized unit) placement)
          (is request)
          (is (null issues))
          (let ((entry (first (ivory-key.backend:lowering-request-entries request))))
            (is-equal '("Return")
                      (ivory-key.backend:key-entry-outputs-for entry :xkb))
            ;; No profile vocabulary means the established physical carrier
            ;; pass-through remains in force.
            (is-equal '("q")
                      (ivory-key.backend:key-entry-outputs-for entry :kanata))))))))

(deftest compiler-project-vocabulary-refuses-missing-unsupported-and-unsafe-outputs
  (dolist (case
           (list
            (list :missing-vocabulary-mapping
                  "(named-symbol needed-symbol)"
                  (compiler-vocabulary-source
                   "xkb kanata"
                   '("(map-output named-symbol other-symbol (:xkb \"F14\") (:kanata \"f14\"))")))
            (list :missing-vocabulary-backend
                  "(named-key synthetic-key)"
                  (compiler-vocabulary-source
                   "xkb"
                   '("(map-output named-key synthetic-key (:xkb \"F15\"))")))
            (list :unsupported-command-output
                  "(command synthetic-command)"
                  (compiler-vocabulary-source
                   "xkb kanata"
                   '("(map-output command synthetic-command (:xkb \"F16\") (:kanata \"f16\"))")))
            ;; The registry leaves backend grammars opaque.  A syntactically
            ;; unsafe Kanata token must therefore reach and be refused by the
            ;; existing backend boundary, never be sanitized or emitted.
            (list :backend-refusal
                  "(named-key unsafe-key)"
                  (compiler-vocabulary-source
                   "xkb kanata"
                   '("(map-output named-key unsafe-key (:xkb \"F17\") (:kanata \"unsafe;token\"))")))))
    (destructuring-bind (expected-code behavior vocabulary-source) case
      (with-compiler-test-directory (directory)
        (let* ((project
                 (write-compiler-vocabulary-project
                  directory (compiler-vocabulary-layout behavior) vocabulary-source))
               (output (merge-pathnames "refused-build/" directory)))
          (is-equal expected-code
                    (compiler-stage-code-from
                     (lambda ()
                       (ivory-key.cli:compile-project-source
                        project "vocabulary-build" :output-directory output))))
          (is (null (probe-file output))))))))

(deftest compiler-refuses-programmatic-vocabulary-profile-mismatch
  ;; Source-decoded profiles reject this in the model.  This boundary test
  ;; proves callers cannot bypass that refusal with a manually made profile.
  (let* ((vocabulary
           (ivory-key.model:make-output-vocabulary
            '("other-backend") nil))
         (profile
           (make-instance
            'ivory-key.model:realization-profile
            :name (ivory-key.model:make-identifier "mismatched-profile")
            :pipeline '("kanata" "xkb")
            :vocabulary vocabulary
            :permitted-losses '("exact")
            :metadata '(:forbid-shell-actions "yes"))))
    (is-equal :vocabulary-profile-mismatch
              (compiler-stage-code-from
               (lambda ()
                 (ivory-key.cli::compiler-realization-from-model profile))))))

(deftest compiler-project-vocabulary-maps-named-key-and-keeps-unicode-static
  (dolist (fixture
           (list
            (list "(named-key synthetic-key)"
                  (compiler-vocabulary-source
                   "xkb kanata"
                   '("(map-output named-key synthetic-key (:xkb \"F18\") (:kanata \"f18\"))"))
                  '("F18") '("f18"))
            ;; A vocabulary supplies spellings only for typed named outputs;
            ;; Unicode remains on the pre-existing static XKB/carrier path.
            (list "(unicode \"q\")"
                  (compiler-vocabulary-source "xkb kanata" nil)
                  '("U71") '("q"))))
    (destructuring-bind (behavior vocabulary-source expected-xkb expected-kanata)
        fixture
      (with-compiler-test-directory (directory)
        (let ((project
                (write-compiler-vocabulary-project
                 directory (compiler-vocabulary-layout behavior) vocabulary-source)))
          (multiple-value-bind (unit placement realization)
              (ivory-key.cli:load-project-composition-for-compilation
               project "vocabulary-build")
            (multiple-value-bind (request issues)
                (ivory-key.cli::analyze-normalized-layout
                 (ivory-key.cli::compiler-unit-normalized unit) placement
                 :vocabulary (ivory-key.cli::compiler-realization-vocabulary realization))
              (is request)
              (is (null issues))
              (let ((entry (first (ivory-key.backend:lowering-request-entries request))))
                (is-equal expected-xkb
                          (ivory-key.backend:key-entry-outputs-for entry :xkb))
                (is-equal expected-kanata
                          (ivory-key.backend:key-entry-outputs-for entry :kanata)))
              ;; The request is deliberately run through both existing
              ;; backend validators without writing any artifact.
              (is (ivory-key.backend:compile-xkb-kanata-request
                   request :allow-lossy nil)))))))))

(deftest compiler-project-explain-uses-the-selected-output-vocabulary
  (dolist (fixture
           (list
            (list "(named-symbol synthetic-symbol)"
                  (compiler-vocabulary-source
                   "xkb kanata"
                   '("(map-output named-symbol synthetic-symbol (:xkb \"F19\") (:kanata \"f19\"))"))
                  t :exact)
            (list "(named-symbol missing-symbol)"
                  (compiler-vocabulary-source
                   "xkb kanata"
                   '("(map-output named-symbol other-symbol (:xkb \"F20\") (:kanata \"f20\"))"))
                  nil :missing-vocabulary-mapping)))
    (destructuring-bind (behavior vocabulary-source expected-request expected-code)
        fixture
      (with-compiler-test-directory (directory)
        (let* ((project
                 (write-compiler-vocabulary-project
                  directory (compiler-vocabulary-layout behavior) vocabulary-source))
               (report (with-output-to-string (stream)
                         (let ((request
                                 (ivory-key.cli:explain-project-source
                                  project "vocabulary-build" :stream stream)))
                           (if expected-request
                               (is request)
                               (is (null request)))))))
          (ecase expected-code
            (:exact
             (is (search "Fidelity: exact for the current direct pipeline" report)))
            (:missing-vocabulary-mapping
             (is (search "Fidelity: unsupported" report))
             (is (search "[MISSING-VOCABULARY-MAPPING]" report)))))))))

(deftest compiler-manna-static-tables-and-function-carriers-are-proposed-exactly
  "The frozen profile may prepare only its evidenced XKB/Kanata pieces.

The resulting request is deliberately not a successful compile: it retains
the explicit selectors, semantic modifiers, missing LSGT placement, and
function activation refusals below.  This distinguishes a mechanically
complete carrier table from an invented Manna behavior.
"
  (multiple-value-bind (unit placement realization)
      (ivory-key.cli:load-project-composition-for-compilation
       "manna-cadet-project.ivory" "manna-cadet-linux")
    (multiple-value-bind (request issues)
        (ivory-key.cli::analyze-normalized-layout
         (ivory-key.cli::compiler-unit-normalized unit) placement
         :vocabulary (ivory-key.cli::compiler-realization-vocabulary realization))
      (is request)
      ;; The frozen XKB inventory has 52 tables; <LSGT> is intentionally
      ;; unplaced in the device evidence, leaving 51 lowerable physical rows.
      (is-equal 51 (length (ivory-key.backend::lowering-request-entries request)))
      (let* ((metadata (ivory-key.backend::lowering-request-metadata request))
             (carriers (getf metadata :xkb-carrier-entries))
             (allocations (getf metadata :carrier-allocations))
             (q (find "q" (ivory-key.backend::lowering-request-entries request)
                      :test #'string= :key #'ivory-key.backend:key-entry-position)))
        (is-equal 29 (length carriers))
        (is-equal 29 (length allocations))
        (is-equal
         '(183 184 185 186 187 188 189 190 191 192 193 194 195 196 197 198 199
           211 212 218 219 220 221 222 223 224 225 226 240)
         (mapcar (lambda (allocation) (getf allocation :carrier)) allocations))
        (is-equal '("U71" "U51" "Greek_theta" "Greek_THETA"
                    "upcaret" "NoSymbol" "upcaret" "NoSymbol")
                  (ivory-key.backend:key-entry-outputs-for q :xkb))
        ;; Kanata preserves the physical q event for the static XKB table.
        (is-equal '("q") (ivory-key.backend:key-entry-outputs-for q :kanata))
        (let ((macro (find "carrier-183/e"
                           carriers :test #'string=
                           :key #'ivory-key.backend:key-entry-position)))
          (is macro)
          (is-equal "I191" (ivory-key.backend:key-entry-code-for macro :xkb))
          (is-equal '("UE000")
                    (ivory-key.backend:key-entry-outputs-for macro :xkb)))
        (let* ((pipeline (ivory-key.backend:compile-xkb-kanata-request request
                                                                        :allow-lossy nil))
               (artifacts (ivory-key.backend:pipeline-result-artifacts pipeline))
               (xkb (find :xkb artifacts :key #'ivory-key.backend:pipeline-artifact-kind))
               (kanata (find :kanata artifacts :key #'ivory-key.backend:pipeline-artifact-kind)))
          (is (search "key <I191>" (ivory-key.backend:pipeline-artifact-content xkb)))
          (is (search "symbols[Group1]=[ UE000 ]"
                      (ivory-key.backend:pipeline-artifact-content xkb)))
          (is (search "(deflayer primary-function"
                      (ivory-key.backend:pipeline-artifact-content kanata)))
          (is (search "(arbitrary-code 183)"
                      (ivory-key.backend:pipeline-artifact-content kanata)))))
      (is-equal
       '(:unsupported-semantic-modifiers :unsupported-context-selection
         :unsupported-timed-interaction :unsupported-timed-interaction
         :unsupported-timed-interaction :unsupported-timed-interaction
         :missing-device-coverage :unsupported-context-selection
         :unproved-patch-activation :unsupported-context-selection)
       (mapcar #'ivory-key.cli::compiler-fidelity-issue-code issues))
      ;; Final project compilation chooses the deterministic first refusal;
      ;; it never writes a partial source proposal.
      (is-equal :unsupported-semantic-modifiers
                (compiler-stage-code-from
                 (lambda ()
                   (ivory-key.cli::make-lowering-request-from-normalized-layout
                    (ivory-key.cli::compiler-unit-normalized unit) placement
                    :vocabulary
                    (ivory-key.cli::compiler-realization-vocabulary realization))))))))
(deftest compiler-project-explain-refuses-unsafe-output-vocabulary-spelling
  ;; Opaque spelling safety remains an adapter concern.  Explain follows the
  ;; same pipeline as compile after analysis and therefore refuses this map
  ;; instead of presenting a false exact disposition.
  (with-compiler-test-directory (directory)
    (let ((project
            (write-compiler-vocabulary-project
             directory
             (compiler-vocabulary-layout "(named-key unsafe-explain-key)")
             (compiler-vocabulary-source
              "xkb kanata"
              '("(map-output named-key unsafe-explain-key (:xkb \"F21\") (:kanata \"unsafe;token\"))")))))
      (is-equal :backend-refusal
                (compiler-stage-code-from
                 (lambda ()
                   (ivory-key.cli:explain-project-source
                    project "vocabulary-build"
                    :stream (make-string-output-stream))))))))

(defparameter +compiler-test-typed-selector-policy+
  "(ivory-key 1)
(define-realization typed-selectors
  (pipeline kanata xkb)
  (allow-grades exact emulated)
  (forbid-shell-actions yes)
  (selector-policy
    (static-type q four-level two-level)
    (selector case shifted shift consumed core-shift)
    (selector script greek level-three consumed consumed-level-three)
    (selector plane top group-two group-action unproved-group-two)
    (carrier greek script greek 85 zeha)
    (carrier top plane top 84 lvl3)))
")

(deftest compiler-decodes-a-closed-typed-selector-policy-and-refuses-unproved-native-semantics
  "Policy parsing uses parser node kinds and returns one public model value.

The first realization slice transports this policy to backend inspection but
does not claim that a parseable XKB/Kanata artifact proves client-visible group
or consumed-modifier behavior.
"
  (with-compiler-test-directory (directory)
    (let* ((realization-path
             (compiler-test-write directory "realization.ivory"
                                  +compiler-test-typed-selector-policy+))
           (realization (ivory-key.cli::decode-realization-source realization-path))
           (policy (ivory-key.cli::compiler-realization-selector-policy realization))
           (layout-path (compiler-test-write directory "layout.ivory" +compiler-test-layout+))
           (topology-path (compiler-test-write directory "topology.ivory" +compiler-test-topology+))
           (device-path (compiler-test-write directory "device.ivory" +compiler-test-device+))
           (unit (ivory-key.cli::load-layout-for-compilation
                  layout-path :topology-path topology-path))
           (placement (ivory-key.cli::decode-device-source device-path)))
      (is (typep policy 'ivory-key.model::realization-selector-policy))
      (is-equal :four-level
                (ivory-key.model::realization-static-type-type
                 (ivory-key.model::realization-policy-static-type-for-position policy "q")))
      (is-equal :two-level
                (ivory-key.model::realization-static-type-group-two-type
                 (ivory-key.model::realization-policy-static-type-for-position policy "q")))
      (is-equal :level-three
                (ivory-key.model::realization-selector-control
                 (ivory-key.model::realization-policy-selector-for-axis policy "script")))
      (is-equal :unproved-group-two
                (ivory-key.model::realization-selector-client-semantics
                 (ivory-key.model::realization-policy-selector-for-axis policy "plane")))
      (is-equal 85
                (ivory-key.model::realization-carrier-linux-code
                 (ivory-key.model::realization-policy-carrier-for-position policy "greek")))
      (multiple-value-bind (request issues)
          (ivory-key.cli::analyze-normalized-layout
           (ivory-key.cli::compiler-unit-normalized unit) placement
           :selector-policy policy)
        (is (eq policy (getf (ivory-key.backend::lowering-request-metadata request)
                             :selector-policy)))
        (is-equal '(:unproved-native-selector-client-semantics)
                  (mapcar #'ivory-key.cli::compiler-fidelity-issue-code issues))
        (let ((xkb-plan
                (ivory-key.backend:lower-request
                 (ivory-key.backend:make-xkb-backend) request)))
          (is (some (lambda (result)
                      (and (eq :selector-policy
                               (ivory-key.backend:realization-feature result))
                           (eq :unsupported
                               (ivory-key.backend:realization-grade result))))
                    (ivory-key.backend:xkb-plan-realizations xkb-plan))))))))

(deftest compiler-selector-policy-rejects-stringly-and-incompatible-carrier-source
  (with-compiler-test-directory (directory)
    (let ((stringly
            (compiler-test-write
             directory "stringly.ivory"
             "(ivory-key 1)
(define-realization bad
  (pipeline kanata xkb)
  (allow-grades exact)
  (forbid-shell-actions yes)
  (selector-policy (selector case shifted \"shift\" consumed core-shift)))
")))
      (is-equal :invalid-realization-selector-policy
                (compiler-stage-code-from
                 (lambda () (ivory-key.cli::decode-realization-source stringly)))))
    (let ((bad-carrier
            (compiler-test-write
             directory "bad-carrier.ivory"
             "(ivory-key 1)
(define-realization bad
  (pipeline kanata xkb)
  (allow-grades exact)
  (forbid-shell-actions yes)
  (selector-policy (carrier greek script greek 84 zeha)))
")))
      (is-equal :incompatible-realization-carrier
                (compiler-stage-code-from
                 (lambda () (ivory-key.cli::decode-realization-source bad-carrier)))))))

(deftest compiler-project-realization-decoder-retains-the-typed-policy
  "Project loading and explicit-file inspection use the same public contract."
  (with-compiler-test-directory (directory)
    (let ((project
            (write-compiler-test-project
             directory :realization-source +compiler-test-typed-selector-policy+
             :composition-source
             "(ivory-key 1)
(realize direct-build (:layout direct) (:device test-device) (:profile typed-selectors))
")))
      (multiple-value-bind (unit placement realization)
          (ivory-key.cli:load-project-composition-for-compilation
           project "direct-build")
        (declare (ignore unit placement))
        (let ((policy (ivory-key.cli::compiler-realization-selector-policy realization)))
          (is (typep policy 'ivory-key.model::realization-selector-policy))
          (is-equal :two-level
                    (ivory-key.model::realization-static-type-group-two-type
                     (ivory-key.model::realization-policy-static-type-for-position
                      policy "q"))))))))
