;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Hermetic reference-simulator versus XKB/Kanata differential harness.

(in-package #:ivory-key.tests)

;;; This is deliberately a plan-level differential.  It does not call xkbcli,
;;; Kanata, a compositor, or a virtual input device; those are separately
;;; tagged external checks in TESTS/EXTERNAL.  The supported comparison below
;;; is intentionally narrow: a one-level Unicode binding which Kanata forwards
;;; unchanged to an XKB key with one U+ keysym.  Every other requested semantic
;;; feature is exercised by the reference simulator and then required to have
;;; an explicit compiler/backend refusal, never a synthesized observation.

(defun backend-differential-assert (truth control &rest arguments)
  (unless truth
    (error (apply #'format nil control arguments))))

(defun backend-differential-assert-equal (expected actual label)
  (backend-differential-assert
   (equal expected actual) "~A: expected ~S, got ~S" label expected actual))

(defun backend-differential-event (time kind position)
  (ivory-key.simulate:make-timed-event time kind position))

(defun backend-differential-topology (positions)
  (ivory-key.model:make-topology
   "differential-topology"
   (mapcar #'ivory-key.model:make-logical-position positions)))

(defun backend-differential-layout (axes bindings
                                    &key modifiers interactions overlays positions)
  (let ((positions (or positions (mapcar #'car bindings))))
    (ivory-key.model:normalize-layout
     (ivory-key.model:make-layout
      "differential-layout" (backend-differential-topology positions)
      axes modifiers
      :bindings
      (mapcar (lambda (binding)
                (ivory-key.model:make-binding (car binding) (cdr binding)))
              bindings)
      :interactions interactions :overlays overlays))))

(defun backend-differential-layout-positions (layout)
  (mapcar (lambda (position)
            (ivory-key.model:identifier-name
             (ivory-key.model:position-name position)))
          (ivory-key.model:topology-positions
           (ivory-key.model:normalized-layout-topology layout))))

(defun backend-differential-placement (positions)
  "Build the direct XKB/Kanata device envelope used only by this test harness."
  (ivory-key.cli::%make-compiler-placement
   "differential-device" "differential-topology"
   (loop for position in positions
         for ordinal from 1
         collect
         (cons position
               (list :xkb (format nil "AD~2,'0D" ordinal)
                     :kanata (string-downcase position))))
   (loop for position in positions
         collect (ivory-key.model::make-device-position-coverage
                  position :physical))))

(defun backend-differential-analyze (layout)
  (ivory-key.cli::analyze-normalized-layout
   layout
   (backend-differential-placement
    (backend-differential-layout-positions layout))))

(defun backend-differential-request (layout)
  (ivory-key.cli::make-lowering-request-from-normalized-layout
   layout
   (backend-differential-placement
    (backend-differential-layout-positions layout))))

(defun backend-differential-stage-code (thunk)
  (handler-case
      (progn
        (funcall thunk)
        (error "Expected a compiler-stage-error."))
    (ivory-key.cli:compiler-stage-error (condition)
      (ivory-key.cli:compiler-stage-error-code condition))))

(defun backend-differential-issue-codes (layout)
  (multiple-value-bind (request issues)
      (backend-differential-analyze layout)
    (declare (ignore request))
    (mapcar #'ivory-key.cli::compiler-fidelity-issue-code issues)))

(defun backend-differential-direct-request (positions &key modifiers interactions)
  "Make a checked direct request for backend-refusal checks.

The output table is intentionally the forwarding form emitted by the compiler
for one Unicode scalar: Kanata forwards the physical event and XKB owns the
observable U+ keysym.
"
  (make-instance
   'ivory-key.backend:lowering-request
   :name "differential"
   :entries
   (loop for position in positions
         for ordinal from 1
         collect
         (make-instance
          'ivory-key.backend:key-entry
          :position position
          :physical-code
          (list :xkb (format nil "AD~2,'0D" ordinal)
                :kanata (string-downcase position))
          :outputs
          (list :xkb (list (format nil "U~X" (char-code (char position 0))))
                :kanata (list (string-downcase position)))))
   :modifiers modifiers :interactions interactions))

(defun backend-differential-lower-plans (request)
  (let* ((xkb-backend (ivory-key.backend:make-xkb-backend))
         (kanata-backend (ivory-key.backend:make-kanata-backend))
         (xkb-plan (ivory-key.backend:lower-request xkb-backend request))
         (kanata-plan (ivory-key.backend:lower-request kanata-backend request))
         (realizations
           (append (ivory-key.backend:xkb-plan-realizations xkb-plan)
                   (ivory-key.backend:kanata-plan-realizations kanata-plan))))
    (ivory-key.backend:require-permitted-realizations realizations)
    ;; Emitting here proves the comparison is over the real plan accepted by
    ;; both emitters, not a parallel test representation.
    (ivory-key.backend:emit-plan-to-string xkb-backend xkb-plan)
    (ivory-key.backend:emit-plan-to-string kanata-backend kanata-plan)
    (values xkb-plan kanata-plan)))

(defun backend-differential-xkb-observation (keysym)
  "Convert the exact U+ keysym subset of the XKB plan back to model output."
  (cond
    ((string= keysym "NoSymbol") nil)
    ((and (> (length keysym) 1)
          (char= (char keysym 0) #\U))
     (let ((code (parse-integer keysym :start 1 :radix 16 :junk-allowed nil)))
       (unless (and (<= code #x10FFFF)
                    (not (<= #xD800 code #xDFFF)))
         (error "Differential fixture has invalid XKB Unicode keysym ~S." keysym))
       (list :text (string (code-char code)))))
    (t
     (error "Differential fixture has no exact model observation for XKB keysym ~S."
            keysym))))

(defun backend-differential-entry-for-position (request position)
  (or (find position (ivory-key.backend:lowering-request-entries request)
            :test #'string=
            :key #'ivory-key.backend:key-entry-position)
      (error "No differential lowering entry for logical position ~S." position)))

(defun backend-differential-kanata-output-for-entry (plan entry)
  (let* ((source
           (string-downcase
            (ivory-key.backend:key-entry-code-for entry :kanata)))
         (index (position source (ivory-key.backend::kanata-plan-sources plan)
                          :test #'string=)))
    (unless index
      (error "Differential Kanata plan omitted source ~S." source))
    (nth index (ivory-key.backend::kanata-plan-outputs plan))))

(defun backend-differential-static-pipeline-observations (request events)
  "Return output observations and translated physical-event trace.

Only the compiler's direct, one-level Kanata-forwarding/XKB-Unicode slice is
represented.  A modifier, interaction, layer, carrier, changed Kanata output,
or multi-level XKB entry is a refusal: interpreting one would define backend
semantics in the test rather than compare proven behavior.
"
  (multiple-value-bind (xkb-plan kanata-plan)
      (backend-differential-lower-plans request)
    (let ((outputs nil)
          (translated-events nil))
      (dolist (event events)
        (let* ((position (ivory-key.simulate::timed-event-position event))
               (entry (backend-differential-entry-for-position request position))
               (kanata-source
                 (string-downcase
                  (ivory-key.backend:key-entry-code-for entry :kanata)))
               (kanata-output
                 (backend-differential-kanata-output-for-entry kanata-plan entry))
               (xkb-code (ivory-key.backend:key-entry-code-for entry :xkb))
               (xkb-entry
                 (find xkb-code (ivory-key.backend::xkb-plan-entries xkb-plan)
                       :test #'string=
                       :key (lambda (candidate)
                              (ivory-key.backend:key-entry-code-for candidate :xkb))))
               (xkb-outputs
                 (and xkb-entry
                      (ivory-key.backend:key-entry-outputs-for xkb-entry :xkb))))
          (unless (string= kanata-source kanata-output)
            (error "Kanata output ~S for ~S is not the exact forwarding slice."
                   kanata-output position))
          (unless (and (listp xkb-outputs) (= (length xkb-outputs) 1))
            (error "XKB entry ~S is not the exact one-level differential slice."
                   position))
          (push (list (ivory-key.simulate::timed-event-time event)
                      (ivory-key.simulate::timed-event-kind event)
                      position kanata-source kanata-output xkb-code)
                translated-events)
          ;; Neither emitted plan gives a physical key-up an abstract output.
          ;; The simulator's ordinary binding commits on the matching key-down.
          (when (eq (ivory-key.simulate::timed-event-kind event) :down)
            (let ((observation
                    (backend-differential-xkb-observation (first xkb-outputs))))
              (when observation
                (push observation outputs))))))
      (values (nreverse outputs) (nreverse translated-events)))))

(defun backend-differential-refusal-result-p (results feature)
  (some (lambda (result)
          (and (equal feature (ivory-key.backend:realization-feature result))
               (eq :unsupported (ivory-key.backend:realization-grade result))))
        results))

(defun backend-differential-assert-backend-refusal (request features label)
  (let* ((xkb (ivory-key.backend:make-xkb-backend))
         (kanata (ivory-key.backend:make-kanata-backend))
         (xkb-plan (ivory-key.backend:lower-request xkb request))
         (kanata-plan (ivory-key.backend:lower-request kanata request)))
    (dolist (feature features)
      (backend-differential-assert
       (backend-differential-refusal-result-p
        (ivory-key.backend:xkb-plan-realizations xkb-plan) feature)
       "~A: XKB must explicitly refuse ~S." label feature)
      (backend-differential-assert
       (backend-differential-refusal-result-p
        (ivory-key.backend:kanata-plan-realizations kanata-plan) feature)
       "~A: Kanata must explicitly refuse ~S." label feature))
    (backend-differential-assert
     (handler-case
         (progn
           (ivory-key.backend:compile-xkb-kanata-request request)
           nil)
       (error () t))
     "~A: combined pipeline must refuse instead of emitting a partial approximation."
     label)))

(defun backend-differential-single-interaction ()
  (ivory-key.simulate::make-sim-interaction
   :name "single" :participants '("a")
   :cases
   (list
    (ivory-key.simulate::make-sim-case
     :name "tap"
     :pattern (ivory-key.simulate::sequence-pattern
               (ivory-key.simulate::down-pattern "a")
               (ivory-key.simulate::up-pattern "a"))
     :actions (list (ivory-key.simulate::emit-action :single))))))

(defun backend-differential-multi-interaction ()
  (ivory-key.simulate::make-sim-interaction
   :name "multi" :participants '("a" "b")
   :cases
   (list
    (ivory-key.simulate::make-sim-case
     :name "a-first"
     :pattern (ivory-key.simulate::sequence-pattern
               (ivory-key.simulate::down-pattern "a")
               (ivory-key.simulate::down-pattern "b")
               (ivory-key.simulate::up-pattern "a")
               (ivory-key.simulate::up-pattern "b"))
     :actions (list (ivory-key.simulate::emit-action :a-first)))
    (ivory-key.simulate::make-sim-case
     :name "b-first"
     :pattern (ivory-key.simulate::sequence-pattern
               (ivory-key.simulate::down-pattern "a")
               (ivory-key.simulate::down-pattern "b")
               (ivory-key.simulate::up-pattern "b")
               (ivory-key.simulate::up-pattern "a"))
     :actions (list (ivory-key.simulate::emit-action :b-first))))))

(defun backend-differential-staged-interaction ()
  (ivory-key.simulate::make-sim-interaction
   :name "staged" :participants '("a")
   :cases
   (list
    (ivory-key.simulate::make-sim-case
     :name "short" :priority 1
     :pattern (ivory-key.simulate::duration-pattern "a" :less-than 1000)
     :actions (list (ivory-key.simulate::emit-action :short)))
    (ivory-key.simulate::make-sim-case
     :name "medium" :priority 2
     :pattern (ivory-key.simulate::duration-pattern "a" :at-least 1000 :less-than 2000)
     :actions (list (ivory-key.simulate::emit-action :medium)))
    (ivory-key.simulate::make-sim-case
     :name "long" :priority 3
     :pattern (ivory-key.simulate::deadline-pattern 2000
                                                     :after-position "a"
                                                     :while-down "a")
     :actions (list (ivory-key.simulate::emit-action :long))))))

(deftest backend-differential-direct-static-forwarding-matches-reference-output
  (let* ((layout
           (backend-differential-layout
            nil
            (list (cons "q" (ivory-key.model:make-text-output "q"))
                  (cons "w" (ivory-key.model:make-text-output "w")))))
         (events
           (list (backend-differential-event 0 :down "q")
                 (backend-differential-event 1 :up "q")
                 (backend-differential-event 2 :down "w")
                 (backend-differential-event 3 :up "w")))
         (reference
           (ivory-key.simulate:simulate-normalized-layout-events layout events))
         (request (backend-differential-request layout)))
    (multiple-value-bind (backend-output translated-events)
        (backend-differential-static-pipeline-observations request events)
      (backend-differential-assert-equal
       (ivory-key.simulate:simulation-result-outputs reference)
       backend-output
       "direct static XKB/Kanata forwarding preserves observable Unicode output")
      (backend-differential-assert-equal
       '((0 :down "q" "q" "q" "AD01")
         (1 :up "q" "q" "q" "AD01")
         (2 :down "w" "w" "w" "AD02")
         (3 :up "w" "w" "w" "AD02"))
       translated-events
       "backend physical translation preserves the complete event order"))))

(deftest backend-differential-refuses-unproved-product-level-selection
  (dolist (count '(2 4 8))
    (let* ((states (loop for index below count collect (format nil "s~D" index)))
           (axis (ivory-key.model:make-context-axis
                  "level" states :resolution :product))
           (behavior
             (ivory-key.model::make-axis-choice-behavior
              "level"
              (loop for state in states
                    for index from 0
                    collect
                    (cons state
                          (ivory-key.model:make-text-output
                           (string (code-char (+ (char-code #\a) index))))))))
           (layout
             (backend-differential-layout
              (list axis) (list (cons "q" behavior))))
           (events (list (backend-differential-event 0 :down "q")
                         (backend-differential-event 1 :up "q"))))
      (loop for state in states
            for index from 0
            for reference =
              (ivory-key.simulate:simulate-normalized-layout-events
               layout events :axes (list (cons "level" state)))
            do (backend-differential-assert-equal
                (list (list :text
                            (string (code-char (+ (char-code #\a) index)))) )
                (ivory-key.simulate:simulation-result-outputs reference)
                "reference simulator selects each tested level"))
      (backend-differential-assert
       (member :unsupported-context-selection
               (backend-differential-issue-codes layout))
       "~D-level product table must be refused before backend emission." count)
      (backend-differential-assert-equal
       :unsupported-context-selection
       (backend-differential-stage-code
        (lambda () (backend-differential-request layout)))
       "product-level selector refusal is stable"))))

(deftest backend-differential-refuses-semantic-modifiers-without-approximation
  (let* ((layout
           (backend-differential-layout
            nil
            (list
             (cons "q"
                   (ivory-key.model:make-modifier-operation :press "meta")))
            :modifiers '("meta")))
         (events (list (backend-differential-event 0 :down "q")
                       (backend-differential-event 1 :up "q")))
         (reference
           (ivory-key.simulate:simulate-normalized-layout-events layout events))
         (request (backend-differential-direct-request '("q") :modifiers '("meta"))))
    (backend-differential-assert-equal
     '((:modifier :press "meta"))
     (ivory-key.simulate:simulation-result-outputs reference)
     "reference simulator retains the semantic modifier observation")
    (backend-differential-assert
     (member :unsupported-semantic-modifiers
             (backend-differential-issue-codes layout))
     "compiler analysis must identify absent semantic modifier allocation")
    (backend-differential-assert-backend-refusal
     request '("meta") "semantic modifier")))

(deftest backend-differential-refuses-single-and-multi-participant-interactions
  (let* ((single (backend-differential-single-interaction))
         (multi (backend-differential-multi-interaction))
         (single-events
           (list (backend-differential-event 0 :down "a")
                 (backend-differential-event 10 :up "a")))
         (multi-events
           (list (backend-differential-event 0 :down "a")
                 (backend-differential-event 10 :down "b")
                 (backend-differential-event 20 :up "b")
                 (backend-differential-event 30 :up "a")))
         (request
           (backend-differential-direct-request
            '("a" "b") :interactions (list single multi))))
    (backend-differential-assert-equal
     '(:single)
     (ivory-key.simulate:simulation-result-outputs
      (ivory-key.simulate::simulate-events (list single) single-events))
     "reference simulator observes the single-participant tap")
    (backend-differential-assert-equal
     '(:b-first)
     (ivory-key.simulate:simulation-result-outputs
      (ivory-key.simulate::simulate-events (list multi) multi-events))
     "reference simulator distinguishes the B-first exact release order")
    (backend-differential-assert-backend-refusal
     request (list single multi) "single and multi-participant interactions")))

(deftest backend-differential-refuses-multi-stage-duration-semantics
  (let ((interaction (backend-differential-staged-interaction)))
    (dolist (fixture '((999 :short) (1000 :medium) (1999 :medium) (2000 :long)))
      (destructuring-bind (release expected) fixture
        (backend-differential-assert-equal
         (list expected)
         (ivory-key.simulate:simulation-result-outputs
          (ivory-key.simulate::simulate-events
           (list interaction)
           (list (backend-differential-event 0 :down "a")
                 (backend-differential-event release :up "a"))))
         "reference simulator retains exact staged-duration boundaries")))
    (backend-differential-assert-backend-refusal
     (backend-differential-direct-request '("a")
                                          :interactions (list interaction))
     (list interaction) "multi-stage duration interaction")))

(deftest backend-differential-refuses-overlay-activation-and-behavioral-latches
  (let* ((patch-axis
           (ivory-key.model:make-context-axis
            "fun" '("base" "active") :resolution :patch))
         (overlay
           (ivory-key.model::make-overlay-patch
            "fun-overlay" "fun" "active"
            (list (ivory-key.model::make-patch-binding
                   "q" (ivory-key.model:make-text-output "F")))))
         (overlay-layout
           (backend-differential-layout
            (list patch-axis)
            (list (cons "q" (ivory-key.model:make-text-output "q")))
            :overlays (list overlay)))
         (latch-axis
           (ivory-key.model:make-context-axis
            "shift-latch" '("plain" "latch") :resolution :behavioral))
         (latch-layout
           (backend-differential-layout
            (list latch-axis)
            (list
             (cons "a" (ivory-key.model:make-text-output "a"))
             (cons "q"
                   (ivory-key.model::make-axis-choice-behavior
                    "shift-latch"
                    (list
                     (cons "plain" (ivory-key.model:make-text-output "q"))
                     (cons "latch" (ivory-key.model:make-text-output "Q")))))))))
    (backend-differential-assert-equal
     '((:text "F"))
     (ivory-key.simulate:simulation-result-outputs
      (ivory-key.simulate:simulate-normalized-layout-events
       overlay-layout
       (list (backend-differential-event 0 :down "q")
             (backend-differential-event 1 :up "q"))
       :axes '(("fun" . "active"))))
     "reference simulator observes the active overlay output")
    (backend-differential-assert
     (member :unproved-patch-activation
             (backend-differential-issue-codes overlay-layout))
     "overlay activation must be an explicit compiler refusal")
    (let ((reference
            (ivory-key.simulate:simulate-normalized-layout-events
             latch-layout
             (list (backend-differential-event 0 :down "a")
                   (backend-differential-event 1 :up "a")
                   (backend-differential-event 2 :down "q")
                   (backend-differential-event 3 :up "q"))
             :latches '(("shift-latch" . "latch")))))
      (backend-differential-assert-equal
       '((:text "a") (:text "Q"))
       (ivory-key.simulate:simulation-result-outputs reference)
       "nonconsulting A preserves the latch for consulting Q")
      (backend-differential-assert-equal
       nil (ivory-key.simulate:simulation-result-latches reference)
       "the committed consulting binding consumes the latch")
      (backend-differential-assert-equal
       1
       (count :latch-consumed
              (mapcar #'ivory-key.simulate::simulation-trace-entry-kind
                      (ivory-key.simulate:simulation-result-trace reference)))
       "reference trace records exactly one latch consumption"))
    (backend-differential-assert
     (member :unsupported-context-selection
             (backend-differential-issue-codes latch-layout))
     "behavioral latch selection must be refused before XKB/Kanata emission")
    (backend-differential-assert-equal
     :unsupported-context-selection
     (backend-differential-stage-code
      (lambda () (backend-differential-request latch-layout)))
     "behavioral latch refusal is stable")))
