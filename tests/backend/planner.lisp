;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Focused capability-planner regressions.

(in-package #:ivory-key.tests)

(defun planner-test-topology (&rest positions)
  (ivory-key.model:make-topology
   "planner-topology"
   (mapcar #'ivory-key.model:make-logical-position positions)))

(defun planner-test-product-binding (position axes &key inherit-hole)
  (let ((tuples (ivory-key.model:allowed-product-tuples axes))
        (number 0))
    (ivory-key.model:make-binding
     position
     (ivory-key.model:make-behavior-table
      (mapcar #'ivory-key.model:axis-name axes)
      (mapcar (lambda (tuple)
                (incf number)
                (cond ((and inherit-hole (= number 4))
                       (ivory-key.model:make-inherit-entry tuple (first tuples)))
                      ((and inherit-hole (= number 5))
                       (ivory-key.model:make-none-entry tuple))
                      (t
                       (ivory-key.model:make-behavior-entry
                        tuple
                        (ivory-key.model:make-text-output
                         (format nil "value-~D" number))))))
              tuples)))))

(defun planner-test-layout (name axes &key modifiers inherit-hole (positions '("q")))
  (let ((topology (apply #'planner-test-topology positions)))
    (ivory-key.model:make-layout
     name topology axes (or modifiers nil)
     :bindings (mapcar (lambda (position)
                         (planner-test-product-binding
                          position (ivory-key.model:product-axes axes)
                          :inherit-hole inherit-hole))
                       positions))))

(defun planner-test-placement (topology mappings)
  (ivory-key.model:make-device-placement "planner-device" topology mappings))

(defun planner-test-plan (layout placement &key resource-pools)
  (ivory-key.backend::plan-normalized-layout
   (ivory-key.model:normalize-layout layout) placement
   :backends (list (ivory-key.backend:make-xkb-backend))
   :resource-pools resource-pools))

(defun planner-result-for (plan feature)
  (find feature (ivory-key.backend::lowering-plan-realizations plan)
        :key #'ivory-key.backend:realization-feature :test #'equal))

(defun planner-result-grade (plan feature)
  (let ((result (planner-result-for plan feature)))
    (unless result
      (error "Planner emitted no realization result for ~S." feature))
    (ivory-key.backend:realization-grade result)))

(defun planner-partition-for (plan position)
  (find position
        (ivory-key.backend::lowering-plan-multi-bank-partition-requirements plan)
        :test #'ivory-key.model:identifier=
        :key #'ivory-key.backend::multi-bank-partition-requirement-position))

(defun planner-resource-for (plan kind position)
  (find-if (lambda (resource)
             (and (eq kind (ivory-key.backend::planner-resource-requirement-kind
                            resource))
                  (ivory-key.model:identifier=
                   position
                   (ivory-key.backend::planner-resource-requirement-owner resource))))
           (ivory-key.backend::lowering-plan-resource-requirements plan)))

(defun planner-test-origin (&key (name "planner-origin.ivory")
                                  (definition-line 3) (definition-column 5)
                                  use-lines)
  (let ((source (ivory-key.source:make-source-file :name name :text "")))
    (ivory-key.source:make-source-origin
     :definition-span
     (ivory-key.source:make-source-span
      :source source :start-line definition-line :start-column definition-column)
     :use-spans
     (mapcar (lambda (line)
               (ivory-key.source:make-source-span
                :source source :start-line line :start-column 3))
             use-lines))))

(deftest planner-preserves-eight-level-first-axis-fastest-table
  (let* ((case (ivory-key.model:make-context-axis "case" '("plain" "shifted")))
         (script (ivory-key.model:make-context-axis "script" '("roman" "greek")))
         (plane (ivory-key.model:make-context-axis "plane" '("base" "top")))
         (layout (planner-test-layout "eight" (list case script plane)))
         (placement (planner-test-placement
                     (ivory-key.model:layout-topology layout) '(("P01" . "q"))))
         (plan (planner-test-plan layout placement))
         (binding (first (ivory-key.backend::lowering-plan-bindings plan))))
    (is-equal 8 (ivory-key.backend::static-table-requirement-state-count binding))
    (is (ivory-key.backend::static-table-requirement-static-p binding))
    (is-equal
     '("case=plain;plane=base;script=roman"
       "case=shifted;plane=base;script=roman"
       "case=plain;plane=base;script=greek"
       "case=shifted;plane=base;script=greek"
       "case=plain;plane=top;script=roman"
       "case=shifted;plane=top;script=roman"
       "case=plain;plane=top;script=greek"
       "case=shifted;plane=top;script=greek")
     (mapcar (lambda (entry)
               (ivory-key.model:context-tuple-key
                (ivory-key.model:normalized-entry-tuple entry)))
             (ivory-key.backend::static-table-requirement-entries binding)))
    (is-equal :exact
              (ivory-key.backend:realization-grade (planner-result-for plan "q")))
    ;; One native-level bank preserves the pre-existing plan shape: no bank
    ;; selection or carrier requirement is introduced for <=8 entries.
    (is (null (ivory-key.backend::lowering-plan-multi-bank-partition-requirements
               plan)))
    (is (null (ivory-key.backend::lowering-plan-bank-selector-requirements plan)))
    (is (null (planner-resource-for plan :bank-selector "q")))
    (is (null (planner-resource-for plan :bank-carrier "q")))
    (is-equal '(("case" . 2) ("plane" . 2) ("script" . 2))
              (mapcar (lambda (requirement)
                        (cons (ivory-key.model:identifier-name
                               (ivory-key.backend::selector-requirement-axis requirement))
                              (length (ivory-key.backend::selector-requirement-states requirement))))
                      (ivory-key.backend::lowering-plan-selector-requirements plan)))
    ;; A table-capacity result remains exact, but each selector and its
    ;; unconsumed resource is a separate refusal.  REQUIRE-PLANNED-REALIZATIONS
    ;; must no longer accept the plan by looking only at the table result.
    (dolist (feature '("selector/case" "selector/plane" "selector/script"
                       "resource-selector/case" "resource-selector/plane"
                       "resource-selector/script"))
      (is-equal :unsupported (planner-result-grade plan feature)))
    (signals ivory-key.backend::planner-refusal
      (ivory-key.backend::require-planned-realizations plan))))

(deftest planner-manna-static-inventory-is-exact-capacity-but-not-selector-proof
  "Keep table capacity distinct from the unresolved Manna realization policy."
  (let* ((layout (ivory-key.model:decode-layout-forms
                  (ivory-key.syntax:parse-file "layouts/manna-cadet.ivory")))
         (topology (ivory-key.model:layout-topology layout))
         (mappings
           (loop for binding in (ivory-key.model:layout-bindings layout)
                 for ordinal from 1
                 collect (cons (format nil "P~2,'0D" ordinal)
                               (ivory-key.model:binding-position binding))))
         (placement (planner-test-placement topology mappings))
         (plan (planner-test-plan layout placement))
         (bindings (ivory-key.backend::lowering-plan-bindings plan)))
    ;; Fifty-two frozen symbol tables fit conventional XKB eight-level
    ;; capacity.  Four literal primary-layer bindings are direct outputs, not
    ;; selector tables; neither class allocates selectors or five modifiers.
    (is-equal 56 (length bindings))
    (let ((selector-tables
            (remove-if-not
             (lambda (binding)
               (= 8 (ivory-key.backend::static-table-requirement-state-count binding)))
             bindings)))
      (is-equal 52 (length selector-tables))
      (is (every (lambda (binding)
                   (= 8 (ivory-key.backend::static-table-requirement-state-count binding)))
                 selector-tables)))
    (is (every (lambda (binding)
                 (eq :exact
                     (ivory-key.backend:realization-grade
                      (planner-result-for
                       plan
                       (ivory-key.model:identifier-name
                        (ivory-key.backend::static-table-requirement-position binding))))))
               bindings))
    (is-equal '("case" "plane" "script")
              (mapcar (lambda (requirement)
                        (ivory-key.model:identifier-name
                         (ivory-key.backend::selector-requirement-axis requirement)))
                      (ivory-key.backend::lowering-plan-selector-requirements plan)))
    (is-equal '("alt" "control" "hyper" "meta" "super")
              (mapcar (lambda (requirement)
                        (ivory-key.model:identifier-name
                         (ivory-key.backend::modifier-requirement-modifier requirement)))
                      (ivory-key.backend::lowering-plan-modifier-requirements plan)))
    (dolist (feature '("selector/case" "selector/plane" "selector/script"
                       "semantic-modifier/alt" "semantic-modifier/control"
                       "semantic-modifier/hyper" "semantic-modifier/meta"
                       "semantic-modifier/super"))
      (is-equal :unsupported (planner-result-grade plan feature)))
    (signals ivory-key.backend::planner-refusal
      (ivory-key.backend::require-planned-realizations plan))))

(deftest planner-refuses-twenty-level-static-table-without-dropping-states
  (let* ((case (ivory-key.model:make-context-axis
                "case" '("plain" "shifted" "alternate" "titlecase")))
         (plane (ivory-key.model:make-context-axis
                 "plane" '("base" "greek" "math" "navigation" "symbols")))
         (layout (planner-test-layout "twenty" (list case plane)))
         (placement (planner-test-placement
                     (ivory-key.model:layout-topology layout) '(("P01" . "q"))))
         (plan (planner-test-plan layout placement))
         (binding (first (ivory-key.backend::lowering-plan-bindings plan)))
         (partition (planner-partition-for plan "q"))
         (bank-selector
           (first (ivory-key.backend::lowering-plan-bank-selector-requirements plan)))
         (result (planner-result-for plan "q")))
    (is-equal 20 (ivory-key.backend::static-table-requirement-state-count binding))
    (is partition)
    (is-equal 8 (ivory-key.backend::multi-bank-partition-requirement-level-capacity
                 partition))
    (is-equal 4 (ivory-key.backend::multi-bank-partition-requirement-bank-capacity
                 partition))
    (is-equal 3 (ivory-key.backend::multi-bank-partition-requirement-bank-count
                 partition))
    (is-equal '(1 2 3)
              (mapcar #'ivory-key.backend::static-table-bank-ordinal
                      (ivory-key.backend::multi-bank-partition-requirement-banks
                       partition)))
    (is-equal '(8 8 4)
              (mapcar (lambda (bank)
                        (length (ivory-key.backend::static-table-bank-entries bank)))
                      (ivory-key.backend::multi-bank-partition-requirement-banks
                       partition)))
    ;; Assignment order stays canonical.  The table order itself is still the
    ;; model's first-axis-varies-fastest order, merely cut into 8-entry banks.
    (is-equal
     (mapcar (lambda (entry)
               (ivory-key.model:context-tuple-key
                (ivory-key.model:normalized-entry-tuple entry)))
             (ivory-key.backend::static-table-requirement-entries binding))
     (mapcar (lambda (assignment)
               (ivory-key.model:context-tuple-key
                (ivory-key.backend::static-table-bank-assignment-context assignment)))
             (ivory-key.backend::multi-bank-partition-requirement-assignments
              partition)))
    (is-equal
     (loop for ordinal from 0 below 20
           collect (list (1+ (floor ordinal 8)) (1+ (mod ordinal 8))))
     (mapcar (lambda (assignment)
               (list (ivory-key.backend::static-table-bank-assignment-bank-index
                      assignment)
                     (ivory-key.backend::static-table-bank-assignment-level-index
                      assignment)))
             (ivory-key.backend::multi-bank-partition-requirement-assignments
              partition)))
    (is-equal "q"
              (ivory-key.model:identifier-name
               (ivory-key.backend::bank-selector-requirement-position bank-selector)))
    (is-equal 3
              (ivory-key.backend::bank-selector-requirement-bank-count bank-selector))
    (is-equal 3
              (ivory-key.backend::bank-selector-requirement-carrier-value-count
               bank-selector))
    (let ((selector-resource (planner-resource-for plan :bank-selector "q"))
          (carrier-resource (planner-resource-for plan :bank-carrier "q")))
      (is selector-resource)
      (is carrier-resource)
      (is-equal 1
                (ivory-key.backend::planner-resource-requirement-cardinality
                 selector-resource))
      (is-equal 3
                (ivory-key.backend::planner-resource-requirement-cardinality
                 carrier-resource)))
    (is-equal :unsupported (ivory-key.backend:realization-grade result))
    (is (search "8+8+4" (ivory-key.backend:realization-detail result)))
    (is (search "bank selector/carrier realization"
                (ivory-key.backend:realization-detail result)))
    (is (search "requires a separately proven emulation"
                (ivory-key.backend:realization-detail result)))
    (signals ivory-key.backend::planner-refusal
      (ivory-key.backend::require-planned-realizations plan))))

(deftest planner-retains-states-beyond-advertised-bank-capacity
  (let* ((first (ivory-key.model:make-context-axis
                 "first" '("one" "two" "three" "four" "five")))
         (second (ivory-key.model:make-context-axis
                  "second" '("a" "b" "c" "d" "e" "f" "g" "h")))
         (layout (planner-test-layout "forty" (list first second)))
         (placement (planner-test-placement
                     (ivory-key.model:layout-topology layout) '(("P01" . "q"))))
         (plan (planner-test-plan layout placement))
         (partition (planner-partition-for plan "q"))
         (result (planner-result-for plan "q")))
    ;; Four advertised banks do not turn five required banks into an exact
    ;; result.  Every state remains represented rather than being clipped.
    (is-equal 40
              (length (ivory-key.backend::multi-bank-partition-requirement-assignments
                       partition)))
    (is-equal '(8 8 8 8 8)
              (mapcar (lambda (bank)
                        (length (ivory-key.backend::static-table-bank-entries bank)))
                      (ivory-key.backend::multi-bank-partition-requirement-banks
                       partition)))
    (is-equal 5 (ivory-key.backend::multi-bank-partition-requirement-bank-count
                 partition))
    (is-equal :unsupported (ivory-key.backend:realization-grade result))
    (is (search "exceeding advertised bank capacity 4"
                (ivory-key.backend:realization-detail result)))
    (signals ivory-key.backend::planner-refusal
      (ivory-key.backend::require-planned-realizations plan))))

(deftest planner-keeps-explicit-none-and-inheritance-distinct-from-holes
  (let* ((case (ivory-key.model:make-context-axis "case" '("plain" "shifted")))
         (script (ivory-key.model:make-context-axis "script" '("roman" "greek")))
         (plane (ivory-key.model:make-context-axis "plane" '("base" "top")))
         (layout (planner-test-layout "holes" (list case script plane) :inherit-hole t))
         (placement (planner-test-placement
                     (ivory-key.model:layout-topology layout) '(("P01" . "q"))))
         (plan (planner-test-plan layout placement))
         (entries (ivory-key.backend::static-table-requirement-entries
                   (first (ivory-key.backend::lowering-plan-bindings plan)))))
    ;; The fourth input table row inherits value-1; the fifth is not missing:
    ;; it is the explicit no-output behavior retained by normalization.
    (is-equal "value-1"
              (ivory-key.model:output-text
               (ivory-key.model:normalized-entry-behavior (fourth entries))))
    (is (typep (ivory-key.model:normalized-entry-behavior (fifth entries))
               'ivory-key.model:no-output-behavior))
    (is-equal 8 (length entries))))

(deftest planner-keeps-semantic-modifiers-separate-from-selectors
  (let* ((case (ivory-key.model:make-context-axis "case" '("plain" "shifted")))
         (layout (planner-test-layout "modifiers" (list case)
                                      :modifiers '("meta" "hyper")))
         (placement (planner-test-placement
                     (ivory-key.model:layout-topology layout) '(("P01" . "q"))))
         (plan (planner-test-plan layout placement)))
    (is-equal '("hyper" "meta")
              (mapcar (lambda (requirement)
                        (ivory-key.model:identifier-name
                         (ivory-key.backend::modifier-requirement-modifier requirement)))
                      (ivory-key.backend::lowering-plan-modifier-requirements plan)))
    (is-equal '("case")
              (mapcar (lambda (requirement)
                        (ivory-key.model:identifier-name
                         (ivory-key.backend::selector-requirement-axis requirement)))
                      (ivory-key.backend::lowering-plan-selector-requirements plan)))
    (is-equal '(:selector :semantic-modifier :semantic-modifier)
              (mapcar #'ivory-key.backend::planner-resource-requirement-kind
                      (ivory-key.backend::lowering-plan-resource-requirements plan)))
    (dolist (feature '("selector/case" "semantic-modifier/hyper"
                       "semantic-modifier/meta" "resource-selector/case"
                       "resource-semantic-modifier/hyper"
                       "resource-semantic-modifier/meta"))
      (is-equal :unsupported (planner-result-grade plan feature)))
    (signals ivory-key.backend::planner-refusal
      (ivory-key.backend::require-planned-realizations plan))))

(deftest planner-resource-collision-is-visible-and-refused
  (let* ((case (ivory-key.model:make-context-axis "case" '("plain" "shifted")))
         (layout (planner-test-layout "resource-collision" (list case)))
         ;; P01 is a physical input and hence cannot also be allocated as the
         ;; only selector resource.
         (placement (planner-test-placement
                     (ivory-key.model:layout-topology layout) '(("P01" . "q"))))
         (pool (ivory-key.backend:make-resource-pool "selectors" '("P01")))
         (plan (planner-test-plan layout placement
                                  :resource-pools (list :selector pool)))
         (result (planner-result-for plan "resource-selector/case")))
    (is result)
    (is (search "RESOURCE SELECTOR IS UNAVAILABLE"
                (string-upcase (ivory-key.backend:realization-detail result))))
    ;; Caller-owned pools are immutable from the planner's perspective.
    (is-equal nil (ivory-key.backend:allocation-alist pool))
    (signals ivory-key.backend::planner-refusal
      (ivory-key.backend::require-planned-realizations plan))))

(deftest planner-resource-exhaustion-is-deterministic
  (let* ((one (ivory-key.model:make-context-axis "one" '("off" "on")))
         (two (ivory-key.model:make-context-axis "two" '("off" "on")))
         (three (ivory-key.model:make-context-axis "three" '("off" "on")))
         (layout (planner-test-layout "resource-exhaustion" (list one two three)))
         (placement (planner-test-placement
                     (ivory-key.model:layout-topology layout) '(("P01" . "q"))))
         (pool (ivory-key.backend:make-resource-pool "selectors" '("S1" "S2")))
         (plan (planner-test-plan layout placement
                                  :resource-pools (list :selector pool))))
    (is-equal '("S1" "S2")
              (mapcar #'ivory-key.backend::planner-allocation-value
                      (ivory-key.backend::lowering-plan-allocations plan)))
    ;; The first two sorted requirements (one, then three) are recorded but
    ;; remain explicitly unproved.  The final sorted requirement (two)
    ;; reports deterministic exhaustion.
    (dolist (feature '("selector/one" "selector/two" "selector/three"
                       "resource-selector/one" "resource-selector/two"
                       "resource-selector/three"))
      (is-equal :unsupported (planner-result-grade plan feature)))
    (is (search "RESOURCE SELECTOR IS UNAVAILABLE"
                (string-upcase
                 (ivory-key.backend:realization-detail
                  (planner-result-for plan "resource-selector/two")))))
    (signals ivory-key.backend::planner-refusal
      (ivory-key.backend::require-planned-realizations plan))))

(deftest planner-accepts-a-complete-direct-static-plan-with-no-hidden-obligations
  (let* ((layout (planner-test-layout "plain-static" nil))
         (placement (planner-test-placement
                     (ivory-key.model:layout-topology layout) '(("P01" . "q"))))
         (plan (planner-test-plan layout placement)))
    (is-equal :exact (planner-result-grade plan "q"))
    (is-equal 1 (length (ivory-key.backend::lowering-plan-realizations plan)))
    (is (ivory-key.backend::require-planned-realizations plan))))

(deftest planner-refuses-every-timed-interaction-requirement-explicitly
  (let* ((topology (planner-test-topology "a"))
         (origin (planner-test-origin :name "interaction.ivory"))
         (candidate
           (ivory-key.model::make-interaction-candidate
            "tap"
            (ivory-key.model::pattern-sequence
             (ivory-key.model::pattern-down "a")
             (ivory-key.model::pattern-up "a"))
            :when-matched
            (ivory-key.model:make-text-output "a")))
         (interaction (ivory-key.model::make-interaction "tap-a" '("a")
                                                          (list candidate)
                                                          :origin origin))
         (layout (ivory-key.model:make-layout "interaction-only" topology nil nil
                                               :interactions (list interaction)))
         (placement (planner-test-placement topology '(("P01" . "a"))))
         (plan (planner-test-plan layout placement)))
    (is-equal :unsupported (planner-result-grade plan "interaction/tap-a"))
    (is (ivory-key.source:source-origin=
         origin
         (ivory-key.backend:realization-source
          (planner-result-for plan "interaction/tap-a"))))
    (signals ivory-key.backend::planner-refusal
      (ivory-key.backend::require-planned-realizations plan))))

(deftest planner-output-is-deterministic-regardless-of-placement-input-order
  (let* ((case (ivory-key.model:make-context-axis "case" '("plain" "shifted")))
         (layout (planner-test-layout "ordering" (list case) :positions '("q" "t")))
         (topology (ivory-key.model:layout-topology layout))
         (first (planner-test-plan layout
                                   (planner-test-placement topology
                                                           '(("P02" . "t") ("P01" . "q")))))
         (second (planner-test-plan layout
                                    (planner-test-placement topology
                                                            '(("P01" . "q") ("P02" . "t"))))))
    (is-equal '("q" "t")
              (mapcar (lambda (binding)
                        (ivory-key.model:identifier-name
                         (ivory-key.backend::static-table-requirement-position binding)))
                      (ivory-key.backend::lowering-plan-bindings first)))
    (is-equal
     (mapcar (lambda (binding)
               (list (ivory-key.model:identifier-name
                      (ivory-key.backend::static-table-requirement-position binding))
                     (ivory-key.backend::static-table-requirement-physical-input binding)))
             (ivory-key.backend::lowering-plan-bindings first))
     (mapcar (lambda (binding)
               (list (ivory-key.model:identifier-name
                      (ivory-key.backend::static-table-requirement-position binding))
                     (ivory-key.backend::static-table-requirement-physical-input binding)))
             (ivory-key.backend::lowering-plan-bindings second)))))

(deftest planner-refuses-ambiguous-device-placement
  (let* ((layout (planner-test-layout "ambiguous" nil))
         (topology (ivory-key.model:layout-topology layout))
         (placement (planner-test-placement topology
                                            '(("P01" . "q") ("P02" . "q")))))
    (signals ivory-key.backend::planner-refusal
      (planner-test-plan layout placement))))

(deftest planner-retains-normalized-entry-origins-through-concrete-allocation
  (let* ((origin (planner-test-origin :use-lines '(11 17)))
         (topology (planner-test-topology "q"))
         (binding
           (ivory-key.model:make-binding
            "q"
            (ivory-key.model:make-named-key-output "escape" :origin origin)
            :origin origin))
         (layout (ivory-key.model:make-layout "origin-plan" topology nil '("meta")
                                              :bindings (list binding)
                                              :origin origin))
         (placement (planner-test-placement topology '(("P01" . "q"))))
         (plan (planner-test-plan
                layout placement
                :resource-pools
                (list :named-key
                      (ivory-key.backend:make-resource-pool "named" '("Escape")))))
         (planned-binding (first (ivory-key.backend::lowering-plan-bindings plan)))
         (requirement (planner-resource-for plan :named-key "escape"))
         (modifier-requirement (planner-resource-for plan :semantic-modifier "meta"))
         (allocation (first (ivory-key.backend::lowering-plan-allocations plan))))
    (is (ivory-key.source:source-origin=
         origin (ivory-key.backend:static-table-requirement-origin planned-binding)))
    (is-equal 1 (length (ivory-key.backend:planner-resource-requirement-origins
                         requirement)))
    (is (ivory-key.source:source-origin=
         origin
         (first (ivory-key.backend:planner-resource-requirement-origins requirement))))
    (is-equal 1 (length (ivory-key.backend:planner-resource-requirement-origins
                         modifier-requirement)))
    (is (ivory-key.source:source-origin=
         origin
         (first (ivory-key.backend:planner-resource-requirement-origins
                 modifier-requirement))))
    (is-equal 1 (length (ivory-key.backend:planner-allocation-origins allocation)))
    (is (ivory-key.source:source-origin=
         origin (first (ivory-key.backend:planner-allocation-origins allocation))))))
