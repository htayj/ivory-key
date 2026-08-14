;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Closed, non-evaluating source format for simulator event streams.

(in-package #:ivory-key.simulate)

;;; Event fixtures are data, not host Lisp.  In particular, this module takes
;;; only the parser's concrete syntax nodes: it never calls READ, EVAL, or
;;; INTERN on the supplied source.  Keeping this vocabulary separate from the
;;; layout decoder also means a trace fixture cannot smuggle in a model form
;;; whose execution semantics were never specified.

(define-condition simulation-event-source-error (error)
  ((code :initarg :code :reader simulation-event-source-error-code)
   (message :initarg :message :reader simulation-event-source-error-message)
   (span :initarg :span :initform nil :reader simulation-event-source-error-span))
  (:report
   (lambda (condition stream)
     (format stream "Simulation event source ~A~@[ at ~A~]: ~A"
             (simulation-event-source-error-code condition)
             (let ((span (simulation-event-source-error-span condition)))
               (and span (ivory-key.source:source-span-location-string span)))
             (simulation-event-source-error-message condition)))))

(defun %event-source-error (code node control &rest arguments)
  (error 'simulation-event-source-error
         :code code
         :span (and (or (typep node 'ivory-key.syntax:syntax-atom)
                        (typep node 'ivory-key.syntax:syntax-list))
                    (ivory-key.syntax:syntax-node-span node))
         :message (apply #'format nil control arguments)))

(defstruct (simulation-event-stream
            (:constructor %make-simulation-event-stream (events axes latches until)))
  "A fully validated, source-derived physical event fixture.

EVENTS contains only DOWN and UP TIMED-EVENT objects in source order.  AXES
and LATCHES are canonical (axis . state) string alists.  UNTIL is NIL or a
non-negative integer millisecond timestamp.  The public constructor is kept
private so callers cannot mistake arbitrary host objects for checked source.
"
  (events nil :type list :read-only t)
  (axes nil :type list :read-only t)
  (latches nil :type list :read-only t)
  (until nil :type (or null timestamp) :read-only t))

(defun %event-source-list-children (node minimum maximum description)
  (unless (typep node 'ivory-key.syntax:syntax-list)
    (%event-source-error :malformed-event-stream-form node
                         "~A must be a parenthesized form." description))
  (let ((children (ivory-key.syntax:syntax-list-children node)))
    (unless (and (>= (length children) minimum)
                 (or (null maximum) (<= (length children) maximum)))
      (%event-source-error :malformed-event-stream-form node
                           "~A has invalid arity; expected ~D~@[ through ~D~] fields, got ~D."
                           description minimum maximum (length children)))
    children))

(defun %event-source-identifier (node description)
  (unless (and (typep node 'ivory-key.syntax:syntax-atom)
               (eq (ivory-key.syntax:syntax-atom-kind node) :identifier))
    (%event-source-error :invalid-event-stream-identifier node
                         "~A must be an Ivory Key identifier." description))
  ;; This is a string-only canonicalizer.  MODEL-IDENTIFIER->SIMULATION-VALUE
  ;; creates no host symbol and gives the fixture the same case-insensitive
  ;; identity as the normalized layout it will later drive.
  (model-identifier->simulation-value
   (ivory-key.syntax:syntax-atom-value node)))

(defun %event-source-time (node description)
  (unless (and (typep node 'ivory-key.syntax:syntax-atom)
               (eq (ivory-key.syntax:syntax-atom-kind node) :integer)
               (typep (ivory-key.syntax:syntax-atom-value node) 'timestamp))
    (%event-source-error :invalid-event-timestamp node
                         "~A must be a non-negative integer millisecond timestamp."
                         description))
  (ivory-key.syntax:syntax-atom-value node))

(defun %event-source-form-name (form)
  (when (typep form 'ivory-key.syntax:syntax-list)
    (let ((head (first (ivory-key.syntax:syntax-list-children form))))
      (and (typep head 'ivory-key.syntax:syntax-atom)
           (eq (ivory-key.syntax:syntax-atom-kind head) :identifier)
           (string-downcase (ivory-key.syntax:syntax-atom-value head))))))

(defun %event-source-header-p (form)
  (let ((children (and (typep form 'ivory-key.syntax:syntax-list)
                       (ivory-key.syntax:syntax-list-children form))))
    (and (= (length children) 2)
         (let ((name (first children))
               (version (second children)))
           (and (typep name 'ivory-key.syntax:syntax-atom)
                (eq (ivory-key.syntax:syntax-atom-kind name) :identifier)
                (string= (ivory-key.syntax:syntax-atom-value name) "ivory-key")
                (typep version 'ivory-key.syntax:syntax-atom)
                (eq (ivory-key.syntax:syntax-atom-kind version) :integer)
                (= (ivory-key.syntax:syntax-atom-value version) 1))))))

(defun %require-complete-event-parse (parsed)
  (unless (typep parsed 'ivory-key.syntax:syntax-parse-result)
    (%event-source-error :invalid-event-stream-parse-result parsed
                         "Expected a syntax parse result, got ~S." parsed))
  (unless (ivory-key.syntax:syntax-parse-result-complete-p parsed)
    ;; Preserve parser diagnostics and resource-limit reporting verbatim rather
    ;; than recoding malformed or oversized input as a semantic stream error.
    (error 'ivory-key.conditions:ivory-key-syntax-error
           :diagnostics (ivory-key.syntax:syntax-parse-result-diagnostics parsed)))
  parsed)

(defun %decode-event-source-event (form last-time)
  (let ((children (%event-source-list-children form 4 4 "EVENT declaration")))
    (unless (string= (or (%event-source-form-name form) "") "event")
      (%event-source-error :unknown-event-stream-form form
                           "Unknown event-stream form ~S." (%event-source-form-name form)))
    (let* ((time (%event-source-time (second children) "EVENT time"))
           (kind-name (%event-source-identifier (third children) "EVENT kind"))
           (position (%event-source-identifier (fourth children) "EVENT position"))
           (kind (cond ((string= kind-name "down") :down)
                       ((string= kind-name "up") :up)
                       ((string= kind-name "deadline")
                        (%event-source-error :generated-deadline-event (third children)
                                             "DEADLINE is generated by the simulator and cannot appear in source."))
                       (t (%event-source-error :unknown-event-kind (third children)
                                             "EVENT kind must be DOWN or UP, not ~A." kind-name)))))
      (when (and last-time (< time last-time))
        (%event-source-error :decreasing-event-time form
                             "EVENT time ~D is earlier than the preceding event time ~D."
                             time last-time))
      (values (make-timed-event time kind position) time))))

(defun %decode-event-source-context (form kind seen)
  (let* ((children (%event-source-list-children
                    form 3 3 (if (eq kind :axis) "AXIS override" "LATCH declaration")))
         (name (or (%event-source-form-name form) "")))
    (unless (string= name (if (eq kind :axis) "axis" "latch"))
      (%event-source-error :unknown-event-stream-form form
                           "Unknown event-stream form ~S." name))
    (let ((axis (%event-source-identifier (second children)
                                          (if (eq kind :axis) "AXIS name" "LATCH axis")))
          (state (%event-source-identifier (third children)
                                           (if (eq kind :axis) "AXIS state" "LATCH state"))))
      (when (member axis seen :test #'string=)
        (%event-source-error :duplicate-event-stream-context form
                             "Event stream declares ~A axis ~A more than once."
                             (if (eq kind :axis) "override" "latch") axis))
      (values (cons axis state) axis))))

(defun decode-simulation-event-stream-forms (parsed)
  "Decode one closed-vocabulary v1 event fixture from parser concrete syntax.

The required envelope is `(ivory-key 1)' followed by exactly one
`(simulation ...)' declaration.  Inside it, `EVENT' declarations have the
form `(event TIME down|up POSITION)'; optional `(axis AXIS STATE)',
`(latch AXIS STATE)', and a single `(until TIME)' may appear in any order.
All identifiers are retained as canonical strings.  No host reader, evaluator,
or package interning is involved.
"
  (%require-complete-event-parse parsed)
  (let ((forms (ivory-key.syntax:syntax-parse-result-forms parsed)))
    (unless (%event-source-header-p (first forms))
      (%event-source-error :missing-event-stream-version (first forms)
                           "Simulation event documents must begin with (ivory-key 1)."))
    (let ((body (rest forms)))
      (when (null body)
        (%event-source-error :missing-event-stream-declaration nil
                             "Event document has no SIMULATION declaration."))
      (when (rest body)
        (%event-source-error :duplicate-event-stream-declaration (second body)
                             "Event document has more than one top-level declaration."))
      (let ((declaration (first body)))
        (unless (string= (or (%event-source-form-name declaration) "") "simulation")
          (%event-source-error :unknown-event-stream-top-level declaration
                               "Expected one SIMULATION declaration, got ~S."
                               (%event-source-form-name declaration)))
        (let ((clauses (rest (%event-source-list-children declaration 1 nil
                                                        "SIMULATION declaration")))
              (events nil)
              (axes nil)
              (latches nil)
              (seen-axes nil)
              (seen-latches nil)
              (last-time nil)
              (until nil)
              (until-seen-p nil))
          (dolist (clause clauses)
            (let ((name (%event-source-form-name clause)))
              (cond
                ((string= (or name "") "event")
                 (multiple-value-bind (event time)
                     (%decode-event-source-event clause last-time)
                   (push event events)
                   (setf last-time time)))
                ((string= (or name "") "axis")
                 (multiple-value-bind (entry axis)
                     (%decode-event-source-context clause :axis seen-axes)
                   (push entry axes)
                   (push axis seen-axes)))
                ((string= (or name "") "latch")
                 (multiple-value-bind (entry axis)
                     (%decode-event-source-context clause :latch seen-latches)
                   (push entry latches)
                   (push axis seen-latches)))
                ((string= (or name "") "until")
                 (when until-seen-p
                   (%event-source-error :duplicate-event-stream-until clause
                                        "Event stream has more than one UNTIL declaration."))
                 (let ((children (%event-source-list-children clause 2 2
                                                                  "UNTIL declaration")))
                   (setf until (%event-source-time (second children) "UNTIL time")
                         until-seen-p t)))
                ((string= (or name "") "deadline")
                 (%event-source-error :generated-deadline-event clause
                                      "DEADLINE is generated by the simulator and cannot appear in source."))
                (t
                 (%event-source-error :unknown-event-stream-form clause
                                      "Unknown SIMULATION form ~S." name)))))
          (when (null events)
            (%event-source-error :missing-event-stream-events declaration
                                 "SIMULATION must contain at least one physical EVENT."))
          (when (and until last-time (< until last-time))
            (%event-source-error :until-before-last-event declaration
                                 "UNTIL time ~D is earlier than the final EVENT time ~D."
                                 until last-time))
          (%make-simulation-event-stream (nreverse events) (nreverse axes)
                                         (nreverse latches) until))))))

(defun decode-simulation-event-stream-file (pathname)
  "Parse PATHNAME under the standard untrusted-input limits, then decode it.

The existing Ivory parser owns UTF-8 decoding, byte/token/depth limits, and
syntax diagnostics.  This wrapper neither opens the file through CL:READ nor
loosens those limits for command-line event fixtures.
"
  (decode-simulation-event-stream-forms (ivory-key.syntax:parse-file pathname)))

(defun simulate-normalized-layout-event-stream (layout stream)
  "Drive supported normalized LAYOUT semantics with a checked source STREAM.

Any refusal from the whole-layout adapter is deliberately allowed to escape
unchanged; a source fixture must never turn an unsupported model behavior or
ambiguous ownership into an approximate simulation.
"
  (unless (typep stream 'simulation-event-stream)
    (%event-source-error :invalid-event-stream stream
                         "Expected a decoded simulation event stream, got ~S." stream))
  (simulate-normalized-layout-events
   layout (simulation-event-stream-events stream)
   :axes (simulation-event-stream-axes stream)
   :latches (simulation-event-stream-latches stream)
   :until (simulation-event-stream-until stream)))

(defun %safe-simulation-dump-value-p (value)
  "True only for the closed scalar/cons vocabulary produced by this adapter.

This deliberately uses a recursion-stack table rather than a global visited
set: shared immutable substructure is safe to render twice, whereas a cycle
would make a host printer introduce implementation-specific circular syntax or
loop.  Arbitrary objects are not a deterministic public dump vocabulary.
"
  (let ((active (make-hash-table :test #'eq)))
    (labels ((safe-p (object)
               (cond ((or (null object) (stringp object) (integerp object)
                          (keywordp object))
                      t)
                     ((consp object)
                      (unless (gethash object active)
                        (setf (gethash object active) t)
                        (unwind-protect
                             (and (safe-p (car object)) (safe-p (cdr object)))
                          (remhash object active))))
                     (t nil))))
      (safe-p value))))

(defun %write-simulation-value (value stream)
  "Print the closed simulator result vocabulary in a deterministic style."
  (unless (%safe-simulation-dump-value-p value)
    (%event-source-error :unsupported-simulation-dump-value value
                         "Simulation dump contains a value outside the closed deterministic vocabulary."))
  (let ((*print-case* :downcase)
        (*print-pretty* nil)
        (*print-circle* nil)
        (*print-level* nil)
        (*print-length* nil))
    (write value :stream stream :escape t)))

(defun %write-trace-name (prefix value stream)
  (when value
    (format stream " ~A=" prefix)
    (%write-simulation-value value stream)))

(defun %write-simulation-trace-entry (entry stream)
  (format stream "  ~D ~A"
          (simulation-trace-entry-time entry)
          (string-downcase (symbol-name (simulation-trace-entry-kind entry))))
  (let ((event (simulation-trace-entry-event entry))
        (interaction (simulation-trace-entry-interaction entry))
        (case (simulation-trace-entry-case entry))
        (candidate (simulation-trace-entry-candidate entry))
        (details (simulation-trace-entry-details entry)))
    (when event
      (%write-trace-name
       "event"
       (list (timed-event-kind event) (timed-event-position event)
             (timed-event-data event))
       stream))
    (when interaction
      (%write-trace-name "interaction" (sim-interaction-name interaction) stream))
    (when case
      (%write-trace-name "case" (sim-case-name case) stream))
    (when candidate
      (%write-trace-name "candidate" (simulation-candidate-id candidate) stream))
    (when details
      (%write-trace-name "details" details stream)))
  (terpri stream))

(defun simulation-result-dump-string (result)
  "Return a deterministic plain-text dump of one reference simulation RESULT.

The dump contains observable output, every ordered transition, and final
abstract context/effect state.  It intentionally does not expose host object
addresses or backend keycodes.
"
  (unless (typep result 'simulation-result)
    (%event-source-error :invalid-simulation-result result
                         "Expected a simulation result, got ~S." result))
  (with-output-to-string (stream)
    (format stream "simulation-result~%outputs~%")
    (dolist (output (simulation-result-outputs result))
      (write-string "  " stream)
      (%write-simulation-value output stream)
      (terpri stream))
    (format stream "trace~%")
    (dolist (entry (simulation-result-trace result))
      (%write-simulation-trace-entry entry stream))
    (format stream "latches~%")
    (dolist (entry (simulation-result-latches result))
      (write-string "  " stream)
      (%write-simulation-value entry stream)
      (terpri stream))
    (format stream "axes~%")
    (dolist (entry (simulation-result-axes result))
      (write-string "  " stream)
      (%write-simulation-value entry stream)
      (terpri stream))
    (format stream "active-effects~%")
    (dolist (effect (simulation-result-active-effects result))
      (write-string "  " stream)
      (%write-simulation-value effect stream)
      (terpri stream))))
