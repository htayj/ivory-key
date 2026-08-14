;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Logical keyboard topology and deliberately non-semantic placement data.

(in-package #:ivory-key.model)

(defclass logical-position ()
  ((name :initarg :name :reader position-name)
   (label :initarg :label :initform nil :reader position-label)
   (coordinates :initarg :coordinates :initform nil :reader position-coordinates)
   (hand :initarg :hand :initform nil :reader position-hand)
   (finger :initarg :finger :initform nil :reader position-finger)
   (metadata :initarg :metadata :initform nil :reader position-metadata)))

(defun make-logical-position (name &key label coordinates hand finger metadata)
  "Create a topology position.  Geometry is descriptive only."
  (make-instance 'logical-position :name (ensure-identifier name)
                 :label label :coordinates coordinates :hand hand
                 :finger finger :metadata metadata))

(defclass topology ()
  ((name :initarg :name :reader topology-name)
   (positions :initarg :positions :reader topology-positions)
   (metadata :initarg :metadata :initform nil :reader topology-metadata)))

(defun make-topology (name positions &key metadata)
  (make-instance 'topology :name (ensure-identifier name)
                 :positions (copy-list positions) :metadata metadata))

(defun find-position (name topology &key (errorp nil))
  "Find NAME as a logical position in TOPOLOGY."
  (or (find (ensure-identifier name) (topology-positions topology)
            :test #'identifier= :key #'position-name)
      (when errorp
        (error "Unknown logical position ~A in topology ~A."
               (canonical-identifier-name name)
               (identifier-name (topology-name topology))))))

(defparameter +device-position-coverage-dispositions+
  '(:physical :unreachable)
  "The closed physical-reachability vocabulary for a device placement.")

(defclass device-position-coverage ()
  ((position :initarg :position :reader device-position-coverage-position)
   ;; This is deliberately a device fact, not a backend allocation.  In
   ;; particular, an unreachable logical position is neither a virtual
   ;; carrier nor permission to omit its semantic binding during lowering.
   (disposition :initarg :disposition
                :reader device-position-coverage-disposition)))

(defun make-device-position-coverage (position disposition)
  "Declare POSITION as :PHYSICAL or :UNREACHABLE on one concrete device.

Absence of a declaration is intentionally not represented by a third value:
it remains missing device-coverage evidence and must be handled fail-closed by
the compiler or another consumer that requires a complete placement.
"
  (unless (member disposition +device-position-coverage-dispositions+ :test #'eq)
    (signal-semantic-error
     'semantic-validation-error :invalid-device-coverage-disposition
     "Device position coverage disposition ~S must be one of ~S."
     disposition +device-position-coverage-dispositions+))
  (make-instance 'device-position-coverage
                 :position (ensure-identifier position)
                 :disposition disposition))

(defclass device-placement ()
  ((name :initarg :name :reader placement-name)
   (topology :initarg :topology :reader placement-topology)
   ;; Association list of physical input identities to logical positions.  The
   ;; physical side is opaque to the semantic model.
   (mappings :initarg :mappings :reader placement-mappings)
   ;; A complete device description names every topology position exactly
   ;; once.  NIL is retained for old programmatic placement construction, but
   ;; is never inferred to mean either physical or unreachable.
   (position-coverage :initarg :position-coverage :initform nil
                      :reader placement-position-coverage)
   (metadata :initarg :metadata :initform nil :reader placement-metadata)))

(defun make-device-placement (name topology mappings &key position-coverage metadata)
  "Create a descriptive physical-device placement.

Physical inputs deliberately remain strings; realizing them as evdev or
firmware codes belongs to a selected realization profile."
  (let ((placement
          (make-instance 'device-placement :name (ensure-identifier name)
                          :topology topology
                          :mappings (mapcar (lambda (entry)
                                              (cons (car entry)
                                                    (ensure-identifier (cdr entry))))
                                            mappings)
                          :position-coverage (copy-list position-coverage)
                          :metadata metadata)))
    ;; Validate every explicit record at its model boundary.  Completeness is
    ;; intentionally a separate question: legacy programmatic callers can
    ;; inspect a partial placement, whereas project compilation requires it.
    (when position-coverage
      (validate-device-placement-coverage placement))
    placement))

(defun placement-coverage-for-position (placement position)
  "Return POSITION's explicit DEVICE-POSITION-COVERAGE record, if any."
  (find (ensure-identifier position) (placement-position-coverage placement)
        :test #'identifier=
        :key #'device-position-coverage-position))

(defun placement-missing-coverage-positions (placement)
  "Return topology positions with no explicit coverage record, in name order."
  (sort
   (remove-if (lambda (position)
                (placement-coverage-for-position placement (position-name position)))
              (copy-list (topology-positions (placement-topology placement))))
   #'identifier< :key #'position-name))

(defun placement-coverage-complete-p (placement)
  "Whether every topology position has an explicit coverage disposition."
  (null (placement-missing-coverage-positions placement)))

(defun validate-device-placement-coverage (placement &key (require-complete nil))
  "Validate explicit coverage records and their relationship to MAPPINGS.

When REQUIRE-COMPLETE is true, every topology position must have a record.
The default preserves backwards-compatible programmatic partial placements;
it does not interpret their omissions as unreachable or physical.
"
  (unless (typep placement 'device-placement)
    (signal-semantic-error 'semantic-validation-error :invalid-device-placement
                           "Device coverage requires a DEVICE-PLACEMENT."))
  (let ((topology (placement-topology placement))
        (coverage (placement-position-coverage placement)))
    (unless (typep topology 'topology)
      (signal-semantic-error 'semantic-validation-error :invalid-device-topology
                             "Device placement ~A has no topology object."
                             (placement-name placement)))
    ;; Old programmatic callers may still construct a partial placement with
    ;; no coverage value at all.  That placement remains inspectable, but no
    ;; mapping-derived reachability is inferred from it.  The moment a caller
    ;; supplies any coverage record, require the entire model envelope to be
    ;; internally consistent with the one-PLACE-per-logical-position surface.
    (when coverage
      (let ((seen-coverage (make-hash-table :test #'equal))
            (coverage-by-position (make-hash-table :test #'equal))
            (mapping-counts (make-hash-table :test #'equal))
            (seen-inputs (make-hash-table :test #'equal))
            (seen-mapping-positions (make-hash-table :test #'equal)))
        ;; First validate the closed coverage relation itself, so mapping
        ;; checks can use it without filling a missing record by inference.
        (dolist (record coverage)
          (unless (typep record 'device-position-coverage)
            (signal-semantic-error 'semantic-validation-error :invalid-device-coverage
                                   "Device placement ~A has a non-coverage record ~S."
                                   (placement-name placement) record))
          (let* ((position (device-position-coverage-position record))
                 (key (identifier-key position))
                 (disposition (device-position-coverage-disposition record)))
            (unless (find-position position topology)
              (signal-semantic-error 'semantic-validation-error
                                     :unknown-device-coverage-position
                                     "Device placement ~A covers unknown topology position ~A."
                                     (placement-name placement) (identifier-name position)))
            (when (gethash key seen-coverage)
              (signal-semantic-error 'semantic-validation-error
                                     :duplicate-device-position-coverage
                                     "Device placement ~A covers position ~A more than once."
                                     (placement-name placement) (identifier-name position)))
            (unless (member disposition +device-position-coverage-dispositions+ :test #'eq)
              (signal-semantic-error 'semantic-validation-error
                                     :invalid-device-coverage-disposition
                                     "Device placement ~A has unsupported coverage disposition ~S."
                                     (placement-name placement) disposition))
            (setf (gethash key seen-coverage) t
                  (gethash key coverage-by-position) record)))
        ;; A covered device has exactly one opaque physical input per logical
        ;; position.  Backend-specific alternate spellings belong in placement
        ;; metadata; they are not additional physical model mappings.
        (dolist (mapping (placement-mappings placement))
          (unless (and (consp mapping) (stringp (car mapping))
                       (plusp (length (car mapping))))
            (signal-semantic-error 'semantic-validation-error
                                   :invalid-device-placement-mapping
                                   "Device placement ~A has malformed physical mapping ~S."
                                   (placement-name placement) mapping))
          (let* ((input (car mapping))
                 (position (cdr mapping)))
            (unless (typep position 'identifier)
              (signal-semantic-error
               'semantic-validation-error :invalid-device-placement-mapping
               "Device placement ~A has malformed logical mapping target ~S."
               (placement-name placement) position))
            (let ((key (identifier-key position)))
            (unless (find-position position topology)
              (signal-semantic-error 'semantic-validation-error
                                     :unknown-device-placement-position
                                     "Device placement ~A maps physical input ~A to unknown topology position ~A."
                                     (placement-name placement) input position))
            (when (gethash input seen-inputs)
              (signal-semantic-error 'semantic-validation-error
                                     :duplicate-physical-placement
                                     "Device placement ~A maps physical input ~A more than once."
                                     (placement-name placement) input))
            (when (gethash key seen-mapping-positions)
              (signal-semantic-error 'semantic-validation-error
                                     :duplicate-device-placement
                                     "Device placement ~A maps logical position ~A more than once."
                                     (placement-name placement) (identifier-name position)))
            (let ((record (gethash key coverage-by-position)))
              (unless record
                (signal-semantic-error 'semantic-validation-error
                                       :missing-device-coverage
                                       "Device placement ~A maps ~A without a coverage declaration."
                                       (placement-name placement) (identifier-name position)))
              (when (eq (device-position-coverage-disposition record) :unreachable)
                (signal-semantic-error 'semantic-validation-error
                                       :unreachable-device-coverage-with-placement
                                       "Device placement ~A maps ~A despite its unreachable coverage declaration."
                                       (placement-name placement) (identifier-name position))))
            (setf (gethash input seen-inputs) t
                  (gethash key seen-mapping-positions) t
                  (gethash key mapping-counts)
                  (1+ (gethash key mapping-counts 0))))))
        (dolist (record coverage)
          (let* ((position (device-position-coverage-position record))
                 (key (identifier-key position))
                 (count (gethash key mapping-counts 0)))
            (ecase (device-position-coverage-disposition record)
              (:physical
               (unless (= count 1)
                 (signal-semantic-error 'semantic-validation-error
                                        :physical-device-coverage-without-placement
                                        "Device placement ~A marks ~A physical but has ~D physical mappings (expected exactly one)."
                                        (placement-name placement)
                                        (identifier-name position) count)))
              (:unreachable
               (unless (zerop count)
                 (signal-semantic-error 'semantic-validation-error
                                        :unreachable-device-coverage-with-placement
                                        "Device placement ~A marks ~A unreachable but has ~D physical mappings."
                                        (placement-name placement)
                                        (identifier-name position) count))))))))
    (when (and require-complete (not (placement-coverage-complete-p placement)))
      (signal-semantic-error
       'semantic-validation-error :missing-device-coverage
       "Device placement ~A has no coverage declaration for ~{~A~^, ~}."
       (placement-name placement)
       (mapcar #'position-name (placement-missing-coverage-positions placement))))
    t))
