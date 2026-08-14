;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Closed structural compatibility contracts for bounded timed interactions.

(in-package #:ivory-key.model)

;;; These values are deliberately model-only.  They do not select a backend
;;; action, simulate a foreign event, or make a positive compatibility claim.
;;; A later planner may consume only a contract which this strict structural
;;; gate has derived from normalized, instance-materialized model objects.

(defclass normalized-interaction-compatibility-contract ()
  ((mode :initarg :mode :reader interaction-compatibility-contract-mode)
   (interaction :initarg :interaction
                :reader interaction-compatibility-contract-interaction)
   (owner :initarg :owner :reader interaction-compatibility-contract-owner)
   ;; This is the normalized interaction's real source origin, or NIL for a
   ;; deliberately programmatic layout.  It is never reconstructed from a
   ;; pathname or an object printer.
   (origin :initarg :origin :reader interaction-compatibility-contract-origin))
  (:documentation
   "Immutable-by-convention compatibility evidence for one normalized interaction."))

(defclass interaction-compatibility-role-reference ()
  ((role :initarg :role :reader interaction-compatibility-role-reference-role)
   (candidate :initarg :candidate
              :reader interaction-compatibility-role-reference-candidate)
   (origin :initarg :origin
           :reader interaction-compatibility-role-reference-origin))
  (:documentation
   "One canonical semantic role and its normalized candidate evidence."))

(defclass interaction-compatibility-held-effect-signature ()
  ((kind :initarg :kind :reader interaction-compatibility-held-effect-signature-kind)
   ;; IDENTITY is a semantic modifier or context-axis identifier.  STATE is
   ;; meaningful only for :AXIS-STATE; RELEASE records the lifecycle boundary
   ;; rather than a simulator- or backend-specific owner token.
   (identity :initarg :identity
             :reader interaction-compatibility-held-effect-signature-identity)
   (state :initarg :state :initform nil
          :reader interaction-compatibility-held-effect-signature-state)
   (release :initarg :release
            :reader interaction-compatibility-held-effect-signature-release))
  (:documentation
   "The one owner-scoped held semantic effect proven by two hold candidates."))

(defclass interaction-compatibility-contract-provenance ()
  ((interaction-origin :initarg :interaction-origin
                       :reader interaction-compatibility-provenance-interaction-origin)
   (timeout-origin :initarg :timeout-origin
                   :reader interaction-compatibility-provenance-timeout-origin)
   (foreign-release-origin :initarg :foreign-release-origin
                           :reader interaction-compatibility-provenance-foreign-release-origin)
   (tap-origin :initarg :tap-origin
               :reader interaction-compatibility-provenance-tap-origin))
  (:documentation
   "Source origin records carried through a compatibility contract unchanged."))

(defclass release-trigger-interaction-compatibility-contract
    (normalized-interaction-compatibility-contract)
  ((role-references :initarg :role-references
                    :reader release-trigger-interaction-compatibility-contract-role-references)
   (deadline :initarg :deadline
             :reader release-trigger-interaction-compatibility-contract-deadline)
   (capture-name :initarg :capture-name
                 :reader release-trigger-interaction-compatibility-contract-capture-name)
   (held-effect-signature :initarg :held-effect-signature
                          :reader release-trigger-interaction-compatibility-contract-held-effect-signature)
   (tap-key :initarg :tap-key
            :reader release-trigger-interaction-compatibility-contract-tap-key)
   (provenance :initarg :provenance
               :reader release-trigger-interaction-compatibility-contract-provenance))
  (:documentation
   "The common, fully structural release-trigger contract payload."))

(defclass pending-foreign-interval-contract
    (release-trigger-interaction-compatibility-contract) ()
  (:documentation
   "A bounded Kanata 1.12 foreign-interval observation contract, not lowering."))

(defclass modern-no-delay-interaction-compatibility-contract
    (release-trigger-interaction-compatibility-contract) ()
  (:documentation
   "A bounded no-delay foreign-interval observation contract, not lowering."))

;; This is a deliberately closed positive evidence boundary, not a taxonomy
;; for interaction syntax, source aliases, or context selectors.  Each entry
;; has the materialized interaction identity followed by its exact owner, D,
;; held signature, tap identity, and capture name:
;;
;;   (INSTANCE OWNER D HOLD-KIND HOLD-IDENTITY HOLD-STATE TAP CAPTURE)
;;
;; The table contains the 14 primary instances with buffered-runtime evidence.
;; The source aliases GDEL and RTOP are absent, as is every renamed or merely
;; structurally similar programmatic interaction.  Modern no-delay remains a
;; structural contract only and deliberately does not consult this table.
(defparameter +kanata-1-12-buffered-evidence+
  '(("tap-hold-case-f" "f" 200 :axis-state "case" "shifted" "f" "foreign")
    ("tap-hold-case-j" "j" 200 :axis-state "case" "shifted" "j" "foreign")
    ("tap-hold-control-d" "d" 200 :modifier "control" nil "d" "foreign")
    ("tap-hold-control-k" "k" 200 :modifier "control" nil "k" "foreign")
    ("tap-hold-meta-s" "s" 200 :modifier "meta" nil "s" "foreign")
    ("tap-hold-meta-l" "l" 200 :modifier "meta" nil "l" "foreign")
    ("tap-hold-super-a" "a" 250 :modifier "super" nil "a" "foreign")
    ("tap-hold-super-semicolon" "semicolon" 200 :modifier "super" nil
     "semicolon" "foreign")
    ("tap-hold-hyper-escape" "escape" 200 :modifier "hyper" nil "escape" "foreign")
    ("tap-hold-hyper-apostrophe" "apostrophe" 200 :modifier "hyper" nil
     "apostrophe" "foreign")
    ("tap-hold-alt-backspace" "backspace" 200 :modifier "alt" nil
     "backspace" "foreign")
    ("tap-hold-alt-space" "space" 200 :modifier "alt" nil "space" "foreign")
    ("tap-hold-function-end" "end" 200 :axis-state "function" "active" "end"
     "foreign")
    ("tap-hold-function-pgdn" "pgdn" 200 :axis-state "function" "active"
     "page-down" "foreign")))

(defun %pending-input-error (code control &rest arguments)
  (apply #'signal-semantic-error 'semantic-validation-error code control arguments))

(defun %proper-list-of-length-p (value length)
  (and (listp value) (= (length value) length)))

(defun %exact-key-plist-p (value allowed-keys)
  "Whether VALUE is a proper plist with every ALLOWED-KEY exactly once."
  (and (listp value)
       (evenp (length value))
       (= (length value) (* 2 (length allowed-keys)))
       (let ((seen nil))
         (loop for (key ignored) on value by #'cddr
               always (and (member key allowed-keys :test #'eq)
                           (not (member key seen :test #'eq))
                           (progn (push key seen) t))))))

(defun %interaction-contract-origin (origin role)
  (unless (or (null origin) (typep origin 'ivory-key.source:source-origin))
    (%pending-input-error
     :invalid-interaction-compatibility-contract-origin
     "~A origin is neither NIL nor a SOURCE-ORIGIN." role))
  origin)

(defun %identifier-p (value)
  (typep value 'identifier))

(defun %same-identifier-p (left right)
  (and (%identifier-p left) (%identifier-p right) (identifier= left right)))

(defun %empty-context-tuple-p (tuple)
  (and (typep tuple 'context-tuple)
       (null (context-tuple-pairs tuple))))

(defun %direct-position-selector-p (selector owner)
  (and (typep selector 'position-selector)
       (eq (position-selector-kind selector) :position)
       (%proper-list-of-length-p (position-selector-positions selector) 1)
       (%same-identifier-p (first (position-selector-positions selector)) owner)))

(defun %other-than-owner-selector-p (selector owner)
  (and (typep selector 'position-selector)
       (eq (position-selector-kind selector) :other-than)
       (%proper-list-of-length-p (position-selector-positions selector) 1)
       (%same-identifier-p (first (position-selector-positions selector)) owner)))

(defun %captured-selector-p (selector capture-name)
  (and (typep selector 'position-selector)
       (eq (position-selector-kind selector) :captured)
       (%proper-list-of-length-p (position-selector-positions selector) 1)
       (%same-identifier-p (first (position-selector-positions selector)) capture-name)))

(defun %simple-event-pattern-p (pattern kind selector-p)
  (and (typep pattern 'temporal-pattern)
       (eq (temporal-pattern-kind pattern) kind)
       (%proper-list-of-length-p (temporal-pattern-arguments pattern) 1)
       (null (temporal-pattern-options pattern))
       (funcall selector-p (first (temporal-pattern-arguments pattern)))))

(defun %direct-down-p (pattern owner)
  (%simple-event-pattern-p pattern :down
                           (lambda (selector)
                             (%direct-position-selector-p selector owner))))

(defun %direct-up-p (pattern owner)
  (%simple-event-pattern-p pattern :up
                           (lambda (selector)
                             (%direct-position-selector-p selector owner))))

(defun %captured-up-p (pattern capture-name)
  (%simple-event-pattern-p pattern :up
                           (lambda (selector)
                             (%captured-selector-p selector capture-name))))

(defun %exact-capture-p (pattern owner)
  "Return the capture identity for the one accepted foreign-down slice."
  (when (and (typep pattern 'temporal-pattern)
             (eq (temporal-pattern-kind pattern) :capture)
             (%proper-list-of-length-p (temporal-pattern-arguments pattern) 2)
             (null (temporal-pattern-options pattern)))
    (let ((capture-name (first (temporal-pattern-arguments pattern)))
          (foreign-down (second (temporal-pattern-arguments pattern))))
      (when (and (%identifier-p capture-name)
                 (%simple-event-pattern-p
                  foreign-down :down
                  (lambda (selector)
                    (%other-than-owner-selector-p selector owner))))
        capture-name))))

(defun %timeout-deadline (pattern owner)
  "Return the closed timeout duration, or signal its structural refusal."
  (unless (and (typep pattern 'temporal-pattern)
               (eq (temporal-pattern-kind pattern) :deadline)
               (%proper-list-of-length-p (temporal-pattern-arguments pattern) 2)
               (%exact-key-plist-p (temporal-pattern-options pattern)
                                   '(:while-down)))
    (%pending-input-error
     :invalid-interaction-compatibility-contract-timeout
     "Timeout candidate has no exact deadline shape."))
  (let ((duration (first (temporal-pattern-arguments pattern)))
        (after (second (temporal-pattern-arguments pattern)))
        (while-down (getf (temporal-pattern-options pattern) :while-down)))
    (unless (and (member duration '(200 250))
                 (%direct-down-p after owner)
                 (%same-identifier-p while-down owner))
      (%pending-input-error
       :invalid-interaction-compatibility-contract-timeout
       "Timeout candidate is outside the bounded 200/250 owner deadline shape."))
    duration))

(defun %foreign-capture-name (pattern owner)
  "Return the exact capture name, proving capture precedes its reference."
  (unless (and (typep pattern 'temporal-pattern)
               (eq (temporal-pattern-kind pattern) :sequence)
               (%proper-list-of-length-p (temporal-pattern-arguments pattern) 3)
               (null (temporal-pattern-options pattern)))
    (%pending-input-error
     :invalid-interaction-compatibility-contract-foreign-release
     "Foreign-release candidate has no exact three-event sequence."))
  (let* ((arguments (temporal-pattern-arguments pattern))
         (capture-name (%exact-capture-p (second arguments) owner)))
    ;; The order itself is part of the proof: accepting a reference before its
    ;; binder would reintroduce the open lexical capture semantics this layer
    ;; is meant to exclude.
    (unless (and (%direct-down-p (first arguments) owner)
                 capture-name
                 (%captured-up-p (third arguments) capture-name))
      (%pending-input-error
       :invalid-interaction-compatibility-contract-foreign-release
       "Foreign-release candidate must capture a foreign down before its matching up."))
    capture-name))

(defun %tap-duration (pattern owner)
  (unless (and (typep pattern 'temporal-pattern)
               (eq (temporal-pattern-kind pattern) :duration)
               (%proper-list-of-length-p (temporal-pattern-arguments pattern) 1)
               (%exact-key-plist-p (temporal-pattern-options pattern)
                                   '(:at-least :less-than)))
    (%pending-input-error
     :invalid-interaction-compatibility-contract-tap
     "Tap candidate has no exact duration shape."))
  (let ((at-least (getf (temporal-pattern-options pattern) :at-least))
        (less-than (getf (temporal-pattern-options pattern) :less-than)))
    (unless (and (null at-least)
                 (member less-than '(200 250))
                 (%direct-position-selector-p
                  (first (temporal-pattern-arguments pattern)) owner))
      (%pending-input-error
       :invalid-interaction-compatibility-contract-tap
       "Tap duration is outside the bounded owner interval shape."))
    less-than))

(defun %tap-deadline (pattern owner)
  "Return the D shared by an exact down/up-and-duration tap pattern."
  (unless (and (typep pattern 'temporal-pattern)
               (eq (temporal-pattern-kind pattern) :and)
               (%proper-list-of-length-p (temporal-pattern-arguments pattern) 2)
               (null (temporal-pattern-options pattern)))
    (%pending-input-error
     :invalid-interaction-compatibility-contract-tap
     "Tap candidate has no exact conjunction shape."))
  (let ((sequence nil) (duration nil))
    (dolist (child (temporal-pattern-arguments pattern))
      (cond ((and (typep child 'temporal-pattern)
                  (eq (temporal-pattern-kind child) :sequence))
             (if sequence
                 (%pending-input-error
                  :invalid-interaction-compatibility-contract-tap
                  "Tap candidate repeats its down/up sequence.")
                 (setf sequence child)))
            ((and (typep child 'temporal-pattern)
                  (eq (temporal-pattern-kind child) :duration))
             (if duration
                 (%pending-input-error
                  :invalid-interaction-compatibility-contract-tap
                  "Tap candidate repeats its duration guard.")
                 (setf duration child)))
            (t (%pending-input-error
                :invalid-interaction-compatibility-contract-tap
                "Tap candidate has an unsupported conjunction child."))))
    (unless (and sequence duration
                 (%proper-list-of-length-p (temporal-pattern-arguments sequence) 2)
                 (null (temporal-pattern-options sequence))
                 (%direct-down-p (first (temporal-pattern-arguments sequence)) owner)
                 (%direct-up-p (second (temporal-pattern-arguments sequence)) owner))
      (%pending-input-error
       :invalid-interaction-compatibility-contract-tap
       "Tap candidate must be an owner down followed by owner up."))
    (%tap-duration duration owner)))

(defun %normalized-effects-p (effects)
  (and (%exact-key-plist-p effects
                            '(:entry :commit :while :while-release :exit :cancel))
       (null (getf effects :entry))
       (null (getf effects :commit))
       (eq (getf effects :while-release) :owner-terminal)
       (null (getf effects :exit))
       (null (getf effects :cancel))))

(defun %single-normalized-entry-behavior (entries predicate)
  (and (%proper-list-of-length-p entries 1)
       (let ((entry (first entries)))
         (and (typep entry 'normalized-binding-entry)
              (%empty-context-tuple-p (normalized-entry-tuple entry))
              (funcall predicate (normalized-entry-behavior entry))))))

(defun %held-effect-signature (candidate)
  "Return one canonical owner-terminal held-effect signature, or refuse."
  (let ((effects (normalized-candidate-effects candidate)))
    (unless (and (%normalized-effects-p effects)
                 (%single-normalized-entry-behavior
                  (normalized-candidate-entries candidate)
                  (lambda (behavior) (typep behavior 'no-output-behavior)))
                 (eq (normalized-candidate-commit candidate) :when-matched)
                 (eq (normalized-candidate-effect-start candidate) :on-commit)
                 (null (normalized-candidate-context-axes candidate))
                 (eq (normalized-candidate-context-policy candidate) :anchor-down))
      (%pending-input-error
       :invalid-interaction-compatibility-contract-held-effect
       "A hold candidate has actions, context variation, or a non-owner lifecycle."))
    (let ((while (getf effects :while)))
      (unless (%proper-list-of-length-p while 1)
        (%pending-input-error
         :invalid-interaction-compatibility-contract-held-effect
         "A hold candidate must contain exactly one owner-scoped :WHILE effect."))
      (let ((variant (first while)))
        (unless (and (consp variant)
                     (%empty-context-tuple-p (car variant))
                     (typep (cdr variant) 'behavior))
          (%pending-input-error
           :invalid-interaction-compatibility-contract-held-effect
           "A hold candidate has malformed normalized :WHILE variants."))
        (let ((behavior (cdr variant)))
          (cond
            ((and (typep behavior 'held-modifier-behavior)
                  (eq (modifier-operation behavior) :press)
                  (%identifier-p (modifier-operation-modifier behavior)))
             (make-instance 'interaction-compatibility-held-effect-signature
                            :kind :modifier
                            :identity (modifier-operation-modifier behavior)
                            :release :owner-terminal))
            ((and (typep behavior 'axis-operation-behavior)
                  (eq (axis-operation behavior) :hold)
                  (%identifier-p (axis-operation-axis behavior))
                  (%identifier-p (axis-operation-state behavior)))
             (make-instance 'interaction-compatibility-held-effect-signature
                            :kind :axis-state
                            :identity (axis-operation-axis behavior)
                            :state (axis-operation-state behavior)
                            :release :owner-terminal))
            (t (%pending-input-error
                :invalid-interaction-compatibility-contract-held-effect
                "A hold candidate does not contain one recognized semantic hold."))))))))

(defun %held-effect-signature= (left right)
  (and (eq (interaction-compatibility-held-effect-signature-kind left)
           (interaction-compatibility-held-effect-signature-kind right))
       (%same-identifier-p
        (interaction-compatibility-held-effect-signature-identity left)
        (interaction-compatibility-held-effect-signature-identity right))
       (let ((left-state (interaction-compatibility-held-effect-signature-state left))
             (right-state (interaction-compatibility-held-effect-signature-state right)))
         (if (and (null left-state) (null right-state))
             t
             (%same-identifier-p left-state right-state)))
       (eq (interaction-compatibility-held-effect-signature-release left)
           (interaction-compatibility-held-effect-signature-release right))))

(defun %tap-key (candidate)
  (let ((effects (normalized-candidate-effects candidate)))
    (unless (and (%normalized-effects-p effects)
                 (null (getf effects :while))
                 (%single-normalized-entry-behavior
                  (normalized-candidate-entries candidate)
                  (lambda (behavior) (typep behavior 'named-key-output)))
                 (eq (normalized-candidate-commit candidate) :when-matched)
                 (eq (normalized-candidate-effect-start candidate) :on-match)
                 (null (normalized-candidate-context-axes candidate))
                 (eq (normalized-candidate-context-policy candidate) :anchor-down))
      (%pending-input-error
       :invalid-interaction-compatibility-contract-tap
       "Tap candidate has lifecycle effects, context variation, or no single named key."))
    (let ((key (named-key-name
                (normalized-entry-behavior
                 (first (normalized-candidate-entries candidate))))))
      (unless (%identifier-p key)
        (%pending-input-error
         :invalid-interaction-compatibility-contract-tap
         "Tap candidate's named-key identity is malformed."))
      key)))

(defun %candidate-role (candidate owner)
  "Recognize CANDIDATE from its finite structure, never from its source name."
  (unless (and (typep candidate 'normalized-interaction-candidate)
               (%identifier-p (normalized-candidate-name candidate)))
    (%pending-input-error
     :invalid-interaction-compatibility-contract-candidate
     "Compatibility candidates must be normalized named candidates."))
  (let ((pattern (normalized-candidate-match candidate)))
    (unless (typep pattern 'temporal-pattern)
      (%pending-input-error
       :invalid-interaction-compatibility-contract-candidate
       "Compatibility candidate has no temporal pattern."))
    (case (temporal-pattern-kind pattern)
      (:deadline (values :timeout (%timeout-deadline pattern owner)))
      (:sequence (values :foreign-release (%foreign-capture-name pattern owner)))
      (:and (values :tap (%tap-deadline pattern owner)))
      (otherwise
       (%pending-input-error
        :unrecognized-interaction-compatibility-contract-candidate
        "Compatibility candidate ~A has unsupported pattern kind ~S."
        (identifier-name (normalized-candidate-name candidate))
        (temporal-pattern-kind pattern))))))

(defun %find-role-reference (references role)
  (find role references :key #'interaction-compatibility-role-reference-role :test #'eq))

(defun %identifier-matches-evidence-name-p (identifier name)
  (and (%identifier-p identifier) (string= (identifier-name identifier) name)))

(defun %kanata-1-12-buffered-evidence-entry (interaction-name)
  (and (%identifier-p interaction-name)
       (find (identifier-name interaction-name)
             +kanata-1-12-buffered-evidence+
             :test #'string= :key #'first)))

(defun %validate-kanata-1-12-buffered-evidence
    (interaction owner deadline capture-name signature tap-key)
  "Refuse every buffered contract not exactly named and described by evidence.

The preceding structural recognizer validates model safety.  This additional
gate validates runtime-specific evidence only; it never turns a structural
match into an inference about a renamed instance or a different selector.
"
  (let ((entry (%kanata-1-12-buffered-evidence-entry
                (normalized-interaction-name interaction))))
    (unless entry
      (%pending-input-error
       :unsupported-kanata-1-12-buffered-interaction
       "Kanata 1.12 buffered compatibility has no selected evidence for interaction ~A."
       (identifier-name (normalized-interaction-name interaction))))
    (destructuring-bind (ignored-name expected-owner expected-deadline expected-kind
                         expected-identity expected-state expected-tap
                         expected-capture)
        entry
      (declare (ignore ignored-name))
      (unless
          (and (%identifier-matches-evidence-name-p owner expected-owner)
               (= deadline expected-deadline)
               (eq (interaction-compatibility-held-effect-signature-kind signature)
                   expected-kind)
               (%identifier-matches-evidence-name-p
                (interaction-compatibility-held-effect-signature-identity signature)
                expected-identity)
               (if expected-state
                   (%identifier-matches-evidence-name-p
                    (interaction-compatibility-held-effect-signature-state signature)
                    expected-state)
                   (null (interaction-compatibility-held-effect-signature-state signature)))
               (%identifier-matches-evidence-name-p tap-key expected-tap)
               (%identifier-matches-evidence-name-p capture-name expected-capture))
        (%pending-input-error
         :unsupported-kanata-1-12-buffered-interaction
         "Kanata 1.12 buffered compatibility evidence does not match interaction ~A."
         (identifier-name (normalized-interaction-name interaction)))))))

(defun %validate-interaction-contract-shape (interaction)
  (unless (typep interaction 'normalized-interaction)
    (%pending-input-error
     :invalid-interaction-compatibility-contract-interaction
     "Compatibility policy selected a non-normalized interaction."))
  (let ((participants (normalized-interaction-participants interaction))
        (anchor (normalized-interaction-anchor interaction)))
    (unless (and (%proper-list-of-length-p participants 1)
                 (%identifier-p (first participants))
                 (%same-identifier-p (first participants) anchor))
      (%pending-input-error
       :invalid-interaction-compatibility-contract-participant-shape
       "Compatibility interaction must have exactly one participant equal to its anchor."))
    (unless (eq (normalized-interaction-observe interaction) :any-position)
      (%pending-input-error
       :invalid-interaction-compatibility-contract-observation
       "Compatibility interaction must explicitly observe :ANY-POSITION."))
    (values (first participants) anchor)))

(defun %derive-release-trigger-contract (mode interaction)
  (multiple-value-bind (owner ignored-anchor)
      (%validate-interaction-contract-shape interaction)
    (declare (ignore ignored-anchor))
    (let ((candidates (normalized-interaction-candidates interaction)))
      (unless (%proper-list-of-length-p candidates 3)
        (%pending-input-error
         :incomplete-interaction-compatibility-contract
         "Compatibility interaction must contain exactly three candidates."))
      (unless (every (lambda (candidate)
                       (and (typep candidate 'normalized-interaction-candidate)
                            (%identifier-p (normalized-candidate-name candidate))))
                     candidates)
        (%pending-input-error
         :invalid-interaction-compatibility-contract-candidate
         "Compatibility interaction contains a malformed normalized candidate."))
      (unless (unique-identifiers-p (mapcar #'normalized-candidate-name candidates))
        (%pending-input-error
         :duplicate-interaction-compatibility-contract-candidate
         "Compatibility interaction repeats a candidate identity."))
      (let ((references nil))
        (dolist (candidate candidates)
          (multiple-value-bind (role ignored)
              (%candidate-role candidate owner)
            (declare (ignore ignored))
            (when (%find-role-reference references role)
              (%pending-input-error
               :duplicate-interaction-compatibility-contract-role
               "Compatibility interaction repeats the ~S semantic role." role))
            (push (make-instance 'interaction-compatibility-role-reference
                                 :role role :candidate candidate
                                 :origin (%interaction-contract-origin
                                          (normalized-candidate-origin candidate) role))
                  references)))
        (setf references
              (mapcar (lambda (role)
                        (or (%find-role-reference references role)
                            (%pending-input-error
                             :incomplete-interaction-compatibility-contract
                             "Compatibility interaction has no ~S candidate." role)))
                      '(:timeout :foreign-release :tap)))
        (let* ((timeout (interaction-compatibility-role-reference-candidate
                         (%find-role-reference references :timeout)))
               (foreign-release (interaction-compatibility-role-reference-candidate
                                 (%find-role-reference references :foreign-release)))
               (tap (interaction-compatibility-role-reference-candidate
                     (%find-role-reference references :tap)))
               (deadline (%timeout-deadline (normalized-candidate-match timeout) owner))
               (capture-name (%foreign-capture-name
                              (normalized-candidate-match foreign-release) owner))
               (tap-deadline (%tap-deadline (normalized-candidate-match tap) owner)))
          (unless (= deadline tap-deadline)
            (%pending-input-error
             :mismatched-interaction-compatibility-contract-deadline
             "Timeout and tap candidates do not share one D."))
          (let ((arbitration (normalized-interaction-arbitration interaction)))
            (unless (and (%proper-list-of-length-p arbitration 2)
                         (eq (first arbitration) :priority)
                         (%proper-list-of-length-p (second arbitration) 3)
                         (every #'%identifier-p (second arbitration))
                         (every #'%same-identifier-p
                                (second arbitration)
                                (mapcar #'normalized-candidate-name
                                        (list timeout foreign-release tap))))
              (%pending-input-error
               :invalid-interaction-compatibility-contract-priority
               "Compatibility interaction must prioritize timeout, foreign release, then tap.")))
          (let ((timeout-signature (%held-effect-signature timeout))
                (foreign-signature (%held-effect-signature foreign-release)))
            (unless (%held-effect-signature= timeout-signature foreign-signature)
              (%pending-input-error
               :mismatched-interaction-compatibility-contract-held-effects
               "Timeout and foreign-release holds are not semantically identical."))
          (let ((tap-key (%tap-key tap))
                (interaction-origin
                  (%interaction-contract-origin
                   (normalized-interaction-origin interaction) :interaction)))
              (when (eq mode :kanata-1-12-buffered)
                ;; This must run before allocating the final typed contract:
                ;; callers must not be able to observe a pending value for an
                ;; instance whose exact buffered runtime evidence is absent.
                (%validate-kanata-1-12-buffered-evidence
                 interaction owner deadline capture-name timeout-signature tap-key))
              (make-instance
               (ecase mode
                 (:kanata-1-12-buffered 'pending-foreign-interval-contract)
                 (:modern-no-delay 'modern-no-delay-interaction-compatibility-contract))
               :mode mode :interaction interaction :owner owner :origin interaction-origin
               :role-references (copy-list references)
               :deadline deadline :capture-name capture-name
               :held-effect-signature timeout-signature :tap-key tap-key
               :provenance
               (make-instance
                'interaction-compatibility-contract-provenance
                :interaction-origin interaction-origin
                :timeout-origin (interaction-compatibility-role-reference-origin
                                 (%find-role-reference references :timeout))
                :foreign-release-origin
                (interaction-compatibility-role-reference-origin
                 (%find-role-reference references :foreign-release))
                :tap-origin (interaction-compatibility-role-reference-origin
                             (%find-role-reference references :tap)))))))))))

(defun derive-interaction-compatibility-contracts (policy normalized-layout)
  "Derive closed structural contracts for POLICY's selected normalized instances.

POLICY must be a validated, explicitly selected realization policy and
NORMALIZED-LAYOUT must already be normalized.  The function accepts no source
forms, reader objects, backend strings, or simulator state.  It returns one
immutable-by-convention contract per canonical policy target, or signals a
structured semantic validation error at the first unsupported shape.
"
  (validate-realization-interaction-compatibility-policy policy)
  (unless (typep normalized-layout 'normalized-layout)
    (%pending-input-error
     :invalid-interaction-compatibility-contract-layout
     "Expected a NORMALIZED-LAYOUT, got ~S." normalized-layout))
  (let ((interactions (normalized-layout-interactions normalized-layout))
        (mode (realization-interaction-compatibility-policy-mode policy)))
    (unless (and (listp interactions)
                 (every (lambda (interaction)
                          (and (typep interaction 'normalized-interaction)
                               (%identifier-p (normalized-interaction-name interaction))))
                        interactions)
                 (unique-identifiers-p (mapcar #'normalized-interaction-name interactions)))
      (%pending-input-error
       :invalid-interaction-compatibility-contract-layout
       "Normalized layout has malformed or duplicate interaction identities."))
    (mapcar
     (lambda (name)
       (let ((interaction (find name interactions :test #'identifier=
                                :key #'normalized-interaction-name)))
         (unless interaction
           (%pending-input-error
            :unknown-interaction-compatibility-contract-interaction
            "Compatibility policy names absent normalized interaction ~A."
            (identifier-name name)))
         (%derive-release-trigger-contract mode interaction)))
     (realization-interaction-compatibility-policy-interactions policy))))
