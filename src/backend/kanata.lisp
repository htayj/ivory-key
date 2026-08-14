;;;; SPDX-License-Identifier: GPL-3.0-or-later

(in-package #:ivory-key.backend)

(defclass kanata-backend (backend) ())

(defclass kanata-plan ()
  ((name :initarg :name :reader kanata-plan-name)
   (sources :initarg :sources :reader kanata-plan-sources)
   (outputs :initarg :outputs :reader kanata-plan-outputs)
   ;; Additional layers are a realization-owned lowering detail.  Each row is
   ;; (NAME . OUTPUTS), where OUTPUTS is aligned with SOURCES.  The semantic
   ;; layout never contains a Kanata layer or carrier spelling.
   (layers :initarg :layers :initform nil :reader kanata-plan-layers)
   (realizations :initarg :realizations :reader kanata-plan-realizations)))

(defun make-kanata-backend ()
  (make-instance 'kanata-backend :name "kanata"))

(defmethod capabilities ((backend kanata-backend))
  (declare (ignore backend))
  (make-instance 'backend-capabilities
                 :input-identities '(:kanata-key-token)
                 :native-level-limit nil
                 :native-group-limit nil
                 :modifier-slots nil
                 ;; Native Kanata has temporal mechanisms, but this backend
                 ;; has no closed abstract-interaction lowering yet.  The
                 ;; capability object describes this implementation, not the
                 ;; host program's marketing surface.
                 :interaction-features nil
                 :clock-semantics nil
                 :lifecycle-semantics nil
                 :output-features '(:key :modifier :layer :carrier)
                 :carrier-channels '(:linux-input-event)
                 :validation-program "kanata"
                 :platform-assumptions '(:kanata-configuration)))

(defun safe-kanata-token-p (value)
  "Accept one direct Kanata atom from the closed emitter vocabulary.

The punctuation atoms are the complete set already evidenced in the frozen
Manna `defsrc` rows.  They are accepted only as one-character atoms, never as
substrings in an otherwise arbitrary action or comment form.
"
  (and (stringp value)
       (plusp (length value))
       (or (every (lambda (character)
                    (let ((code (char-code character)))
                      (or (<= (char-code #\A) code (char-code #\Z))
                          (<= (char-code #\a) code (char-code #\z))
                          (<= (char-code #\0) code (char-code #\9))
                          (find character "_-"))))
                  value)
           (member value '("=" "[" "]" ";" "'" "\\" "," "." "/")
                   :test #'string=))))

(defun kanata-carrier-action-code (value)
  "Return the exact arbitrary-code value in VALUE, or NIL.

This is deliberately the only emitted Kanata action form.  It is needed for
the evidence-backed Linux carrier bridge; aliases, nested actions, comments,
and arbitrary parenthesized source still fail closed.
"
  (when (and (stringp value)
             (<= (length "(arbitrary-code 0)") (length value))
             (string= "(arbitrary-code " value :end2 (length "(arbitrary-code "))
             (char= (char value (1- (length value))) #\)))
    (let ((digits (subseq value (length "(arbitrary-code ")
                         (1- (length value)))))
      (when (and (plusp (length digits))
                 (every #'digit-char-p digits))
        (parse-integer digits)))))

(defun safe-kanata-output-p (value)
  (or (safe-kanata-token-p value)
      (integerp (kanata-carrier-action-code value))))

(defun ensure-distinct-kanata-sources (sources)
  (let ((seen (make-hash-table :test #'equal)))
    (dolist (source sources)
      (when (gethash source seen)
        (error "Duplicate Kanata source token ~S in one lowering request." source))
      (setf (gethash source seen) t))))

(defun %kanata-metadata-value (request key)
  (getf (lowering-request-metadata request) key))

(defun %kanata-interaction-compatibility-refusal-detail (policy)
  "Return one closed interaction-policy refusal without selecting an action.

The two accepted values are V1 Manna/Kanata compatibility choices, not a
generic Kanata interaction capability.  In particular, neither may be
translated into a raw tap-hold form until a typed ownership/buffer/replay IR
exists and can be matched to its source evidence.
"
  (ivory-key.model::validate-realization-interaction-compatibility-policy
   policy)
  (case (ivory-key.model::realization-interaction-compatibility-policy-mode policy)
    (:modern-no-delay
     "Kanata 1.12 buffers/replays pending foreign events, so generic Kanata actions are not exact for the selected modern no-delay policy.")
    (:kanata-1-12-buffered
     "The selected Kanata 1.12 buffered policy lacks a closed ownership, cancellation, and ordered-replay action IR.")
    ;; The model validator makes this defensive branch unreachable for
    ;; source-decoded values.  Preserve a refusal for an object changed after
    ;; validation instead of guessing a backend action.
    (otherwise
     "The interaction compatibility policy is not a closed V1 Manna/Kanata route.")))

(defun %kanata-interaction-identifier (interaction)
  "Return INTERACTION's source identifier without coercing host symbols.

Compiler-originated requests carry normalized interactions, while focused
backend callers may supply source identifier strings.  Other host values stay
unrecognized: treating an arbitrary symbol/plist as an intended Manna instance
would reintroduce the profile-wide applicability leak.
"
  (cond
    ((typep interaction 'ivory-key.model:normalized-interaction)
     (ivory-key.model:normalized-interaction-name interaction))
    ((typep interaction 'ivory-key.model:identifier) interaction)
    ((stringp interaction)
     (handler-case
         (ivory-key.model:make-identifier interaction)
       (error () nil)))
    (t nil)))

(defun %kanata-interaction-compatibility-target-p (policy interaction)
  "Whether POLICY explicitly names INTERACTION without coercing host symbols."
  (let ((identifier (%kanata-interaction-identifier interaction)))
    (and identifier
         (ivory-key.model:identifier-member-p
          identifier
          (ivory-key.model::realization-interaction-compatibility-policy-interactions
           policy)))))

(defun %kanata-unmatched-interaction-compatibility-targets (policy interactions)
  "Return canonical POLICY targets absent from this direct lowering request.

The compiler normally validates these source identities against normalized
interactions.  This backend boundary repeats the essential fail-closed check
for programmatic requests: metadata cannot silently disappear merely because a
caller supplied no matching interaction entries.
"
  (remove-if
   (lambda (target)
     (some (lambda (interaction)
             (let ((identifier (%kanata-interaction-identifier interaction)))
               (and identifier
                    (ivory-key.model:identifier= target identifier))))
           interactions))
   (ivory-key.model::realization-interaction-compatibility-policy-interactions
    policy)))

(defun %kanata-source-rows (request mappings)
  "Return canonical (POSITION . SOURCE) rows for one generated config.

When a realization supplies a complete source order, it may include physical
positions which XKB intentionally leaves untouched.  This is essential for a
carrier layer to remain aligned with the physical device without claiming a
semantic output for those pass-through events.
"
  (let ((declared (%kanata-metadata-value request :kanata-source-order)))
    (if declared
        (let ((rows nil))
          (dolist (row declared)
            (unless (and (consp row) (stringp (car row)) (stringp (cdr row))
                         (safe-kanata-token-p (cdr row)))
              (error "Unsafe Kanata source-order row ~S." row))
            (push (cons (car row) (string-downcase (cdr row))) rows))
          (setf rows (nreverse rows))
          (ensure-distinct-kanata-sources (mapcar #'cdr rows))
          rows)
        (mapcar (lambda (mapping)
                  (cons (car mapping) (car mapping)))
                mappings))))

(defun %kanata-layer-rows (request source-rows)
  "Validate realization-owned sparse Kanata layer output rows.

The layer declaration is compiler IR.  Its values have already been resolved
through a profile vocabulary; this backend still validates each resulting
atom/action before text emission.
"
  (let ((layers (%kanata-metadata-value request :kanata-layers))
        (seen (make-hash-table :test #'equal))
        (source-names (mapcar #'car source-rows)))
    (mapcar
     (lambda (layer)
       (unless (and (listp layer) (stringp (getf layer :name))
                    (listp (getf layer :outputs)))
         (error "Malformed Kanata layer declaration ~S." layer))
       (let ((name (getf layer :name))
             (outputs (getf layer :outputs))
             (by-position (make-hash-table :test #'equal)))
         (unless (safe-kanata-token-p name)
           (error "Unsafe Kanata layer name ~S." name))
         (when (gethash name seen)
           (error "Duplicate Kanata layer name ~S." name))
         (setf (gethash name seen) t)
         (dolist (row outputs)
           (unless (and (consp row) (stringp (car row)) (stringp (cdr row))
                        (member (car row) source-names :test #'string=)
                        (safe-kanata-output-p (cdr row)))
             (error "Unsafe Kanata layer output row ~S." row))
           (when (gethash (car row) by-position)
             (error "Duplicate Kanata layer output for position ~S." (car row)))
           (setf (gethash (car row) by-position) (cdr row)))
         (cons name
               (mapcar (lambda (source)
                         (or (gethash (car source) by-position) "_"))
                       source-rows))))
     layers)))

(defmethod lower-request ((backend kanata-backend) (request lowering-request))
  (declare (ignore backend))
  (unless (safe-kanata-token-p (lowering-request-name request))
    (error "Unsafe Kanata layer name ~S." (lowering-request-name request)))
  (let ((mappings nil)
        (results nil))
    (dolist (entry (lowering-request-entries request))
      (let* ((source (string-downcase (key-entry-code-for entry :kanata)))
             (entry-outputs (key-entry-outputs-for entry :kanata)))
        (unless (and (listp entry-outputs)
                     (= (length entry-outputs) 1))
          (error "Kanata entry ~S must provide exactly one explicit output."
                 (key-entry-position entry)))
        (let ((output (first entry-outputs)))
        (unless (and (safe-kanata-token-p source)
                     (safe-kanata-output-p output))
          (error "Unsafe Kanata mapping ~S -> ~S." source output))
        (push (cons source output) mappings)
        (push (make-realization-result (key-entry-position entry) :exact
                                       :detail "Direct Kanata token mapping.")
              results))))
    (ensure-distinct-kanata-sources (mapcar #'car mappings))
    ;; Backend capability names are not a generic semantic lowering.  Until a
    ;; profile supplies an exact Kanata template, the request-level semantic
    ;; modifier remains an explicit refusal rather than a silently omitted
    ;; deflayer action.
    (dolist (modifier (lowering-request-modifiers request))
      (push (make-realization-result
             modifier :unsupported
             :detail "Semantic modifier lowering requires an explicit Kanata template.")
            results))
    (let ((interactions (lowering-request-interactions request))
          (interaction-compatibility-policy
            (%kanata-metadata-value request :interaction-compatibility-policy)))
      (when interaction-compatibility-policy
        ;; Programmatic callers do not get to smuggle a plist/string through
        ;; metadata merely because no source decoder was involved.
        (ivory-key.model::validate-realization-interaction-compatibility-policy
         interaction-compatibility-policy))
      ;; A policy is an obligation on each named source interaction, not
      ;; decoration for whatever entries happened to reach this backend.  Keep
      ;; static-only or partial programmatic requests non-emittable when they
      ;; omit an intended policy target.
      (when interaction-compatibility-policy
        (dolist (target
                 (%kanata-unmatched-interaction-compatibility-targets
                  interaction-compatibility-policy interactions))
          (push
           (make-realization-result
            (ivory-key.model:identifier-name target) :unsupported
            :detail
            (format nil "Selected interaction compatibility policy names ~A, but this lowering request has no matching interaction."
                    (ivory-key.model:identifier-name target)))
           results)))
      (dolist (interaction interactions)
        (push
         (make-realization-result
          interaction :unsupported
          :detail
          (if (and interaction-compatibility-policy
                   (%kanata-interaction-compatibility-target-p
                    interaction-compatibility-policy interaction))
              (%kanata-interaction-compatibility-refusal-detail
               interaction-compatibility-policy)
              ;; NIL, an explicitly unlisted interaction, or an unrecognizable
              ;; programmatic value retains the target-generic refusal.
              "Generic interaction lowering requires an explicit Kanata template."))
         results))
    ;; The typed carrier/selector policy is deliberately not a raw Kanata
    ;; action template.  Until lifecycle and source-consumption behavior are
    ;; lowered by a closed action IR, keep the policy as an explicit refusal.
    (when (%kanata-metadata-value request :selector-policy)
      (push (make-realization-result
             :selector-policy :unsupported
             :detail "Typed selector allocation lacks a proven closed Kanata action plan.")
            results))
    (let* ((ordered-mappings (sort mappings #'string< :key #'car))
           (source-rows (%kanata-source-rows request ordered-mappings))
           (outputs-by-source (make-hash-table :test #'equal)))
      (dolist (mapping ordered-mappings)
        (setf (gethash (car mapping) outputs-by-source) (cdr mapping)))
      (let ((base-outputs
              (mapcar (lambda (row)
                        ;; A source not owned by the abstract static table is
                        ;; an explicit physical pass-through, not an inferred
                        ;; semantic binding.
                        (or (gethash (cdr row) outputs-by-source) (cdr row)))
                      source-rows))
            (layers (%kanata-layer-rows request source-rows)))
      (make-instance 'kanata-plan
                     :name (lowering-request-name request)
                     :sources (mapcar #'cdr source-rows)
                     :outputs base-outputs
                     :layers layers
                     :realizations (nreverse results)))))))

(defmethod emit-plan ((backend kanata-backend) (plan kanata-plan) stream)
  (declare (ignore backend))
  (require-permitted-realizations (kanata-plan-realizations plan))
  (format stream "(defcfg~%  process-unmapped-keys yes)~%~%")
  (format stream "(defsrc~%  ~{~A~^ ~})~%~%" (kanata-plan-sources plan))
  (format stream "(deflayer ~A~%  ~{~A~^ ~})~%" (kanata-plan-name plan)
          (kanata-plan-outputs plan))
  (dolist (layer (kanata-plan-layers plan))
    (format stream "~%~%(deflayer ~A~%  ~{~A~^ ~})~%" (car layer) (cdr layer))))

(defmethod validate-artifact ((backend kanata-backend) pathname)
  (declare (ignore backend))
  (let ((arguments (list "kanata" "--check" "-c" (namestring pathname))))
    (handler-case
        (values t
                (uiop:run-program arguments
                                  :output :string
                                  :error-output :output)
                arguments)
      (error (condition)
        (values nil (princ-to-string condition) arguments)))))
