;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Surface overlay declarations: closed grammar and semantic patch behavior.

(in-package #:ivory-key.tests)

(defun overlay-decoder-layout (source)
  (ivory-key.model:decode-layout-forms (ivory-key.syntax:parse-string source)))

(defun overlay-decoder-signals-code (code thunk)
  (handler-case
      (progn
        (funcall thunk)
        (error "Expected semantic error ~S, but none was signaled." code))
    (ivory-key.model:semantic-error (condition)
      (is-equal code (ivory-key.model:semantic-error-code condition)))))

(defparameter +overlay-decoder-layout+
  "(ivory-key 1)
(define-layout sparse-patches
  (axis fun (:states base active) (:resolution patch))
  (axis game (:states base active) (:resolution patch))
  (binding q (unicode \"q\"))
  (binding t (unicode \"t\"))
  (overlay fun-overlay
    (:axis fun)
    (:state active)
    (:precedence 10)
    (binding q (unicode \"F\"))
    (binding t transparent))
  (overlay game-overlay
    (:axis game)
    (:state active)
    (:precedence 5)
    (binding q (unicode \"G\"))
    (binding t (unicode \"T\"))))")

(defun overlay-context (layout &rest values)
  (ivory-key.model:make-semantic-context
   (ivory-key.model:layout-axes layout) :values values))

(defun overlay-entry-text (entry)
  (ivory-key.model:output-text (ivory-key.model:normalized-entry-behavior entry)))

(deftest overlay-decoder-keeps-sparse-transparency-and-explicit-precedence
  (let* ((layout (overlay-decoder-layout +overlay-decoder-layout+))
         (resolved (ivory-key.model:resolve-layout layout))
         (normalized (ivory-key.model:normalize-layout layout))
         (overlays (ivory-key.model:layout-overlays layout))
         (patches (ivory-key.model:normalized-layout-patches normalized))
         (both-active (overlay-context layout (cons "fun" "active")
                                       (cons "game" "active")))
         (fun-active (overlay-context layout (cons "fun" "active")))
         (active-patches '("fun-overlay" "game-overlay")))
    (is-equal '("fun-overlay" "game-overlay")
              (mapcar (lambda (overlay)
                        (ivory-key.model:identifier-name
                         (ivory-key.model:overlay-patch-name overlay)))
                      overlays))
    (is-equal 2 (length (ivory-key.model:layout-overlays resolved)))
    (ivory-key.model:validate-layout layout)
    ;; Normalization establishes descending precedence deterministically.
    (is-equal '(10 5)
              (mapcar #'ivory-key.model:normalized-patch-precedence patches))
    ;; The higher-priority FUN override wins for q.
    (is-equal "F"
              (overlay-entry-text
               (ivory-key.model:normalized-layout-binding-for-context
                normalized "q" both-active :active-patches active-patches)))
    ;; FUN's explicit transparency falls through to GAME, then to base.
    (is-equal "T"
              (overlay-entry-text
               (ivory-key.model:normalized-layout-binding-for-context
                normalized "t" both-active :active-patches active-patches)))
    (is-equal "t"
              (overlay-entry-text
               (ivory-key.model:normalized-layout-binding-for-context
                normalized "t" fun-active :active-patches '("fun-overlay"))))))

(deftest overlay-decoder-rejects-malformed-duplicate-and-unknown-clauses
  (dolist
      (fixture
       (list
        (cons :missing-required-option
              "(ivory-key 1) (define-layout bad
                 (axis fun (:states base active) (:resolution patch))
                 (overlay f (:axis fun) (:state active)))")
        (cons :duplicate-option
              "(ivory-key 1) (define-layout bad
                 (axis fun (:states base active) (:resolution patch))
                 (overlay f (:axis fun) (:axis fun) (:state active) (:precedence 1)))")
        (cons :unknown-form
              "(ivory-key 1) (define-layout bad
                 (axis fun (:states base active) (:resolution patch))
                 (overlay f (:axis fun) (:state active) (:precedence 1) (:carrier nope)))")
        (cons :duplicate-overlay-binding
              "(ivory-key 1) (define-layout bad
                 (axis fun (:states base active) (:resolution patch))
                 (overlay f (:axis fun) (:state active) (:precedence 1)
                   (binding q transparent) (binding q (unicode \"q\"))))")
        (cons :duplicate-overlay
              "(ivory-key 1) (define-layout bad
                 (axis fun (:states base active) (:resolution patch))
                 (overlay f (:axis fun) (:state active) (:precedence 1))
                 (overlay f (:axis fun) (:state base) (:precedence 2)))")
        (cons :malformed-overlay-binding
              "(ivory-key 1) (define-layout bad
                 (axis fun (:states base active) (:resolution patch))
                 (overlay f (:axis fun) (:state active) (:precedence 1)
                   (binding q transparent extra)))")))
    (overlay-decoder-signals-code
     (car fixture) (lambda () (overlay-decoder-layout (cdr fixture))))))

(deftest overlay-decoder-validates-axis-state-and-abstract-behaviors
  (dolist
      (fixture
       (list
        (cons :unknown-context-axis
              "(ivory-key 1) (define-layout bad
                 (overlay f (:axis absent) (:state active) (:precedence 1)))")
        (cons :wrong-axis-resolution
              "(ivory-key 1) (define-layout bad
                 (axis case (:states plain shifted) (:resolution product))
                 (overlay f (:axis case) (:state shifted) (:precedence 1)))")
        (cons :unknown-axis-state
              "(ivory-key 1) (define-layout bad
                 (axis fun (:states base active) (:resolution patch))
                 (overlay f (:axis fun) (:state absent) (:precedence 1)))")
        (cons :invalid-overlay-precedence
              "(ivory-key 1) (define-layout bad
                 (axis fun (:states base active) (:resolution patch))
                 (overlay f (:axis fun) (:state active) (:precedence non-integer)))")
        ;; A backend spelling is not part of the abstract behavior grammar.
        (cons :unknown-behavior-form
              "(ivory-key 1) (define-layout bad
                 (axis fun (:states base active) (:resolution patch))
                 (overlay f (:axis fun) (:state active) (:precedence 1)
                   (binding q (keysym XF86AudioMute))))")))
    (overlay-decoder-signals-code
     (car fixture) (lambda () (overlay-decoder-layout (cdr fixture))))))

(deftest overlay-precedence-ambiguity-is-rejected-by-validation-and-normalization
  (let ((layout
          (overlay-decoder-layout
           "(ivory-key 1)
(define-layout ambiguous-overlays
  (axis fun (:states base active) (:resolution patch))
  (axis game (:states base active) (:resolution patch))
  (binding q (unicode \"q\"))
  (overlay fun-overlay
    (:axis fun) (:state active) (:precedence 3)
    (binding q (unicode \"F\")))
  (overlay game-overlay
    (:axis game) (:state active) (:precedence 3)
    (binding q (unicode \"G\"))))")))
    (overlay-decoder-signals-code
     :ambiguous-patch-precedence
     (lambda () (ivory-key.model:validate-layout layout)))
    (overlay-decoder-signals-code
     :ambiguous-patch-precedence
     (lambda () (ivory-key.model:normalize-layout layout)))))
