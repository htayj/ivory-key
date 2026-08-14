;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Raw finite buffered-dispatch contract regressions.

(in-package #:ivory-key.tests)

(defun dispatch-event (time kind position)
  (ivory-key.simulate::make-timed-event time kind position))

(defun dispatch-semantic-edges (result)
  (mapcar (lambda (edge)
            (list (ivory-key.simulate::semantic-key-transition-kind edge)
                  (ivory-key.simulate::semantic-key-transition-key edge)))
          (ivory-key.simulate::simulation-result-semantic-transitions result)))

(defun dispatch-layout-with-named-b ()
  "Make B the one direct named-key binding eligible for buffered custody."
  (let* ((layout (pending-input-normalized-layout))
         (b (find "b" (ivory-key.model:normalized-layout-bindings layout)
                  :test #'ivory-key.model:identifier=
                  :key #'ivory-key.model:normalized-binding-position))
         (entry (first (ivory-key.model:normalized-binding-entries b)))
         (named-b (make-instance
                   'ivory-key.model:normalized-binding
                   :position (ivory-key.model:normalized-binding-position b)
                   :axes (ivory-key.model:normalized-binding-axes b)
                   :entries
                   (list (ivory-key.model:make-normalized-binding-entry
                          (ivory-key.model:normalized-entry-tuple entry)
                          (ivory-key.model:make-named-key-output "b"))))))
    (make-instance
     'ivory-key.model:normalized-layout
     :name (ivory-key.model:normalized-layout-name layout)
     :topology (ivory-key.model:normalized-layout-topology layout)
     :axes (ivory-key.model:normalized-layout-axes layout)
     :modifiers (ivory-key.model:normalized-layout-modifiers layout)
     :bindings (cons named-b (remove b (ivory-key.model:normalized-layout-bindings layout)))
     :patches (ivory-key.model:normalized-layout-patches layout)
     :interactions (ivory-key.model:normalized-layout-interactions layout)
     :origin (ivory-key.model:normalized-layout-origin layout))))

(defun dispatch-layout-with-contextful-named-b ()
  "Make B a two-row named-key table: invalid for buffered foreign custody."
  (let* ((layout (dispatch-layout-with-named-b))
         (b (find "b" (ivory-key.model:normalized-layout-bindings layout)
                  :test #'ivory-key.model:identifier=
                  :key #'ivory-key.model:normalized-binding-position))
         (context-entry
           (lambda (state key)
             (ivory-key.model:make-normalized-binding-entry
              (ivory-key.model:make-context-tuple
               (list (cons "case" state)))
              (ivory-key.model:make-named-key-output key))))
         (contextful-b
           (make-instance
            'ivory-key.model:normalized-binding
            :position (ivory-key.model:normalized-binding-position b)
            :axes (list (ivory-key.model:ensure-identifier "case"))
            :entries (list (funcall context-entry "plain" "b")
                           (funcall context-entry "shifted" "B")))))
    (make-instance
     'ivory-key.model:normalized-layout
     :name (ivory-key.model:normalized-layout-name layout)
     :topology (ivory-key.model:normalized-layout-topology layout)
     :axes (ivory-key.model:normalized-layout-axes layout)
     :modifiers (ivory-key.model:normalized-layout-modifiers layout)
     :bindings (cons contextful-b
                     (remove b (ivory-key.model:normalized-layout-bindings layout)))
     :patches (ivory-key.model:normalized-layout-patches layout)
     :interactions (ivory-key.model:normalized-layout-interactions layout)
     :origin (ivory-key.model:normalized-layout-origin layout))))

(deftest simulation-dispatch-whole-layout-selected-contract-is-structural
  "The public whole-layout adapter derives the contract before enabling custody."
  (let* ((layout (pending-input-normalized-layout))
         (buffered (pending-input-policy
                    :names '("tap-hold-super-semicolon")))
         (events (list (dispatch-event 0 :down "semicolon")
                       (dispatch-event 1 :down "b"))))
    (signals ivory-key.simulate:model-simulation-compilation-error
      (ivory-key.simulate:simulate-normalized-layout-events
       layout events :interaction-compatibility-policy buffered)))
  (let* ((layout (pending-input-normalized-layout))
         (modern (pending-input-policy
                  :mode :modern-no-delay
                  :names '("tap-hold-super-semicolon")))
         (result
           (ivory-key.simulate:simulate-normalized-layout-events
            layout
            (list (dispatch-event 0 :down "semicolon")
                  (dispatch-event 1 :down "b")
                  (dispatch-event 2 :up "semicolon")
                  (dispatch-event 3 :up "b"))
            :interaction-compatibility-policy modern)))
    (is-equal '((:text "b") (:named-key "semicolon"))
              (ivory-key.simulate:simulation-result-outputs result))
    (is-equal nil (dispatch-semantic-edges result))))

(deftest simulation-dispatch-refuses-contextful-named-key-foreign-route-at-compile-time
  "A context table is not a direct route merely because every row names a key."
  (signals ivory-key.simulate:model-simulation-compilation-error
    (ivory-key.simulate::compile-normalized-layout-simulation
     (dispatch-layout-with-contextful-named-b)
     :interaction-compatibility-policy
     (pending-input-policy :names '("tap-hold-super-semicolon")))))

(deftest simulation-dispatch-whole-layout-tap-brackets-named-key-route
  (let* ((layout (pending-input-normalized-layout))
         ;; Replace the fixture's text B binding with one pressable named key
         ;; so the normative edge ordering is observable end to end.
         (b (find "b" (ivory-key.model:normalized-layout-bindings layout)
                  :test #'ivory-key.model:identifier=
                  :key #'ivory-key.model:normalized-binding-position))
         (entry (first (ivory-key.model:normalized-binding-entries b)))
         (named-b
           (make-instance
            'ivory-key.model:normalized-binding
            :position (ivory-key.model:normalized-binding-position b)
            :axes (ivory-key.model:normalized-binding-axes b)
            :entries
            (list (ivory-key.model:make-normalized-binding-entry
                   (ivory-key.model:normalized-entry-tuple entry)
                   (ivory-key.model:make-named-key-output "b")))))
         (layout
           (make-instance
            'ivory-key.model:normalized-layout
            :name (ivory-key.model:normalized-layout-name layout)
            :topology (ivory-key.model:normalized-layout-topology layout)
            :axes (ivory-key.model:normalized-layout-axes layout)
            :modifiers (ivory-key.model:normalized-layout-modifiers layout)
            :bindings (cons named-b (remove b (ivory-key.model:normalized-layout-bindings layout)))
            :patches (ivory-key.model:normalized-layout-patches layout)
            :interactions (ivory-key.model:normalized-layout-interactions layout)
            :origin (ivory-key.model:normalized-layout-origin layout)))
         (result
           (ivory-key.simulate:simulate-normalized-layout-events
            layout
            (list (dispatch-event 0 :down "semicolon")
                  (dispatch-event 1 :down "b")
                  (dispatch-event 2 :up "semicolon")
                  (dispatch-event 2 :up "b"))
            :interaction-compatibility-policy
            (pending-input-policy :names '("tap-hold-super-semicolon")))))
    (is-equal '((:named-key "semicolon") (:named-key "b"))
              (ivory-key.simulate:simulation-result-outputs result))
    (is-equal '((:press "semicolon") (:press "b")
                (:release "semicolon") (:release "b"))
              (dispatch-semantic-edges result))
    (let ((b-release
            (find "b" (ivory-key.simulate:simulation-result-semantic-transitions result)
                  :test #'string=
                  :key #'ivory-key.simulate::semantic-key-transition-key
                  :from-end t)))
      (is-equal :release
                (ivory-key.simulate::semantic-key-transition-kind b-release))
      (is-equal :routed-up
                (ivory-key.simulate::semantic-key-transition-origin b-release))
      (is-equal 3
                (ivory-key.simulate::semantic-key-transition-original-index b-release)))))

(deftest simulation-dispatch-contract-provenance-and-determinism
  (flet ((run ()
           (ivory-key.simulate:simulate-normalized-layout-events
            (dispatch-layout-with-named-b)
            (list (dispatch-event 0 :down "semicolon")
                  (dispatch-event 1 :down "b")
                  (dispatch-event 2 :up "b")
                  (dispatch-event 3 :up "semicolon"))
            :interaction-compatibility-policy
            (pending-input-policy :names '("tap-hold-super-semicolon")))))
    (let* ((first (run))
           (second (run))
           (transaction (first (ivory-key.simulate:simulation-result-dispatch-transactions first))))
      (let ((contract (getf transaction :contract)))
        (is-equal :kanata-1-12-buffered (getf contract :mode))
        (is-equal "tap-hold-super-semicolon" (getf contract :interaction))
        (is-equal "semicolon" (getf contract :owner))
        (is-equal 200 (getf contract :deadline))
        (is-equal "foreign" (getf contract :capture))
        (is-equal '(:kind :modifier :identity "super" :state nil :release :owner-terminal)
                  (getf contract :held-signature))
        (is-equal "semicolon" (getf contract :tap-key))
        (is-equal '((:timeout "hold-timeout")
                    (:foreign-release "hold-after-foreign-release")
                    (:tap "tap"))
                  (mapcar (lambda (role)
                            (list (getf role :role) (getf role :candidate)))
                          (getf contract :roles)))
        (dolist (role (getf contract :roles))
          (is-equal "<string>"
                    (getf (getf (getf role :origin) :definition) :source)))
        (is-equal "<string>"
                  (getf (getf (getf contract :origin) :definition) :source))
        (dolist (key '(:interaction :timeout :foreign-release :tap))
          (is-equal "<string>"
                    (getf (getf (getf (getf contract :provenance) key)
                                :definition)
                          :source))))
      (is-equal :foreign-release (getf transaction :committed-role))
      (is-equal :foreign-release-hold (getf transaction :disposition))
      (is-equal "b" (getf transaction :terminal-foreign-position))
      (is-equal 2 (getf transaction :terminal-foreign-index))
      (is-equal 2 (getf transaction :terminal-foreign-time))
      (is-equal (dispatch-semantic-edges first) (dispatch-semantic-edges second))
      (is-equal (ivory-key.simulate:simulation-result-dump-string first)
                (ivory-key.simulate:simulation-result-dump-string second))
      (is-equal (mapcar (lambda (entry)
                          (list (getf entry :state) (getf entry :committed-role)
                                (getf entry :foreign-down-index)))
                        (ivory-key.simulate:simulation-result-dispatch-transactions first))
                (mapcar (lambda (entry)
                          (list (getf entry :state) (getf entry :committed-role)
                                (getf entry :foreign-down-index)))
                        (ivory-key.simulate:simulation-result-dispatch-transactions second))))))

(deftest simulation-dispatch-refuses-typed-contract-bypass-and-owner-overlap
  (signals error
    (ivory-key.simulate:make-simulator
     :interactions
     (list (ivory-key.simulate::make-sim-interaction
           :name :bad :participants '(:a) :route-kind :timed
            :buffered-dispatch-contract t))))
  (let* ((layout (dispatch-layout-with-named-b))
         (policy (pending-input-policy :names '("tap-hold-super-semicolon"))))
    (multiple-value-bind (interactions axes)
        (ivory-key.simulate::compile-normalized-layout-simulation
         layout :interaction-compatibility-policy policy)
      (let* ((selected (find-if (lambda (interaction)
                                  (equal "tap-hold-super-semicolon"
                                         (ivory-key.simulate::sim-interaction-name interaction)))
                                interactions))
             (overlap (ivory-key.simulate::make-sim-interaction
                       :name :unproved-overlap
                       :participants (copy-list
                                      (ivory-key.simulate::sim-interaction-participants selected))
                       :route-kind :timed :cases nil)))
        (signals ivory-key.simulate:buffered-dispatch-refusal
          (ivory-key.simulate:simulate-events
           (append interactions (list overlap))
           (list (dispatch-event 0 :down "semicolon")) :axes axes))))))

(deftest simulation-dispatch-refuses-forged-contract-name-and-layout-overlap
  (let* ((layout (dispatch-layout-with-named-b))
         (policy (pending-input-policy :names '("tap-hold-super-semicolon"))))
    (multiple-value-bind (interactions ignored-axes)
        (ivory-key.simulate::compile-normalized-layout-simulation
         layout :interaction-compatibility-policy policy)
      (declare (ignore ignored-axes))
      (let* ((selected (find-if (lambda (interaction)
                                  (equal "tap-hold-super-semicolon"
                                         (ivory-key.simulate::sim-interaction-name interaction)))
                                interactions))
             (contract (ivory-key.simulate::sim-interaction-buffered-dispatch-contract
                        selected)))
        (signals error
          (ivory-key.simulate:make-simulator
           :interactions
           (list (ivory-key.simulate::%make-sim-interaction
                  :name :tap-hold-super-semicolon
                  :participants (ivory-key.simulate::sim-interaction-participants selected)
                  :route-kind :timed
                  :buffered-dispatch-contract contract
                  :dispatch-plan-token (make-symbol "FORGED-PLAN"))))))
    (let* ((selected
             (find "tap-hold-super-semicolon"
                   (ivory-key.model:normalized-layout-interactions layout)
                   :test #'string=
                   :key (lambda (interaction)
                          (ivory-key.model:identifier-name
                           (ivory-key.model:normalized-interaction-name interaction)))))
           (overlap
             (make-instance
              'ivory-key.model:normalized-interaction
              :name (ivory-key.model:ensure-identifier "unproved-overlap")
              :participants (ivory-key.model:normalized-interaction-participants selected)
              :observe (ivory-key.model:normalized-interaction-observe selected)
              :anchor (ivory-key.model:normalized-interaction-anchor selected)
              :candidates (ivory-key.model:normalized-interaction-candidates selected)
              :arbitration (ivory-key.model:normalized-interaction-arbitration selected)
              :origin nil))
           (overlapping-layout
             (make-instance
              'ivory-key.model:normalized-layout
              :name (ivory-key.model:normalized-layout-name layout)
              :topology (ivory-key.model:normalized-layout-topology layout)
              :axes (ivory-key.model:normalized-layout-axes layout)
              :modifiers (ivory-key.model:normalized-layout-modifiers layout)
              :bindings (ivory-key.model:normalized-layout-bindings layout)
              :patches (ivory-key.model:normalized-layout-patches layout)
              :interactions (append (ivory-key.model:normalized-layout-interactions layout)
                                    (list overlap))
              :origin (ivory-key.model:normalized-layout-origin layout))))
      (signals ivory-key.simulate:model-simulation-compilation-error
        (ivory-key.simulate:compile-normalized-layout-simulation
         overlapping-layout :interaction-compatibility-policy policy))))))

(deftest simulation-dispatch-refuses-forged-normalized-contract-clone
  "Same source spelling and role names cannot authorize altered simulator IR."
  (let* ((layout (pending-input-normalized-layout))
         (policy (pending-input-policy :names '("tap-hold-super-semicolon")))
         (selected
           (find "tap-hold-super-semicolon"
                 (ivory-key.model:normalized-layout-interactions layout)
                 :test #'string=
                 :key (lambda (interaction)
                        (ivory-key.model:identifier-name
                         (ivory-key.model:normalized-interaction-name interaction)))))
         (contract (first (ivory-key.model:derive-interaction-compatibility-contracts
                           policy layout)))
         (tap (find "tap" (ivory-key.model:normalized-interaction-candidates selected)
                    :test #'string=
                    :key (lambda (candidate)
                           (ivory-key.model:identifier-name
                            (ivory-key.model:normalized-candidate-name candidate)))))
         (evil-tap
           (make-instance
            'ivory-key.model::normalized-interaction-candidate
            :name (ivory-key.model:normalized-candidate-name tap)
            :match (ivory-key.model:normalized-candidate-match tap)
            :commit (ivory-key.model:normalized-candidate-commit tap)
            :entries
            (list (ivory-key.model:make-normalized-binding-entry
                   (ivory-key.model:normalized-entry-tuple (first (ivory-key.model:normalized-candidate-entries tap)))
                   (ivory-key.model:make-named-key-output "evil")))
            :effects (ivory-key.model:normalized-candidate-effects tap)
            :context-axes (ivory-key.model:normalized-candidate-context-axes tap)
            :context-policy (ivory-key.model:normalized-candidate-context-policy tap)
            :effect-start (ivory-key.model:normalized-candidate-effect-start tap)
            :origin (ivory-key.model:normalized-candidate-origin tap)))
         (forged
           (make-instance
            'ivory-key.model:normalized-interaction
            :name (ivory-key.model:normalized-interaction-name selected)
            :participants (ivory-key.model:normalized-interaction-participants selected)
            :observe (ivory-key.model:normalized-interaction-observe selected)
            :anchor (ivory-key.model:normalized-interaction-anchor selected)
            :candidates
            (mapcar (lambda (candidate) (if (eq candidate tap) evil-tap candidate))
                    (ivory-key.model:normalized-interaction-candidates selected))
            :arbitration (ivory-key.model:normalized-interaction-arbitration selected)
            :origin (ivory-key.model:normalized-interaction-origin selected))))
    (signals ivory-key.simulate:model-simulation-compilation-error
      (ivory-key.simulate::%compile-normalized-interaction-with-contract
       forged contract (make-symbol "FORGED-PLAN")))
    (signals error
      (funcall (symbol-function 'ivory-key.simulate:compile-normalized-interaction)
               forged :buffered-dispatch-contract contract))
    (signals error
      (funcall (symbol-function 'ivory-key.simulate:compile-normalized-interactions)
               (list forged) :interaction-compatibility-contracts (list contract)))))

(deftest simulation-dispatch-selected-owners-remain-independent
  "Selected owners are excluded from one another's foreign capture frontier."
  (flet ((run (first-up second-up)
           (ivory-key.simulate:simulate-normalized-layout-events
            (dispatch-layout-with-named-b)
            (list (dispatch-event 0 :down "a")
                  (dispatch-event 1 :down "semicolon")
                  (dispatch-event 252 :up first-up)
                  (dispatch-event 253 :up second-up))
            :interaction-compatibility-policy
            (pending-input-policy :names '("tap-hold-super-a"
                                           "tap-hold-super-semicolon")))))
    (dolist (result (list (run "a" "semicolon")
                          (run "semicolon" "a")))
      (is-equal '((:modifier :press "super") (:modifier :release "super"))
                (ivory-key.simulate:simulation-result-outputs result))
      (is-equal nil (dispatch-semantic-edges result))
      (is-equal '(:complete :complete)
                (mapcar (lambda (transaction) (getf transaction :state))
                        (ivory-key.simulate:simulation-result-dispatch-transactions result)))
      (dolist (transaction (ivory-key.simulate:simulation-result-dispatch-transactions result))
        (is-equal nil (getf transaction :foreign-position))
        (is-equal nil (getf transaction :disposition))))))

(deftest simulation-dispatch-whole-layout-tap-and-equal-deadline-boundaries
  (flet ((run (up-time)
           (ivory-key.simulate:simulate-normalized-layout-events
            (dispatch-layout-with-named-b)
            (list (dispatch-event 0 :down "semicolon")
                  (dispatch-event up-time :up "semicolon"))
            :interaction-compatibility-policy
            (pending-input-policy :names '("tap-hold-super-semicolon")))))
    (let ((tap (run 199))
          (deadline (run 200)))
      (is-equal '((:named-key "semicolon"))
                (ivory-key.simulate:simulation-result-outputs tap))
      (is-equal '((:modifier :press "super") (:modifier :release "super"))
                (ivory-key.simulate:simulation-result-outputs deadline))
      (dolist (result (list tap deadline))
        (let ((transaction
                (first (ivory-key.simulate:simulation-result-dispatch-transactions result))))
          (is-equal :complete (getf transaction :state))
          (is-equal nil (getf transaction :foreign-position))
          (is-equal nil (getf transaction :terminal-foreign-position)))))))

(deftest simulation-dispatch-refuses-overlay-foreign-route
  (let* ((layout (dispatch-layout-with-named-b))
         (policy (pending-input-policy :names '("tap-hold-super-semicolon"))))
    (multiple-value-bind (interactions axes)
        (ivory-key.simulate::compile-normalized-layout-simulation
         layout :interaction-compatibility-policy policy)
      (let* ((case (ivory-key.simulate::make-sim-case
                    :name :overlay-b :pattern (ivory-key.simulate::down-pattern "b")
                    :commit :when-matched
                    :actions (list (ivory-key.simulate::emit-action '(:named-key "b")))))
             (overlay (ivory-key.simulate::make-sim-interaction
                       :name :overlay-b :participants '("b") :route-kind :overlay-binding
                       :cases (list case))))
        (signals ivory-key.simulate:buffered-dispatch-refusal
          (ivory-key.simulate:simulate-events
           (append
            (remove-if (lambda (interaction)
                         (member "b" (ivory-key.simulate::sim-interaction-participants interaction)
                                 :test #'string=))
                       interactions)
            (list overlay))
           (list (dispatch-event 0 :down "semicolon")
                 (dispatch-event 1 :down "b"))
           :axes axes))))))

(deftest simulation-dispatch-refuses-raw-ordinary-route-substitution
  (let* ((layout (dispatch-layout-with-named-b))
         (policy (pending-input-policy :names '("tap-hold-super-semicolon"))))
    (multiple-value-bind (interactions axes)
        (ivory-key.simulate::compile-normalized-layout-simulation
         layout :interaction-compatibility-policy policy)
      (let* ((case (ivory-key.simulate::make-sim-case
                    :name :raw-b :pattern (ivory-key.simulate::down-pattern "b")
                    :commit :when-matched
                    :actions (list (ivory-key.simulate::emit-action '(:named-key "b")))))
             (raw-b (ivory-key.simulate::make-sim-interaction
                     :name :raw-b :participants '("b") :route-kind :ordinary-binding
                     :cases (list case))))
        (signals ivory-key.simulate:buffered-dispatch-refusal
          (ivory-key.simulate:simulate-events
           (append
            (remove-if (lambda (interaction)
                         (member "b" (ivory-key.simulate::sim-interaction-participants interaction)
                                 :test #'string=))
                       interactions)
            (list raw-b))
           (list (dispatch-event 0 :down "semicolon")
                 (dispatch-event 1 :down "b"))
           :axes axes)))))
  (signals error
    (ivory-key.simulate::make-sim-action :kind :emit :value '(:named-key :b))))

(deftest simulation-dispatch-refuses-raw-timed-foreign-splice-before-publication
  "A raw timed B cannot observe a foreign event that buffered custody withholds."
  (let* ((layout (dispatch-layout-with-named-b))
         (policy (pending-input-policy :names '("tap-hold-super-semicolon"))))
    (multiple-value-bind (interactions axes)
        (ivory-key.simulate::compile-normalized-layout-simulation
         layout :interaction-compatibility-policy policy)
      (let* ((evil-case
               (ivory-key.simulate::make-sim-case
                :name :evil-b :pattern (ivory-key.simulate::down-pattern "b")
                :commit :when-matched
                :actions (list (ivory-key.simulate::emit-action '(:named-key "evil")))))
             (evil-timed
               (ivory-key.simulate::make-sim-interaction
                :name :evil-b :participants '("b") :route-kind :timed
                :cases (list evil-case)))
             (machine
               (ivory-key.simulate:make-simulator
                :interactions (append interactions (list evil-timed)) :axes axes)))
        (ivory-key.simulate:simulator-feed-event
         machine (dispatch-event 0 :down "semicolon"))
        (handler-case
            (progn
              (ivory-key.simulate:simulator-feed-event
               machine (dispatch-event 1 :down "b"))
              (error "Expected foreign timed-route refusal."))
          (ivory-key.simulate:buffered-dispatch-refusal (condition)
            (is-equal :foreign-timed-interaction
                      (ivory-key.simulate:buffered-dispatch-refusal-code condition))))
        ;; The rejected B never joins the physical frontier and its evil case
        ;; never receives a candidate start/commit opportunity.
        (is-equal 1 (length (ivory-key.simulate:simulator-events machine)))
        (is-equal nil
                  (ivory-key.simulate:simulation-result-outputs
                   (ivory-key.simulate:simulator-result machine)))))))

(deftest simulation-dispatch-refuses-forged-ordinary-route-authority
  (let* ((layout (dispatch-layout-with-named-b))
         (binding (find "b" (ivory-key.model:normalized-layout-bindings layout)
                        :test #'ivory-key.model:identifier=
                        :key #'ivory-key.model:normalized-binding-position))
         (entry (first (ivory-key.model:normalized-binding-entries binding)))
         (forged
           (make-instance
            'ivory-key.model:normalized-binding
            :position (ivory-key.model:normalized-binding-position binding)
            :axes (ivory-key.model:normalized-binding-axes binding)
            :entries
            (list (ivory-key.model:make-normalized-binding-entry
                   (ivory-key.model:normalized-entry-tuple entry)
                   (ivory-key.model:make-named-key-output "evil"))))))
    (signals ivory-key.simulate:model-simulation-compilation-error
      (ivory-key.simulate::%compile-normalized-ordinary-binding-with-route
       forged binding (make-symbol "FORGED-PLAN")))
    (signals error
      (funcall (symbol-function 'ivory-key.simulate:compile-normalized-ordinary-binding)
               forged :routed-dispatch-p t))
    (signals error
      (funcall (symbol-function 'ivory-key.simulate:compile-normalized-ordinary-bindings)
               (list forged) :routed-dispatch-positions '("b")))))

(deftest simulation-dispatch-refuses-cross-plan-route-splice
  "Timed ownership and privileged ordinary custody must share one plan token."
  (let ((layout (dispatch-layout-with-named-b))
        (policy (pending-input-policy :names '("tap-hold-super-semicolon"))))
    (multiple-value-bind (left-interactions left-axes)
        (ivory-key.simulate::compile-normalized-layout-simulation
         layout :interaction-compatibility-policy policy)
      (multiple-value-bind (right-interactions ignored-axes)
          (ivory-key.simulate::compile-normalized-layout-simulation
           layout :interaction-compatibility-policy policy)
        (declare (ignore ignored-axes))
        (let ((selected
                (remove-if-not
                 #'ivory-key.simulate::sim-interaction-buffered-dispatch-contract
                 left-interactions))
              (foreign-route
                (find-if (lambda (interaction)
                           (member "b"
                                   (ivory-key.simulate::sim-interaction-participants interaction)
                                   :test #'string=))
                         right-interactions)))
          (signals error
            (ivory-key.simulate:simulate-events
             (append selected (list foreign-route))
             (list (dispatch-event 0 :down "semicolon")
                   (dispatch-event 1 :down "b"))
             :axes left-axes)))))))
