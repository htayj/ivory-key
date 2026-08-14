;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Adversarial checks for the direct XKB and Kanata text emitters.

(in-package #:ivory-key.tests)

(deftest backend-rejects-ambiguous-xkb-direct-mappings
  (let ((backend (ivory-key.backend:make-xkb-backend)))
    ;; An empty list would otherwise become an implicit empty symbol table.
    (signals error
      (ivory-key.backend:lower-request
       backend
       (backend-test-request
        :entries (list (backend-test-entry :xkb-outputs nil)))))
    ;; Repeating one physical key would make the generated keymap's meaning
    ;; depend on declaration order.
    (signals error
      (ivory-key.backend:lower-request
       backend
       (backend-test-request
        :entries (list (backend-test-entry :position "first" :xkb-code "AD01")
                       (backend-test-entry :position "second" :xkb-code "AD01")))))))

(deftest backend-rejects-kanata-grammar-expansion-and-collisions
  (let ((backend (ivory-key.backend:make-kanata-backend)))
    ;; These direct mappings must stay atoms; comments, aliases, and a second
    ;; output would otherwise expand or silently change the target grammar.
    (dolist (entry
             (list (backend-test-entry :kanata-code "q;comment")
                   (backend-test-entry :kanata-outputs '("@alias"))
                   (backend-test-entry :kanata-outputs '("q" "w"))))
      (signals error
        (ivory-key.backend:lower-request
         backend (backend-test-request :entries (list entry)))))
    ;; Kanata source codes are case-folded before emission, so collision
    ;; detection must use the emitted spelling rather than raw input strings.
    (signals error
      (ivory-key.backend:lower-request
       backend
       (backend-test-request
        :entries (list (backend-test-entry :position "first" :kanata-code "Q")
                       (backend-test-entry :position "second" :kanata-code "q")))))))

(deftest backend-kanata-emission-is-independent-of-entry-order
  (let* ((backend (ivory-key.backend:make-kanata-backend))
         (q-entry (backend-test-entry :position "q" :kanata-code "q"
                                      :kanata-outputs '("a")))
         (w-entry (backend-test-entry :position "w" :kanata-code "w"
                                      :kanata-outputs '("b")))
         (forward (ivory-key.backend:emit-plan-to-string
                   backend
                   (ivory-key.backend:lower-request
                    backend (backend-test-request :entries (list q-entry w-entry)))))
         (reverse (ivory-key.backend:emit-plan-to-string
                   backend
                   (ivory-key.backend:lower-request
                    backend (backend-test-request :entries (list w-entry q-entry))))))
    (is-equal forward reverse)))
