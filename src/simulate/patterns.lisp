;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Finite, declarative timed-pattern algebra.

(in-package #:ivory-key.simulate)

(defstruct (event-pattern
             (:constructor %make-event-pattern
                 (&key kind children event-kind position at-least less-than
                       milliseconds after-position while-down forbidden
                       start-pattern end-pattern repeat-min repeat-max label
                       capture-name context-axis context-state)))
  "A normalized finite pattern node.

KIND is one of :EVENT, :CAPTURE, :CONTEXT-IS, :SEQUENCE, :ALL, :EITHER, :AND,
:DURATION, :DEADLINE, :WITHIN, :WITHOUT, or :REPEAT.  The small representation
keeps simulator input independent of surface syntax and backend vocabulary."
  kind
  (children nil :type list)
  event-kind
  position
  at-least
  less-than
  milliseconds
  after-position
  while-down
  forbidden
  start-pattern
  end-pattern
  repeat-min
  repeat-max
  label
  capture-name
  context-axis
  context-state)

(defstruct (pattern-match-context
             (:constructor make-pattern-match-context
                 (&key events start-index anchor-index captures context
                       latch-snapshot)))
  "The finite prefix against which a candidate is evaluated."
  (events #() :type vector)
  (start-index 0 :type fixnum)
  (anchor-index 0 :type fixnum)
  ;; A candidate-owned hash table of immutable CAPTURE bindings.  Keys are
  ;; canonical strings; values are CAPTURE-BINDING records.
  captures
  ;; Candidate-owned anchor-time snapshots.  Latches shadow ordinary context,
  ;; exactly as they do for runtime behavior selection and consumption.
  (context nil :type list)
  (latch-snapshot nil :type list))

(defstruct (capture-binding
            (:constructor make-capture-binding (position down-index)))
  "One immutable first CAPTURE result for a candidate pattern."
  position
  (down-index 0 :type fixnum))

(defun event-pattern (kind position &key label)
  "Match one abstract event.  KIND is :DOWN, :UP, or :DEADLINE.

POSITION is an exact logical identifier, :ANY, or (:OTHER-THAN POSITION)."
  (unless (member kind '(:down :up :deadline) :test #'eq)
    (error "Unknown event-pattern kind ~S." kind))
  (when (and (eq kind :deadline) position)
    (error "A deadline pattern cannot name a physical position."))
  (%make-event-pattern :kind :event :event-kind kind :position position :label label))

(defun down-pattern (position &key label)
  (event-pattern :down position :label label))

(defun up-pattern (position &key label)
  (event-pattern :up position :label label))

(defun capture-pattern (name pattern)
  "Bind NAME to the physical position matched by one direct DOWN PATTERN.

The compiler and semantic validator constrain this to the first finite capture
slice.  Keeping the binding as an explicit IR node prevents a later UP from
silently matching a different foreign key."
  (%make-event-pattern :kind :capture :capture-name name :children (list pattern)))

(defun context-is-pattern (axis state)
  "Match one dependency-scoped axis value captured at candidate anchor-down."
  (%make-event-pattern :kind :context-is :context-axis axis :context-state state))

(defun sequence-pattern (&rest patterns)
  (%make-event-pattern :kind :sequence :children patterns))

(defun all-pattern (&rest patterns)
  (%make-event-pattern :kind :all :children patterns))

(defun either-pattern (&rest patterns)
  (%make-event-pattern :kind :either :children patterns))

(defun and-pattern (&rest patterns)
  (%make-event-pattern :kind :and :children patterns))

(defun duration-pattern (position &key at-least less-than)
  "Match the completed interval for POSITION.  Bounds are [AT-LEAST, LESS-THAN)."
  (when (and at-least (not (typep at-least 'timestamp)))
    (error "Duration lower bound must be a timestamp, not ~S." at-least))
  (when (and less-than (not (typep less-than 'timestamp)))
    (error "Duration upper bound must be a timestamp, not ~S." less-than))
  (%make-event-pattern :kind :duration :position position
                       :at-least at-least :less-than less-than))

(defun deadline-pattern (milliseconds &key after-position while-down label)
  "Match the generated clock tick MILLISECONDS after AFTER-POSITION's down.

If WHILE-DOWN is supplied, that logical interval must include the tick."
  (unless (typep milliseconds 'timestamp)
    (error "Deadline must be a non-negative integer millisecond, not ~S." milliseconds))
  (%make-event-pattern :kind :deadline :milliseconds milliseconds
                       :after-position after-position :while-down while-down
                       :label label))

(defun within-pattern (milliseconds first second)
  "Match two event occurrences that are no farther than MILLISECONDS apart."
  (unless (typep milliseconds 'timestamp)
    (error "Within window must be a non-negative integer millisecond, not ~S." milliseconds))
  (%make-event-pattern :kind :within :milliseconds milliseconds
                       :children (list first second)))

(defun overlap-pattern (&rest positions)
  "Match when the named logical intervals have a non-empty common overlap."
  (when (null positions)
    (error "An overlap pattern needs at least one participant."))
  (%make-event-pattern :kind :overlap :children positions))

(defun without-pattern (forbidden &key between)
  "Match only when FORBIDDEN does not occur strictly between two boundaries.
BETWEEN is a two-element list of start and closing patterns."
  (unless (and (listp between) (= (length between) 2))
    (error "WITHOUT requires exactly two :BETWEEN boundaries."))
  (%make-event-pattern :kind :without :forbidden forbidden
                       :start-pattern (first between) :end-pattern (second between)))

(defun repeat-pattern (pattern &key (at-least 0) at-most)
  "Finite repetition.  An upper bound is required by the version-1 model."
  (unless (and (integerp at-least) (not (minusp at-least)))
    (error "Repeat lower bound must be a non-negative integer."))
  (unless (and (integerp at-most) (not (minusp at-most)) (>= at-most at-least))
    (error "Repeat requires a finite :AT-MOST bound no lower than :AT-LEAST."))
  (%make-event-pattern :kind :repeat :children (list pattern)
                       :repeat-min at-least :repeat-max at-most))

(defun captured-position-reference-p (position)
  (and (consp position) (eq (first position) :captured)
       (= (length position) 2)))

(defun captured-position-value (context reference)
  (let ((captures (pattern-match-context-captures context)))
    (and captures
         (let ((binding (gethash (second reference) captures)))
           (and binding (capture-binding-position binding))))))

(defun pattern-position-matches-p (wanted actual context)
  (or (eq wanted :any)
      (equal wanted actual)
      (and (captured-position-reference-p wanted)
           (equal (captured-position-value context wanted) actual))
      (and (consp wanted)
           (eq (first wanted) :other-than)
           (not (equal (second wanted) actual)))))

(defun event-pattern-matches-p (pattern event context)
  (and (eq (event-pattern-event-kind pattern) (timed-event-kind event))
       (or (eq (timed-event-kind event) :deadline)
           (pattern-position-matches-p (event-pattern-position pattern)
                                       (timed-event-position event)
                                       context))))

(defun context-event-indices (context predicate &optional (from nil))
  (let* ((events (pattern-match-context-events context))
         (start (or from (pattern-match-context-start-index context)))
         (matches nil))
    (loop for index from start below (length events)
          for event = (aref events index)
          when (funcall predicate event)
            do (push index matches))
    (nreverse matches)))

(defun atomic-occurrence-indices (pattern context)
  "Return all satisfying event indices for atomic occurrence patterns.

Composite temporal predicates intentionally do not pretend to be occurrences;
they belong under AND/ALL instead of SEQUENCE/WITHIN in normalized IR."
  (when (eq (event-pattern-kind pattern) :event)
    (context-event-indices context
                           (lambda (event) (event-pattern-matches-p pattern event context)))))

(defun event-at (context index)
  (aref (pattern-match-context-events context) index))

(defun first-index-after (indices minimum)
  (find-if (lambda (index) (>= index minimum)) indices))

(defun sequence-matches-p (patterns context)
  (labels ((ordinary-sequence-matches-p ()
             (labels ((walk (remaining minimum)
                        (if (null remaining)
                            t
                            (let ((occurrences (atomic-occurrence-indices (first remaining) context)))
                              (and occurrences
                                   (loop for index in occurrences
                                         thereis (and (>= index minimum)
                                                      (walk (rest remaining) (1+ index)))))))))
               (walk patterns (pattern-match-context-start-index context))))
           (capture-child-event (capture)
             (first (event-pattern-children capture)))
           (first-occurrence-at-or-after (pattern minimum)
             (first-index-after (atomic-occurrence-indices pattern context) minimum))
           (captured-sequence-matches-p ()
             ;; Validation and model compilation admit precisely
             ;; EVENT(DOWN), CAPTURE(EVENT(DOWN)), EVENT(UP CAPTURED).  Keep
             ;; this machine routine equally narrow so callers that bypass
             ;; validation cannot accidentally acquire a broader search rule.
             (unless (and (= (length patterns) 3)
                          (eq (event-pattern-kind (second patterns)) :capture))
               (return-from captured-sequence-matches-p nil))
             (let* ((first (first patterns))
                    (capture (second patterns))
                    (last (third patterns))
                    (capture-name (event-pattern-capture-name capture))
                    (captures (pattern-match-context-captures context))
                    (first-index
                      (first-occurrence-at-or-after
                       first (pattern-match-context-start-index context))))
               (unless first-index (return-from captured-sequence-matches-p nil))
               (let* ((binding (and captures (gethash capture-name captures)))
                      (capture-index
                        (if binding
                            (capture-binding-down-index binding)
                            (first-occurrence-at-or-after
                             (capture-child-event capture) (1+ first-index)))))
                 (unless capture-index (return-from captured-sequence-matches-p nil))
                 (unless binding
                   ;; The first eligible physical DOWN is sticky for this
                   ;; candidate.  Later unrelated events cannot rebind NAME.
                   (let ((event (event-at context capture-index)))
                     (unless captures
                       (error "Capture sequence has no candidate-owned capture store."))
                     (setf binding
                           (make-capture-binding (timed-event-position event) capture-index)
                           (gethash capture-name captures) binding)))
                 (let ((up-index (first-occurrence-at-or-after last (1+ capture-index))))
                   (and up-index t))))))
    (if (some (lambda (pattern) (eq (event-pattern-kind pattern) :capture)) patterns)
        (captured-sequence-matches-p)
        (ordinary-sequence-matches-p))))

(defun matching-down-index (context position)
  (first-index-after
   (context-event-indices
    context
    (lambda (event)
      (and (eq (timed-event-kind event) :down)
           (pattern-position-matches-p position (timed-event-position event) context))))
   (pattern-match-context-start-index context)))

(defun matching-up-index-after (context position down-index)
  (first-index-after
   (context-event-indices
    context
    (lambda (event)
      (and (eq (timed-event-kind event) :up)
           (pattern-position-matches-p position (timed-event-position event) context))))
   (1+ down-index)))

(defun position-down-at-index-p (context position index)
  "Whether POSITION is held just before the event at INDEX is interpreted.
The event prefix contains every physical event, so this also works for a
deadline at the same timestamp as a later physical release."
  (let ((down nil))
    (loop for event-index from 0 below index
          for event = (event-at context event-index)
          when (and (member (timed-event-kind event) '(:down :up) :test #'eq)
                    (equal (timed-event-position event) position))
            do (setf down (eq (timed-event-kind event) :down)))
    down))

(defun interval-indices (context position)
  "Return the first interval beginning in this candidate's prefix, if any."
  (let ((down (matching-down-index context position)))
    (when down
      (values down (matching-up-index-after context position down)))))

(defun deadline-match-p (pattern context)
  (let* ((after-position (or (event-pattern-after-position pattern)
                             (timed-event-position
                              (event-at context (pattern-match-context-anchor-index context)))))
         (anchor (matching-down-index context after-position)))
    (when anchor
      (let ((target (+ (timed-event-time (event-at context anchor))
                       (event-pattern-milliseconds pattern))))
        (loop for index from (1+ anchor) below (length (pattern-match-context-events context))
              for event = (event-at context index)
              thereis (and (eq (timed-event-kind event) :deadline)
                           (= (timed-event-time event) target)
                           (or (null (event-pattern-while-down pattern))
                               (position-down-at-index-p
                                context (event-pattern-while-down pattern) index))))))))

(defun duration-status (pattern context)
  (multiple-value-bind (down up) (interval-indices context (event-pattern-position pattern))
    (cond
      ((null down) :pending)
      ((null up) :pending)
      (t (let ((duration (- (timed-event-time (event-at context up))
                            (timed-event-time (event-at context down)))))
           (if (and (or (null (event-pattern-at-least pattern))
                        (>= duration (event-pattern-at-least pattern)))
                    (or (null (event-pattern-less-than pattern))
                        (< duration (event-pattern-less-than pattern))))
               :matched
               :failed))))))

(defun within-status (pattern context)
  (destructuring-bind (first second) (event-pattern-children pattern)
    (let ((firsts (atomic-occurrence-indices first context))
          (seconds (atomic-occurrence-indices second context)))
      (cond
        ((or (null firsts) (null seconds)) :pending)
        ((loop for left in firsts thereis
           (loop for right in seconds
                 thereis (<= (abs (- (timed-event-time (event-at context left))
                                     (timed-event-time (event-at context right))))
                             (event-pattern-milliseconds pattern))))
         :matched)
        ;; Another occurrence may still enter the finite window.
        (t :pending)))))

(defun overlap-status (pattern context)
  (let ((starts nil) (ends nil) (all-closed t))
    (dolist (position (event-pattern-children pattern))
      (multiple-value-bind (down up) (interval-indices context position)
        (unless down (return-from overlap-status :pending))
        (push (timed-event-time (event-at context down)) starts)
        (if up
            (push (timed-event-time (event-at context up)) ends)
            (setf all-closed nil))))
    (let ((latest-start (apply #'max starts))
          (earliest-end (and ends (apply #'min ends))))
      (cond
        ((or (null earliest-end) (< latest-start earliest-end)) :matched)
        ;; It can only become true by a later fresh interval; preserve the
        ;; candidate until arbitration or an explicit cancellation decides it.
        (all-closed :pending)
        (t :pending)))))

(defun without-status (pattern context)
  (let ((starts (atomic-occurrence-indices (event-pattern-start-pattern pattern) context))
        (ends (atomic-occurrence-indices (event-pattern-end-pattern pattern) context))
        (forbidden (atomic-occurrence-indices (event-pattern-forbidden pattern) context)))
    (cond
      ((null starts) :pending)
      (t
       (let* ((start (first starts))
              (end (find-if (lambda (index) (> index start)) ends))
              (bad (find-if (lambda (index)
                              (and (> index start) (or (null end) (< index end))))
                            forbidden)))
         (cond
           (bad :failed)
           (end :matched)
           (t :pending)))))))

(defun repeat-status (pattern context)
  (let ((occurrences (atomic-occurrence-indices (first (event-pattern-children pattern)) context)))
    (cond
      ((null occurrences) :pending)
      ((> (length occurrences) (event-pattern-repeat-max pattern)) :failed)
      ((>= (length occurrences) (event-pattern-repeat-min pattern)) :matched)
      (t :pending))))

(defun pattern-status (pattern context)
  "Return :MATCHED, :PENDING, or :FAILED for the current finite event prefix."
  (ecase (event-pattern-kind pattern)
    (:event (if (atomic-occurrence-indices pattern context) :matched :pending))
    ;; CAPTURE is an occurrence only as the middle node of the validated
    ;; three-event sequence.  Treating it as independently matched would
    ;; create a second, under-specified binding lifetime.
    (:capture :pending)
    (:context-is
     (let* ((axis (event-pattern-context-axis pattern))
            (latch (assoc axis (pattern-match-context-latch-snapshot context)
                          :test #'equal))
            (actual (if latch
                        (second latch)
                        (cdr (assoc axis (pattern-match-context-context context)
                                    :test #'equal)))))
       (if (and actual (equal actual (event-pattern-context-state pattern)))
           :matched
           :failed)))
    (:sequence (if (sequence-matches-p (event-pattern-children pattern) context)
                   :matched :pending))
    (:all (let ((statuses (mapcar (lambda (child) (pattern-status child context))
                                  (event-pattern-children pattern))))
            (cond ((member :failed statuses) :failed)
                  ((every (lambda (status) (eq status :matched)) statuses) :matched)
                  (t :pending))))
    (:and (let ((statuses (mapcar (lambda (child) (pattern-status child context))
                                  (event-pattern-children pattern))))
            (cond ((member :failed statuses) :failed)
                  ((every (lambda (status) (eq status :matched)) statuses) :matched)
                  (t :pending))))
    (:either (let ((statuses (mapcar (lambda (child) (pattern-status child context))
                                     (event-pattern-children pattern))))
               (cond ((member :matched statuses) :matched)
                     ((every (lambda (status) (eq status :failed)) statuses) :failed)
                     (t :pending))))
    (:duration (duration-status pattern context))
    (:deadline (if (deadline-match-p pattern context) :matched :pending))
    (:within (within-status pattern context))
    (:overlap (overlap-status pattern context))
    (:without (without-status pattern context))
    (:repeat (repeat-status pattern context))))

(defun collect-deadline-patterns (pattern)
  "Return every finite clock declaration reachable from PATTERN."
  (cond
    ((null pattern) nil)
    ((eq (event-pattern-kind pattern) :deadline) (list pattern))
    ((member (event-pattern-kind pattern) '(:sequence :all :either :and :within :repeat :capture)
             :test #'eq)
     (mapcan #'collect-deadline-patterns (event-pattern-children pattern)))
    ((eq (event-pattern-kind pattern) :without)
     (append (collect-deadline-patterns (event-pattern-forbidden pattern))
             (collect-deadline-patterns (event-pattern-start-pattern pattern))
             (collect-deadline-patterns (event-pattern-end-pattern pattern))))
    (t nil)))
