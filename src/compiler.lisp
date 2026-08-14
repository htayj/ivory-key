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
            (:constructor %make-compiler-placement
                (name topology mappings &optional position-coverage)))
  "A narrow, non-semantic device view used only at the lowering boundary.

MAPPINGS is a canonical list of (logical-position . plist) pairs.  The plist
contains only the physical spellings required by the existing bootstrap
backends.  It is intentionally not a replacement for MODEL:DEVICE-PLACEMENT.
"
  name
  topology
  mappings
  ;; Typed MODEL:DEVICE-POSITION-COVERAGE records.  NIL means coverage was not
  ;; supplied; it is deliberately not inferred from MAPPINGS.
  (position-coverage nil)
  ;; Device-reserved Linux carrier codes are not semantic layout data.  A
  ;; realization may use one only when its profile vocabulary spells the
  ;; exact evidenced carrier action; every other lowering treats this
  ;; inventory as unavailable.
  (reserved-carriers nil))

(defstruct (compiler-realization
            (:constructor %make-compiler-realization
                (name pipeline grades vocabulary selector-policy)))
  "The subset of a realization profile consumed by this bootstrap pipeline."
  name
  pipeline
  grades
  ;; NIL means the established direct static table is selected.  A non-NIL
  ;; vocabulary is realization-owned data resolved by the project loader; it
  ;; is never inferred from a layout binding or direct source file.
  vocabulary
  ;; A typed realization-owned allocation.  NIL is significant: no source
  ;; profile may obtain native selectors by falling back to compiler guesses.
  selector-policy)

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
  (handler-case
      (ivory-key.model:validate-device-placement-coverage device)
    (ivory-key.model:semantic-error (condition)
      (%stage-error :decode (ivory-key.model:semantic-error-code condition)
                    "Invalid project device coverage: ~A"
                    (ivory-key.model:semantic-error-message condition))))
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
      (let ((placement
              (%make-compiler-placement
               (ivory-key.model:identifier-name (ivory-key.model:placement-name device))
               (ivory-key.model:identifier-name
                (ivory-key.model:topology-name
                 (ivory-key.model:placement-topology device)))
               (sort converted #'string< :key #'car)
               (copy-list
                (ivory-key.model:placement-position-coverage device)))))
        (let ((reserved
                (%project-metadata-value
                 (ivory-key.model:placement-metadata device) :reserved-carriers
                 :decode :missing-device-reserved-carriers
                 (format nil "Device ~A"
                         (ivory-key.model:identifier-name
                          (ivory-key.model:placement-name device))))))
          (unless (and (listp reserved)
                       (every (lambda (value)
                                (and (integerp value) (not (minusp value))))
                              reserved)
                       (= (length reserved)
                          (length (remove-duplicates reserved :test #'=))))
            (%stage-error :decode :invalid-device-reserved-carriers
                          "Device ~A has malformed reserved carrier inventory."
                          (compiler-placement-name placement)))
          (setf (compiler-placement-reserved-carriers placement)
                (sort (copy-list reserved) #'<)))
        placement))))

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
          (vocabulary (ivory-key.model:realization-profile-vocabulary realization))
          (selector-policy
            (ivory-key.model::realization-profile-selector-policy realization)))
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
       (copy-list pipeline) (copy-list grades) vocabulary selector-policy))))

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
         (mappings nil)
         (position-coverage nil)
         (seen-positions (make-hash-table :test #'equal))
         (reserved-carriers nil))
    (unless topology
      (%stage-error :decode :missing-device-topology
                    "Device ~A has no USES-TOPOLOGY declaration." name))
    (dolist (clause clauses)
      (cond ((%named-form-p clause "uses-topology"))
          ((%named-form-p clause "reserve-carriers")
           (dolist (carrier (cdr clause))
             (unless (and (integerp carrier) (not (minusp carrier)))
               (%stage-error :decode :invalid-reserved-carrier
                             "Device ~A has invalid reserved carrier ~S." name carrier))
             (push carrier reserved-carriers)))
            ((%named-form-p clause "place")
             (let ((position (%identifier-string (second clause) :decode
                                                 "Placed logical position")))
               (when (gethash position seen-positions)
                 (%stage-error :decode :duplicate-device-position-coverage
                               "Device ~A declares coverage for logical position ~A more than once."
                               name position))
               (setf (gethash position seen-positions) t)
               (push (cons position
                           (list :xkb (%backend-option (cddr clause) "xkb" position name)
                                 :kanata (%backend-option (cddr clause) "kanata" position name)))
                     mappings)
               (push (ivory-key.model:make-device-position-coverage
                      position :physical)
                     position-coverage)))
            ((%named-form-p clause "unreachable")
             (unless (= (length clause) 2)
               (%stage-error :decode :invalid-device-coverage
                             "Device ~A UNREACHABLE declarations need one position." name))
             (let ((position (%identifier-string (second clause) :decode
                                                 "Unreachable logical position")))
               (when (gethash position seen-positions)
                 (%stage-error :decode :duplicate-device-position-coverage
                               "Device ~A declares coverage for logical position ~A more than once."
                               name position))
               (setf (gethash position seen-positions) t)
               (push (ivory-key.model:make-device-position-coverage
                      position :unreachable)
                     position-coverage)))
            (t (%stage-error :decode :unknown-device-clause
                             "Device ~A has unsupported clause ~S." name clause))))
    (let ((placement (%make-compiler-placement name topology
                                                 (sort mappings #'string< :key #'car)
                                                 (sort position-coverage #'ivory-key.model:identifier<
                                                       :key #'ivory-key.model:device-position-coverage-position))))
      (setf (compiler-placement-reserved-carriers placement)
            (sort (remove-duplicates reserved-carriers :test #'=) #'<))
      placement)))

(defun %compiler-syntax-form-name (node)
  (and (ivory-key.syntax:syntax-list-p node)
       (let ((head (first (ivory-key.syntax:syntax-list-children node))) )
         (and (ivory-key.syntax:syntax-atom-p head)
              (eq (ivory-key.syntax:syntax-atom-kind head) :identifier)
              (string-downcase (ivory-key.syntax:syntax-atom-value head))))))

(defun %compiler-syntax-identifier (node what)
  (unless (and (ivory-key.syntax:syntax-atom-p node)
               (eq (ivory-key.syntax:syntax-atom-kind node) :identifier))
    (%stage-error :decode :invalid-realization-selector-policy
                  "~A must be an Ivory Key identifier." what))
  (ivory-key.syntax:syntax-atom-value node))

(defun %compiler-syntax-integer (node what)
  (unless (and (ivory-key.syntax:syntax-atom-p node)
               (eq (ivory-key.syntax:syntax-atom-kind node) :integer))
    (%stage-error :decode :invalid-realization-selector-policy
                  "~A must be an Ivory Key integer." what))
  (ivory-key.syntax:syntax-atom-value node))

(defun %compiler-selector-policy-value (node choices what)
  (let* ((name (%compiler-syntax-identifier node what))
         (choice (assoc name choices :test #'string=)))
    (unless choice
      (%stage-error :decode :unknown-realization-selector-policy-value
                    "~A has unsupported value ~S." what name))
    (cdr choice)))

(defun %decode-realization-selector-policy-source (node)
  "Decode a policy from parser nodes without accepting source strings/actions.

The project decoder has the same grammar.  The explicit-file compiler retains
this small duplicate because it intentionally does not load an import graph;
both paths construct the one public MODEL policy value.
"
  (unless (ivory-key.syntax:syntax-list-p node)
    (%stage-error :decode :invalid-realization-selector-policy
                  "SELECTOR-POLICY must be a list."))
  (let ((static-types nil) (selectors nil) (carriers nil))
    (dolist (clause (rest (ivory-key.syntax:syntax-list-children node)))
      (unless (ivory-key.syntax:syntax-list-p clause)
        (%stage-error :decode :invalid-realization-selector-policy
                      "SELECTOR-POLICY clause must be a list."))
      (let ((children (ivory-key.syntax:syntax-list-children clause)))
        (labels ((arity (expected description)
                   (unless (= (length children) expected)
                     (%stage-error :decode :invalid-realization-selector-policy
                                   "Malformed ~A selector policy clause." description))))
          (cond
            ((string= (or (%compiler-syntax-form-name clause) "") "static-type")
             (arity 4 "STATIC-TYPE")
             (push (ivory-key.model::make-realization-static-type
                    (%compiler-syntax-identifier (second children) "STATIC-TYPE position")
                    (%compiler-selector-policy-value
                     (third children)
                     '(("four-level" . :four-level)
                       ("four-level-alphabetic" . :four-level-alphabetic))
                     "STATIC-TYPE Group1 kind")
                    (%compiler-selector-policy-value
                     (fourth children) '(("two-level" . :two-level))
                     "STATIC-TYPE Group2 kind")) static-types))
            ((string= (or (%compiler-syntax-form-name clause) "") "selector")
             (arity 6 "SELECTOR")
             (push (ivory-key.model::make-realization-context-selector
                    (%compiler-syntax-identifier (second children) "SELECTOR axis")
                    (%compiler-syntax-identifier (third children) "SELECTOR state")
                    (%compiler-selector-policy-value
                     (fourth children)
                     '(("shift" . :shift) ("level-three" . :level-three)
                       ("group-two" . :group-two))
                     "SELECTOR control")
                    (%compiler-selector-policy-value
                     (fifth children)
                     '(("consumed" . :consumed) ("group-action" . :group-action))
                     "SELECTOR consumption")
                    (%compiler-selector-policy-value
                     (sixth children)
                     '(("core-shift" . :core-shift)
                       ("consumed-level-three" . :consumed-level-three)
                       ("unproved-group-two" . :unproved-group-two))
                     "SELECTOR client semantics")) selectors))
            ((string= (or (%compiler-syntax-form-name clause) "") "carrier")
             (arity 6 "CARRIER")
             (push (ivory-key.model::make-realization-direct-carrier
                    (%compiler-syntax-identifier (second children) "CARRIER position")
                    (%compiler-syntax-identifier (third children) "CARRIER axis")
                    (%compiler-syntax-identifier (fourth children) "CARRIER state")
                    (%compiler-syntax-integer (fifth children) "CARRIER Linux code")
                    (%compiler-selector-policy-value
                     (sixth children) '(("zeha" . :zeha) ("lvl3" . :lvl3))
                     "CARRIER XKB key")) carriers))
            (t
             (%stage-error :decode :unknown-realization-selector-policy-clause
                           "SELECTOR-POLICY has unsupported clause ~S."
                           (%compiler-syntax-form-name clause)))))))
    (handler-case
        (ivory-key.model::make-realization-selector-policy
         (nreverse static-types) (nreverse selectors) (nreverse carriers))
      (ivory-key.model:semantic-error (condition)
        (%stage-error :decode (ivory-key.model:semantic-error-code condition)
                      "Could not decode selector policy: ~A"
                      (ivory-key.model:semantic-error-message condition))))))

(defun decode-realization-source (pathname)
  "Decode the policy subset needed to select the XKB + Kanata bootstrap path."
  (let* ((parsed (%parse-required-file pathname "realization"))
         (values (%parsed-values parsed))
         (form (%find-named-form values "define-realization" :decode))
         (syntax-form
           (let ((matches
                   (remove-if-not
                    (lambda (node)
                      (string= (or (%compiler-syntax-form-name node) "")
                               "define-realization"))
                    (ivory-key.syntax:syntax-parse-result-forms parsed))))
             (unless (= (length matches) 1)
               (%stage-error :decode :missing-declaration
                             "Source contains no unique DEFINE-REALIZATION declaration."))
             (first matches)))
         (name (%identifier-string (second form) :decode "Realization name"))
         (clauses (cddr form))
         (pipeline (%option-value clauses "pipeline"))
         (grades (%option-value clauses "allow-grades"))
         (forbid-shell (%option-value clauses "forbid-shell-actions"))
         (policy-nodes
           (remove-if-not
            (lambda (node)
              (string= (or (%compiler-syntax-form-name node) "") "selector-policy"))
            (cddr (ivory-key.syntax:syntax-list-children syntax-form))))
         (selector-policy
           (cond ((null policy-nodes) nil)
                 ((rest policy-nodes)
                 (%stage-error :decode :duplicate-realization-clause
                                "Realization ~A repeats SELECTOR-POLICY." name))
                 (t (handler-case
                        (%decode-realization-selector-policy-source (first policy-nodes))
                      (ivory-key.model:semantic-error (condition)
                        (%stage-error :decode (ivory-key.model:semantic-error-code condition)
                                      "Could not decode selector policy: ~A"
                                      (ivory-key.model:semantic-error-message condition))))))))
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
    (%make-compiler-realization name (copy-list pipeline) (copy-list grades) nil
                                selector-policy)))

(defun %layout-topology-name (layout)
  (ivory-key.model:identifier-name
   (ivory-key.model:topology-name
    (ivory-key.model:normalized-layout-topology layout))))

(defun %placement-for-position (placement position)
  (cdr (find position (compiler-placement-mappings placement)
             :test #'ivory-key.model:identifier=
             :key #'car)))

(defun %placement-coverage-disposition-for-position (placement position)
  "Return POSITION's declared coverage disposition, NIL, or :INVALID.

This compiler envelope may be built from a direct device file, so topology
membership is checked against the normalized layout below.  It nevertheless
requires typed, single-valued model records: physical mappings are never used
as an implicit coverage declaration.
"
  (let ((records
          (remove-if-not
           (lambda (coverage)
             (and (typep coverage 'ivory-key.model:device-position-coverage)
                  (ivory-key.model:identifier=
                   position
                   (ivory-key.model:device-position-coverage-position coverage))))
           (compiler-placement-position-coverage placement))))
    (cond ((null records) nil)
          ((rest records) :invalid)
          (t (let ((disposition
                     (ivory-key.model:device-position-coverage-disposition
                      (first records))))
               (if (member disposition '(:physical :unreachable) :test #'eq)
                   disposition
                   :invalid))))))

(defun %input-coverage-records (normalized placement)
  "Return deterministic, inspectable coverage records for a compiler request.

NIL (missing) and :INVALID states can occur only on a refused inspection
request.  Generated contracts receive this metadata only after the final
exact gate, where records are therefore restricted to the two public model
dispositions.
"
  (sort
   (mapcar (lambda (position)
             (let ((name (ivory-key.model:identifier-name
                          (ivory-key.model:position-name position))))
               (list :position name :disposition
                     (%placement-coverage-disposition-for-position placement name))))
           (ivory-key.model:topology-positions
            (ivory-key.model:normalized-layout-topology normalized)))
   #'string< :key (lambda (record) (getf record :position))))

(defun %coverage-disposition-name (disposition)
  (if (member disposition '(:physical :unreachable) :test #'eq)
      (string-downcase (symbol-name disposition))
      "missing-or-invalid"))

(defun %coverage-fidelity-issue (placement position &key require-mapping)
  "Return one precise coverage blocker for POSITION, or NIL.

REQUIRE-MAPPING is true for an ordinary binding or interaction participant.
An unused :UNREACHABLE topology position is a complete device declaration and
does not itself lower a semantic behavior.
"
  (let* ((feature (ivory-key.model:identifier-name position))
         (disposition (%placement-coverage-disposition-for-position placement position)))
    (cond ((null disposition)
           (%make-compiler-fidelity-issue
            feature :missing-device-coverage
            "No physical/unreachable coverage declaration is present for this topology position."))
          ((eq disposition :invalid)
           (%make-compiler-fidelity-issue
            feature :invalid-device-coverage
            "Device coverage for this topology position is malformed or conflicting."))
          ((and require-mapping (eq disposition :unreachable))
           (%make-compiler-fidelity-issue
            feature :unreachable-device-position
            "A real semantic binding or interaction participant is declared on an unreachable device position."))
          ((and require-mapping (eq disposition :physical)
                (null (%placement-for-position placement position)))
           (%make-compiler-fidelity-issue
            feature :physical-device-coverage-without-placement
            "The position is declared physical but has no XKB/Kanata placement.")))))

(defun %coverage-declaration-issues (normalized placement)
  "Validate compiler-envelope records against NORMALIZED's actual topology.

Direct device decoding intentionally does not load a topology file.  This is
the one point where its typed declarations can be checked against the selected
layout without reparsing or inferring any reachability.
"
  (let ((positions
          (ivory-key.model:topology-positions
           (ivory-key.model:normalized-layout-topology normalized)))
        (seen (make-hash-table :test #'equal))
        (issues nil))
    (dolist (coverage (compiler-placement-position-coverage placement))
      (cond ((not (typep coverage 'ivory-key.model:device-position-coverage))
             (push (%make-compiler-fidelity-issue
                    :device :invalid-device-coverage
                    "Device coverage contains a non-model record.")
                   issues))
            (t
             (let* ((position
                      (ivory-key.model:device-position-coverage-position coverage))
                    (name (ivory-key.model:identifier-name position)))
               (cond ((gethash name seen)
                      (push (%make-compiler-fidelity-issue
                             name :duplicate-device-position-coverage
                             "Device coverage declares this topology position more than once.")
                            issues))
                     ((not (find position positions
                                 :key #'ivory-key.model:position-name
                                 :test #'ivory-key.model:identifier=))
                      (push (%make-compiler-fidelity-issue
                             name :unknown-device-coverage-position
                             "Device coverage names a position absent from the selected topology.")
                            issues)))
               (setf (gethash name seen) t)))))
    issues))

(defun %push-fidelity-issue-once (issue issues)
  "Preserve one deterministic coverage diagnostic per feature/code pair."
  (if (or (null issue)
          (find issue issues
                :test (lambda (left right)
                        (and (eq (compiler-fidelity-issue-code left)
                                 (compiler-fidelity-issue-code right))
                             (string= (compiler-fidelity-issue-feature left)
                                      (compiler-fidelity-issue-feature right))))))
      issues
      (cons issue issues)))

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

(defun %profile-output-lowering (behavior feature vocabulary
                                 &key allow-kanata-forwarding allow-command-carrier)
  "Return profile spellings for one typed semantic output.

An XKB-owned static table may omit a Kanata spelling: Kanata then forwards the
explicit physical event to XKB.  A patch output may not use that fall-through;
it needs its own checked Kanata action.  Semantic commands remain refused
unless that action is the one closed, source-evidenced carrier form accepted
by the Kanata backend.
"
  (let ((xkb-output
          (%vocabulary-spelling-for-output vocabulary behavior "xkb" feature)))
    (if (typep xkb-output 'compiler-fidelity-issue)
        xkb-output
        (let ((kanata-output
                (%vocabulary-spelling-for-output vocabulary behavior "kanata" feature)))
          (cond ((and allow-kanata-forwarding
                      (typep kanata-output 'compiler-fidelity-issue)
                      (eq (compiler-fidelity-issue-code kanata-output)
                          :missing-vocabulary-mapping))
                 (list :xkb xkb-output))
                ((typep kanata-output 'compiler-fidelity-issue)
                 kanata-output)
                ((and (typep behavior 'ivory-key.model:command-output)
                      (or (not allow-command-carrier)
                          (not (ivory-key.backend::kanata-carrier-action-code
                                kanata-output))))
                 (%make-compiler-fidelity-issue
                  feature :unsupported-command-output
                  "A command needs an exact realization-owned Kanata carrier action."))
                (t (list :xkb xkb-output :kanata kanata-output)))))))

(defun %output-lowering (behavior feature vocabulary &key allow-kanata-forwarding)
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
      (%profile-output-lowering behavior feature vocabulary
                               :allow-kanata-forwarding allow-kanata-forwarding)
      (let ((xkb-output (%static-output-lowering behavior feature)))
        (if (typep xkb-output 'compiler-fidelity-issue)
            xkb-output
            (list :xkb xkb-output)))))

(defun %table-output-lowering (behavior feature vocabulary)
  "Resolve one entry of an XKB-owned static table.

The only non-static outputs admitted here are vocabulary-backed named values;
when their Kanata spelling is intentionally absent, the caller preserves the
physical event.  This does not prove any selector activation.
"
  (if (and vocabulary
           (or (typep behavior 'ivory-key.model:named-key-output)
               (typep behavior 'ivory-key.model:named-symbol-output)
               (typep behavior 'ivory-key.model:command-output)))
      (%profile-output-lowering behavior feature vocabulary
                               :allow-kanata-forwarding t)
      (%output-lowering behavior feature vocabulary)))

(defun %kanata-table-output (lowerings physical-code feature)
  "Return one Kanata output for an XKB-owned static table.

All omitted Kanata spellings mean physical pass-through.  Distinct explicit
spellings would require a selector/layer policy and are therefore refused.
"
  (let ((explicit (remove nil (mapcar (lambda (lowering)
                                        (getf lowering :kanata))
                                      lowerings))))
    (cond ((null explicit) physical-code)
          ((and (= (length explicit) (length lowerings))
                (every (lambda (value) (string= value (first explicit)))
                       explicit))
           (first explicit))
          (t (%make-compiler-fidelity-issue
              feature :unsupported-kanata-context-selection
              "Static table entries require different Kanata outputs; no selector/layer policy is selected.")))))

(defun %xkb-carrier-key-name (carrier)
  "Return the Linux evdev XKB key name for one checked carrier code.

The frozen Manna XKB source uses the standard evdev `I` names: Linux input
code N is XKB key name `I(N+8)`.  This conversion is realization code, never
layout data, and is used only after the profile has supplied the exact
`(arbitrary-code N)` spelling.
"
  (format nil "I~D" (+ carrier 8)))

(defun %carrier-entry (feature carrier xkb-output &key origin)
  (make-instance 'ivory-key.backend:key-entry
                 :position (format nil "carrier-~D/~A" carrier feature)
                 :physical-code (list :xkb (%xkb-carrier-key-name carrier))
                 :outputs (list :xkb (list xkb-output))
                 ;; Carrier entries are materialized from a single sparse
                 ;; patch entry.  Keep that exact source rather than treating
                 ;; the realization-owned carrier spelling as layout data.
                 :sources (list (ivory-key.backend:make-key-entry-source
                                 nil :origin origin))))

(defun %patch-lowering (normalized placement vocabulary issues)
  "Return function-layer metadata, XKB carrier entries, and updated ISSUES.

Sparse patch output is emitted only as an exact, profile-owned carrier pair:
the XKB vocabulary chooses the observable keysym while the Kanata spelling is
the closed arbitrary-code action.  Activation remains a separate explicit
refusal; this function never synthesizes a tap-hold, layer switch, or timing.
"
  (let ((layers nil)
        (carrier-entries nil)
        (allocations nil)
        (reserved (compiler-placement-reserved-carriers placement)))
    (dolist (patch (ivory-key.model:normalized-layout-patches normalized))
      (let ((patch-name (ivory-key.model::normalized-patch-name patch))
            (outputs nil))
        (dolist (entry (ivory-key.model::normalized-patch-bindings patch))
          (unless (eq (cdr entry) :transparent)
            (let* ((binding (cdr entry))
                   (position (ivory-key.model:normalized-binding-position binding))
                   (feature (ivory-key.model:identifier-name position))
                   (variants (ivory-key.model:normalized-binding-entries binding)))
              (cond ((/= (length variants) 1)
                     (push (%make-compiler-fidelity-issue
                            feature :unsupported-patch-context-selection
                            "A sparse patch binding needs one context-independent output.")
                           issues))
                    ((null vocabulary)
                     (push (%make-compiler-fidelity-issue
                            feature :missing-output-vocabulary
                            "A patch output requires a selected realization vocabulary.")
                           issues))
                    (t
                     (let ((lowering
                             (%profile-output-lowering
                              (ivory-key.model:normalized-entry-behavior (first variants))
                              feature vocabulary :allow-command-carrier t)))
                       (cond ((typep lowering 'compiler-fidelity-issue)
                              (push lowering issues))
                             (t
                              (let ((carrier
                                      (ivory-key.backend::kanata-carrier-action-code
                                       (getf lowering :kanata))))
                                (cond ((null carrier)
                                       (push (%make-compiler-fidelity-issue
                                              feature :unsupported-patch-output
                                              "A patch output needs an exact Kanata arbitrary-code carrier action.")
                                             issues))
                                      ((not (member carrier reserved :test #'=))
                                       (push (%make-compiler-fidelity-issue
                                              feature :unreserved-carrier
                                              (format nil "Carrier ~D is not reserved by device ~A."
                                                      carrier
                                                      (compiler-placement-name placement)))
                                             issues))
                                      (t
                                       (push (cons feature (getf lowering :kanata)) outputs)
                                       (let ((origin
                                               (ivory-key.model:normalized-entry-origin
                                                (first variants))))
                                         (push (%carrier-entry feature carrier
                                                               (getf lowering :xkb)
                                                               :origin origin)
                                             carrier-entries)
                                         (push (list :feature feature :carrier carrier
                                                     :xkb-key-name (%xkb-carrier-key-name carrier)
                                                     :keysym (getf lowering :xkb)
                                                     :origin origin)
                                               allocations)))))))))))))
        ;; An inactive layer declaration is safe to inspect and validate, but
        ;; never makes this an exact realization.  The Manna evidence names
        ;; source tap-holds, not an Ivory Key candidate/arbitration contract.
        (push (list :name (ivory-key.model:identifier-name patch-name)
                    :outputs (sort outputs #'string< :key #'car))
              layers)
        (push (%make-compiler-fidelity-issue
               (ivory-key.model:identifier-name patch-name)
               :unproved-patch-activation
               "Patch carrier outputs are allocated, but no semantic activation/timing/arbitration lowering is selected.")
              issues)))
    (values (nreverse layers)
            (sort carrier-entries #'string<
                  :key (lambda (entry)
                         (ivory-key.backend:key-entry-code-for entry :xkb)))
            (sort allocations #'< :key (lambda (row) (getf row :carrier)))
            issues)))

(defun analyze-normalized-layout (normalized placement &key vocabulary selector-policy)
  "Return an inspectable lowering proposal and every blocking fidelity issue.

The proposal retains only individually evidenced direct tables/carriers; a
non-empty issue list means it is not compilable.  In particular, this function
never converts a context level, semantic modifier, interaction, or unknown
vocabulary entry into an approximate direct key mapping.  Call
MAKE-LOWERING-REQUEST-FROM-NORMALIZED-LAYOUT to enforce the final no-issues
compile gate.
"
  (let ((issues nil)
        (entries nil))
    (when selector-policy
      (handler-case
          (ivory-key.model::validate-realization-selector-policy selector-policy)
        (ivory-key.model:semantic-error (condition)
          (%stage-error :lower (ivory-key.model:semantic-error-code condition)
                        "Invalid selector policy: ~A"
                        (ivory-key.model:semantic-error-message condition)))))
    ;; A policy may describe only source-derived carrier/type resources; it is
    ;; not itself proof of the XKB client's group/modifier consumption rules.
    ;; Preserve it on the inspectable request while keeping an explicit gate
    ;; until the backend-specific realization proves that observable boundary.
    (when selector-policy
      (push (%make-compiler-fidelity-issue
             :selector-policy :unproved-native-selector-client-semantics
             "The typed selector policy is available for inspection, but native XKB group/modifier client semantics are not yet proven for exact emission.")
            issues))
    (unless (string= (%layout-topology-name normalized)
                     (compiler-placement-topology placement))
      (push (%make-compiler-fidelity-issue
             :topology :topology-mismatch
             (format nil "Layout topology ~A does not match device topology ~A."
                     (%layout-topology-name normalized)
                     (compiler-placement-topology placement)))
            issues))
    (dolist (issue (%coverage-declaration-issues normalized placement))
      (setf issues (%push-fidelity-issue-once issue issues)))
    ;; A selected project composition is structurally complete only when its
    ;; device states how every topology position is covered.  Do this before
    ;; binding lowering so a position omitted from both device mapping and
    ;; layout binding remains an explicit evidence gap rather than silently
    ;; disappearing from the composition.
    (dolist (position (ivory-key.model:topology-positions
                       (ivory-key.model:normalized-layout-topology normalized)))
      (setf issues
            (%push-fidelity-issue-once
             (%coverage-fidelity-issue placement
                                       (ivory-key.model:position-name position))
             issues)))
    (when (ivory-key.model:modifier-set-members
           (ivory-key.model:normalized-layout-modifiers normalized))
      (push (%make-compiler-fidelity-issue
             :semantic-modifiers :unsupported-semantic-modifiers
             "The bootstrap pipeline has no modifier allocation or consumed-modifier plan.")
            issues))
    (dolist (interaction (ivory-key.model:normalized-layout-interactions normalized))
      ;; Participants are physical inputs even if their behavior is mediated
      ;; by a timed interaction rather than an ordinary binding.  Do not let
      ;; the generic interaction refusal conceal missing/unreachable coverage.
      (dolist (participant
               (ivory-key.model:normalized-interaction-participants interaction))
        (setf issues
              (%push-fidelity-issue-once
               (%coverage-fidelity-issue placement participant :require-mapping t)
               issues)))
      (push (%make-compiler-fidelity-issue
             (ivory-key.model:identifier-name
              (ivory-key.model:normalized-interaction-name interaction))
             :unsupported-timed-interaction
             "Generic timed interactions require an explicit Kanata template lowering.")
            issues))
    ;; Product selectors describe meaning, not a default XKB modifier/group
    ;; arrangement.  Preserve the table data below, but refuse final emission
    ;; until a profile allocates every selector and proves its client-visible
    ;; modifier behavior.
    (dolist (axis (ivory-key.model:normalized-layout-axes normalized))
      (when (eq (ivory-key.model:axis-resolution axis) :product)
        (push (%make-compiler-fidelity-issue
               (ivory-key.model:identifier-name (ivory-key.model:axis-name axis))
               :unsupported-context-selection
               "A product-axis selector needs an explicit realization allocation.")
              issues)))
    ;; Behavioral axes can select ordinary table entries just as product axes
    ;; can.  The bootstrap XKB/Kanata bridge has no latch/hold/lock selector
    ;; lowering or consumption proof, so a distinct table entry behind one of
    ;; these axes must fail closed.  Patch axes are handled independently by
    ;; %PATCH-LOWERING and receive their own activation refusal.
    (dolist (axis (ivory-key.model:normalized-layout-axes normalized))
      (when (and (eq (ivory-key.model:axis-resolution axis) :behavioral)
                 (some (lambda (binding)
                         (member (ivory-key.model:axis-name axis)
                                 (ivory-key.model:normalized-binding-axes binding)
                                 :test #'ivory-key.model:identifier=))
                       (ivory-key.model:normalized-layout-bindings normalized)))
        (push (%make-compiler-fidelity-issue
               (ivory-key.model:identifier-name (ivory-key.model:axis-name axis))
               :unsupported-context-selection
               "A behavioral-axis selector needs an explicit latch/hold/lock realization and consumption proof.")
              issues)))
    (dolist (binding (ivory-key.model:normalized-layout-bindings normalized))
      (let* ((position (ivory-key.model:normalized-binding-position binding))
             (feature (ivory-key.model:identifier-name position))
             (placement-entry (%placement-for-position placement position))
             (coverage-issue
               (%coverage-fidelity-issue placement position :require-mapping t))
             (entries-for-binding (ivory-key.model:normalized-binding-entries binding)))
        (cond
          (coverage-issue
           (setf issues (%push-fidelity-issue-once coverage-issue issues)))
          ((null placement-entry)
           (push (%make-compiler-fidelity-issue
                  feature :missing-device-placement
                  "No physical XKB/Kanata placement is declared for this logical position.")
                 issues))
          (t
           (let ((outputs
                   (mapcar (lambda (entry)
                             (%table-output-lowering
                              (ivory-key.model:normalized-entry-behavior entry)
                              feature vocabulary))
                           entries-for-binding)))
             (let ((failure (find-if (lambda (output)
                                       (typep output 'compiler-fidelity-issue))
                                     outputs)))
               (if failure
                   (push failure issues)
                   (let ((kanata-output
                           (%kanata-table-output outputs
                                                 (getf placement-entry :kanata)
                                                 feature)))
                     (if (typep kanata-output 'compiler-fidelity-issue)
                         (push kanata-output issues)
                         (push (make-instance 'ivory-key.backend:key-entry
                                              :position feature
                                              :physical-code
                                              (list :xkb (getf placement-entry :xkb)
                                                    :kanata (getf placement-entry :kanata))
                                              :outputs
                                              (list :xkb (mapcar (lambda (output)
                                                                   (getf output :xkb))
                                                                 outputs)
                                                    :kanata (list kanata-output))
                                              :sources
                                              (mapcar
                                               (lambda (entry)
                                                 (ivory-key.backend:make-key-entry-source
                                                  (ivory-key.model:normalized-entry-tuple entry)
                                                  :origin
                                                  (ivory-key.model:normalized-entry-origin entry)))
                                               entries-for-binding))
                               entries))))))))))
    (multiple-value-bind (kanata-layers xkb-carrier-entries carrier-allocations updated-issues)
        (%patch-lowering normalized placement vocabulary issues)
      (setf issues updated-issues)
    (setf issues
          (sort issues #'string<
                :key (lambda (issue)
                       (format nil "~A/~A"
                               (compiler-fidelity-issue-feature issue)
                               (compiler-fidelity-issue-code issue)))))
      ;; Keep the evidence-backed partial request available to inspection
      ;; callers together with its blockers.  MAKE-LOWERING-REQUEST below
      ;; remains the compile gate and rejects any non-empty issue list.
      (values (make-instance 'ivory-key.backend:lowering-request
                             :name (ivory-key.model:identifier-name
                                    (ivory-key.model:normalized-layout-name normalized))
                             :entries (nreverse entries)
                             :modifiers nil
                             :interactions nil
                             :metadata
                             (list :xkb-carrier-entries xkb-carrier-entries
                                   :selector-policy selector-policy
                                   :input-coverage
                                   (%input-coverage-records normalized placement)
                                   :kanata-source-order
                                   (mapcar (lambda (mapping)
                                             (cons (car mapping) (getf (cdr mapping) :kanata)))
                                           (compiler-placement-mappings placement))
                                   :kanata-layers kanata-layers
                                   :carrier-allocations carrier-allocations))
              issues))))

(defun make-lowering-request-from-normalized-layout (normalized placement
                                                       &key vocabulary selector-policy)
  "Return a complete bootstrap lowering request or signal its first failure."
  (multiple-value-bind (request issues)
      (analyze-normalized-layout normalized placement :vocabulary vocabulary
                                 :selector-policy selector-policy)
    (if (and request (null issues))
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
                  :vocabulary (compiler-realization-vocabulary realization)
                  :selector-policy
                  (compiler-realization-selector-policy realization))))
    (handler-case
        (ivory-key.backend:compile-xkb-kanata-request request :allow-lossy nil)
      (error (condition)
        (%stage-error :pipeline :backend-refusal "~A" condition)))))

;;; Deterministic inspection -------------------------------------------------

(defun %planner-placement-from-compiler-placement (placement topology)
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
     ;; Keep the normalized topology's positions for coverage inspection, but
     ;; retain the device-declared topology identity so the planner still
     ;; exposes a topology mismatch rather than borrowing it away.
     (ivory-key.model:make-topology
      (compiler-placement-topology placement)
      (ivory-key.model:topology-positions topology))
     (sort mappings #'string< :key #'car)
     :position-coverage
     (copy-list (compiler-placement-position-coverage placement)))))

(defun %plan-normalized-layout-for-inspection (normalized placement)
  "Return a target-neutral capability plan or its structured refusal.

The direct compiler remains intentionally stricter than this inspection:
successful table grading is not permission to emit selectors, semantic
modifiers, named symbols, commands, or interactions.
"
  (handler-case
      (values
       (ivory-key.backend:plan-normalized-layout
        normalized
        (%planner-placement-from-compiler-placement
         placement (ivory-key.model:normalized-layout-topology normalized))
        :backends (list (ivory-key.backend:make-xkb-backend)))
       nil)
    (ivory-key.backend:planner-refusal (condition)
      (values nil condition))
    (ivory-key.model:semantic-error (condition)
      ;; Direct device inspection can surface an unknown coverage position
      ;; only after the selected layout supplies a topology.  Present it as a
      ;; planner disposition instead of leaking a model condition through an
      ;; explain-only API.
      (values nil
              (make-condition 'ivory-key.backend:planner-refusal
                              :code (ivory-key.model:semantic-error-code condition)
                              :detail (ivory-key.model:semantic-error-message condition))))))

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

(defun %realization-result< (left right)
  "Order inspection results by stable semantic identity, never object address."
  (string< (format nil "~A/~A"
                   (%planner-inspection-name
                    (ivory-key.backend:realization-feature left))
                   (%planner-inspection-name
                    (ivory-key.backend:realization-grade left)))
           (format nil "~A/~A"
                   (%planner-inspection-name
                    (ivory-key.backend:realization-feature right))
                   (%planner-inspection-name
                    (ivory-key.backend:realization-grade right)))))

(defun %write-realization-results (stream results)
  "Write complete, source-path-free realization dispositions."
  (if results
      (dolist (result (sort (copy-list results) #'%realization-result<))
        (format stream "  ~A: ~A -- ~A~%"
                (%planner-inspection-name
                 (ivory-key.backend:realization-feature result))
                (%planner-inspection-name
                 (ivory-key.backend:realization-grade result))
                (ivory-key.backend:realization-detail result)))
      (format stream "  none~%")))

(defun %planner-allocation< (left right)
  "Order allocation report rows without relying on resource-pool mutation order."
  (let ((left-requirement (ivory-key.backend:planner-allocation-requirement left))
        (right-requirement (ivory-key.backend:planner-allocation-requirement right)))
    (string<
     (format nil "~A/~A/~A"
             (%planner-inspection-name
              (ivory-key.backend:planner-allocation-pool-kind left))
             (%planner-inspection-name
              (ivory-key.backend:planner-resource-requirement-owner left-requirement))
             (ivory-key.backend:planner-allocation-value left))
     (format nil "~A/~A/~A"
             (%planner-inspection-name
              (ivory-key.backend:planner-allocation-pool-kind right))
             (%planner-inspection-name
              (ivory-key.backend:planner-resource-requirement-owner right-requirement))
             (ivory-key.backend:planner-allocation-value right)))))

(defun %write-planner-allocations (stream plan)
  "Write all finite reservations, without claiming that reservation is lowering."
  (format stream "Planner allocations (not lowering proof)~%")
  (let ((allocations (ivory-key.backend:lowering-plan-allocations plan)))
    (if allocations
        (dolist (allocation (sort (copy-list allocations) #'%planner-allocation<))
          (let ((requirement
                  (ivory-key.backend:planner-allocation-requirement allocation)))
            (format stream "  ~A ~A -> ~A~%"
                    (%planner-inspection-name
                     (ivory-key.backend:planner-allocation-pool-kind allocation))
                    (%planner-inspection-name
                     (ivory-key.backend:planner-resource-requirement-owner requirement))
                    (ivory-key.backend:planner-allocation-value allocation))))
        (format stream "  none~%"))))

(defun %write-planner-interaction-obligations (stream plan)
  "Show every timed interaction as a semantic planner obligation."
  (format stream "Planner timed-interaction obligations~%")
  (let ((interactions
          (sort (copy-list
                 (ivory-key.model:normalized-layout-interactions
                  (ivory-key.backend:lowering-plan-layout plan)))
                #'ivory-key.model:identifier<
                :key #'ivory-key.model:normalized-interaction-name)))
    (if interactions
        (dolist (interaction interactions)
          (format stream "  ~A~%"
                  (ivory-key.model:identifier-name
                   (ivory-key.model:normalized-interaction-name interaction))))
        (format stream "  none~%"))))

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
  (%write-planner-interaction-obligations stream plan)
  (format stream "Planner realization grades (complete)~%")
  (%write-realization-results
   stream (ivory-key.backend:lowering-plan-realizations plan))
  (%write-planner-allocations stream plan)
  plan)

(defun planned-layout-dump-string (unit placement realization)
  "Return a deterministic, non-emitting capability-planning IR dump.

Planning records a selected profile only after its existing direct-pipeline
compatibility check; it still classifies unsupported obligations rather than
pretending the profile can lower them.  This function never constructs backend
plans, artifact text, contract data, or output paths.
"
  (%require-compatible-realization realization)
  (multiple-value-bind (plan refusal)
      (%plan-normalized-layout-for-inspection
       (compiler-unit-normalized unit) placement)
    (with-output-to-string (stream)
      (format stream "planned-ir ~A~%"
              (ivory-key.model:identifier-name
               (ivory-key.model:normalized-layout-name
                (compiler-unit-normalized unit))))
      (format stream "device ~A~%realization ~A~%"
              (compiler-placement-name placement)
              (compiler-realization-name realization))
      (%write-planner-inspection stream plan refusal))))

(defun %write-backend-request-entry (stream entry)
  "Write the closed, already-decoded backend spellings for one key entry."
  (format stream "  ~A: xkb ~A => ~{~A~^ ~}; kanata ~A => ~{~A~^ ~}~%"
          (ivory-key.backend:key-entry-position entry)
          (ivory-key.backend:key-entry-code-for entry :xkb)
          (ivory-key.backend:key-entry-outputs-for entry :xkb)
          (ivory-key.backend:key-entry-code-for entry :kanata)
          (ivory-key.backend:key-entry-outputs-for entry :kanata)))

(defun %backend-request-entry< (left right)
  (string< (ivory-key.backend:key-entry-position left)
           (ivory-key.backend:key-entry-position right)))

(defun %write-backend-request-inspection (stream request)
  "Write backend-request data without serializing opaque or pathname metadata."
  (format stream "Backend lowering request~%")
  (format stream "  name: ~A~%" (ivory-key.backend:lowering-request-name request))
  (format stream "  entries~%")
  (let ((entries (ivory-key.backend:lowering-request-entries request)))
    (if entries
        (dolist (entry (sort (copy-list entries) #'%backend-request-entry<))
          (%write-backend-request-entry stream entry))
        (format stream "    none~%")))
  (format stream "  metadata: only closed backend fields are shown~%")
  (let ((metadata (ivory-key.backend:lowering-request-metadata request)))
    (dolist (record (or (getf metadata :input-coverage) nil))
      (format stream "    coverage ~A: ~A~%"
              (getf record :position)
              (%coverage-disposition-name (getf record :disposition))))
    (dolist (allocation (or (getf metadata :carrier-allocations) nil))
      (format stream "    carrier ~A: code ~D; XKB key ~A; keysym ~A~%"
              (getf allocation :feature) (getf allocation :carrier)
              (getf allocation :xkb-key-name) (getf allocation :keysym)))))

(defun %write-xkb-plan-inspection (stream plan)
  "Write one XKB backend IR, never its emitted keymap text."
  (format stream "XKB backend plan~%")
  (format stream "  name: ~A~%" (ivory-key.backend::xkb-plan-name plan))
  (format stream "  entries~%")
  (let ((entries (ivory-key.backend::xkb-plan-entries plan)))
    (if entries
        (dolist (entry (sort (copy-list entries) #'string<
                              :key (lambda (entry)
                                     (ivory-key.backend:key-entry-code-for entry :xkb))))
          (format stream "    <~A> => ~{~A~^ ~}~%"
                  (ivory-key.backend:key-entry-code-for entry :xkb)
                  (ivory-key.backend:key-entry-outputs-for entry :xkb)))
        (format stream "    none~%")))
  (format stream "  realization grades~%")
  (%write-realization-results stream (ivory-key.backend:xkb-plan-realizations plan)))

(defun %write-kanata-plan-inspection (stream plan)
  "Write one Kanata backend IR, never its emitted configuration text."
  (format stream "Kanata backend plan~%")
  (format stream "  name: ~A~%" (ivory-key.backend::kanata-plan-name plan))
  (format stream "  source/output rows~%")
  (let ((sources (ivory-key.backend::kanata-plan-sources plan))
        (outputs (ivory-key.backend::kanata-plan-outputs plan)))
    (if sources
        (loop for source in sources
              for output in outputs do
                (format stream "    ~A => ~A~%" source output))
        (format stream "    none~%")))
  (format stream "  realization grades~%")
  (%write-realization-results stream (ivory-key.backend:kanata-plan-realizations plan)))

(defun %backend-request-for-inspection (unit placement realization)
  "Return an all-exact request or fail before target plan construction."
  (%require-compatible-realization realization)
  (multiple-value-bind (request issues)
      (analyze-normalized-layout
       (compiler-unit-normalized unit) placement
       :vocabulary (compiler-realization-vocabulary realization)
       :selector-policy (compiler-realization-selector-policy realization))
    (unless request
      (%stage-error :backend :missing-lowering-request
                    "No inspectable backend request was produced."))
    (when issues
      (let ((issue (first issues)))
        (%stage-error :backend (compiler-fidelity-issue-code issue)
                      "~A: ~A"
                      (compiler-fidelity-issue-feature issue)
                      (compiler-fidelity-issue-detail issue))))
    request))

(defun backend-layout-dump-string (unit placement realization)
  "Return deterministic backend IR after exact lowering, without emission.

Only an all-exact direct request reaches this stage.  Backend plans remain
in-memory values; this function does not call EMIT-PLAN, create a pipeline
result, write artifacts, invoke validators, or allocate an output directory.
"
  (let ((request (%backend-request-for-inspection unit placement realization)))
    (handler-case
        (let* ((xkb-plan
                 (ivory-key.backend:lower-request
                  (ivory-key.backend:make-xkb-backend) request))
               (kanata-plan
                 (ivory-key.backend:lower-request
                  (ivory-key.backend:make-kanata-backend) request))
               (results
                 (append (ivory-key.backend:xkb-plan-realizations xkb-plan)
                         (ivory-key.backend:kanata-plan-realizations kanata-plan))))
          ;; Backend capability shape can still reject an otherwise accepted
          ;; compiler request.  Do not print that plan as successful or enter
          ;; pipeline/artifact construction; convert it into one stable stage
          ;; refusal instead.
          (ivory-key.backend:require-permitted-realizations results :allow-lossy nil)
          (with-output-to-string (stream)
            (format stream "backend-ir ~A~%"
                    (ivory-key.backend:lowering-request-name request))
            (format stream "device ~A~%realization ~A~%"
                    (compiler-placement-name placement)
                    (compiler-realization-name realization))
            (%write-backend-request-inspection stream request)
            (%write-xkb-plan-inspection stream xkb-plan)
            (%write-kanata-plan-inspection stream kanata-plan)))
      (compiler-stage-error (condition) (error condition))
      (error (condition)
        (%stage-error :backend :backend-refusal "~A" condition)))))

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

(defun %expected-staged-artifact-file-names (pipeline-result &optional marker)
  "Return the exact backend-owned files permitted before contract rendering."
  (let ((names
          (append (mapcar #'ivory-key.backend:pipeline-artifact-relative-path
                          (ivory-key.backend:pipeline-result-artifacts pipeline-result))
                  (and marker (list marker)))))
    (unless (= (length names) (length (remove-duplicates names :test #'string=)))
      (%stage-error :emit :duplicate-artifact-path
                    "Backend returned duplicate artifact paths."))
    (sort names #'string<)))

(defun %expected-build-file-names (pipeline-result &optional marker)
  (let ((names
          (append (%expected-staged-artifact-file-names pipeline-result)
                  ;; The contract files are fixed compiler outputs, not backend
                  ;; artifacts.  Keeping them in this exact content check means
                  ;; an interrupted emission cannot publish a partial contract.
                  (list "manifest.json" "allocations.json" "source-map.json"
                        "REPORT.md")
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

(defun %validation-backend-for-artifact (artifact)
  "Return the exact backend that owns ARTIFACT's validator, or refuse."
  (case (ivory-key.backend:pipeline-artifact-kind artifact)
    (:xkb (ivory-key.backend:make-xkb-backend))
    (:kanata (ivory-key.backend:make-kanata-backend))
    (otherwise
     (%stage-error :validate-before-publish :unsupported-validation-artifact
                   "No staged validator is defined for artifact kind ~S."
                   (ivory-key.backend:pipeline-artifact-kind artifact)))))

(defun %staged-artifact-pathname (artifact temporary)
  (let ((relative (ivory-key.backend:pipeline-artifact-relative-path artifact)))
    (unless (%safe-artifact-relative-path-p relative)
      (%stage-error :validate-before-publish :unsafe-artifact-path
                    "Cannot validate unsafe artifact path ~S." relative))
    (let ((pathname (merge-pathnames relative temporary)))
      (unless (probe-file pathname)
        (%stage-error :validate-before-publish :missing-staged-artifact
                      "Staged artifact ~A is missing before validation." relative))
      pathname)))

(defun %staged-artifact-digests (pipeline-result temporary)
  "Hash the exact artifact bytes that are about to be externally validated."
  (sort
   (mapcar
    (lambda (artifact)
      (let ((relative (ivory-key.backend:pipeline-artifact-relative-path artifact)))
        (handler-case
            (cons relative
                  (ivory-key.build-contract:sha256-hex
                   (%staged-artifact-pathname artifact temporary)))
          (error (condition)
            (%stage-error :validate-before-publish :staged-artifact-hash-failure
                          "Could not hash staged artifact ~A: ~A" relative condition)))))
    (ivory-key.backend:pipeline-result-artifacts pipeline-result))
   #'string< :key #'car))

(defun %validation-version-output (program)
  "Run PROGRAM --version through an argument vector, never a shell command."
  (handler-case
      (values t
              (uiop:run-program (list program "--version")
                                :output :string :error-output :output))
    (error (condition)
      (values nil (princ-to-string condition)))))

(defun %normalized-validation-version (program output)
  "Return a bounded one-line version value safe to publish with PROGRAM.

The raw stream remains evidence only by hash.  A version probe which emits an
empty, multiline, control-containing, or path-like response is not safe to
turn into a build manifest claim and therefore fails closed before publication.
"
  (unless (stringp output)
    (%stage-error :validate-before-publish :invalid-validation-version
                  "Validator ~A did not return string version output." program))
  (let ((normalized (string-trim '(#\Space #\Tab #\Newline #\Return) output)))
    (unless (and (plusp (length normalized))
                 (<= (length normalized) 256)
                 (not (find #\Newline normalized))
                 (not (find #\Return normalized))
                 (not (find #\\ normalized))
                 (not (find #\/ normalized))
                 (every (lambda (character)
                          (<= 32 (char-code character) 126))
                        normalized))
      (%stage-error :validate-before-publish :unsafe-validation-version
                    "Validator ~A returned a version string unsafe for publication."
                    program))
    normalized))

(defun %staged-validation-evidence-record (artifact program version-output
                                             status result-output)
  "Make privacy-preserving exact evidence for one direct validator invocation."
  (unless (and (stringp result-output) (member status '("passed" "failed" "unavailable")
                                             :test #'string=))
    (%stage-error :validate-before-publish :invalid-validation-result
                  "Validator ~A returned malformed result evidence." program))
  (list :artifact artifact
        :tool program
        :version (%normalized-validation-version program version-output)
        :version-sha256 (ivory-key.build-contract:sha256-hex version-output)
        :status status
        :result-sha256 (ivory-key.build-contract:sha256-hex result-output)))

(defun %run-staged-pipeline-validation (pipeline-result temporary)
  "Return closed evidence for validation of staged artifacts in TEMPORARY.

An unavailable version probe is a validation result, not an optimistic skip.
The caller records it in the retained staging contract and refuses publication.
"
  (mapcar
   (lambda (artifact)
     (let* ((backend (%validation-backend-for-artifact artifact))
            (program (ivory-key.backend:capability-validation-program
                      (ivory-key.backend:capabilities backend)))
            (relative (ivory-key.backend:pipeline-artifact-relative-path artifact))
            (pathname (%staged-artifact-pathname artifact temporary)))
       (unless (and (stringp program) (plusp (length program)))
         (%stage-error :validate-before-publish :missing-validation-program
                       "Artifact ~A has no configured validation program." relative))
       (multiple-value-bind (version-available-p version-output)
           (%validation-version-output program)
         (if (not version-available-p)
             ;; Version output still has an exact digest, but no observed
             ;; version can be published when the probe itself is unavailable.
             (list :artifact relative :tool program :version "unavailable"
                   :version-sha256 (ivory-key.build-contract:sha256-hex version-output)
                   :status "unavailable"
                   :result-sha256 (ivory-key.build-contract:sha256-hex version-output))
             (handler-case
                 (multiple-value-bind (success output arguments)
                     (ivory-key.backend:validate-artifact backend pathname)
                   ;; Backend methods already own their direct argument vectors;
                   ;; they are intentionally not serialized because TEMPORARY is
                   ;; randomized and must not leak into the immutable contract.
                   (declare (ignore arguments))
                   (%staged-validation-evidence-record
                    relative program version-output (if success "passed" "failed") output))
               (error (condition)
                 (%staged-validation-evidence-record
                  relative program version-output "failed" (princ-to-string condition))))))))
   (sort (copy-list (ivory-key.backend:pipeline-result-artifacts pipeline-result))
         #'string< :key #'ivory-key.backend:pipeline-artifact-relative-path)))

(defparameter *staged-pipeline-validation-runner*
  #'%run-staged-pipeline-validation
  "Internal test seam for the staged validator; production uses direct tools.")

(defun %passed-staged-validation-p (evidence)
  (and evidence
       (every (lambda (record)
                (and (listp record)
                     (string= (getf record :status) "passed")))
              evidence)))

(defun %validation-evidence-covers-staged-artifacts-p (pipeline-result evidence)
  "Whether EVIDENCE gives one unambiguous validator result per emitted artifact."
  (let ((expected
          (sort
           (mapcar #'ivory-key.backend:pipeline-artifact-relative-path
                   (ivory-key.backend:pipeline-result-artifacts pipeline-result))
           #'string<))
        (observed
          (sort (mapcar (lambda (record) (getf record :artifact)) evidence)
                #'string<)))
    (equal expected observed)))

(defun %staged-validation-summary (evidence)
  (format nil "~{~A~^, ~}"
          (mapcar (lambda (record)
                    (format nil "~A/~A" (getf record :tool)
                            (getf record :status)))
                  evidence)))

(defun write-new-pipeline-result (pipeline-result output-directory
                                  &key build-contract validate-before-publish)
  "Write a new build through a reserved sibling directory without overwriting.

The current backend API owns deterministic artifact text but not atomic output
handling.  With VALIDATE-BEFORE-PUBLISH true, direct argument-vector validators
run only against the verified staging directory, their result is rendered into
a fresh immutable contract, and any non-pass refuses the final rename.  NIL
preserves ordinary compilation without tool invocation.  Post-build validation
remains a separate read-only observation.  Portable Common Lisp cannot make a
final directory rename non-replacing against a hostile concurrent writer, so
OUTPUT-DIRECTORY's existing parent must be trusted and not concurrently mutable
by an untrusted principal.
"
  (unless build-contract
    (%stage-error :emit :missing-build-contract
                  "Build emission requires an explicit generated-output contract."))
  (unless (member validate-before-publish '(nil t))
    (%stage-error :arguments :invalid-validation-mode
                  "VALIDATE-BEFORE-PUBLISH must be true or NIL, got ~S."
                  validate-before-publish))
  (when (and (not validate-before-publish)
             (ivory-key.build-contract::build-contract-validation-evidence
              build-contract))
    (%stage-error :emit :validation-evidence-without-validation
                  "Refusing to publish supplied validation evidence without a staged validation run."))
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
             ;; Verify the staging directory before a validator is allowed to
             ;; inspect it.  At this point it contains exactly backend artifacts
             ;; plus our ownership marker—not a partially published contract.
             (%verify-temporary-build-directory
              temporary parent
              (%expected-staged-artifact-file-names pipeline-result marker))
             (let ((final-contract build-contract))
               (if validate-before-publish
                   (let* ((before (%staged-artifact-digests pipeline-result temporary))
                          (evidence
                            (funcall *staged-pipeline-validation-runner*
                                     pipeline-result temporary))
                          (after (%staged-artifact-digests pipeline-result temporary)))
                     ;; A validator must not change the artifact bytes it just
                     ;; accepted.  The manifest hashes below therefore name the
                     ;; exact bytes validated in this trusted staging directory.
                     (unless (equal before after)
                       (%stage-error :validate-before-publish :staged-artifact-changed
                                     "Validation changed a staged artifact; refusing publication."))
                     (setf final-contract
                           (ivory-key.build-contract::with-build-contract-validation-evidence
                            build-contract evidence))
                     (unless (%validation-evidence-covers-staged-artifacts-p
                              pipeline-result
                              (ivory-key.build-contract::build-contract-validation-evidence
                               final-contract))
                       (%stage-error :validate-before-publish
                                     :incomplete-validation-evidence
                                     "Staged validation must report exactly one result for every emitted artifact."))
                     ;; Failed and unavailable observations are retained in this
                     ;; private staging contract for diagnosis, then the target is
                     ;; refused below.  They are never renamed into a build.
                     (ivory-key.build-contract:write-build-contract-files
                      final-contract temporary)
                     (%verify-temporary-build-directory
                      temporary parent (%expected-build-file-names pipeline-result marker))
                     (unless (%passed-staged-validation-p evidence)
                       (%stage-error :validate-before-publish :validation-failed
                                     "Refusing to publish staged build ~A: ~A."
                                     temporary (%staged-validation-summary evidence))))
                   (ivory-key.build-contract:write-build-contract-files
                    final-contract temporary))
               (%verify-temporary-build-directory
                temporary parent (%expected-build-file-names pipeline-result marker)))
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

(defun %source-hash-records-for-pathnames (labeled-pathnames)
  "Hash each (LOGICAL-IDENTITY . PATHNAME) source without exposing PATHNAME.

The label is a stable build-contract identity, not a physical source location.
Compilation performs no source discovery here: direct mode supplies fixed role
labels and project mode supplies labels for the project loader's completed,
confined import graph.  A changed, unreadable, or ambiguously labelled source
is an emission refusal, never an omitted manifest entry.
"
  (let ((seen (make-hash-table :test #'equal))
        (records nil))
    (dolist (source labeled-pathnames)
      (unless (and (consp source) (stringp (car source))
                   (plusp (length (car source))))
        (%stage-error :emit :invalid-contract-source-identity
                      "Build-contract source identity must be a non-empty string, got ~S."
                      source))
      (let ((identity (car source))
            (pathname (cdr source)))
        (when (gethash identity seen)
          (%stage-error :emit :ambiguous-contract-source-identity
                        "Build-contract source identity ~S names more than one input."
                        identity))
        (setf (gethash identity seen) t)
        (let ((physical
                (handler-case
                    (truename pathname)
                  (error (condition)
                    (%stage-error :emit :unreadable-contract-source
                                  "Could not re-open source ~A for its contract hash: ~A"
                                  pathname condition)))))
          (push
           (handler-case
               (ivory-key.build-contract:make-source-hash-record
                identity (ivory-key.build-contract:sha256-hex physical))
             (error (condition)
               (%stage-error :emit :source-hash-failure
                             "Could not hash source identity ~A for the build contract: ~A"
                             identity condition)))
           records))))
    (sort records #'string<
          :key #'ivory-key.build-contract:source-hash-record-path)))

(defun %contract-source-name-identities (labeled-pathnames)
  "Resolve parser source-file names to stable contract input identities.

The parser may have retained either the spelling supplied to PARSE-FILE or a
canonical physical spelling supplied by the confined project loader.  Both are
accepted here, but neither physical pathname enters BUILD-CONTRACT.  If one
parser name could designate two declared contract identities, provenance would
be ambiguous after relocation, so final emission fails closed.
"
  (let ((by-name (make-hash-table :test #'equal))
        (known-identities (make-hash-table :test #'equal))
        (result nil))
    (dolist (source labeled-pathnames)
      (unless (and (consp source) (stringp (car source))
                   (plusp (length (car source))))
        (%stage-error :emit :invalid-contract-source-identity
                      "Build-contract source identity must be a non-empty string, got ~S."
                      source))
      (let ((identity (car source))
            (pathname (cdr source)))
        (when (gethash identity known-identities)
          (%stage-error :emit :ambiguous-contract-source-identity
                        "Build-contract source identity ~S names more than one input."
                        identity))
        (setf (gethash identity known-identities) t)
        (let ((physical
                (handler-case
                    (truename pathname)
                  (error (condition)
                    (%stage-error :emit :unreadable-contract-source
                                  "Could not re-open source ~A for provenance: ~A"
                                  pathname condition)))))
          (dolist (name
                   (remove-duplicates
                    (list (namestring (uiop:ensure-pathname pathname))
                          (uiop:native-namestring
                           (uiop:ensure-pathname pathname))
                          (namestring physical)
                          (uiop:native-namestring physical))
                    :test #'string=))
            (let ((previous (gethash name by-name)))
              (cond ((null previous)
                     (setf (gethash name by-name) identity))
                    ((not (string= previous identity))
                     (%stage-error :emit :ambiguous-contract-origin-source
                                   "Parser source name ~S maps to both contract inputs ~S and ~S."
                                   name previous identity))))))))
    (maphash (lambda (name identity)
               (push (cons name identity) result))
             by-name)
    ;; Physical names are deliberately consumed only above.  Sort by internal
    ;; parser-name key for deterministic construction; renderers serialize the
    ;; stable identity values only.
    (sort result #'string< :key #'car)))

(defun %contract-project-roots (project-path source-roots)
  "Return the project's canonical source roots.

Physical roots are local authority only: they determine whether an already
loaded source is confined and which most-specific root supplies its relative
identity.  No physical pathname or root ordering enters generated data.
"
  (let* ((working-directory
           (uiop:ensure-directory-pathname (truename (uiop:getcwd))))
         (entry (uiop:ensure-absolute-pathname project-path working-directory))
         (roots (or source-roots
                    (list (uiop:pathname-directory-pathname entry)))))
    (unless (listp roots)
      (setf roots (list roots)))
    (handler-case
        (remove-duplicates
         (mapcar (lambda (root)
                   (uiop:ensure-directory-pathname
                    (truename
                     (uiop:ensure-directory-pathname
                      (uiop:ensure-absolute-pathname root working-directory)))))
                 roots)
         :test #'equal)
      (error (condition)
        (%stage-error :emit :unreadable-contract-source-root
                      "Could not canonicalize a project source root: ~A" condition)))))

(defun %contract-relative-source-path (source root)
  "Return SOURCE relative to ROOT using stable slash-separated components."
  (let* ((source-directory (pathname-directory source))
         (root-directory (pathname-directory root))
         (root-length (length root-directory)))
    (unless (and (<= root-length (length source-directory))
                 (equal root-directory (subseq source-directory 0 root-length)))
      (%stage-error :emit :source-outside-contract-root
                    "Project source ~A is outside its selected source root."
                    source))
    (let ((components
            (append (subseq source-directory root-length)
                    (list (file-namestring source)))))
      (unless (and components
                   (every (lambda (component)
                            (and (stringp component) (plusp (length component))
                                 (not (string= component "."))
                                 (not (string= component ".."))))
                          components))
        (%stage-error :emit :invalid-contract-relative-source
                      "Could not derive a safe relative identity for source ~A."
                      source))
      (format nil "~{~A~^/~}" components))))

(defun %project-contract-source-inputs (project-path source-roots source-paths)
  "Make stable most-specific-root-relative identities for loaded project sources."
  (let ((roots (%contract-project-roots project-path source-roots))
        (inputs nil))
    (dolist (source-path source-paths)
      (let* ((physical
               (handler-case
                   (truename source-path)
                 (error (condition)
                   (%stage-error :emit :unreadable-contract-source
                                 "Could not re-open project source ~A: ~A"
                                 source-path condition))))
             (candidates
               (loop for root in roots
                     when (uiop:subpathp physical root)
                       collect root)))
        (unless candidates
          (%stage-error :emit :source-outside-contract-root
                        "Loaded project source ~A is outside every configured source root."
                        source-path))
        ;; A nested root supplies the most descriptive identity.  There is no
        ;; ordering fallback: physical roots must never influence an emitted
        ;; label.  Equal-depth distinct canonical roots cannot both contain a
        ;; physical path, but refuse defensively if a host violates that fact.
        (let* ((maximum-depth
                 (loop for root in candidates
                       maximize (length (pathname-directory root))))
               (most-specific
                 (remove maximum-depth candidates :test-not #'=
                         :key (lambda (root) (length (pathname-directory root)))))
               (selected (first most-specific)))
          (unless (= (length most-specific) 1)
            (%stage-error :emit :ambiguous-contract-source-root
                          "Loaded project source ~A has no unique most-specific source root."
                          source-path))
          (let ((identity (%contract-relative-source-path physical selected)))
            (push (cons identity physical) inputs)))))
    ;; The hash-record constructor rejects an identical relative path across
    ;; roots, rather than introducing a physical-root discriminator.
    (nreverse inputs)))

(defun %build-contract-for-pipeline (unit placement realization pipeline-result
                                      source-inputs)
  "Make one data-only output contract for the current exact direct pipeline."
  (let* ((normalized (compiler-unit-normalized unit))
         (topology (ivory-key.model:normalized-layout-topology normalized))
         ;; This request reached a pipeline result only through the final
         ;; no-issues compile gate.  The contract layer independently accepts
         ;; only :PHYSICAL/:UNREACHABLE records, so an inspection-only missing
         ;; state can never be published as successful build data.
         (input-coverage
           (getf (ivory-key.backend:lowering-request-metadata
                  (ivory-key.backend:pipeline-result-request pipeline-result))
                 :input-coverage)))
    (ivory-key.build-contract:make-build-contract
     :layout (ivory-key.model:identifier-name
              (ivory-key.model:normalized-layout-name normalized))
     :topology (ivory-key.model:identifier-name
                (ivory-key.model:topology-name topology))
     :device (compiler-placement-name placement)
     :profile (compiler-realization-name realization)
     :source-hashes (%source-hash-records-for-pathnames source-inputs)
     :source-name-identities (%contract-source-name-identities source-inputs)
     :input-coverage input-coverage
     :pipeline-result pipeline-result)))

(defun compile-layout-source (layout-path &key topology-path device-path
                                          realization-path output-directory
                                          validate-before-publish)
  "Compile one fully-supported layout into a new non-deploying build directory.

VALIDATE-BEFORE-PUBLISH is explicit opt-in environmental evidence.  Ordinary
compilation remains tool-free, while an enabled path refuses publication unless
each staged artifact has passed its exact backend validator.
"
  (unless (and device-path realization-path output-directory)
    (%stage-error :arguments :missing-compile-input
                  "Compile requires layout, device, realization, and output paths."))
  (let* ((unit (load-layout-for-compilation layout-path :topology-path topology-path))
         (placement (decode-device-source device-path))
         (realization (decode-realization-source realization-path))
         (pipeline-result (%compile-unit-to-pipeline unit placement realization))
         (build-contract
           (%build-contract-for-pipeline
            unit placement realization pipeline-result
            (remove nil
                    (list (cons "layout" layout-path)
                          (and topology-path (cons "topology" topology-path))
                          (cons "device" device-path)
                          (cons "realization" realization-path))))))
    (write-new-pipeline-result pipeline-result output-directory
                               :build-contract build-contract
                               :validate-before-publish validate-before-publish)
    pipeline-result))

(defun compile-project-source (project-path composition-name &key source-roots
                                                        output-directory
                                                        validate-before-publish)
  "Compile one named project composition into a fresh non-deploying build.

PROJECT-PATH is loaded exactly once by the confined project loader.  The
selected composition supplies its already-resolved layout, device placement,
and realization profile; no imported source is parsed again by this bridge.
"
  (unless output-directory
    (%stage-error :arguments :missing-compile-input
                  "Project compile requires a project, composition, and output path."))
  (multiple-value-bind (unit placement realization composition project-result)
      (load-project-composition-for-compilation project-path composition-name
                                                :source-roots source-roots)
    (declare (ignore composition))
    (let* ((pipeline-result (%compile-unit-to-pipeline unit placement realization))
           (build-contract
             (%build-contract-for-pipeline
              unit placement realization pipeline-result
              (%project-contract-source-inputs
               project-path source-roots
               (ivory-key.project:project-load-result-source-paths project-result)))))
      (write-new-pipeline-result pipeline-result output-directory
                                 :build-contract build-contract
                                 :validate-before-publish validate-before-publish)
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
         :vocabulary (compiler-realization-vocabulary realization)
         :selector-policy
         (compiler-realization-selector-policy realization))
      (format stream "Ivory Key capability explanation~%")
      (format stream "Layout: ~A~%Device: ~A~%Realization: ~A~%"
              (ivory-key.model:identifier-name
               (ivory-key.model:normalized-layout-name (compiler-unit-normalized unit)))
              (compiler-placement-name placement)
              (compiler-realization-name realization))
      (format stream "Input coverage:~%")
      (dolist (record (%input-coverage-records
                       (compiler-unit-normalized unit) placement))
        (format stream "  ~A: ~A~%"
                (getf record :position)
                (%coverage-disposition-name (getf record :disposition))))
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

(defun preflight-build-directory (directory)
  "Read-only generated-build integrity preflight for controlled integration.

Unlike VALIDATE-BUILD-DIRECTORY, this invokes no external validator.  It checks
the generated contract's fixed artifact inventory, hashes, and relocatable
provenance records through BUILD-CONTRACT's non-evaluating decoder.  It cannot
install, activate, reload, or otherwise contact a keyboard/service/device.
"
  (handler-case
      (ivory-key.build-contract:preflight-build-contract-directory directory)
    (error (condition)
      (%stage-error :preflight-build :invalid-generated-build-contract "~A" condition))))

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
