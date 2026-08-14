;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Small, deliberately conservative bridge from the semantic model to the
;;;; bootstrap XKB + Kanata request protocol.

(in-package #:ivory-key.cli)

;;; This file is in IVORY-KEY.CLI for the bootstrap because that package is
;;; already part of the public system.  A later backend-planner package should
;;; own this protocol once the ASDF/package bootstrap can add one without
;;; changing this bridge's observable behavior.

(define-condition compiler-stage-error (error)
  ((stage :initarg :stage :reader compiler-stage-error-stage)
   (code :initarg :code :reader compiler-stage-error-code)
   (message :initarg :message :reader compiler-stage-error-message))
  (:report (lambda (condition stream)
             (format stream "~A [~A]: ~A"
                     (compiler-stage-error-stage condition)
                     (compiler-stage-error-code condition)
                     (compiler-stage-error-message condition)))))

(defun %stage-error (stage code control &rest arguments)
  (error 'compiler-stage-error :stage stage :code code
         :message (apply #'format nil control arguments)))

(defstruct (compiler-unit
            (:constructor %make-compiler-unit
                (pathname parsed layout normalized)))
  "The explicit successful front-end stages for one layout source."
  pathname
  parsed
  layout
  normalized)

(defstruct (compiler-placement
            (:constructor %make-compiler-placement (name topology mappings)))
  "A narrow, non-semantic device view used only at the lowering boundary.

MAPPINGS is a canonical list of (logical-position . plist) pairs.  The plist
contains only the physical spellings required by the existing bootstrap
backends.  It is intentionally not a replacement for MODEL:DEVICE-PLACEMENT.
"
  name
  topology
  mappings)

(defstruct (compiler-realization
            (:constructor %make-compiler-realization (name pipeline grades)))
  "The subset of a realization profile consumed by this bootstrap pipeline."
  name
  pipeline
  grades)

(defstruct (compiler-fidelity-issue
            (:constructor %make-compiler-fidelity-issue (feature code detail)))
  feature
  code
  detail)

;;; Safe concrete-syntax inspection -----------------------------------------

(defun %syntax-node->value (node)
  "Copy a parser node into reader-safe strings, integers, and lists.

This is intentionally local rather than using READ or evaluating any source
form.  It is only used to decode the small topology/device/profile envelope
that is not yet represented by the model decoder.
"
  (cond ((ivory-key.syntax:syntax-atom-p node)
         (ivory-key.syntax:syntax-atom-value node))
        ((ivory-key.syntax:syntax-list-p node)
         (mapcar #'%syntax-node->value
                 (ivory-key.syntax:syntax-list-children node)))
        (t (%stage-error :parse :invalid-concrete-node
                         "Parser returned an unknown concrete node ~S." node))))

(defun %parsed-values (parsed)
  (mapcar #'%syntax-node->value
          (ivory-key.syntax:syntax-parse-result-forms parsed)))

(defun %form-name (form)
  (and (consp form) (stringp (first form)) (string-downcase (first form))))

(defun %named-form-p (form name)
  (and (string= (or (%form-name form) "") name)))

(defun %find-named-form (forms name stage)
  (let ((matches (remove-if-not (lambda (form) (%named-form-p form name)) forms)))
    (cond ((null matches)
           (%stage-error stage :missing-declaration
                         "Source contains no ~A declaration." name))
          ((rest matches)
           (%stage-error stage :duplicate-declaration
                         "Source contains more than one ~A declaration." name))
          (t (first matches)))))

(defun %syntax-diagnostic-string (diagnostics)
  (with-output-to-string (stream)
    (dolist (diagnostic diagnostics)
      (format stream "~A: ~A~%"
              (ivory-key.conditions:diagnostic-code diagnostic)
              (ivory-key.conditions:diagnostic-message diagnostic)))))

(defun %parse-required-file (pathname role)
  (handler-case
      (let ((parsed (ivory-key.syntax:parse-file pathname)))
        (unless (and (ivory-key.syntax:syntax-parse-result-complete-p parsed)
                     (null (ivory-key.syntax:syntax-parse-result-diagnostics parsed)))
          (%stage-error :parse :syntax-error
                        "~A source ~A did not parse cleanly:~%~A"
                        role pathname
                        (%syntax-diagnostic-string
                         (ivory-key.syntax:syntax-parse-result-diagnostics parsed))))
        parsed)
    (compiler-stage-error (condition) (error condition))
    (error (condition)
      (%stage-error :parse :unreadable-source
                    "Cannot parse ~A source ~A: ~A" role pathname condition))))

(defun %identifier-string (value stage what)
  (unless (stringp value)
    (%stage-error stage :invalid-identifier
                  "~A must be an identifier, got ~S." what value))
  value)

(defun %option-value (forms name)
  (let ((form (find name forms :test #'string= :key #'%form-name)))
    (and form (rest form))))

;;; Optional topology decoding ----------------------------------------------

(defun decode-topology-source (pathname)
  "Decode the small checked-in topology fixture vocabulary into MODEL:TOPOLOGY.

Geometry stays descriptive: only position names are needed by the compiler
bridge, but preserving the declared labels makes validation useful to callers.
"
  (let* ((parsed (%parse-required-file pathname "topology"))
         (form (%find-named-form (%parsed-values parsed) "define-topology" :decode))
         (name (%identifier-string (second form) :decode "Topology name"))
         (positions nil))
    (dolist (clause (cddr form))
      (unless (%named-form-p clause "position")
        (%stage-error :decode :unknown-topology-clause
                      "Topology ~A has unsupported clause ~S." name clause))
      (let ((position (%identifier-string (second clause) :decode "Position name")))
        (when (find position positions :test #'ivory-key.model:identifier=
                                      :key #'ivory-key.model:position-name)
          (%stage-error :decode :duplicate-position
                        "Topology ~A declares position ~A more than once." name position))
        (push (ivory-key.model:make-logical-position position) positions)))
    (ivory-key.model:make-topology name (nreverse positions))))

(defun load-layout-for-compilation (pathname &key topology-path)
  "Run parse, typed decode, semantic validation, and normalization explicitly.

The returned COMPILER-UNIT preserves successful values from every front-end
stage.  It does not plan a backend and cannot write or deploy anything.
"
  (let* ((parsed (%parse-required-file pathname "layout"))
         (topology (and topology-path (decode-topology-source topology-path)))
         (decoded
           (handler-case
               (ivory-key.model:decode-layout-forms parsed :topology topology)
             (ivory-key.model:semantic-error (condition)
               (%stage-error :decode (ivory-key.model:semantic-error-code condition)
                             "~A" (ivory-key.model:semantic-error-message condition)))
             (error (condition)
               (%stage-error :decode :decoder-failure "~A" condition))))
         (layout
           (handler-case
               (ivory-key.model:resolve-layout decoded)
             (ivory-key.model:semantic-error (condition)
               (%stage-error :resolve (ivory-key.model:semantic-error-code condition)
                             "~A" (ivory-key.model:semantic-error-message condition)))
             (error (condition)
               (%stage-error :resolve :resolver-failure "~A" condition)))))
    (handler-case
        (ivory-key.model:validate-layout layout)
      (ivory-key.model:semantic-error (condition)
        (%stage-error :validate (ivory-key.model:semantic-error-code condition)
                      "~A" (ivory-key.model:semantic-error-message condition)))
      (error (condition)
        (%stage-error :validate :validator-failure "~A" condition)))
    (let ((normalized
            (handler-case
                ;; Validation above is intentionally a distinct reported stage.
                (ivory-key.model:normalize-layout layout :validate nil)
              (ivory-key.model:semantic-error (condition)
                (%stage-error :normalize (ivory-key.model:semantic-error-code condition)
                              "~A" (ivory-key.model:semantic-error-message condition)))
              (error (condition)
                (%stage-error :normalize :normalizer-failure "~A" condition)))))
      (%make-compiler-unit pathname parsed layout normalized))))

;;; Device and realization envelopes ----------------------------------------

(defun %backend-option (options backend position device-name)
  (let ((matching
          (remove-if-not
           (lambda (option)
             (and (consp option) (string= (or (%form-name option) "") backend)))
           options)))
    (unless (= (length matching) 1)
      (%stage-error :decode :invalid-device-placement
                    "Device ~A position ~A needs exactly one :~A spelling."
                    device-name position backend))
    (let ((values (rest (first matching))))
      (unless (and (= (length values) 1) (stringp (first values)))
        (%stage-error :decode :invalid-device-placement
                      "Device ~A position ~A has malformed :~A spelling."
                      device-name position backend))
      (first values))))

(defun decode-device-source (pathname)
  "Decode only physical placement spellings required by the bootstrap backends.

The function deliberately rejects unknown device clauses instead of inventing
backend behavior from them.  Reserved carriers remain a future allocation
input and are not silently consumed here.
"
  (let* ((parsed (%parse-required-file pathname "device"))
         (form (%find-named-form (%parsed-values parsed) "define-device" :decode))
         (name (%identifier-string (second form) :decode "Device name"))
         (clauses (cddr form))
         (topology-form (find "uses-topology" clauses :test #'string= :key #'%form-name))
         (topology (and topology-form
                        (%identifier-string (second topology-form) :decode
                                            "Device topology name")))
         (mappings nil))
    (unless topology
      (%stage-error :decode :missing-device-topology
                    "Device ~A has no USES-TOPOLOGY declaration." name))
    (dolist (clause clauses)
      (cond ((%named-form-p clause "uses-topology"))
            ((%named-form-p clause "reserve-carriers")
             ;; The resource allocator is not connected to the bootstrap
             ;; pipeline; retaining this as a no-op would disguise that fact.
             nil)
            ((%named-form-p clause "place")
             (let ((position (%identifier-string (second clause) :decode
                                                 "Placed logical position")))
               (when (assoc position mappings :test #'string=)
                 (%stage-error :decode :duplicate-device-placement
                               "Device ~A places logical position ~A more than once."
                               name position))
               (push (cons position
                           (list :xkb (%backend-option (cddr clause) "xkb" position name)
                                 :kanata (%backend-option (cddr clause) "kanata" position name)))
                     mappings)))
            (t (%stage-error :decode :unknown-device-clause
                             "Device ~A has unsupported clause ~S." name clause))))
    (%make-compiler-placement name topology
                              (sort mappings #'string< :key #'car))))

(defun decode-realization-source (pathname)
  "Decode the policy subset needed to select the XKB + Kanata bootstrap path."
  (let* ((parsed (%parse-required-file pathname "realization"))
         (form (%find-named-form (%parsed-values parsed) "define-realization" :decode))
         (name (%identifier-string (second form) :decode "Realization name"))
         (clauses (cddr form))
         (pipeline (%option-value clauses "pipeline"))
         (grades (%option-value clauses "allow-grades"))
         (forbid-shell (%option-value clauses "forbid-shell-actions")))
    (unless (equal pipeline '("kanata" "xkb"))
      (%stage-error :decode :unsupported-realization-pipeline
                    "Realization ~A must declare exactly (pipeline kanata xkb), got ~S."
                    name pipeline))
    (unless (and forbid-shell (= (length forbid-shell) 1)
                 (string= (first forbid-shell) "yes"))
      (%stage-error :decode :unsafe-realization-policy
                    "Realization ~A must explicitly forbid shell actions." name))
    (dolist (grade grades)
      (unless (member grade '("exact" "emulated" "lossy") :test #'string=)
        (%stage-error :decode :unknown-realization-grade
                      "Realization ~A allows unknown fidelity grade ~S." name grade)))
    (%make-compiler-realization name (copy-list pipeline) (copy-list grades))))

(defun %layout-topology-name (layout)
  (ivory-key.model:identifier-name
   (ivory-key.model:topology-name
    (ivory-key.model:normalized-layout-topology layout))))

(defun %placement-for-position (placement position)
  (cdr (find position (compiler-placement-mappings placement)
             :test #'ivory-key.model:identifier=
             :key #'car)))

;;; Fidelity analysis and lowering ------------------------------------------

(defun %single-unicode-keysym (text feature)
  (unless (= (length text) 1)
    (return-from %single-unicode-keysym
      (%make-compiler-fidelity-issue
       feature :unsupported-text-output
       "The bootstrap XKB/Kanata path supports one Unicode scalar per static binding.")))
  (let ((code (char-code (char text 0))))
    (if (or (> code #x10FFFF) (<= #xD800 code #xDFFF))
        (%make-compiler-fidelity-issue
         feature :invalid-unicode-scalar "Text output is not a Unicode scalar.")
        (format nil "U~X" code))))

(defparameter +named-key-lowerings+
  '(("return" "Return" "ret")
    ("backspace" "BackSpace" "bspc")
    ("delete" "Delete" "del")
    ("escape" "Escape" "esc")
    ("tab" "Tab" "tab")
    ("space" "space" "spc")
    ("left" "Left" "left")
    ("right" "Right" "right")
    ("up" "Up" "up")
    ("down" "Down" "down"))
  "Documented static named-key mappings accepted by the bootstrap pipeline.")

(defun %static-output-lowering (behavior feature)
  "Return XKB keysym, or a COMPILER-FIDELITY-ISSUE for an unsupported meaning."
  (cond
    ((typep behavior 'ivory-key.model:text-output)
     (%single-unicode-keysym (ivory-key.model:output-text behavior) feature))
    ((typep behavior 'ivory-key.model:no-output-behavior) "NoSymbol")
    ((typep behavior 'ivory-key.model:named-key-output)
     (let ((lowering (find (ivory-key.model:identifier-name
                           (ivory-key.model:named-key-name behavior))
                          +named-key-lowerings+ :test #'string= :key #'first)))
       (if lowering
           (second lowering)
           (%make-compiler-fidelity-issue
            feature :unmapped-named-key
            (format nil "Named key ~A has no approved XKB/Kanata mapping."
                    (ivory-key.model:identifier-name
                     (ivory-key.model:named-key-name behavior)))))))
    ((typep behavior 'ivory-key.model:named-symbol-output)
     (%make-compiler-fidelity-issue feature :unmapped-named-symbol
                                    "Named symbols need a profile registry mapping."))
    ((typep behavior 'ivory-key.model:command-output)
     (%make-compiler-fidelity-issue feature :unmapped-command
                                    "Semantic commands need a profile registry mapping."))
    ((typep behavior 'ivory-key.model:modifier-operation-behavior)
     (%make-compiler-fidelity-issue feature :unsupported-semantic-modifier
                                    "The bootstrap pipeline does not allocate application-visible modifiers."))
    ((typep behavior 'ivory-key.model:axis-operation-behavior)
     (%make-compiler-fidelity-issue feature :unsupported-axis-operation
                                    "The bootstrap pipeline does not lower axis state operations."))
    (t (%make-compiler-fidelity-issue
        feature :unsupported-composite-behavior
        "The bootstrap pipeline accepts only one static output per binding."))))

(defun analyze-normalized-layout (normalized placement)
  "Return a backend-neutral lowering request and every blocking fidelity issue.

The request is non-NIL only when every normalized feature is exactly
representable by the current direct XKB/Kanata path.  In particular, this
function never converts a context level, semantic modifier, interaction, or
unknown vocabulary entry into an approximate direct key mapping.
"
  (let ((issues nil)
        (entries nil))
    (unless (string= (%layout-topology-name normalized)
                     (compiler-placement-topology placement))
      (push (%make-compiler-fidelity-issue
             :topology :topology-mismatch
             (format nil "Layout topology ~A does not match device topology ~A."
                     (%layout-topology-name normalized)
                     (compiler-placement-topology placement)))
            issues))
    (when (ivory-key.model:modifier-set-members
           (ivory-key.model:normalized-layout-modifiers normalized))
      (push (%make-compiler-fidelity-issue
             :semantic-modifiers :unsupported-semantic-modifiers
             "The bootstrap pipeline has no modifier allocation or consumed-modifier plan.")
            issues))
    (dolist (interaction (ivory-key.model:normalized-layout-interactions normalized))
      (push (%make-compiler-fidelity-issue
             (ivory-key.model:identifier-name
              (ivory-key.model:normalized-interaction-name interaction))
             :unsupported-timed-interaction
             "Generic timed interactions require an explicit Kanata template lowering.")
            issues))
    (dolist (binding (ivory-key.model:normalized-layout-bindings normalized))
      (let* ((position (ivory-key.model:normalized-binding-position binding))
             (feature (ivory-key.model:identifier-name position))
             (placement-entry (%placement-for-position placement position))
             (entries-for-binding (ivory-key.model:normalized-binding-entries binding)))
        (cond
          ((null placement-entry)
           (push (%make-compiler-fidelity-issue
                  feature :missing-device-placement
                  "No physical XKB/Kanata placement is declared for this logical position.")
                 issues))
          ((/= (length entries-for-binding) 1)
           (push (%make-compiler-fidelity-issue
                  feature :unsupported-context-selection
                  "The bootstrap pipeline cannot prove exact selection of multiple abstract context entries.")
                 issues))
          (t
           (let ((xkb-output
                   (%static-output-lowering
                    (ivory-key.model:normalized-entry-behavior
                     (first entries-for-binding))
                    feature)))
             (if (typep xkb-output 'compiler-fidelity-issue)
                 (push xkb-output issues)
                 ;; Kanata forwards the device's explicit carrier spelling to
                 ;; XKB.  It must not substitute the abstract output token.
                 (push (make-instance 'ivory-key.backend:key-entry
                                      :position feature
                                      :physical-code
                                      (list :xkb (getf placement-entry :xkb)
                                            :kanata (getf placement-entry :kanata))
                                      :outputs
                                      (list :xkb (list xkb-output)
                                            :kanata (list (getf placement-entry :kanata)))
                                      )
                       entries)))))))
    (setf issues
          (sort issues #'string<
                :key (lambda (issue)
                       (format nil "~A/~A"
                               (compiler-fidelity-issue-feature issue)
                               (compiler-fidelity-issue-code issue)))))
    (if issues
        (values nil issues)
        (values (make-instance 'ivory-key.backend:lowering-request
                               :name (ivory-key.model:identifier-name
                                      (ivory-key.model:normalized-layout-name normalized))
                               :entries (nreverse entries)
                               :modifiers nil
                               :interactions nil
                               :metadata nil)
                nil))))

(defun make-lowering-request-from-normalized-layout (normalized placement)
  "Return a complete bootstrap lowering request or signal its first failure."
  (multiple-value-bind (request issues) (analyze-normalized-layout normalized placement)
    (if request
        request
        (let ((issue (first issues)))
          (%stage-error :lower (compiler-fidelity-issue-code issue)
                        "~A: ~A" (compiler-fidelity-issue-feature issue)
                        (compiler-fidelity-issue-detail issue))))))

(defun %require-compatible-realization (realization)
  (unless (equal (compiler-realization-pipeline realization) '("kanata" "xkb"))
    (%stage-error :lower :unsupported-realization-pipeline
                  "Realization ~A does not select the XKB + Kanata pipeline."
                  (compiler-realization-name realization)))
  (when (member "lossy" (compiler-realization-grades realization) :test #'string=)
    ;; The bootstrap request currently contains only exact direct mappings;
    ;; accepting a lossy profile here would be an accidental future opt-in.
    (%stage-error :lower :unsupported-lossy-policy
                  "Realization ~A permits lossy output, but this bootstrap bridge accepts exact mappings only."
                  (compiler-realization-name realization))))

(defun %compile-unit-to-pipeline (unit placement realization)
  (%require-compatible-realization realization)
  (let ((request (make-lowering-request-from-normalized-layout
                  (compiler-unit-normalized unit) placement)))
    (handler-case
        (ivory-key.backend:compile-xkb-kanata-request request :allow-lossy nil)
      (error (condition)
        (%stage-error :pipeline :backend-refusal "~A" condition)))))

;;; Deterministic inspection -------------------------------------------------

(defun %behavior-summary (behavior)
  (cond ((typep behavior 'ivory-key.model:text-output)
         (format nil "(unicode ~S)" (ivory-key.model:output-text behavior)))
        ((typep behavior 'ivory-key.model:named-key-output)
         (format nil "(named-key ~A)"
                 (ivory-key.model:identifier-name
                  (ivory-key.model:named-key-name behavior))))
        ((typep behavior 'ivory-key.model:named-symbol-output)
         (format nil "(named-symbol ~A)"
                 (ivory-key.model:identifier-name
                  (ivory-key.model:named-symbol-name behavior))))
        ((typep behavior 'ivory-key.model:command-output)
         (format nil "(command ~A)"
                 (ivory-key.model:identifier-name
                  (ivory-key.model:command-name behavior))))
        ((typep behavior 'ivory-key.model:no-output-behavior) "none")
        ((typep behavior 'ivory-key.model:modifier-operation-behavior)
         (format nil "(~A-modifier ~A)"
                 (ivory-key.model:modifier-operation behavior)
                 (ivory-key.model:identifier-name
                  (ivory-key.model:modifier-operation-modifier behavior))))
        ((typep behavior 'ivory-key.model:axis-operation-behavior)
         (format nil "(~A-axis-state ~A~@[ ~A~])"
                 (ivory-key.model:axis-operation behavior)
                 (ivory-key.model:identifier-name
                  (ivory-key.model:axis-operation-axis behavior))
                 (let ((state (ivory-key.model:axis-operation-state behavior)))
                   (and state (ivory-key.model:identifier-name state)))))
        (t (format nil "(unsupported-behavior ~A)"
                   (class-name (class-of behavior))))))

(defun normalized-layout-dump-string (normalized)
  "Produce a deterministic, backend-neutral human-readable normalized IR dump."
  (with-output-to-string (stream)
    (format stream "normalized-layout ~A~%"
            (ivory-key.model:identifier-name
             (ivory-key.model:normalized-layout-name normalized)))
    (format stream "axes~%")
    (dolist (axis (ivory-key.model:normalized-layout-axes normalized))
      (format stream "  ~A (~A): ~{~A~^ ~}~%"
              (ivory-key.model:identifier-name (ivory-key.model:axis-name axis))
              (ivory-key.model:axis-resolution axis)
              (mapcar #'ivory-key.model:identifier-name
                      (ivory-key.model:axis-states axis))))
    (format stream "modifiers: ~{~A~^ ~}~%"
            (mapcar #'ivory-key.model:identifier-name
                    (ivory-key.model:modifier-set-members
                     (ivory-key.model:normalized-layout-modifiers normalized))))
    (format stream "bindings~%")
    (dolist (binding (ivory-key.model:normalized-layout-bindings normalized))
      (format stream "  ~A [axes: ~{~A~^ ~}]~%"
              (ivory-key.model:identifier-name
               (ivory-key.model:normalized-binding-position binding))
              (mapcar #'ivory-key.model:identifier-name
                      (ivory-key.model:normalized-binding-axes binding)))
      (dolist (entry (ivory-key.model:normalized-binding-entries binding))
        (format stream "    ~A => ~A~%"
                (ivory-key.model:context-tuple-key
                 (ivory-key.model:normalized-entry-tuple entry))
                (%behavior-summary
                 (ivory-key.model:normalized-entry-behavior entry)))))
    (format stream "interactions~%")
    (dolist (interaction (ivory-key.model:normalized-layout-interactions normalized))
      (format stream "  ~A~%"
              (ivory-key.model:identifier-name
               (ivory-key.model:normalized-interaction-name interaction))))))

(defun dump-normalized-layout (normalized &optional (stream *standard-output*))
  "Write a deterministic normalized IR dump and return NORMALIZED.

This exported wrapper deliberately accepts an already normalized model.  The
CLI owns source parsing and stage selection; embedding callers can inspect the
backend-neutral value without re-running any source stage.
"
  (write-string (normalized-layout-dump-string normalized) stream)
  normalized)

(defun level-report-string (normalized)
  "Show dependency-scoped canonical level rows, without implying a backend cap."
  (with-output-to-string (stream)
    (format stream "levels for ~A~%"
            (ivory-key.model:identifier-name
             (ivory-key.model:normalized-layout-name normalized)))
    (dolist (binding (ivory-key.model:normalized-layout-bindings normalized))
      (format stream "~A~%"
              (ivory-key.model:identifier-name
               (ivory-key.model:normalized-binding-position binding)))
      (loop for entry in (ivory-key.model:normalized-binding-entries binding)
            for number from 1 do
              (format stream "  ~D  ~A  ~A~%" number
                      (ivory-key.model:context-tuple-key
                       (ivory-key.model:normalized-entry-tuple entry))
                       (%behavior-summary
                       (ivory-key.model:normalized-entry-behavior entry)))))))

(defun simulate-layout-events (&rest arguments)
  "Refuse a whole-layout simulation until the public adapter can represent it.

The exported simulator has an event-machine API, but its model adapter is not
currently public and cannot dispatch ordinary normalized bindings.  Keeping a
named refusal here prevents callers from accidentally treating interaction-
only simulation as complete layout semantics.
"
  (declare (ignore arguments))
  (%stage-error :simulate :simulation-adapter-unavailable
                "The public simulator API cannot yet simulate a complete normalized layout."))

;;; Non-destructive build emission ------------------------------------------

(defun %safe-output-directory (pathname)
  (let* ((directory (uiop:ensure-directory-pathname pathname))
         (components (pathname-directory directory))
         (marker (first components))
         (leaf (car (last components))))
    (unless (and (member marker '(:relative :absolute))
                 (stringp leaf)
                 (not (member :up components)))
      (%stage-error :emit :unsafe-output-directory
                    "Output directory ~A must name one concrete directory without parent traversal."
                    pathname))
    (when (probe-file directory)
      (%stage-error :emit :output-already-exists
                    "Refusing to overwrite existing output directory ~A." directory))
    directory))

(defun %parent-directory (directory)
  (let* ((components (pathname-directory directory))
         (parent-components (butlast components)))
    (make-pathname :directory parent-components :name nil :type nil :defaults directory)))

(defun %fresh-sibling-directory (output-directory)
  (let* ((parent (%parent-directory output-directory))
         (leaf (car (last (pathname-directory output-directory)))))
    (ensure-directories-exist (merge-pathnames "placeholder" parent))
    (loop for counter from 0 below 1000
          for candidate =
            (merge-pathnames (format nil ".~A.ivory-key-tmp-~D/" leaf counter) parent)
          unless (probe-file candidate) return candidate
          finally (%stage-error :emit :temporary-directory-exhausted
                                "Could not reserve a fresh temporary sibling for ~A."
                                output-directory))))

(defun %safe-artifact-relative-path-p (path)
  (and (stringp path)
       (plusp (length path))
       (not (find #\Newline path))
       (not (find #\Return path))
       (not (find #\\ path))
       (not (find #\/ path))
       (not (search ".." path))))

(defun %write-report-file (pipeline-result directory)
  (with-open-file (stream (merge-pathnames "REPORT.txt" directory)
                          :direction :output :if-exists :error :if-does-not-exist :create)
    (write-string (ivory-key.report:realization-report-string pipeline-result) stream)
    (format stream "~%Validation: not run by compile; use validate-build for tool evidence.~%")))

(defun write-new-pipeline-result (pipeline-result output-directory)
  "Write a new build through a fresh sibling directory, never overwriting.

The current backend API owns deterministic artifact text but not atomic output
handling.  This wrapper supplies the latter and deliberately does not invoke
external validators or deployment machinery.
"
  (let* ((target (%safe-output-directory output-directory))
         (temporary (%fresh-sibling-directory target))
         (moved nil))
    (dolist (artifact (ivory-key.backend:pipeline-result-artifacts pipeline-result))
      (unless (%safe-artifact-relative-path-p
               (ivory-key.backend:pipeline-artifact-relative-path artifact))
        (%stage-error :emit :unsafe-artifact-path
                      "Backend returned unsafe artifact path ~S."
                      (ivory-key.backend:pipeline-artifact-relative-path artifact))))
    (unwind-protect
         (progn
           (ivory-key.backend:write-pipeline-result pipeline-result temporary)
           (%write-report-file pipeline-result temporary)
           ;; TEMPORARY is a sibling of TARGET, making this a same-filesystem
           ;; rename on ordinary filesystems.  TARGET was proven absent above.
           (rename-file temporary target)
           (setf moved t)
           target)
      (unless moved
        (when (probe-file temporary)
          (uiop:delete-directory-tree temporary :validate t))))))

(defun compile-layout-source (layout-path &key topology-path device-path
                                          realization-path output-directory)
  "Compile one fully-supported layout into a new non-deploying build directory."
  (unless (and device-path realization-path output-directory)
    (%stage-error :arguments :missing-compile-input
                  "Compile requires layout, device, realization, and output paths."))
  (let* ((unit (load-layout-for-compilation layout-path :topology-path topology-path))
         (placement (decode-device-source device-path))
         (realization (decode-realization-source realization-path))
         (pipeline-result (%compile-unit-to-pipeline unit placement realization)))
    (write-new-pipeline-result pipeline-result output-directory)
    pipeline-result))

(defun explain-layout-source (layout-path &key topology-path device-path realization-path
                                          (stream *standard-output*))
  "Print an exact-or-refused pipeline explanation without emitting artifacts."
  (let* ((unit (load-layout-for-compilation layout-path :topology-path topology-path))
         (placement (decode-device-source device-path))
         (realization (decode-realization-source realization-path)))
    (%require-compatible-realization realization)
    (multiple-value-bind (request issues)
        (analyze-normalized-layout (compiler-unit-normalized unit) placement)
      (format stream "Ivory Key capability explanation~%")
      (format stream "Layout: ~A~%Device: ~A~%Realization: ~A~%"
              (ivory-key.model:identifier-name
               (ivory-key.model:normalized-layout-name (compiler-unit-normalized unit)))
              (compiler-placement-name placement)
              (compiler-realization-name realization))
      (if issues
          (progn
            (format stream "Fidelity: unsupported~%")
            (dolist (issue issues)
              (format stream "  ~A [~A]: ~A~%"
                      (compiler-fidelity-issue-feature issue)
                      (compiler-fidelity-issue-code issue)
                      (compiler-fidelity-issue-detail issue)))
            nil)
          (let ((result (%compile-unit-to-pipeline unit placement realization)))
            (format stream "Fidelity: exact for the current direct pipeline~%")
            (write-string (ivory-key.report:realization-report-string result) stream)
            request)))))

(defun validate-build-directory (directory)
  "Return explicit tool-validation dispositions for an emitted build directory.

An unavailable executable is reported as :UNAVAILABLE rather than a pass.
This function neither mutates the build nor contacts a device.
"
  (let ((build (uiop:ensure-directory-pathname directory)))
    (unless (probe-file build)
      (%stage-error :validate-build :missing-build-directory
                    "Build directory ~A does not exist." build))
    (loop for kind in '(:xkb :kanata)
          for filename in '("keymap.xkb" "layout.kbd")
          for backend = (ecase kind
                          (:xkb (ivory-key.backend:make-xkb-backend))
                          (:kanata (ivory-key.backend:make-kanata-backend)))
          for artifact = (merge-pathnames filename build)
          collect
          (cond ((not (probe-file artifact))
                 (list :kind kind :status :missing :path artifact))
                ((not (%validation-program-available-p backend))
                 (list :kind kind :status :unavailable :path artifact
                       :program (ivory-key.backend:capability-validation-program
                                 (ivory-key.backend:capabilities backend))))
                (t (multiple-value-bind (success output arguments)
                       (ivory-key.backend:validate-artifact backend artifact)
                     (list :kind kind :status (if success :passed :failed)
                           :path artifact :output output :arguments arguments)))))))

(defun %validation-program-available-p (backend)
  (let ((program (ivory-key.backend:capability-validation-program
                  (ivory-key.backend:capabilities backend))))
    (and program
         (handler-case
             (progn
               (uiop:run-program (list program "--version")
                                 :output :string :error-output :output)
               t)
           (error () nil)))))
