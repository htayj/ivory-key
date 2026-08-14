;;;; SPDX-License-Identifier: GPL-3.0-or-later

(in-package #:ivory-key.tests)

;;; The test system's package bootstrap deliberately owns imports.  Fully
;;; qualified model names keep this focused model suite loadable while that
;;; public export list evolves with the bootstrap phase.

(defun model-test-topology (&rest names)
  (ivory-key.model::make-topology
   "test-topology"
   (mapcar #'ivory-key.model::make-logical-position names)))

(defun model-product-binding (position axes)
  (let ((tuples (ivory-key.model::allowed-product-tuples axes))
        (counter 0))
    (ivory-key.model::make-binding
     position
     (ivory-key.model::make-behavior-table
      (mapcar #'ivory-key.model::axis-name axes)
      (mapcar (lambda (tuple)
                (ivory-key.model::make-behavior-entry
                 tuple (ivory-key.model::make-text-output
                        (format nil "value-~D" (incf counter)))))
              tuples)))))

(defun model-product-layout (name axes &key (position "q") modifiers)
  (ivory-key.model::make-layout
   name (model-test-topology position) axes (or modifiers '("control"))
   :bindings (list (model-product-binding position
                                          (ivory-key.model::product-axes axes)))))

(defun model-validation-codes (layout)
  "Return every static refusal code without choosing only the first signal."
  (multiple-value-bind (ignored diagnostics)
      (ivory-key.model::validate-layout layout :signal-on-error nil)
    (declare (ignore ignored))
    (mapcar #'ivory-key.model::semantic-diagnostic-code diagnostics)))

(deftest model-eight-state-product-order
  (let* ((case (ivory-key.model::make-context-axis "case" '("plain" "shifted")))
         (script (ivory-key.model::make-context-axis "script" '("roman" "greek")))
         (plane (ivory-key.model::make-context-axis "plane" '("base" "top")))
         (layout (model-product-layout "eight" (list case script plane)))
         (normalized (ivory-key.model::normalize-layout layout))
         (binding (first (ivory-key.model::normalized-layout-bindings normalized))))
    (is-equal 8 (length (ivory-key.model::normalized-binding-entries binding)))
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
               (ivory-key.model::context-tuple-key
                (ivory-key.model::normalized-entry-tuple entry)))
             (ivory-key.model::normalized-binding-entries binding)))))

(deftest model-twenty-state-product
  (let* ((case (ivory-key.model::make-context-axis
                "case" '("plain" "shifted" "alternate" "titlecase")))
         (plane (ivory-key.model::make-context-axis
                 "plane" '("base" "greek" "math" "navigation" "symbols")))
         (layout (model-product-layout "twenty" (list case plane)))
         (normalized (ivory-key.model::normalize-layout layout))
         (binding (first (ivory-key.model::normalized-layout-bindings normalized))))
    (is-equal 20 (length (ivory-key.model::normalized-binding-entries binding)))
    (is-equal "case=plain;plane=base"
              (ivory-key.model::context-tuple-key
               (ivory-key.model::normalized-entry-tuple
                (first (ivory-key.model::normalized-binding-entries binding)))))
    (is-equal "case=titlecase;plane=symbols"
              (ivory-key.model::context-tuple-key
               (ivory-key.model::normalized-entry-tuple
                (car (last (ivory-key.model::normalized-binding-entries binding))))))))

(deftest model-refuses-incomplete-and-cyclic-inheritance-tables-explicitly
  ;; The semantic-model phase must refuse a missing product coordinate rather
  ;; than inventing NONE or a backend-specific fallback.
  (let* ((case (ivory-key.model::make-context-axis "case" '("plain" "shifted")))
         (table
           (ivory-key.model::make-behavior-table
            '("case")
            (list
             (ivory-key.model::make-behavior-entry
              '(("case" . "plain"))
              (ivory-key.model::make-text-output "q")))))
         (layout
           (ivory-key.model::make-layout
            "incomplete-table" (model-test-topology "q") (list case) nil
            :bindings (list (ivory-key.model::make-binding "q" table)))))
    (is (member :incomplete-level-table (model-validation-codes layout)))
    (signals ivory-key.model::semantic-validation-error
      (ivory-key.model::validate-layout layout)))
  ;; Explicit inheritance remains finite only when its source graph is
  ;; acyclic; a pair of otherwise complete entries must refuse deterministically.
  (let* ((case (ivory-key.model::make-context-axis "case" '("plain" "shifted")))
         (plain '(("case" . "plain")))
         (shifted '(("case" . "shifted")))
         (table
           (ivory-key.model::make-behavior-table
            '("case")
            (list (ivory-key.model::make-inherit-entry plain shifted)
                  (ivory-key.model::make-inherit-entry shifted plain))))
         (layout
           (ivory-key.model::make-layout
            "inheritance-cycle" (model-test-topology "q") (list case) nil
            :bindings (list (ivory-key.model::make-binding "q" table)))))
    (is (member :inheritance-cycle (model-validation-codes layout)))
    (signals ivory-key.model::semantic-validation-error
      (ivory-key.model::validate-layout layout))))

(deftest model-semantic-modifiers-are-unbounded
  (let* ((modifiers (loop for number below 70 collect (format nil "modifier-~D" number)))
         (layout (ivory-key.model::make-layout
                  "many-modifiers" (model-test-topology "q") nil modifiers
                  :bindings (list (ivory-key.model::make-binding
                                   "q" (ivory-key.model::make-text-output "q")))))
         (set (ivory-key.model::layout-modifiers layout)))
    (multiple-value-bind (validated diagnostics)
        (ivory-key.model::validate-layout layout :signal-on-error nil)
      (is (eq validated layout))
      (is (null diagnostics)))
    (is-equal 70 (length (ivory-key.model::modifier-set-members set)))
    (is (ivory-key.model::modifier-set-contains-p "modifier-69" set))))

(deftest model-behavioral-axis-is-dependency-scoped-and-latches-consume-on-consult
  (let* ((case (ivory-key.model::make-context-axis "case" '("plain" "shifted")))
         (script (ivory-key.model::make-context-axis "script" '("roman" "greek")))
         (plane (ivory-key.model::make-context-axis "plane" '("base" "top")))
         (shift-latch (ivory-key.model::make-context-axis
                       "shift-latch" '("plain" "latch") :resolution :behavioral))
         (layout (model-product-layout "shift-latch" (list case script plane shift-latch)))
         (normalized (ivory-key.model::normalize-layout layout))
         (binding (first (ivory-key.model::normalized-layout-bindings normalized)))
         (context (ivory-key.model::context-with-latch
                   (ivory-key.model::make-semantic-context
                    (ivory-key.model::layout-axes layout))
                   "shift-latch" "latch")))
    ;; The letter table lists exactly its product axes; the unrelated
    ;; behavioral axis neither doubles its table nor enters its dependency set.
    (is-equal 8 (length (ivory-key.model::normalized-binding-entries binding)))
    (is-equal '("case" "script" "plane")
              (mapcar #'ivory-key.model::identifier-name
                      (ivory-key.model::normalized-binding-axes binding)))
    (multiple-value-bind (after-nonconsulting consumed)
        (ivory-key.model::consume-context-latches context '("script"))
      (is (null consumed))
      (is-equal 1 (length (ivory-key.model::semantic-context-latches after-nonconsulting)))
      (multiple-value-bind (after-consulting consumed-at-commit)
          (ivory-key.model::consume-context-latches after-nonconsulting '("shift-latch"))
        (is-equal 1 (length consumed-at-commit))
        (is (null (ivory-key.model::semantic-context-latches after-consulting)))))))

(defun model-simple-candidate (name &key (pattern nil) (commit :when-matched))
  (ivory-key.model::make-interaction-candidate
   name
   (or pattern
       (ivory-key.model::pattern-sequence
        (ivory-key.model::pattern-down "a")
        (ivory-key.model::pattern-up "a")))
   commit
   (ivory-key.model::make-text-output name)))

(defun model-interaction-layout (interaction)
  (ivory-key.model::make-layout
   "interaction-layout" (model-test-topology "a" "b") nil nil
   :interactions (list interaction)))

(deftest model-finite-interaction-patterns-validate
  (let* ((candidate (model-simple-candidate "tap"))
         (interaction (ivory-key.model::make-interaction
                       "tap-a" '("a") (list candidate)))
         (layout (model-interaction-layout interaction)))
    (multiple-value-bind (validated diagnostics)
        (ivory-key.model::validate-layout layout :signal-on-error nil)
      (is (eq validated layout))
      (is (null diagnostics))))
  (let* ((unbounded (ivory-key.model::pattern-repeat
                     (ivory-key.model::pattern-down "a")))
         (candidate (model-simple-candidate "bad" :pattern unbounded))
         (layout (model-interaction-layout
                  (ivory-key.model::make-interaction "bad-repeat" '("a") (list candidate)))))
    (signals ivory-key.model::semantic-validation-error
      (ivory-key.model::validate-layout layout))))

(deftest model-ambiguous-commitment-is-rejected-unless-arbitrated
  (let* ((first (model-simple-candidate "first"))
         (second (model-simple-candidate "second"))
         (ambiguous (model-interaction-layout
                     (ivory-key.model::make-interaction
                      "ambiguous" '("a") (list first second)))))
    (signals ivory-key.model::semantic-validation-error
      (ivory-key.model::validate-layout ambiguous)))
  (let* ((first (model-simple-candidate "first"))
         (second (model-simple-candidate "second"))
         (arbitrated (model-interaction-layout
                      (ivory-key.model::make-interaction
                       "arbitrated" '("a") (list first second)
                       :arbitration (ivory-key.model::priority-arbitration "first" "second")))))
    (multiple-value-bind (layout diagnostics)
        (ivory-key.model::validate-layout arbitrated :signal-on-error nil)
      (is (eq layout arbitrated))
      (is (null diagnostics)))))

(deftest model-interaction-templates-expand-finitely-and-cycles-fail
  (let* ((position (ivory-key.model::make-interaction-template-parameter "position"))
         (candidate (ivory-key.model::make-interaction-candidate
                     "tap"
                     (ivory-key.model::pattern-sequence
                      (ivory-key.model::pattern-down position)
                      (ivory-key.model::pattern-up position))
                     :when-matched
                     (ivory-key.model::make-text-output "x")))
         (template (ivory-key.model::make-interaction-template
                    "tap-template" '("position")
                    (ivory-key.model::make-interaction "template-body" (list position)
                                                       (list candidate))))
         (layout (ivory-key.model::make-layout
                  "template-layout" (model-test-topology "a") nil nil
                  :interaction-templates (list template)
                  :interactions
                  (list (ivory-key.model::make-interaction-template-reference
                         "tap-template" '("a")))))
         (normalized (ivory-key.model::normalize-layout layout))
         (interaction (first (ivory-key.model::normalized-layout-interactions normalized))))
    (is-equal '("a")
              (mapcar #'ivory-key.model::identifier-name
                      (ivory-key.model::normalized-interaction-participants interaction))))
  (let* ((first (ivory-key.model::make-interaction-template
                 "first" nil
                 (ivory-key.model::make-interaction-template-reference "second" nil)))
         (second (ivory-key.model::make-interaction-template
                  "second" nil
                  (ivory-key.model::make-interaction-template-reference "first" nil)))
         (layout (ivory-key.model::make-layout
                  "recursive-template" (model-test-topology "a") nil nil
                  :interaction-templates (list first second))))
    (signals ivory-key.model::semantic-validation-error
      (ivory-key.model::validate-layout layout))))

(deftest model-schema-decoder-reaches-normalization
  (let* ((parsed (ivory-key.syntax:parse-string
                  "(ivory-key 1)
(define-layout tiny
  (axis case (:states plain shifted) (:resolution product))
  (binding q
    (at (plain) (unicode \"q\"))
    (at (shifted) (unicode \"Q\"))))
"))
         (layout (ivory-key.model::decode-layout-forms parsed))
         (normalized (ivory-key.model::normalize-layout layout)))
    (is-equal "tiny" (ivory-key.model::identifier-name
                       (ivory-key.model::normalized-layout-name normalized)))
    (is-equal 2 (length (ivory-key.model::normalized-binding-entries
                         (first (ivory-key.model::normalized-layout-bindings normalized)))))))
