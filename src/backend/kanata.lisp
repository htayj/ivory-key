;;;; SPDX-License-Identifier: GPL-3.0-or-later

(in-package #:ivory-key.backend)

(defclass kanata-backend (backend) ())

(defclass kanata-plan ()
  ((name :initarg :name :reader kanata-plan-name)
   (sources :initarg :sources :reader kanata-plan-sources)
   (outputs :initarg :outputs :reader kanata-plan-outputs)
   (realizations :initarg :realizations :reader kanata-plan-realizations)))

(defun make-kanata-backend ()
  (make-instance 'kanata-backend :name "kanata"))

(defmethod capabilities ((backend kanata-backend))
  (declare (ignore backend))
  (make-instance 'backend-capabilities
                 :native-level-limit nil
                 :native-group-limit nil
                 :modifier-slots nil
                 :interaction-features
                 '(:tap :hold :tap-hold :layer :multi-tap :chord)
                 :output-features '(:key :modifier :layer :carrier)
                 :validation-program "kanata"))

(defun safe-kanata-token-p (value)
  (and (stringp value)
       (plusp (length value))
       (every (lambda (character)
                ;; This emitter produces only direct atom mappings.  Alias,
                ;; comment, and action punctuation has no legitimate use
                ;; here and would expand the generated configuration grammar.
                (let ((code (char-code character)))
                  (or (<= (char-code #\A) code (char-code #\Z))
                      (<= (char-code #\a) code (char-code #\z))
                      (<= (char-code #\0) code (char-code #\9))
                      (find character "_-"))))
              value)))

(defun ensure-distinct-kanata-sources (sources)
  (let ((seen (make-hash-table :test #'equal)))
    (dolist (source sources)
      (when (gethash source seen)
        (error "Duplicate Kanata source token ~S in one lowering request." source))
      (setf (gethash source seen) t))))

(defmethod lower-request ((backend kanata-backend) (request lowering-request))
  (declare (ignore backend))
  (unless (safe-kanata-token-p (lowering-request-name request))
    (error "Unsafe Kanata layer name ~S." (lowering-request-name request)))
  (let ((mappings nil)
        (results nil))
    (dolist (entry (lowering-request-entries request))
      (let* ((source (string-downcase (key-entry-code-for entry :kanata)))
             (entry-outputs (key-entry-outputs-for entry :kanata)))
        (unless (and (listp entry-outputs)
                     (= (length entry-outputs) 1))
          (error "Kanata entry ~S must provide exactly one explicit output."
                 (key-entry-position entry)))
        (let ((output (first entry-outputs)))
        (unless (and (safe-kanata-token-p source)
                     (safe-kanata-token-p output))
          (error "Unsafe Kanata mapping ~S -> ~S." source output))
        (push (cons source output) mappings)
        (push (make-realization-result (key-entry-position entry) :exact
                                       :detail "Direct Kanata token mapping.")
              results))))
    (ensure-distinct-kanata-sources (mapcar #'car mappings))
    (dolist (interaction (lowering-request-interactions request))
      (push (make-realization-result interaction :unsupported
                                     :detail "Generic interaction lowering requires an explicit Kanata template.")
            results))
    (let ((ordered-mappings (sort mappings #'string< :key #'car)))
      (make-instance 'kanata-plan
                     :name (lowering-request-name request)
                     :sources (mapcar #'car ordered-mappings)
                     :outputs (mapcar #'cdr ordered-mappings)
                     :realizations (nreverse results)))))

(defmethod emit-plan ((backend kanata-backend) (plan kanata-plan) stream)
  (declare (ignore backend))
  (require-permitted-realizations (kanata-plan-realizations plan))
  (format stream "(defcfg~%  process-unmapped-keys yes)~%~%")
  (format stream "(defsrc~%  ~{~A~^ ~})~%~%" (kanata-plan-sources plan))
  (format stream "(deflayer ~A~%  ~{~A~^ ~})~%" (kanata-plan-name plan)
          (kanata-plan-outputs plan)))

(defmethod validate-artifact ((backend kanata-backend) pathname)
  (declare (ignore backend))
  (let ((arguments (list "kanata" "--check" "-c" (namestring pathname))))
    (handler-case
        (values t
                (uiop:run-program arguments
                                  :output :string
                                  :error-output :output)
                arguments)
      (error (condition)
        (values nil (princ-to-string condition) arguments)))))
