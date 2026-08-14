;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;;
;;;; Tagged generated-XKB selector state probe; not an ASDF component.
;;;;
;;;; Invoke from the Ivory Key checkout root:
;;;;   sbcl --script tests/external/manna-xkb-group2-state.lisp MANNA-ROOT
;;;;   sbcl --script tests/external/manna-xkb-group2-state.lisp --generated-only MANNA-ROOT
;;;;
;;;; It verifies the hash-addressed frozen Manna review inputs, then creates
;;;; closed Ivory Key generated XKB selector maps and exercises those emitted
;;;; artifacts through libxkbcommon.  The generated-only mode is for a host
;;;; whose xkeyboard-config data cannot satisfy the separately pinned frozen
;;;; map observation; it preserves the same byte hash gate.  Neither mode
;;;; compiles the frozen map as equivalent or invokes Kanata, a device, or a
;;;; client protocol.

(require "asdf")

(defpackage #:ivory-key.external-manna-xkb-group2-state
  (:use #:cl))

(in-package #:ivory-key.external-manna-xkb-group2-state)

(defparameter +external-validation-tag+ :external-manna-xkb-group2-state)

(defparameter +frozen-validation-tag+ :external-manna-frozen-xkb-group2-state)

(defparameter +frozen-manna-inputs+
  '(("xkb/symbols/spacecadet"
     "b559d8832462556f990bee273b53a91ab2c6c81fc7e2fa9c9bb0cdfce739f3a0")
    ("xkb/keymap/spacecadet.xkb"
     "68dcb0f3c77fa2b88cfc2db04347b07089efad25a2bcf8b86324a5f283539fba")
    ("kanata/kinesis.advantage2.layered.kanata.kbd"
     "d36a93eab6e2355707f7a6bfbcfac2a4e3b0ea361cc399d388543f51e1f5226b")
    ("kanata/kinesis.advantage360.layered.kanata.kbd"
     "632a7574938b535a8d4b1d2e3ce1c5f711d0486298d2ce4d98adda702496df5a")
    ("space-cadet-layered-mnemonics.md"
     "8c4c975e0acee03f96f51ae144f2c12c1efc249672b4ef50e39a781e8f27bc7b")))

(defun repository-root ()
  "Return the Ivory Key root from this script's stable load pathname."
  (let* ((script (or *load-pathname* *compile-file-pathname*
                     (error "External validation needs a load pathname.")))
         (external-directory
           (uiop:pathname-directory-pathname (truename script)))
         (tests-directory
           (uiop:pathname-parent-directory-pathname external-directory)))
    (uiop:pathname-parent-directory-pathname tests-directory)))

(defun load-ivory-key ()
  "Load exactly this checkout's core system, excluding the external probe."
  (let ((root (repository-root)))
    (asdf:load-asd (merge-pathnames "ivory-key.asd" root))
    (asdf:load-system "ivory-key")))

;; LOAD reads one form at a time, so make the generated-map packages exist
;; before it reads the package-qualified forms below.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (load-ivory-key))

(defun source-root (argument)
  "Resolve one existing Manna checkout directory without accepting a default."
  (let ((pathname (uiop:ensure-directory-pathname (pathname argument))))
    (unless (uiop:directory-exists-p pathname)
      (error "Frozen Manna checkout is not a directory: ~A" argument))
    (truename pathname)))

(defun require-frozen-inputs (root)
  "Reject any checkout whose reviewed historical source inputs differ in bytes."
  (dolist (entry +frozen-manna-inputs+)
    (destructuring-bind (relative expected) entry
      (let ((pathname (merge-pathnames relative root)))
        (unless (probe-file pathname)
          (error "Frozen Manna input is absent: ~A" pathname))
        (let* ((result (uiop:run-program
                        (list "sha256sum" (namestring pathname))
                        :output :string :error-output :output))
               (actual (subseq result 0 64)))
          (unless (string= actual expected)
            (error "Frozen Manna input hash differs for ~A: ~A"
                   relative actual)))))))

(defun split-tool-flags (text)
  "Split PKG-CONFIG flags without invoking a shell."
  (remove ""
          (uiop:split-string text
                             :separator '(#\Space #\Tab #\Newline #\Return))
          :test #'string=))

(defun temporary-directory ()
  (let ((directory
          (merge-pathnames
           (format nil "ivory-key-generated-xkb-selector-state-~A/"
                   (symbol-name (gensym "VALIDATION-")))
           (uiop:temporary-directory))))
    (ensure-directories-exist (merge-pathnames "placeholder" directory))
    directory))

(defun compile-probe (directory)
  "Compile the checked-in C probe with literal argv elements."
  (let* ((source (merge-pathnames "tests/external/manna-xkb-group2-state.c"
                                  (repository-root)))
         (binary (merge-pathnames "manna-xkb-group2-state" directory))
         (flags
           (split-tool-flags
            (uiop:run-program '("pkg-config" "--cflags" "--libs" "xkbcommon")
                              :output :string :error-output :output)))
         (arguments
           (append (list "gcc" "-std=c11" "-Wall" "-Wextra" "-Werror"
                         (namestring source) "-o" (namestring binary))
                   flags)))
    (uiop:run-program arguments :output :string :error-output :output)
    binary))

(defun generated-selector-context (case script plane)
  (ivory-key.model:make-context-tuple
   (list (cons "case" case) (cons "script" script) (cons "plane" plane))))

(defun generated-selector-policy (&key (group-one-type :four-level-alphabetic))
  "Return the sole typed policy whose emitted state boundary is probed here."
  (ivory-key.model:make-realization-selector-policy
   (list (ivory-key.model:make-realization-static-type
          "q" group-one-type :two-level))
   (list
    (ivory-key.model:make-realization-context-selector
     "case" "shifted" :shift :consumed :core-shift)
    (ivory-key.model:make-realization-context-selector
     "script" "greek" :level-three :consumed :consumed-level-three)
    (ivory-key.model:make-realization-context-selector
     "plane" "top" :group-two :group-action
     :libxkbcommon-depressed-group-two-with-visible-level-three))
   (list
    (ivory-key.model:make-realization-direct-carrier
     "greek" "script" "greek" 85 :zeha)
    (ivory-key.model:make-realization-direct-carrier
     "top" "plane" "top" 84 :lvl3))))

(defun generated-selector-entry ()
  "One canonical first-axis-varies-fastest table for the emitted-map probe."
  (make-instance
   'ivory-key.backend:key-entry
   :position "q"
   :physical-code (list :xkb "AD01")
   :outputs (list :xkb '("q" "Q" "Greek_theta" "Greek_THETA"
                          "upcaret" "NoSymbol" "upcaret" "NoSymbol"))
   :sources
   (mapcar (lambda (states)
             (ivory-key.backend:make-key-entry-source
              (apply #'generated-selector-context states)))
           '(("plain" "roman" "base")
             ("shifted" "roman" "base")
             ("plain" "greek" "base")
             ("shifted" "greek" "base")
             ("plain" "roman" "top")
             ("shifted" "roman" "top")
             ("plain" "greek" "top")
             ("shifted" "greek" "top")))))

(defun generated-selector-keymap (directory group-one-type)
  "Emit the closed XKB-only carrier contract after its exact lowerer grade."
  (let* ((backend (ivory-key.backend:make-xkb-backend))
         (request
           (make-instance
            'ivory-key.backend:lowering-request
            :name "generated-selector-state"
            :entries (list (generated-selector-entry))
            :metadata
            (list :selector-policy
                  (generated-selector-policy :group-one-type group-one-type))))
         (plan (ivory-key.backend:lower-request backend request))
         (selector-result
           (find :selector-policy
                 (ivory-key.backend:xkb-plan-realizations plan)
                 :key #'ivory-key.backend:realization-feature))
         (pathname
           (merge-pathnames
            (format nil "generated-selector-keymap-~(~A~).xkb" group-one-type)
            directory)))
    (unless (and selector-result
                 (eq (ivory-key.backend:realization-grade selector-result) :exact))
      (error "Generated selector map was not granted the required exact XKB grade."))
    (with-open-file (stream pathname :direction :output :if-exists :error
                                     :if-does-not-exist :create
                                     :external-format :utf-8)
      ;; The selected allocation has only 84/LVL3 and 85/ZEHA.  pc+us may
      ;; still contribute inherited LVL5 behavior outside the selected input
      ;; domain; the C state probe checks that compiled-map boundary.
      (write-string (ivory-key.backend:emit-plan-to-string backend plan) stream))
    pathname))

(defun generated-manna-selector-keymap (directory)
  "Emit the actual selected 51-override Manna XKB partial request for probing.

This deliberately lowers XKB directly after compiler inspection.  The same
request remains ineligible for the combined XKB/Kanata pipeline because no
Kanata selector action/lifetime implementation exists.
"
  (multiple-value-bind (unit placement realization)
      (ivory-key.cli:load-project-composition-for-compilation
       "manna-cadet-project.ivory" "manna-cadet-linux")
    (multiple-value-bind (request issues)
        (ivory-key.cli::analyze-normalized-layout
         (ivory-key.cli::compiler-unit-normalized unit) placement
         :vocabulary (ivory-key.cli::compiler-realization-vocabulary realization)
         :selector-policy
         (ivory-key.cli::compiler-realization-selector-policy realization))
      (unless request
        (error "Manna selector probe could not construct an inspection request."))
      (dolist (required-issue
               '(:unsupported-kanata-selector-action-plan
                 :unsupported-semantic-modifiers
                 :unsupported-timed-interaction
                 :unreachable-device-position
                 :unproved-patch-activation))
        (unless (member required-issue issues
                        :key #'ivory-key.cli::compiler-fidelity-issue-code)
          (error "Manna selector probe lost required final-pipeline refusal ~S."
                 required-issue)))
      (let* ((backend (ivory-key.backend:make-xkb-backend))
             (plan (ivory-key.backend:lower-request backend request))
             (static-entries
               (ivory-key.backend::xkb-plan-selector-static-entries plan))
             (selector-result
               (find :selector-policy
                     (ivory-key.backend:xkb-plan-realizations plan)
                     :key #'ivory-key.backend:realization-feature))
             (pathname (merge-pathnames "generated-manna-selector-keymap.xkb"
                                        directory)))
        (unless (and selector-result
                     (eq (ivory-key.backend:realization-grade selector-result)
                         :exact)
                     (= (length static-entries) 51)
                     (null (find "less-greater" static-entries :test #'string=
                                 :key
                                 (lambda (static-entry)
                                   (ivory-key.backend:key-entry-position
                                    (ivory-key.backend::xkb-selector-static-entry-entry
                                     static-entry))))))
          (error "Manna generated XKB partial request is not exactly its 51 selected static overrides."))
        (with-open-file (stream pathname :direction :output :if-exists :error
                                       :if-does-not-exist :create
                                       :external-format :utf-8)
          (write-string (ivory-key.backend:emit-plan-to-string backend plan)
                        stream))
        pathname))))

(defun run-probe (root &key (frozen-mode-p t))
  "Run distinct frozen-map and generated-map state contracts.

The hash gate fixes the source review set.  The frozen mode preserves the
historical LVL3/LVL5 and absent-ZEHA observation; the generated mode proves
only the separately selected typed carrier contract.
"
  (require-frozen-inputs root)
  (let ((directory (temporary-directory)))
    (unwind-protect
         (let* ((binary (compile-probe directory))
                (frozen-keymap (merge-pathnames "xkb/keymap/spacecadet.xkb" root))
                (frozen-includes (merge-pathnames "xkb/" root))
                (frozen-output
                  (when frozen-mode-p
                    (uiop:run-program
                     (list (namestring binary) "--frozen"
                           (namestring frozen-keymap) (namestring frozen-includes))
                     :output :string :error-output :output)))
                (generated-outputs
                  (loop for group-one-type in '(:four-level :four-level-alphabetic)
                        for keymap =
                          (generated-selector-keymap directory group-one-type)
                        collect
                        (cons group-one-type
                              (uiop:run-program
                               (list (namestring binary) (namestring keymap))
                               :output :string :error-output :output))))
                (manna-output
                  (uiop:run-program
                   (list (namestring binary)
                         (namestring (generated-manna-selector-keymap directory)))
                   :output :string :error-output :output)))
           (when frozen-mode-p
             (unless (search "FROZEN-MANNA-XKB-GROUP2-STATE: PASSED" frozen-output)
               (error "Frozen Manna XKB state probe did not pass:~%~A"
                      frozen-output)))
           (dolist (generated-output generated-outputs)
             (unless (search "GENERATED-XKB-SELECTOR-STATE: PASSED"
                             (cdr generated-output))
               (error "Generated XKB selector state probe did not pass for ~S:~%~A"
                      (car generated-output) (cdr generated-output))))
           (unless (search "GENERATED-XKB-SELECTOR-STATE: PASSED" manna-output)
             (error "Generated full Manna XKB partial request state probe did not pass:~%~A"
                    manna-output))
           (when frozen-mode-p
             (format t "EXTERNAL-VALIDATION ~S: PASSED (frozen LVL3/LVL5 state observation retained).~%"
                     +frozen-validation-tag+))
           (format t "EXTERNAL-VALIDATION ~S: PASSED (generated FOUR_LEVEL and FOUR_LEVEL_ALPHABETIC XKB/libxkbcommon selector contracts).~%"
                   +external-validation-tag+)
           (format t "EXTERNAL-VALIDATION ~S: PASSED (generated 51-override Manna XKB partial request only).~%"
                   +external-validation-tag+)
           :passed)
      (when (probe-file directory)
        (uiop:delete-directory-tree directory :validate t)))))

(defun external-command-line-arguments ()
  "Return script arguments on the two checked Common Lisp implementations."
  #+ecl
  (let ((shell (member "-shell" si:*command-args* :test #'string=)))
    (if shell
        (cddr shell)
        (uiop:command-line-arguments)))
  #-ecl
  (uiop:command-line-arguments))

(defun main ()
  (let ((arguments (external-command-line-arguments)))
    (cond ((= (length arguments) 1)
           (run-probe (source-root (first arguments))))
          ((and (= (length arguments) 2)
                (string= (first arguments) "--generated-only"))
           (run-probe (source-root (second arguments)) :frozen-mode-p nil))
          (t (error "Usage: manna-xkb-group2-state.lisp [--generated-only] MANNA-ROOT")))))

(handler-case
    (progn
      (main)
      (uiop:quit 0))
  (error (condition)
    (format *error-output* "EXTERNAL-VALIDATION ~S: FAILED~%~A~%"
            +external-validation-tag+ condition)
    (uiop:quit 1)))
