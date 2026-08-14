;;;; SPDX-License-Identifier: GPL-3.0-or-later

(in-package #:ivory-key.tests)

(defun qmk-test-entry (position physical outputs)
  (make-instance 'ivory-key.backend:key-entry
                 :position position
                 :physical-code (list :qmk physical)
                 :outputs (list :qmk outputs)))

(defun qmk-test-request (&key (name "ivory_key")
                              (keyboard "planck/rev6")
                              (layout "LAYOUT_ortho_4x12")
                              (order '("K00" "K01"))
                              entries modifiers interactions)
  (make-instance 'ivory-key.backend:lowering-request
                 :name name
                 :entries (or entries
                              (list (qmk-test-entry "a" "K00" '("KC_A"))
                                    (qmk-test-entry "b" "K01" '("KC_B"))))
                 :modifiers modifiers :interactions interactions
                 :metadata (list :qmk-keyboard keyboard :qmk-layout layout
                                 :qmk-position-order order)))

(deftest backend-qmk-emits-deterministic-configurator-json
  (let* ((backend (ivory-key.backend:make-qmk-backend))
         (plan (ivory-key.backend:lower-request backend (qmk-test-request)))
         (text (ivory-key.backend:emit-plan-to-string backend plan)))
    (is-equal '(2) (mapcar #'length (ivory-key.backend:qmk-plan-layers plan)))
    (is-equal
     (format nil
             "{~%  \"version\": 1,~%  \"notes\": \"Generated deterministically by Ivory Key.\",~%  \"documentation\": \"https://docs.qmk.fm/\",~%  \"keyboard\": \"planck/rev6\",~%  \"keymap\": \"ivory_key\",~%  \"layout\": \"LAYOUT_ortho_4x12\",~%  \"layers\": [~%    [\"KC_A\", \"KC_B\"]~%  ]~%}~%")
     text)
    (is-equal text (ivory-key.backend:emit-plan-to-string backend plan))))

(deftest backend-qmk-refuses-implicit-order-code-and-semantics
  (let ((backend (ivory-key.backend:make-qmk-backend)))
    (signals error
      (ivory-key.backend:lower-request backend (qmk-test-request :order nil)))
    (signals error
      (ivory-key.backend:lower-request
       backend
       (qmk-test-request
        :entries (list (qmk-test-entry "a" "K00" '("KC_A;INJECT"))
                       (qmk-test-entry "b" "K01" '("KC_B"))))))
    (signals error
      (ivory-key.backend:lower-request
       backend
       (qmk-test-request
        :entries (list (qmk-test-entry "a" "K00" '("KC_A" "KC_1"))
                       (qmk-test-entry "b" "K01" '("KC_B" "KC_2"))))))
    (signals error
      (ivory-key.backend:lower-request
       backend
       (qmk-test-request
        :entries
        (list (qmk-test-entry "a" "K00"
                              (loop repeat 33 collect "KC_A"))
              (qmk-test-entry "b" "K01"
                              (loop repeat 33 collect "KC_B"))))))
    (signals error
      (ivory-key.backend:emit-plan-to-string
       backend
       (ivory-key.backend:lower-request
        backend (qmk-test-request :interactions '(tap-hold)))))
    (signals error
      (ivory-key.backend:emit-plan-to-string
       backend
       (ivory-key.backend:lower-request
        backend (qmk-test-request :modifiers '(hyper)))))))

(deftest backend-qmk-validation-uses-an-argument-vector
  (let ((arguments (ivory-key.backend::qmk-validation-arguments #p"--help")))
    (is-equal '("qmk" "compile") (subseq arguments 0 2))
    (is (uiop:absolute-pathname-p (pathname (third arguments))))
    (is (not (string= "--help" (third arguments))))))

(deftest backend-qmk-and-xkb-preserve-the-same-static-base-level-order
  (let* ((qmk-backend (ivory-key.backend:make-qmk-backend))
         (qmk-request
           (qmk-test-request
            :entries (list (qmk-test-entry "a" "K00" '("KC_A"))
                           (qmk-test-entry "b" "K01" '("KC_C")))))
         (qmk-plan (ivory-key.backend:lower-request qmk-backend qmk-request))
         (xkb-levels '("KC_A"))
         (xkb-request
           (make-instance
            'ivory-key.backend:lowering-request :name "ivory_key"
            :entries
            (list (make-instance 'ivory-key.backend:key-entry
                                 :position "a" :physical-code (list :xkb "AD01")
                                 :outputs (list :xkb xkb-levels)))))
         (xkb-plan (ivory-key.backend:lower-request
                    (ivory-key.backend:make-xkb-backend) xkb-request)))
    ;; The supported QMK slice preserves the same base-level position order as
    ;; XKB. Multi-level QMK output is refused until selectors are modeled.
    (is-equal xkb-levels
              (mapcar #'first (ivory-key.backend:qmk-plan-layers qmk-plan)))
    (is (search "symbols[Group1]=[ KC_A ]"
                (ivory-key.backend:emit-plan-to-string
                 (ivory-key.backend:make-xkb-backend) xkb-plan)))))
