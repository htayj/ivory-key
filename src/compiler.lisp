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
            (:constructor %make-compiler-realization
                (name pipeline grades vocabulary)))
  "The subset of a realization profile consumed by this bootstrap pipeline."
  name
  pipeline
  grades
  ;; NIL means the established direct static table is selected.  A non-NIL
  ;; vocabulary is realization-owned data resolved by the project loader; it
  ;; is never inferred from a layout binding or direct source file.
  vocabulary)

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

;;; Project composition front end -------------------------------------------

(defun %project-metadata-value (metadata key stage code description)
  "Read one closed project metadata field without inventing a default.

Project metadata is model data produced by IVORY-KEY.PROJECT, rather than
concrete source syntax.  The compiler still treats the narrow backend bridge
metadata as an input boundary: a missing or malformed value is a refusal, not
a reason to guess a physical spelling or safety policy.
"
  (unless (listp metadata)
    (%stage-error stage code "~A metadata is malformed." description))
  (let ((marker (gensym "MISSING-METADATA-")))
    (let ((value (getf metadata key marker)))
      (if (eq value marker)
          (%stage-error stage code "~A metadata is missing ~S." description key)
          value))))

(defun compiler-placement-from-model (device)
  "Convert project DEVICE placement metadata for the exact bootstrap bridge.

The semantic model deliberately keeps physical inputs opaque.  The project
loader records the two approved backend spellings under :BACKEND-MAPPINGS;
this conversion accepts only that already-decoded representation and does not
parse source or infer carrier codes from the generic placement association
list.
"
  (unless (typep device 'ivory-key.model:device-placement)
    (%stage-error :decode :invalid-project-device
                  "Project composition device is not a model device placement."))
  (let ((mappings
          (%project-metadata-value
           (ivory-key.model:placement-metadata device) :backend-mappings
           :decode :missing-device-backend-mappings
           (format nil "Device ~A"
                   (ivory-key.model:identifier-name
                    (ivory-key.model:placement-name device))))))
    (unless (listp mappings)
      (%stage-error :decode :invalid-device-backend-mappings
                    "Device backend mappings must be a list."))
    (let ((seen (make-hash-table :test #'equal))
          (converted nil))
      (dolist (mapping mappings)
        (unless (and (consp mapping) (stringp (car mapping))
                     (listp (cdr mapping)))
          (%stage-error :decode :invalid-device-backend-mappings
                        "Device backend mapping ~S is malformed." mapping))
        (let* ((position (car mapping))
               (spellings (cdr mapping))
               (xkb (getf spellings :xkb))
               (kanata (getf spellings :kanata)))
          (when (gethash position seen)
            (%stage-error :decode :duplicate-device-placement
                          "Device declares backend placement for ~A more than once."
                          position))
          (unless (and (= (length spellings) 4)
                       (stringp xkb) (plusp (length xkb))
                       (stringp kanata) (plusp (length kanata)))
            (%stage-error :decode :invalid-device-backend-mappings
                          "Device backend mapping for ~A needs one non-empty :XKB and :KANATA spelling."
                          position))
          (setf (gethash position seen) t)
          (push (cons position (list :xkb xkb :kanata kanata)) converted)))
      (%make-compiler-placement
       (ivory-key.model:identifier-name (ivory-key.model:placement-name device))
       (ivory-key.model:identifier-name
        (ivory-key.model:topology-name
         (ivory-key.model:placement-topology device)))
       (sort converted #'string< :key #'car)))))

(defun compiler-realization-from-model (realization)
  "Convert a project realization profile for the exact bootstrap bridge."
  (unless (typep realization 'ivory-key.model:realization-profile)
    (%stage-error :decode :invalid-project-realization
                  "Project composition profile is not a realization profile."))
  (let ((forbid-shell
          (%project-metadata-value
           (ivory-key.model:realization-profile-metadata realization)
           :forbid-shell-actions :decode :unsafe-realization-policy
           (format nil "Realization ~A"
                   (ivory-key.model:identifier-name
                    (ivory-key.model:realization-profile-name realization))))))
    (unless (and (stringp forbid-shell) (string= forbid-shell "yes"))
      (%stage-error :decode :unsafe-realization-policy
                    "Realization ~A must explicitly forbid shell actions."
                    (ivory-key.model:identifier-name
                     (ivory-key.model:realization-profile-name realization))))
    (let ((pipeline (ivory-key.model:realization-profile-pipeline realization))
          (grades (ivory-key.model:realization-profile-permitted-losses realization))
          (vocabulary (ivory-key.model:realization-profile-vocabulary realization)))
      (unless (and (listp pipeline) (every #'stringp pipeline)
                   (listp grades) (every #'stringp grades))
        (%stage-error :decode :invalid-project-realization
                      "Realization ~A has malformed pipeline policy."
                      (ivory-key.model:identifier-name
                       (ivory-key.model:realization-profile-name realization))))
      ;; The project loader retains the broader vocabulary needed for future
      ;; planners.  This direct bridge deliberately recognizes only the same
      ;; grade vocabulary as its explicit-file decoder; a profile that opts
      ;; into an unsupported future disposition cannot become an implicit
      ;; approval for this bootstrap lowering.
      (dolist (grade grades)
        (unless (member grade '("exact" "emulated" "lossy") :test #'string=)
          (%stage-error :decode :unknown-realization-grade
                        "Realization ~A allows unsupported bootstrap grade ~S."
                        (ivory-key.model:identifier-name
                         (ivory-key.model:realization-profile-name realization))
                        grade)))
      ;; The model validates this invariant for source-decoded profiles.  Keep
      ;; it at the compiler boundary too: callers can construct model objects
      ;; programmatically, and a vocabulary cannot silently describe a
      ;; backend which the selected profile does not run.
      (when vocabulary
        (unless (typep vocabulary 'ivory-key.model:output-vocabulary)
          (%stage-error :decode :invalid-project-vocabulary
                        "Realization ~A has a non-vocabulary output mapping."
                        (ivory-key.model:identifier-name
                         (ivory-key.model:realization-profile-name realization))))
        (dolist (backend (ivory-key.model:output-vocabulary-backends vocabulary))
          (unless (member (ivory-key.model:identifier-name backend)
                          pipeline :test #'string=)
            (%stage-error :decode :vocabulary-profile-mismatch
                          "Realization ~A selects no backend named ~A for its output vocabulary."
                          (ivory-key.model:identifier-name
                           (ivory-key.model:realization-profile-name realization))
                          (ivory-key.model:identifier-name backend)))))
      (%make-compiler-realization
       (ivory-key.model:identifier-name
        (ivory-key.model:realization-profile-name realization))
       (copy-list pipeline) (copy-list grades) vocabulary))))

(defun %project-layout-compiler-unit (project-path layout)
  "Normalize an already validated project layout without a second source load."
  (let ((normalized
          (handler-case
              ;; LOAD-PROJECT has already decoded, resolved, and validated the
              ;; selected layout.  Retaining this distinct normalization stage
              ;; avoids changing the compiler IR while avoiding unsafe reparse.
              (ivory-key.model:normalize-layout layout :validate nil)
            (ivory-key.model:semantic-error (condition)
              (%stage-error :normalize (ivory-key.model:semantic-error-code condition)
                            "~A" (ivory-key.model:semantic-error-message condition)))
            (error (condition)
              (%stage-error :normalize :normalizer-failure "~A" condition)))))
    (%make-compiler-unit project-path nil layout normalized)))

(defun load-project-composition-for-compilation (project-path composition-name
                                                   &key source-roots)
  "Load one named project composition for inspection or exact compilation.

Returns five values: the compiler unit, bootstrap placement, realization,
composition, and complete project result.  The project loader remains the only
component that resolves imports and source roots; this bridge consumes only
its resolved registries and typed composition values.
"
  (let* ((project (ivory-key.project:load-project project-path
                                                   :source-roots source-roots))
         ;; ERRORP deliberately preserves the project loader's stable unknown
         ;; definition condition instead of silently selecting another layout.
         (composition (ivory-key.project:project-composition
                       project composition-name :errorp t))
         (layout (ivory-key.project:project-realization-composition-layout
                  composition))
         (device (ivory-key.project:project-realization-composition-device
                  composition))
         (realization
           (ivory-key.project:project-realization-composition-realization
            composition)))
    (values (%project-layout-compiler-unit project-path layout)
            (compiler-placement-from-model device)
            (compiler-realization-from-model realization)
            composition
            project)))

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
    ;; Output vocabularies are project declarations and may be imported or
    ;; forward-referenced.  The one-file compiler intentionally has no
    ;; project graph to resolve them, so refusing is safer than discarding a
    ;; selected profile contract and falling back to the static table.
    (when (find "uses-output-vocabulary" clauses :test #'string= :key #'%form-name)
      (%stage-error :decode :unsupported-single-file-vocabulary
                    "Realization ~A selects an output vocabulary; use project compilation to resolve it."
                    name))
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
    (%make-compiler-realization name (copy-list pipeline) (copy-list grades) nil)))

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

(defun %vocabulary-spelling-for-output (vocabulary behavior backend feature)
  "Resolve one opaque profile spelling, retaining model failures as lowering data.

The vocabulary model owns identity validation; this compiler boundary turns
its closed diagnostics into an ordinary fidelity refusal so the caller cannot
partially emit a build after a missing mapping.
"
  (handler-case
      (ivory-key.model:output-vocabulary-spelling-for-output
       vocabulary behavior backend)
    (ivory-key.model:semantic-error (condition)
      (%make-compiler-fidelity-issue
       feature
       (case (ivory-key.model:semantic-error-code condition)
         (:unknown-vocabulary-backend :missing-vocabulary-backend)
         (:missing-vocabulary-mapping :missing-vocabulary-mapping)
         (:unsupported-vocabulary-output :unsupported-vocabulary-output)
         (otherwise :invalid-output-vocabulary))
       (ivory-key.model:semantic-error-message condition)))))

(defun %profile-output-lowering (behavior feature vocabulary)
  "Return (:XKB SPELLING :KANATA SPELLING), or one fidelity issue.

Both selected direct backends need an explicit spelling for a typed semantic
output.  We resolve both before accepting the entry, which makes a missing
backend or identity mapping fail before the backend adapters see a request.
Commands still have no conservative direct lowering, even if a vocabulary
contains opaque spellings for them: neither selected backend advertises a
semantic command capability.
"
  (let ((xkb-output
          (%vocabulary-spelling-for-output vocabulary behavior "xkb" feature)))
    (if (typep xkb-output 'compiler-fidelity-issue)
        xkb-output
        (let ((kanata-output
                (%vocabulary-spelling-for-output vocabulary behavior "kanata" feature)))
          (if (typep kanata-output 'compiler-fidelity-issue)
              kanata-output
              (if (typep behavior 'ivory-key.model:command-output)
                  (%make-compiler-fidelity-issue
                   feature :unsupported-command-output
                   "The direct XKB/Kanata pipeline has no approved semantic command lowering.")
                  (list :xkb xkb-output :kanata kanata-output)))))))

(defun %output-lowering (behavior feature vocabulary)
  "Return backend outputs for one static binding, or a fidelity issue.

Only typed named outputs consult a selected realization vocabulary.  Unicode
and no-output behavior retain their established static lowering and Kanata
carrier forwarding; modifier, selector, interaction, and composite refusals
remain entirely unchanged.
"
  (if (and vocabulary
           (or (typep behavior 'ivory-key.model:named-key-output)
               (typep behavior 'ivory-key.model:named-symbol-output)
               (typep behavior 'ivory-key.model:command-output)))
      (%profile-output-lowering behavior feature vocabulary)
      (let ((xkb-output (%static-output-lowering behavior feature)))
        (if (typep xkb-output 'compiler-fidelity-issue)
            xkb-output
            (list :xkb xkb-output)))))

(defun analyze-normalized-layout (normalized placement &key vocabulary)
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
           (let ((outputs
                   (%output-lowering
                    (ivory-key.model:normalized-entry-behavior
                     (first entries-for-binding))
                    feature vocabulary)))
             (if (typep outputs 'compiler-fidelity-issue)
                 (push outputs issues)
                 ;; Kanata forwards the device's explicit carrier spelling to
                 ;; XKB for static Unicode/no-output bindings.  A selected
                 ;; realization vocabulary instead supplies a checked opaque
                 ;; Kanata spelling for a typed named output.
                 (push (make-instance 'ivory-key.backend:key-entry
                                      :position feature
                                      :physical-code
                                      (list :xkb (getf placement-entry :xkb)
                                            :kanata (getf placement-entry :kanata))
                                      :outputs
                                      (list :xkb (list (getf outputs :xkb))
                                            :kanata
                                            (list (or (getf outputs :kanata)
                                                      (getf placement-entry
                                                            :kanata)))))
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

(defun make-lowering-request-from-normalized-layout (normalized placement &key vocabulary)
  "Return a complete bootstrap lowering request or signal its first failure."
  (multiple-value-bind (request issues)
      (analyze-normalized-layout normalized placement :vocabulary vocabulary)
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
                  (compiler-unit-normalized unit) placement
                  :vocabulary (compiler-realization-vocabulary realization))))
    (handler-case
        (ivory-key.backend:compile-xkb-kanata-request request :allow-lossy nil)
      (error (condition)
        (%stage-error :pipeline :backend-refusal "~A" condition)))))

;;; Deterministic inspection -------------------------------------------------

(defun %planner-placement-from-compiler-placement (placement)
  "Project the bootstrap device envelope into the planner's one-to-one view.

The compiler envelope deliberately preserves both XKB and Kanata spellings for
each physical switch, whereas PLAN-NORMALIZED-LAYOUT accepts one opaque input
identity per logical position.  Inspection uses the explicitly declared XKB
key-name spelling, tagged as an opaque identity, because XKB is the selected
finite-static-table capability.  This projection is only planner input: it
does not select a lowering, translate an abstract output, or alter the direct
emitter request.
"
  (unless (typep placement 'compiler-placement)
    (%stage-error :plan :invalid-compiler-placement
                  "Capability inspection requires a compiler device placement."))
  (let ((mappings nil))
    (dolist (mapping (compiler-placement-mappings placement))
      (let ((position (car mapping))
            (spellings (cdr mapping)))
        (unless (and (stringp position) (listp spellings)
                     (stringp (getf spellings :xkb))
                     (plusp (length (getf spellings :xkb))))
          (%stage-error :plan :invalid-compiler-placement
                        "Compiler placement mapping ~S lacks one XKB input spelling."
                        mapping))
        ;; Prefixing preserves the source spelling as an opaque planner input
        ;; and keeps it distinct from any future input namespace.
        (push (cons (format nil "xkb:~A" (getf spellings :xkb)) position)
              mappings)))
    (ivory-key.model:make-device-placement
     (compiler-placement-name placement)
     ;; The planner only compares topology identities.  Do not borrow the
     ;; layout's topology object here: doing so would conceal a mismatched
     ;; compiler-placement topology from its explicit planner refusal.
     (ivory-key.model:make-topology (compiler-placement-topology placement) nil)
     (sort mappings #'string< :key #'car))))

(defun %plan-normalized-layout-for-inspection (normalized placement)
  "Return a target-neutral capability plan or its structured refusal.

The direct compiler remains intentionally stricter than this inspection:
successful table grading is not permission to emit selectors, semantic
modifiers, named symbols, commands, or interactions.
"
  (handler-case
      (values
       (ivory-key.backend:plan-normalized-layout
        normalized (%planner-placement-from-compiler-placement placement)
        :backends (list (ivory-key.backend:make-xkb-backend)))
       nil)
    (ivory-key.backend:planner-refusal (condition)
      (values nil condition))))

(defun %planner-inspection-name (value)
  (typecase value
    (ivory-key.model:identifier (ivory-key.model:identifier-name value))
    (string value)
    (symbol (string-downcase (symbol-name value)))
    (t (princ-to-string value))))

(defun %planner-result-for-binding (plan binding)
  (find (ivory-key.model:identifier-name
         (ivory-key.backend:static-table-requirement-position binding))
        (ivory-key.backend:lowering-plan-realizations plan)
        :test #'string=
        :key (lambda (result)
               (%planner-inspection-name
                (ivory-key.backend:realization-feature result)))))

(defun %planner-bank-capacity-status (partition)
  "Return a stable statement of advertised versus required bank capacity."
  (let ((advertised
          (ivory-key.backend:multi-bank-partition-requirement-bank-capacity
           partition))
        (required
          (ivory-key.backend:multi-bank-partition-requirement-bank-count
           partition)))
    (cond ((null advertised) "advertised bank capacity: unadvertised")
          ((< advertised required)
           (format nil "advertised bank capacity: ~D (exceeded; ~D required)"
                   advertised required))
          (t (format nil "advertised bank capacity: ~D (within capacity)"
                     advertised)))))

(defun %write-planner-bank-partitions (stream plan)
  "Write complete canonical bank assignments only when a table needs banks."
  (let ((partitions
          (ivory-key.backend:lowering-plan-multi-bank-partition-requirements
           plan)))
    (when partitions
      (format stream "Planner multi-bank partitions~%")
      (dolist (partition partitions)
        (let ((banks (ivory-key.backend:multi-bank-partition-requirement-banks
                      partition)))
          (format stream "  ~A: ~D banks; native level capacity: ~D; ~A~%"
                  (ivory-key.model:identifier-name
                   (ivory-key.backend:multi-bank-partition-requirement-position
                    partition))
                  (ivory-key.backend:multi-bank-partition-requirement-bank-count
                   partition)
                  (ivory-key.backend:multi-bank-partition-requirement-level-capacity
                   partition)
                  (%planner-bank-capacity-status partition))
          ;; Do not use a nested FORMAT iteration here: its escape directive
          ;; is scoped to each two-element bank tuple.  Writing the stable
          ;; summary explicitly keeps every bank visible.
          (format stream "    bank sizes:")
          (dolist (bank banks)
            (format stream " ~A=~D"
                    (ivory-key.backend:static-table-bank-ordinal bank)
                    (length (ivory-key.backend:static-table-bank-entries
                             bank))))
          (terpri stream)
          (format stream "    canonical context assignments~%")
          (dolist (assignment
                   (ivory-key.backend:multi-bank-partition-requirement-assignments
                    partition))
            (format stream "      ~A -> bank ~D level ~D~%"
                    (ivory-key.model:context-tuple-key
                     (ivory-key.backend:static-table-bank-assignment-context
                      assignment))
                    (ivory-key.backend:static-table-bank-assignment-bank-index
                     assignment)
                    (ivory-key.backend:static-table-bank-assignment-level-index
                     assignment))))))))

(defun %write-planner-bank-selector-obligations (stream plan)
  "Write bank-selection needs without suggesting a selected target lowering."
  (let ((requirements
          (ivory-key.backend:lowering-plan-bank-selector-requirements plan)))
    (when requirements
      (format stream "Planner bank-selector/carrier obligations~%")
      (dolist (requirement requirements)
        (format stream
                "  ~A: select ~D banks; requires ~D distinguishable carrier values; lowering unproved~%"
                (ivory-key.model:identifier-name
                 (ivory-key.backend:bank-selector-requirement-position requirement))
                (ivory-key.backend:bank-selector-requirement-bank-count requirement)
                (ivory-key.backend:bank-selector-requirement-carrier-value-count
                 requirement))))))

(defun %write-planner-inspection (stream plan refusal)
  "Write a canonical capability-planner report without implying emission."
  (format stream "Planner inspection~%")
  (when refusal
    (format stream "Planner: refused [~A]: ~A~%"
            (ivory-key.backend:planner-refusal-code refusal)
            (ivory-key.backend:planner-refusal-detail refusal))
    (return-from %write-planner-inspection nil))
  (format stream "Planner static tables (canonical normalized entry counts)~%")
  (dolist (binding (ivory-key.backend:lowering-plan-bindings plan))
    (let ((result (%planner-result-for-binding plan binding)))
      (format stream "  ~A: ~D entries; XKB grade ~A~%"
              (ivory-key.model:identifier-name
               (ivory-key.backend:static-table-requirement-position binding))
              (ivory-key.backend:static-table-requirement-state-count binding)
              (if result
                  (%planner-inspection-name
                   (ivory-key.backend:realization-grade result))
                  "unreported"))
      (when result
        (format stream "    ~A~%"
                (ivory-key.backend:realization-detail result)))))
  ;; These sections appear only for tables exceeding one advertised native
  ;; level bank.  Their detailed assignments are evidence for a future
  ;; selector lowering, not an emission request or an emulation claim.
  (%write-planner-bank-partitions stream plan)
  (%write-planner-bank-selector-obligations stream plan)
  (format stream "Planner selector obligations~%")
  (let ((selectors (ivory-key.backend:lowering-plan-selector-requirements plan)))
    (if selectors
        (dolist (selector selectors)
          (format stream "  ~A [~A] states: ~{~A~^ ~}; default: ~A; positions: ~{~A~^ ~}~%"
                  (ivory-key.model:identifier-name
                   (ivory-key.backend:selector-requirement-axis selector))
                  (%planner-inspection-name
                   (ivory-key.backend:selector-requirement-resolution selector))
                  (mapcar #'ivory-key.model:identifier-name
                          (ivory-key.backend:selector-requirement-states selector))
                  (ivory-key.model:identifier-name
                   (ivory-key.backend:selector-requirement-default-state selector))
                  (mapcar #'ivory-key.model:identifier-name
                          (ivory-key.backend:selector-requirement-positions selector))))
        (format stream "  none~%")))
  (format stream "Planner semantic-modifier obligations~%")
  (let ((modifiers (ivory-key.backend:lowering-plan-modifier-requirements plan)))
    (if modifiers
        (dolist (modifier modifiers)
          (format stream "  ~A~%"
                  (ivory-key.model:identifier-name
                   (ivory-key.backend:modifier-requirement-modifier modifier))))
        (format stream "  none~%")))
  (format stream "Planner resource obligations~%")
  (let ((resources (ivory-key.backend:lowering-plan-resource-requirements plan)))
    (if resources
        (dolist (resource resources)
          (format stream "  ~A ~A~@[ x~D~]: ~A~%"
                  (%planner-inspection-name
                   (ivory-key.backend:planner-resource-requirement-kind resource))
                  (%planner-inspection-name
                   (ivory-key.backend:planner-resource-requirement-owner resource))
                  (let ((cardinality
                          (ivory-key.backend:planner-resource-requirement-cardinality
                           resource)))
                    (and (> cardinality 1) cardinality))
                  (ivory-key.backend:planner-resource-requirement-detail resource)))
        (format stream "  none~%")))
  plan)

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
  (let* ((working-directory
           (uiop:ensure-directory-pathname (truename (uiop:getcwd))))
         (directory
           (uiop:ensure-directory-pathname
            (uiop:ensure-absolute-pathname pathname working-directory)))
         (components (pathname-directory directory))
         (marker (first components))
         (leaf (car (last components))))
    (unless (and (member marker '(:relative :absolute))
                 (stringp leaf)
                 (not (member :up components)))
      (%stage-error :emit :unsafe-output-directory
                    "Output directory ~A must name one concrete directory without parent traversal."
                    pathname))
    (let ((parent (%parent-directory directory)))
      ;; Portable Common Lisp has no directory-descriptor or exclusive-MKDIR
      ;; protocol.  Requiring a pre-existing parent lets us resolve and
      ;; repeatedly check the observable pathname transitions.  It cannot
      ;; prove identity after same-spelling replacement, so callers must not
      ;; use a parent concurrently writable by an untrusted principal.
      (unless (probe-file parent)
        (%stage-error :emit :missing-output-parent
                      "Output parent directory ~A must already exist and be trusted."
                      parent))
      (let* ((physical-parent
               (uiop:ensure-directory-pathname (truename parent)))
             (target
               (make-pathname
                :directory (append (pathname-directory physical-parent)
                                   (list leaf))
                :name nil :type nil :defaults physical-parent)))
        (when (%output-target-exists-p target)
          (%stage-error :emit :output-already-exists
                        "Refusing to overwrite existing output directory ~A." target))
        target))))

(defun %parent-directory (directory)
  (let* ((components (pathname-directory directory))
         (parent-components (butlast components)))
    (make-pathname :directory parent-components :name nil :type nil :defaults directory)))

(defun %same-physical-pathname-p (left right)
  (string= (uiop:native-namestring left)
           (uiop:native-namestring right)))

(defun %verified-output-parent (parent)
  "Return PARENT's resolved directory path, or fail on detectable changes.

TRUENAME detects a changed symlink target but cannot prove that a directory was
replaced at the same spelling.  The build-emission API therefore requires its
parent to be trusted and not concurrently mutable by an untrusted principal.
"
  (let ((physical
          (handler-case
              (uiop:ensure-directory-pathname (truename parent))
            (error (condition)
              (%stage-error :emit :output-parent-changed
                            "Could not re-verify output parent ~A: ~A"
                            parent condition)))))
    (unless (%same-physical-pathname-p parent physical)
      (%stage-error :emit :output-parent-changed
                    "Output parent ~A no longer names its verified directory."
                    parent))
    physical))

(defun %directory-entry-name (pathname)
  "Return PATHNAME's final directory entry spelling without following links."
  (if (uiop:directory-pathname-p pathname)
      (let ((component (car (last (pathname-directory pathname)))))
        (and (stringp component) component))
      (file-namestring pathname)))

(defun %directory-entry-named-p (directory name)
  "Detect a named entry, including a dangling symlink where DIRECTORY exposes it.

Common Lisp has no portable LSTAT.  DIRECTORY normally exposes dangling links
on the supported Unix hosts, so this is an additional no-overwrite guard; the
trusted-parent precondition covers hosts that cannot report such an entry.
"
  (handler-case
      (some (lambda (entry)
              (string= name (or (%directory-entry-name entry) "")))
            (directory (merge-pathnames "*" directory)))
    (error (condition)
      (%stage-error :emit :unreadable-output-parent
                    "Could not inspect output parent ~A: ~A" directory condition))))

(defun %output-target-exists-p (target)
  "Return true if TARGET has a visible filesystem entry, even if dangling."
  (or (probe-file target)
      (%directory-entry-named-p (%parent-directory target)
                                (car (last (pathname-directory target))))))

(defun %path-below-parent-p (pathname parent)
  "Whether already physical PATHNAME remains below already physical PARENT."
  (and (uiop:subpathp pathname parent)
       (not (%same-physical-pathname-p pathname parent))))

(defun %directory-file-names (directory)
  (sort (mapcar #'file-namestring (uiop:directory-files directory)) #'string<))

(defun %directory-is-empty-p (directory)
  (and (null (uiop:directory-files directory))
       (null (uiop:subdirectories directory))))

(defun %temporary-directory-from-reservation (reservation)
  "Derive a private sibling directory name from UIOP's exclusive random file."
  (let* ((parent (uiop:pathname-directory-pathname reservation))
         (name (format nil "~A.build" (file-namestring reservation))))
    (merge-pathnames (format nil "~A/" name) parent)))

(defun %reserve-fresh-build-directory (output-directory)
  "Reserve an unpredictable temporary build sibling beneath a trusted parent.

The reservation file is created by UIOP with exclusive temporary-file
semantics, so unrelated compiler invocations cannot select a predictable
counter-based directory.  A hostile writer with access to the parent can still
race portable pathname operations; callers must therefore provide a trusted,
non-concurrently-mutated parent directory.
"
  (let* ((parent (%parent-directory output-directory))
         (verified-parent (%verified-output-parent parent))
         (leaf (car (last (pathname-directory output-directory)))))
    (uiop:with-temporary-file
        (:pathname reservation
         :directory verified-parent
         :prefix (format nil ".~A.ivory-key-reservation-" leaf)
         :suffix ".lock"
         :keep t)
      (let ((temporary (%temporary-directory-from-reservation reservation)))
        (when (probe-file temporary)
          (%stage-error :emit :temporary-directory-collision
                        "Refusing occupied temporary build directory ~A."
                        temporary))
        (ensure-directories-exist (merge-pathnames "placeholder" temporary))
        (let ((physical-temporary
                (handler-case
                    (uiop:ensure-directory-pathname (truename temporary))
                  (error (condition)
                    (%stage-error :emit :unsafe-temporary-directory
                                  "Could not verify temporary build directory ~A: ~A"
                                  temporary condition)))))
          (unless (and (%same-physical-pathname-p verified-parent
                                                     (%verified-output-parent verified-parent))
                       (%path-below-parent-p physical-temporary verified-parent)
                       (%directory-is-empty-p physical-temporary))
            (%stage-error :emit :unsafe-temporary-directory
                          "Temporary build directory failed trusted-parent verification."))
          (values physical-temporary reservation))))))

(defun %expected-build-file-names (pipeline-result &optional marker)
  (let ((names
          (append (mapcar #'ivory-key.backend:pipeline-artifact-relative-path
                          (ivory-key.backend:pipeline-result-artifacts pipeline-result))
                  (list "REPORT.txt")
                  (and marker (list marker)))))
    (unless (= (length names) (length (remove-duplicates names :test #'string=)))
      (%stage-error :emit :duplicate-artifact-path
                    "Backend returned duplicate artifact paths."))
    (sort names #'string<)))

(defun %verify-temporary-build-directory (temporary parent expected-names)
  (let ((physical
          (handler-case
              (uiop:ensure-directory-pathname (truename temporary))
            (error (condition)
              (%stage-error :emit :unsafe-temporary-directory
                            "Temporary build directory changed: ~A" condition)))))
    (unless (and (%same-physical-pathname-p temporary physical)
                 (%same-physical-pathname-p parent (%verified-output-parent parent))
                 (%path-below-parent-p physical parent)
                 (null (uiop:subdirectories physical))
                 (equal expected-names (%directory-file-names physical)))
      (%stage-error :emit :unsafe-temporary-directory
                    "Temporary build directory contents or parent changed."))
    physical))

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
  "Write a new build through a reserved sibling directory without overwriting.

The current backend API owns deterministic artifact text but not atomic output
handling.  This wrapper verifies each observable pathname transition and
deliberately does not invoke external validators or deployment machinery.
Portable Common Lisp cannot make a final directory rename non-replacing against
a hostile concurrent writer, so OUTPUT-DIRECTORY's existing parent must be
trusted and not concurrently mutable by an untrusted principal.
"
  (let* ((target (%safe-output-directory output-directory))
         (parent (%parent-directory target))
         (marker ".ivory-key-build-owner")
         (reservation nil)
         (temporary nil))
    (dolist (artifact (ivory-key.backend:pipeline-result-artifacts pipeline-result))
      (unless (%safe-artifact-relative-path-p
               (ivory-key.backend:pipeline-artifact-relative-path artifact))
        (%stage-error :emit :unsafe-artifact-path
                      "Backend returned unsafe artifact path ~S."
                      (ivory-key.backend:pipeline-artifact-relative-path artifact))))
    (multiple-value-setq (temporary reservation)
      (%reserve-fresh-build-directory target))
    (unwind-protect
         (progn
           (let ((owner (merge-pathnames marker temporary)))
             (with-open-file (stream owner :direction :output
                                           :if-exists :error
                                           :if-does-not-exist :create)
               (write-line "Ivory Key temporary build ownership marker." stream))
             (ivory-key.backend:write-pipeline-result pipeline-result temporary)
             (%write-report-file pipeline-result temporary)
             (%verify-temporary-build-directory
              temporary parent (%expected-build-file-names pipeline-result marker))
             (delete-file owner)
             (%verify-temporary-build-directory
              temporary parent (%expected-build-file-names pipeline-result))
             ;; Recheck immediately before RENAME-FILE.  The trusted-parent
             ;; precondition above is still needed for the remaining host-level
             ;; race because portable Common Lisp has no no-replace rename.
             (%verified-output-parent parent)
             (when (%output-target-exists-p target)
               (%stage-error :emit :output-already-exists
                             "Refusing to overwrite newly created output directory ~A."
                             target))
             (rename-file temporary target)
             target))
      ;; The reservation is a file, so deleting it cannot traverse a directory
      ;; symlink.  On failure retain the build directory for inspection rather
      ;; than recursively deleting a pathname that a concurrent writer may have
      ;; replaced.
      (when (and reservation (probe-file reservation))
        (ignore-errors (delete-file reservation))))))

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

(defun compile-project-source (project-path composition-name &key source-roots
                                                        output-directory)
  "Compile one named project composition into a fresh non-deploying build.

PROJECT-PATH is loaded exactly once by the confined project loader.  The
selected composition supplies its already-resolved layout, device placement,
and realization profile; no imported source is parsed again by this bridge.
"
  (unless output-directory
    (%stage-error :arguments :missing-compile-input
                  "Project compile requires a project, composition, and output path."))
  (multiple-value-bind (unit placement realization)
      (load-project-composition-for-compilation project-path composition-name
                                                :source-roots source-roots)
    (let ((pipeline-result (%compile-unit-to-pipeline unit placement realization)))
      (write-new-pipeline-result pipeline-result output-directory)
      pipeline-result)))

(defun %explain-compiler-unit (unit placement realization stream)
  "Print target-neutral obligations and the stricter direct-pipeline result.

The planner section is deliberately observational.  Its exact static-table
grade establishes only the advertised XKB table-capacity fact; the existing
direct bridge still independently rejects every selector, semantic output, or
timed interaction it cannot lower exactly.
"
  (%require-compatible-realization realization)
  (multiple-value-bind (plan planner-refusal)
      (%plan-normalized-layout-for-inspection
       (compiler-unit-normalized unit) placement)
    (multiple-value-bind (request issues)
        (analyze-normalized-layout
         (compiler-unit-normalized unit) placement
         :vocabulary (compiler-realization-vocabulary realization))
      (format stream "Ivory Key capability explanation~%")
      (format stream "Layout: ~A~%Device: ~A~%Realization: ~A~%"
              (ivory-key.model:identifier-name
               (ivory-key.model:normalized-layout-name (compiler-unit-normalized unit)))
              (compiler-placement-name placement)
              (compiler-realization-name realization))
      (%write-planner-inspection stream plan planner-refusal)
      (if issues
          (progn
            ;; Preserve the established direct-pipeline disposition and its
            ;; exact output shape for callers that distinguish this refusal
            ;; from a planner's independent table-capacity report.
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

(defun explain-layout-source (layout-path &key topology-path device-path realization-path
                                          (stream *standard-output*))
  "Print an exact-or-refused pipeline explanation without emitting artifacts."
  (let* ((unit (load-layout-for-compilation layout-path :topology-path topology-path))
         (placement (decode-device-source device-path))
         (realization (decode-realization-source realization-path)))
    (%explain-compiler-unit unit placement realization stream)))

(defun explain-project-source (project-path composition-name &key source-roots
                                                           (stream *standard-output*))
  "Explain exact lowering for one named project composition without emission."
  (multiple-value-bind (unit placement realization)
      (load-project-composition-for-compilation project-path composition-name
                                                :source-roots source-roots)
    (%explain-compiler-unit unit placement realization stream)))

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
