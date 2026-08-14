;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Dependency-free tests for resource allocation and safe backend emission.

(in-package #:ivory-key.tests)

(defun backend-test-entry (&key (position "q")
                                (xkb-code "AD01")
                                (xkb-outputs '("q" "Q"))
                                (kanata-code "q")
                                (kanata-outputs '("q")))
  (make-instance 'ivory-key.backend:key-entry
                 :position position
                 :physical-code (list :xkb xkb-code :kanata kanata-code)
                 :outputs (list :xkb xkb-outputs :kanata kanata-outputs)))

(defun backend-test-request (&key (name "test-layout") entries interactions)
  (make-instance 'ivory-key.backend:lowering-request
                 :name name :entries entries :interactions interactions))

(defun pipeline-artifact-of-kind (result kind)
  (find kind (ivory-key.backend:pipeline-result-artifacts result)
        :key #'ivory-key.backend:pipeline-artifact-kind))

(deftest backend-resource-allocation-is-stable-and-exclusive
  (let ((pool (ivory-key.backend:make-resource-pool
               "carrier" '("C1" "C2" "C3") :reserved '("C2"))))
    (is-equal "C1" (ivory-key.backend:allocate-resource pool :first))
    (is-equal "C1" (ivory-key.backend:allocate-resource pool :first))
    (is-equal "C3" (ivory-key.backend:reserve-resource pool "C3"))
    (is-equal '((:first . "C1"))
              (ivory-key.backend:allocation-alist pool))
    (signals error
      (ivory-key.backend:reserve-resource pool "C1"))
    (signals error
      (ivory-key.backend:allocate-resource pool :second))))

(deftest backend-resource-pools-reject-duplicate-capacity
  (signals error
    (ivory-key.backend:make-resource-pool "carrier" '("C1" "C1"))))

(deftest backend-xkb-rejects-emission-injection-values
  (let ((backend (ivory-key.backend:make-xkb-backend)))
    (signals error
      (ivory-key.backend:lower-request
       backend
       (backend-test-request :name "safe\"; include \"evil")))
    (signals error
      (ivory-key.backend:lower-request
       backend
       (backend-test-request
        :entries (list (backend-test-entry :xkb-code "AD01> }; include \"evil")))))
    (signals error
      (ivory-key.backend:lower-request
       backend
       (backend-test-request
        :entries (list (backend-test-entry :xkb-outputs '("q] }; include \"evil"))))))))

(deftest backend-kanata-rejects-emission-injection-values
  (let ((backend (ivory-key.backend:make-kanata-backend)))
    ;; A layer name is emitted in DEFLAYER and must be validated just like
    ;; source and output tokens.
    (signals error
      (ivory-key.backend:lower-request
       backend
       (backend-test-request :name "safe) (deflayer injected")))
    (signals error
      (ivory-key.backend:lower-request
       backend
       (backend-test-request
        :entries (list (backend-test-entry :kanata-code "q) (deflayer injected")))))
    (signals error
      (ivory-key.backend:lower-request
       backend
       (backend-test-request
        :entries (list (backend-test-entry :kanata-outputs '("q) (deflayer injected"))))))))

(deftest backend-fidelity-refusal-requires-an-explicit-permitted-grade
  (is (ivory-key.backend:require-permitted-realizations
       (list (ivory-key.backend:make-realization-result :direct :exact))))
  (is (ivory-key.backend:require-permitted-realizations
       (list (ivory-key.backend:make-realization-result :workaround :emulated))))
  (signals error
    (ivory-key.backend:require-permitted-realizations
     (list (ivory-key.backend:make-realization-result :approximation :lossy))))
  (is (ivory-key.backend:require-permitted-realizations
       (list (ivory-key.backend:make-realization-result :approximation :lossy))
       :allow-lossy t))
  (signals error
    (ivory-key.backend:require-permitted-realizations
     (list (ivory-key.backend:make-realization-result :missing :unsupported))))
  (signals error
    (ivory-key.backend:compile-xkb-kanata-request
     (backend-test-request :interactions '(generic-tap-hold)))))

(deftest backend-pipeline-emits-deterministic-xkb-and-kanata-strings
  (let* ((result
           (ivory-key.backend:compile-xkb-kanata-request
            (backend-test-request
             :entries (list (backend-test-entry)))))
         (xkb (pipeline-artifact-of-kind result :xkb))
         (kanata (pipeline-artifact-of-kind result :kanata)))
    (is xkb)
    (is kanata)
    (is-equal
     (format nil
             "xkb_keymap {~%  xkb_keycodes { include \"evdev+aliases(qwerty)\" };~%  xkb_types { include \"complete\" };~%  xkb_compatibility { include \"complete\" };~%  xkb_symbols {~%    include \"pc+us\"~%    name[Group1] = \"test-layout\";~%    key <AD01> { type[Group1]=\"TWO_LEVEL\", symbols[Group1]=[ q, Q ] };~%  };~%  xkb_geometry { include \"pc(pc105)\" };~%};~%")
     (ivory-key.backend:pipeline-artifact-content xkb))
    (is-equal
     (format nil "(defcfg~%  process-unmapped-keys yes)~%~%(defsrc~%  q)~%~%(deflayer test-layout~%  q)~%")
     (ivory-key.backend:pipeline-artifact-content kanata))))

(deftest backend-pipeline-artifacts-cannot-escape-output-directory
  (dolist (relative-path '("../escape" "sub/../../escape" "/tmp/escape"))
    (let ((artifact (make-instance 'ivory-key.backend::pipeline-artifact
                                   :kind :xkb
                                   :relative-path relative-path
                                   :content "")))
      (signals error
        (ivory-key.backend::%artifact-output-pathname artifact #p"build/")))))

(deftest backend-xkb-preserves-eight-level-order-and-refuses-nine
  (let* ((backend (ivory-key.backend:make-xkb-backend))
         (outputs '("a" "A" "b" "B" "c" "C" "d" "D"))
         (request (backend-test-request
                   :entries (list (backend-test-entry :xkb-outputs outputs))))
         (text (ivory-key.backend:emit-plan-to-string
                backend (ivory-key.backend:lower-request backend request))))
    (is (search "type[Group1]=\"EIGHT_LEVEL\"" text))
    (is (search "symbols[Group1]=[ a, A, b, B, c, C, d, D ]" text))
    (signals error
      (ivory-key.backend:emit-plan-to-string
       backend
       (ivory-key.backend:lower-request
        backend
        (backend-test-request
         :entries
         (list (backend-test-entry
                :xkb-outputs '("a" "A" "b" "B" "c" "C" "d" "D" "e")))))))))
