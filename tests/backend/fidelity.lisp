;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Executable fake constrained backend for all fidelity-grade paths.

(in-package #:ivory-key.tests)

(defclass constrained-test-backend (ivory-key.backend:backend) ())

(defclass constrained-test-plan ()
  ((realizations :initarg :realizations :reader constrained-test-realizations)
   (allow-lossy :initarg :allow-lossy :reader constrained-test-allow-lossy)))

(defmethod ivory-key.backend:capabilities ((backend constrained-test-backend))
  (declare (ignore backend))
  (make-instance 'ivory-key.backend:backend-capabilities
                 :native-level-limit 1
                 :native-group-limit 1
                 :modifier-slots '("M0")
                 :interaction-features '(:emulated-hold)
                 :output-features '(:direct :documented-approximation)))

(defun constrained-test-grade (entry)
  (let ((marker (first (ivory-key.backend:key-entry-outputs entry))))
    (cond ((string= marker "exact") :exact)
          ((string= marker "emulated") :emulated)
          ((string= marker "lossy") :lossy)
          (t :unsupported))))

(defmethod ivory-key.backend:lower-request
    ((backend constrained-test-backend)
     (request ivory-key.backend:lowering-request))
  (declare (ignore backend))
  (make-instance
   'constrained-test-plan
   :allow-lossy (getf (ivory-key.backend:lowering-request-metadata request)
                      :allow-lossy)
   :realizations
   (mapcar
    (lambda (entry)
      (let ((grade (constrained-test-grade entry)))
        (ivory-key.backend:make-realization-result
         (ivory-key.backend:key-entry-position entry) grade
         :detail
         (ecase grade
           (:exact "Native one-level output.")
           (:emulated "Observable output preserved through a test carrier.")
           (:lossy "Explicit test profile permits dropping key-up provenance.")
           (:unsupported "No test-backend output mechanism."))
         :source (list :fixture (ivory-key.backend:key-entry-position entry)))))
    (ivory-key.backend:lowering-request-entries request))))

(defmethod ivory-key.backend:emit-plan
    ((backend constrained-test-backend) (plan constrained-test-plan) stream)
  (declare (ignore backend))
  (ivory-key.backend:require-permitted-realizations
   (constrained-test-realizations plan)
   :allow-lossy (constrained-test-allow-lossy plan))
  (format stream "constrained-test-plan~%"))

(defmethod ivory-key.backend:validate-artifact
    ((backend constrained-test-backend) pathname)
  (declare (ignore backend pathname))
  (values t "in-memory test backend" '("constrained-test-validator")))

(defun constrained-fidelity-entry (name marker)
  (make-instance 'ivory-key.backend:key-entry
                 :position name :physical-code name :outputs (list marker)))

(defun constrained-fidelity-request (entries &key allow-lossy)
  (make-instance 'ivory-key.backend:lowering-request
                 :name "fidelity"
                 :entries entries :metadata (list :allow-lossy allow-lossy)))

(deftest backend-fake-constrained-lowerer-exercises-all-fidelity-grades
  (let* ((backend (make-instance 'constrained-test-backend :name "constrained"))
         (entries (list (constrained-fidelity-entry "native" "exact")
                        (constrained-fidelity-entry "carrier" "emulated")
                        (constrained-fidelity-entry "approximation" "lossy")
                        (constrained-fidelity-entry "missing" "unsupported")))
         (plan (ivory-key.backend:lower-request
                backend (constrained-fidelity-request entries :allow-lossy t)))
         (results (constrained-test-realizations plan)))
    (is-equal '(:exact :emulated :lossy :unsupported)
              (mapcar #'ivory-key.backend:realization-grade results))
    (is-equal '((:fixture "native") (:fixture "carrier")
                (:fixture "approximation") (:fixture "missing"))
              (mapcar #'ivory-key.backend:realization-source results))
    ;; Unsupported is never permitted, even when the profile permits a named
    ;; lossy difference.
    (signals error (ivory-key.backend:emit-plan-to-string backend plan))))

(deftest backend-fake-constrained-lowerer-requires-lossy-opt-in
  (let* ((backend (make-instance 'constrained-test-backend :name "constrained"))
         (entry (constrained-fidelity-entry "approximation" "lossy"))
         (refused (ivory-key.backend:lower-request
                   backend (constrained-fidelity-request (list entry))))
         (permitted (ivory-key.backend:lower-request
                     backend
                     (constrained-fidelity-request (list entry) :allow-lossy t))))
    (signals error (ivory-key.backend:emit-plan-to-string backend refused))
    (is-equal (format nil "constrained-test-plan~%")
              (ivory-key.backend:emit-plan-to-string backend permitted))))
