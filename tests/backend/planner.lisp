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
    (is-equal '(("case" . 2) ("plane" . 2) ("script" . 2))
              (mapcar (lambda (requirement)
                        (cons (ivory-key.model:identifier-name
                               (ivory-key.backend::selector-requirement-axis requirement))
                              (length (ivory-key.backend::selector-requirement-states requirement))))
                      (ivory-key.backend::lowering-plan-selector-requirements plan)))
    (is (ivory-key.backend::require-planned-realizations plan))))

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
         (result (planner-result-for plan "q")))
    (is-equal 20 (ivory-key.backend::static-table-requirement-state-count binding))
    (is-equal :unsupported (ivory-key.backend:realization-grade result))
    (is (search "requires a separately proven emulation"
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
                      (ivory-key.backend::lowering-plan-resource-requirements plan)))))

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
         (result (find :unsupported (ivory-key.backend::lowering-plan-realizations plan)
                       :key #'ivory-key.backend:realization-grade)))
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
    (is (= 1 (count :unsupported (ivory-key.backend::lowering-plan-realizations plan)
                    :key #'ivory-key.backend:realization-grade)))
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
