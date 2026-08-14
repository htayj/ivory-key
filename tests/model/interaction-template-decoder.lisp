;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Closed source interaction-template declarations and instantiation.

(in-package #:ivory-key.tests)

(defun interaction-template-decoder-layout (source)
  (ivory-key.model:decode-layout-forms (ivory-key.syntax:parse-string source)))

(defun interaction-template-decoder-signals-code (code thunk)
  (handler-case
      (progn
        (funcall thunk)
        (error "Expected semantic error ~S, but none was signaled." code))
    (ivory-key.model:semantic-error (condition)
      (is-equal code (ivory-key.model:semantic-error-code condition)))))

(defparameter +interaction-template-decoder-layout+
  "(ivory-key 1)
(define-layout source-interaction-templates
  (binding a (unicode \"a\"))
  ;; The wrapper intentionally precedes its target, proving source definitions
  ;; may forward-reference a known declaration without reader evaluation.
  (define-interaction-template tap-wrapper (position)
    (instantiate-interaction tap-core (:position position)))
  (define-interaction-template tap-core (position)
    (interaction tap-core-result
      (:participants position)
      (:anchor position)
      (:match (sequence (down position) (up position)))
      (:commit (up position))
      (:do (unicode \"x\"))))
  ;; Only this top-level call materializes an interaction identity.  The
  ;; wrapper's nested call delegates without a second instance name.
  (instantiate-interaction source-tap tap-wrapper (:position a)))")

;;; Modern no-delay release-trigger profile ---------------------------------

(defparameter +manna-release-trigger-v1-inventory+
  ;; This independently reviewable 14+2 table is transcribed from the frozen
  ;; primary aliases in docs/manna-cadet-evidence-audit.md.  It deliberately
  ;; names only target-neutral output identities, never Kanata action tokens.
  '(("tap-hold-case-f" "Sf" "f" "f" 200 :axis "case" "shifted")
    ("tap-hold-case-j" "Sj" "j" "j" 200 :axis "case" "shifted")
    ("tap-hold-control-d" "Cd" "d" "d" 200 :modifier "control")
    ("tap-hold-control-k" "Ck" "k" "k" 200 :modifier "control")
    ("tap-hold-meta-s" "Ms" "s" "s" 200 :modifier "meta")
    ("tap-hold-meta-l" "Ml" "l" "l" 200 :modifier "meta")
    ("tap-hold-super-a" "sa" "a" "a" 250 :modifier "super")
    ("tap-hold-super-semicolon" "s;" "semicolon" "semicolon" 200 :modifier "super")
    ("tap-hold-hyper-escape" "eoam" "escape" "escape" 200 :modifier "hyper")
    ("tap-hold-hyper-apostrophe" "qoam" "apostrophe" "apostrophe" 200 :modifier "hyper")
    ("tap-hold-alt-backspace" "Hro" "backspace" "backspace" 200 :modifier "alt")
    ("tap-hold-alt-space" "Hsp" "space" "space" 200 :modifier "alt")
    ("tap-hold-function-end" "HscL" "end" "end" 200 :axis "function" "active")
    ("tap-hold-function-pgdn" "HscR" "pgdn" "page-down" 200 :axis "function" "active")
    ("tap-hold-script-delete" "gdel" "delete" "delete" 200 :axis "script" "greek")
    ("tap-hold-plane-enter" "rtop" "enter" "enter" 200 :axis "plane" "top")))

(defun make-manna-release-trigger-v1-source ()
  "Render the complete, unselected 14+2 inventory as closed source forms."
  (with-output-to-string (stream)
    (format stream "(ivory-key 1)~%(define-layout modern-manna-release-trigger-v1~%")
    (format stream "  (axis case (:states plain shifted) (:resolution product))~%")
    (format stream "  (axis script (:states roman greek) (:resolution product))~%")
    (format stream "  (axis plane (:states base top) (:resolution product))~%")
    (format stream "  (axis function (:states inactive active) (:resolution patch))~%")
    (format stream "  (modifiers control meta super hyper alt)~%")
    ;; This ordinary binding exposes the no-delay foreign-input boundary in
    ;; whole-layout reference traces without making B an interaction member.
    (format stream "  (binding b (unicode ~S))~%" "b")
    (dolist (row +manna-release-trigger-v1-inventory+)
      (destructuring-bind (name alias position tap timeout kind identity &optional state) row
        (declare (ignore alias))
        (format stream "  (interaction ~A~%" name)
        (format stream "    (:participants ~A)~%    (:observe any-position)~%    (:anchor ~A)~%" position position)
        (format stream "    (:arbitration (priority hold-timeout hold-after-foreign-release tap))~%")
        (dolist (case '("hold-timeout" "hold-after-foreign-release"))
          (format stream "    (case ~A~%      (:match ~A)~%      (:commit when-matched)~%      (:do none)~%      (:effect-start on-commit)~%      (:while (~A ~A~@[ ~A~])))~%"
                  case
                  (if (string= case "hold-timeout")
                      (format nil "(deadline ~D :after (down ~A) :while-down ~A)" timeout position position)
                      (format nil "(sequence (down ~A) (capture foreign (down (other-than ~A))) (up (captured foreign)))" position position))
                  (ecase kind (:modifier "hold-modifier") (:axis "hold-axis-state"))
                  identity state))
        (format stream "    (case tap~%      (:match (and (sequence (down ~A) (up ~A)) (duration ~A :less-than ~D)))~%      (:commit when-matched)~%      (:do (named-key ~A))))~%"
                position position position timeout tap)))
    (format stream ")")))

(defparameter +manna-release-trigger-v1-source+
  (make-manna-release-trigger-v1-source))

(defun interaction-template-decoder-interaction (layout name)
  (find name (ivory-key.model:layout-interactions layout)
        :test #'ivory-key.model:identifier=
        :key #'ivory-key.model:interaction-name))

(deftest interaction-template-decoder-materializes-modern-release-trigger-v1
  "Decode/normalize the whole frozen 14+2 inventory without selecting it."
  (let ((layout (interaction-template-decoder-layout
                 +manna-release-trigger-v1-source+)))
    (ivory-key.model:validate-layout layout)
    (is-equal (mapcar #'first +manna-release-trigger-v1-inventory+)
              (mapcar (lambda (entry)
                        (ivory-key.model:identifier-name
                         (ivory-key.model:interaction-name entry)))
                      (ivory-key.model:layout-interactions layout)))
    (dolist (row +manna-release-trigger-v1-inventory+)
      (destructuring-bind (name alias position tap timeout kind identity &optional state) row
        (declare (ignore alias kind identity state))
        (let* ((interaction (interaction-template-decoder-interaction layout name))
               (candidates (ivory-key.model:interaction-candidates interaction))
               (timeout-candidate (first candidates))
               (tap-candidate (third candidates)))
          (is-equal (list position)
                    (mapcar #'ivory-key.model:identifier-name
                            (ivory-key.model:interaction-participants interaction)))
          (is-equal '(:priority ("hold-timeout" "hold-after-foreign-release" "tap"))
                    (let ((arbitration
                            (ivory-key.model:interaction-arbitration interaction)))
                      (list (first arbitration)
                            (mapcar #'ivory-key.model:identifier-name (second arbitration)))))
          (is-equal '(("hold-timeout" :on-commit)
                      ("hold-after-foreign-release" :on-commit)
                      ("tap" :on-match))
                    (mapcar (lambda (candidate)
                              (list (ivory-key.model:identifier-name
                                     (ivory-key.model:candidate-name candidate))
                                    (ivory-key.model:candidate-effect-start candidate)))
                            candidates))
          (is-equal timeout
                    (first (ivory-key.model:temporal-pattern-arguments
                            (ivory-key.model:candidate-match timeout-candidate))))
          (is-equal tap
                    (ivory-key.model:identifier-name
                     (ivory-key.model:named-key-name
                      (ivory-key.model:candidate-behavior tap-candidate)))))))
    (let ((normalized (ivory-key.model:normalize-layout layout)))
      (is-equal (sort (copy-list (mapcar #'first +manna-release-trigger-v1-inventory+))
                      #'string<)
                (mapcar (lambda (entry)
                          (ivory-key.model:identifier-name
                           (ivory-key.model:normalized-interaction-name entry)))
                        (ivory-key.model:normalized-layout-interactions normalized))))))

(deftest interaction-template-decoder-expands-forward-named-arguments
  (let* ((layout (interaction-template-decoder-layout
                  +interaction-template-decoder-layout+))
         (templates (ivory-key.model:layout-interaction-templates layout))
         (interaction (first (ivory-key.model:layout-interactions layout)))
         (candidate (first (ivory-key.model:interaction-candidates interaction)))
         (first-selector
           (first (ivory-key.model:temporal-pattern-arguments
                  (first (ivory-key.model:temporal-pattern-arguments
                          (ivory-key.model:candidate-match candidate)))))))
    ;; The decoder returns expanded interactions, so callers never need to
    ;; choose a template by source order or validate an unresolved reference.
    (is-equal '("tap-wrapper" "tap-core")
              (mapcar (lambda (template)
                        (ivory-key.model:identifier-name
                         (ivory-key.model:interaction-template-name template)))
                      templates))
    (is (typep interaction 'ivory-key.model:interaction))
    (is-equal "source-tap"
              (ivory-key.model:identifier-name
               (ivory-key.model:interaction-name interaction)))
    (is-equal '("a")
              (mapcar #'ivory-key.model:identifier-name
                      (ivory-key.model:interaction-participants interaction)))
    (is-equal "a"
              (ivory-key.model:identifier-name
               (ivory-key.model:interaction-anchor interaction)))
    (is-equal :position (ivory-key.model:position-selector-kind first-selector))
    (is-equal '("a")
              (mapcar #'ivory-key.model:identifier-name
                      (ivory-key.model:position-selector-positions first-selector)))
    (ivory-key.model:validate-layout layout)))

(deftest interaction-template-decoder-rejects-closed-argument-failures
  (dolist
      (fixture
       (list
        (cons :unknown-interaction-template
              "(ivory-key 1) (define-layout bad
                 (instantiate-interaction absent-instance absent))")
        (cons :unknown-interaction-template-argument
              "(ivory-key 1) (define-layout bad
                 (define-interaction-template tap (position)
                   (interaction tap-body
                     (:participants position)
                     (:match (down position)) (:commit (down position))
                     (:do (unicode \"x\"))))
                 (instantiate-interaction tap-instance tap (:other a)))")
        (cons :duplicate-interaction-template-argument
              "(ivory-key 1) (define-layout bad
                 (define-interaction-template tap (position)
                   (interaction tap-body
                     (:participants position)
                     (:match (down position)) (:commit (down position))
                     (:do (unicode \"x\"))))
                 (instantiate-interaction tap-instance tap (:position a) (:position b)))")
        (cons :template-arity
              "(ivory-key 1) (define-layout bad
                 (define-interaction-template tap (position)
                   (interaction tap-body
                     (:participants position)
                     (:match (down position)) (:commit (down position))
                     (:do (unicode \"x\"))))
                 (instantiate-interaction tap-instance tap))")
        (cons :duplicate-interaction-template-parameter
              "(ivory-key 1) (define-layout bad
                 (define-interaction-template tap (position position)
                   (interaction tap-body
                     (:participants position)
                     (:match (down position)) (:commit (down position))
                     (:do (unicode \"x\")))))")
        (cons :duplicate-interaction-template
              "(ivory-key 1) (define-layout bad
                 (define-interaction-template tap ()
                   (interaction one (:participants a) (:match (down a))
                     (:commit (down a)) (:do (unicode \"x\"))))
                 (define-interaction-template TAP ()
                   (interaction two (:participants b) (:match (down b))
                     (:commit (down b)) (:do (unicode \"x\")))))")
        (cons :invalid-interaction-template-body
              "(ivory-key 1) (define-layout bad
                 (define-interaction-template tap () (unknown-body x)))")
        (cons :nested-interaction-template-instance-name
              "(ivory-key 1) (define-layout bad
                 (define-interaction-template wrapper (position)
                   (instantiate-interaction forbidden-instance target
                     (:position position)))
                 (define-interaction-template target (position)
                   (interaction target-body
                     (:participants position)
                     (:match (down position)) (:commit (down position))
                     (:do (unicode \"x\"))))))")))
    (interaction-template-decoder-signals-code
     (car fixture)
     (lambda () (interaction-template-decoder-layout (cdr fixture))))))

(deftest interaction-template-decoder-rejects-cycles-and-invalid-instances
  ;; The cycle is rejected even though no top-level instantiation reaches it.
  (interaction-template-decoder-signals-code
   :recursive-interaction-template
   (lambda ()
     (interaction-template-decoder-layout
      "(ivory-key 1) (define-layout recursive
         (define-interaction-template first ()
           (instantiate-interaction second))
         (define-interaction-template second ()
           (instantiate-interaction first)))")))
  ;; A public instantiation names its concrete result, so one template can
  ;; safely expand more than once with different resolved participants.
  (let ((layout
          (interaction-template-decoder-layout
           "(ivory-key 1) (define-layout two-instances
              (define-interaction-template tap (position)
                (interaction template-body-name
                  (:participants position) (:anchor position)
                  (:match (sequence (down position) (up position)))
                  (:commit (up position)) (:do (unicode \"x\"))))
              (instantiate-interaction first-tap tap (:position a))
              (instantiate-interaction second-tap tap (:position b)))")))
    (let* ((normalized (ivory-key.model:normalize-layout layout))
           ;; This layout intentionally has no ordinary bindings: interaction
           ;; positions must not acquire an unspecified ordinary fallback.
           (result
             (ivory-key.simulate:simulate-normalized-layout-events
              normalized
              (list (ivory-key.simulate:make-timed-event 0 :down "a")
                    (ivory-key.simulate:make-timed-event 1 :up "a")
                    (ivory-key.simulate:make-timed-event 2 :down "b")
                    (ivory-key.simulate:make-timed-event 3 :up "b")))))
      (is-equal '("first-tap" "second-tap")
                (mapcar (lambda (interaction)
                          (ivory-key.model:identifier-name
                           (ivory-key.model:interaction-name interaction)))
                        (ivory-key.model:layout-interactions layout)))
      (is-equal '(("a") ("b"))
                (mapcar (lambda (interaction)
                          (mapcar #'ivory-key.model:identifier-name
                                  (ivory-key.model:interaction-participants interaction)))
                        (ivory-key.model:layout-interactions layout)))
      (is-equal '("first-tap" "second-tap")
                (mapcar (lambda (interaction)
                          (ivory-key.model:identifier-name
                           (ivory-key.model:normalized-interaction-name interaction)))
                        (ivory-key.model:normalized-layout-interactions normalized)))
      (is-equal '((:text "x") (:text "x"))
                (ivory-key.simulate:simulation-result-outputs result))
      (is-equal '("first-tap" "second-tap")
                (mapcar
                 (lambda (entry)
                   (ivory-key.simulate::sim-interaction-name
                    (ivory-key.simulate:simulation-trace-entry-interaction entry)))
                 (remove-if-not
                  (lambda (entry)
                    (eq :commit (ivory-key.simulate::simulation-trace-entry-kind entry)))
                  (ivory-key.simulate:simulation-result-trace result))))
      (ivory-key.model:validate-layout layout)))
  ;; All source interaction declarations and instances share one name space.
  ;; Duplicate public instance names are rejected before expansion.
  (interaction-template-decoder-signals-code
   :duplicate-interaction
   (lambda ()
     (interaction-template-decoder-layout
      "(ivory-key 1) (define-layout duplicate-instance
         (binding a (unicode \"a\"))
         (binding b (unicode \"b\"))
         (define-interaction-template tap (position)
           (interaction tap-result
             (:participants position) (:anchor position)
             (:match (sequence (down position) (up position)))
             (:commit (up position)) (:do (unicode \"x\"))))
         (instantiate-interaction tap-instance tap (:position a))
         (instantiate-interaction tap-instance tap (:position b)))")))
  ;; A direct interaction cannot claim an explicit template-instance name
  ;; either; it receives the same source-level duplicate diagnostic.
  (interaction-template-decoder-signals-code
   :duplicate-interaction
   (lambda ()
     (interaction-template-decoder-layout
      "(ivory-key 1) (define-layout direct-instance-collision
         (interaction shared
           (:participants a) (:match (down a)) (:commit (down a))
           (:do (unicode \"d\")))
         (define-interaction-template tap ()
           (interaction template-body
             (:participants a) (:match (down a)) (:commit (down a))
             (:do (unicode \"t\"))))
         (instantiate-interaction shared tap))")))
  ;; The old top-level spelling remains valid only as a nested delegation.  At
  ;; layout scope it has no concrete identity and gets a stable diagnostic.
  (interaction-template-decoder-signals-code
   :missing-interaction-template-instance-name
   (lambda ()
     (interaction-template-decoder-layout
      "(ivory-key 1) (define-layout legacy-instance
         (define-interaction-template tap (position)
           (interaction tap-result
             (:participants position) (:anchor position)
             (:match (down position)) (:commit (down position))
             (:do (unicode \"x\"))))
         (instantiate-interaction tap (:position a)))"))))

(deftest interaction-template-decoder-never-interns-source-identifiers
  (let ((name "interaction-template-source-must-not-intern")
        (instance-name "interaction-template-instance-must-not-intern")
        (package (find-package :ivory-key.model)))
    (is (null (find-symbol (string-upcase name) package)))
    (is (null (find-symbol (string-upcase instance-name) package)))
    (interaction-template-decoder-layout
     "(ivory-key 1) (define-layout no-intern
        (binding q (unicode \"q\"))
        (define-interaction-template interaction-template-source-must-not-intern (position)
          (interaction resolved-name
            (:participants position) (:anchor position)
            (:match (down position)) (:commit (down position))
            (:do (unicode \"x\"))))
        (instantiate-interaction interaction-template-instance-must-not-intern
          interaction-template-source-must-not-intern (:position q)))")
    (is (null (find-symbol (string-upcase name) package)))
    (is (null (find-symbol (string-upcase instance-name) package)))))

(defun origin-span-start (origin)
  (let ((span (ivory-key.source:source-origin-definition-span origin)))
    (list (ivory-key.source:source-span-start-line span)
          (ivory-key.source:source-span-start-column span))))

(defun origin-use-starts (origin)
  (mapcar (lambda (span)
            (list (ivory-key.source:source-span-start-line span)
                  (ivory-key.source:source-span-start-column span)))
          (ivory-key.source:source-origin-use-spans origin)))

(defparameter +behavior-template-origin-source+
  "(ivory-key 1)
(define-layout origin-demo
(define-behavior core () (unicode \"x\"))
(define-behavior wrapper () (core))
(binding a (wrapper)))")

(deftest interaction-template-decoder-preserves-behavior-template-origins
  (labels ((decode ()
             (ivory-key.model:decode-layout-forms
              (ivory-key.syntax:parse-string +behavior-template-origin-source+
                                              :name "logical/origin-demo.ivory"))))
    (let* ((layout (decode))
           (binding (ivory-key.model:layout-binding layout "a" :errorp t))
           (behavior (ivory-key.model:binding-behavior binding))
           (origin (ivory-key.model:behavior-origin behavior))
           (normalized (ivory-key.model:normalize-layout layout))
           (entry (first (ivory-key.model:normalized-binding-entries
                          (first (ivory-key.model:normalized-layout-bindings normalized))))))
      ;; CORE's body is the definition, while the nested reference in WRAPPER
      ;; and materializing binding use are ordered from inner to outer.
      (is-equal '(3 26) (origin-span-start origin))
      (is-equal '((4 29) (5 12)) (origin-use-starts origin))
      (is-equal '(5 1)
                (origin-span-start (ivory-key.model:binding-origin binding)))
      (is (ivory-key.source:source-origin=
           origin (ivory-key.model:normalized-entry-origin entry)))
      (is-equal '(5 1)
                (origin-span-start
                 (ivory-key.model:normalized-binding-origin
                  (first (ivory-key.model:normalized-layout-bindings normalized)))))
      ;; Origin equality is structural: separately parsed source has a fresh
      ;; SOURCE-FILE object but the same logical identity and bytes.
      (let* ((other (decode))
             (other-origin
               (ivory-key.model:behavior-origin
                (ivory-key.model:binding-behavior
                 (ivory-key.model:layout-binding other "a" :errorp t)))))
        (is (ivory-key.source:source-origin= origin other-origin))))))

(defparameter +interaction-template-origin-source+
  "(ivory-key 1)
(define-layout interaction-origin-demo
(define-interaction-template core-interaction (position)
(interaction template-body
(:participants position)
(:anchor position)
(:match (sequence (down position) (up position)))
(:commit (up position))
(:do (unicode \"i\"))))
(define-interaction-template wrapper-interaction (position)
(instantiate-interaction core-interaction (:position position)))
(instantiate-interaction materialized wrapper-interaction (:position a)))")

(deftest interaction-template-decoder-preserves-nested-interaction-origins
  (let* ((layout
           (ivory-key.model:decode-layout-forms
            (ivory-key.syntax:parse-string +interaction-template-origin-source+
                                            :name "logical/interaction-origin.ivory")))
         (interaction (first (ivory-key.model:layout-interactions layout)))
         (candidate (first (ivory-key.model:interaction-candidates interaction)))
         (origin (ivory-key.model:candidate-origin candidate))
         (normalized (ivory-key.model:normalize-layout layout))
         (normalized-interaction
           (first (ivory-key.model:normalized-layout-interactions normalized)))
         (normalized-candidate
           (first (ivory-key.model:normalized-interaction-candidates normalized-interaction))))
    ;; The candidate body is defined by INTERACTION; its path crosses the
    ;; non-materializing nested delegation then the top-level materialization.
    (is-equal '(4 1) (origin-span-start origin))
    (is-equal '((11 1) (12 1)) (origin-use-starts origin))
    (is-equal '(4 1)
              (origin-span-start (ivory-key.model:interaction-origin interaction)))
    (is-equal '((11 1) (12 1))
              (origin-use-starts (ivory-key.model:interaction-origin interaction)))
    (is (ivory-key.source:source-origin=
         origin (ivory-key.model:normalized-candidate-origin normalized-candidate)))
    (is-equal "materialized"
              (ivory-key.model:identifier-name
               (ivory-key.model:normalized-interaction-name normalized-interaction)))))

(defparameter +table-entry-origin-source+
  "(ivory-key 1)
(define-layout table-entry-origin-demo
(axis case (:states plain shifted) (:resolution product))
(define-behavior inherited-none ()
  (by-level
    ((plain) none)
    ((shifted) (inherit (plain)))))
(binding inherited (inherited-none))
(binding fallback-none
  (at (plain) none)
  (fallback none)))")

(defun normalized-entry-origin-for (layout position context)
  (let* ((normalized (ivory-key.model:normalize-layout layout))
         (binding (find position
                        (ivory-key.model:normalized-layout-bindings normalized)
                        :key (lambda (entry)
                               (ivory-key.model:identifier-name
                                (ivory-key.model:normalized-binding-position entry)))
                        :test #'string=))
         (entry
           (ivory-key.model:normalized-binding-entry-for-context
            binding
            (ivory-key.model:make-semantic-context
             (ivory-key.model:layout-axes layout) :values context))))
    (ivory-key.model:normalized-entry-origin entry)))

(deftest interaction-template-decoder-preserves-none-and-inheritance-entry-origins
  (let ((layout
          (ivory-key.model:decode-layout-forms
           (ivory-key.syntax:parse-string +table-entry-origin-source+
                                           :name "logical/table-entry-origin.ivory"))))
    ;; NONE is defined by the selected concrete AT entry, even after the
    ;; enclosing table is materialized through a behavior template.
    (let ((plain-origin
            (normalized-entry-origin-for layout "inherited" '(("case" . "plain"))))
          (shifted-origin
            (normalized-entry-origin-for layout "inherited" '(("case" . "shifted")))))
      (is-equal '(6 5) (origin-span-start plain-origin))
      (is-equal '((8 20)) (origin-use-starts plain-origin))
      ;; The inherited result retains the source NONE declaration and records
      ;; the target INHERIT entry before the outer template materialization.
      (is-equal '(6 5) (origin-span-start shifted-origin))
      (is-equal '((7 5) (8 20)) (origin-use-starts shifted-origin)))
    ;; Generated entries supplied by FALLBACK retain that concrete FALLBACK
    ;; clause instead of inheriting the enclosing binding's source span.
    (let ((origin
            (normalized-entry-origin-for layout "fallback-none"
                                         '(("case" . "shifted")))))
      (is-equal '(11 3) (origin-span-start origin))
      (is-equal nil (origin-use-starts origin)))))
