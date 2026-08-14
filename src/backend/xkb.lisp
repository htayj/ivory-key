;;;; SPDX-License-Identifier: GPL-3.0-or-later

(in-package #:ivory-key.backend)

(defclass xkb-backend (backend) ())

(defclass xkb-plan ()
  ((name :initarg :name :reader xkb-plan-name)
   (entries :initarg :entries :reader xkb-plan-entries)
   (realizations :initarg :realizations :reader xkb-plan-realizations)))

(defun make-xkb-backend ()
  (make-instance 'xkb-backend :name "xkb"))

(defmethod capabilities ((backend xkb-backend))
  (declare (ignore backend))
  (make-instance 'backend-capabilities
                 :native-level-limit 8
                 :native-group-limit 4
                 :modifier-slots '("Shift" "Lock" "Control"
                                   "Mod1" "Mod2" "Mod3" "Mod4" "Mod5")
                 :interaction-features nil
                 :output-features '(:keysym :unicode :modifier :group-selector)
                 :validation-program "xkbcli"))

(defun safe-xkb-identifier-p (value)
  (and (stringp value)
       (plusp (length value))
       (every (lambda (character)
                (let ((code (char-code character)))
                  (or (<= (char-code #\A) code (char-code #\Z))
                      (<= (char-code #\a) code (char-code #\z))
                      (<= (char-code #\0) code (char-code #\9))
                      (find character "_-"))))
              value)))

(defun safe-xkb-key-name-p (value)
  (and (stringp value)
       (<= 1 (length value) 4)
       (every (lambda (character)
                (let ((code (char-code character)))
                  (or (<= (char-code #\A) code (char-code #\Z))
                      (<= (char-code #\0) code (char-code #\9)))))
              value)))

(defun safe-xkb-keysym-p (value)
  (and (stringp value)
       (plusp (length value))
       (every (lambda (character)
                (let ((code (char-code character)))
                  (or (<= (char-code #\A) code (char-code #\Z))
                      (<= (char-code #\a) code (char-code #\z))
                      (<= (char-code #\0) code (char-code #\9))
                      (find character "_+-"))))
              value)))

(defun ensure-safe-xkb-entry (entry)
  (unless (safe-xkb-key-name-p (key-entry-code-for entry :xkb))
    (error "Unsafe XKB key name ~S." (key-entry-code-for entry :xkb)))
  (let ((outputs (key-entry-outputs-for entry :xkb)))
    (unless (and (listp outputs) outputs)
      (error "XKB entry ~S must provide at least one explicit output."
             (key-entry-position entry)))
    (dolist (output outputs)
    (unless (safe-xkb-keysym-p output)
        (error "Unsafe XKB keysym ~S." output))))
  entry)

(defun ensure-distinct-xkb-key-names (entries)
  (let ((seen (make-hash-table :test #'equal)))
    (dolist (entry entries)
      (let ((key-name (key-entry-code-for entry :xkb)))
        (when (gethash key-name seen)
          (error "Duplicate XKB key name ~S in one lowering request." key-name))
        (setf (gethash key-name seen) t)))))

(defmethod lower-request ((backend xkb-backend) (request lowering-request))
  (declare (ignore backend))
  (unless (safe-xkb-identifier-p (lowering-request-name request))
    (error "Unsafe XKB layout name ~S." (lowering-request-name request)))
  (let ((results nil))
    (ensure-distinct-xkb-key-names (lowering-request-entries request))
    (dolist (entry (lowering-request-entries request))
      (ensure-safe-xkb-entry entry)
      (let ((levels (length (key-entry-outputs-for entry :xkb))))
        (push (make-realization-result
               (key-entry-position entry)
               (if (<= levels 8) :exact :unsupported)
               :detail (if (<= levels 8)
                           "Representable in the selected conventional XKB type."
                           "More than eight levels require pipeline planning."))
              results)))
    (make-instance 'xkb-plan
                   :name (lowering-request-name request)
                   :entries (copy-list (lowering-request-entries request))
                   :realizations (nreverse results))))

(defun xkb-type-for-level-count (count)
  (cond
    ((<= count 1) "ONE_LEVEL")
    ((<= count 2) "TWO_LEVEL")
    ((<= count 4) "FOUR_LEVEL")
    ((<= count 8) "EIGHT_LEVEL")
    (t (error "No conventional XKB type allocated for ~D levels." count))))

(defmethod emit-plan ((backend xkb-backend) (plan xkb-plan) stream)
  (declare (ignore backend))
  (require-permitted-realizations (xkb-plan-realizations plan))
  (format stream "xkb_keymap {~%")
  (format stream "  xkb_keycodes { include \"evdev+aliases(qwerty)\" };~%")
  (format stream "  xkb_types { include \"complete\" };~%")
  (format stream "  xkb_compatibility { include \"complete\" };~%")
  (format stream "  xkb_symbols {~%")
  (format stream "    include \"pc+us\"~%")
  (format stream "    name[Group1] = \"~A\";~%" (xkb-plan-name plan))
  (dolist (entry (sort (copy-list (xkb-plan-entries plan))
                       #'string<
                       :key (lambda (entry) (key-entry-code-for entry :xkb))))
    (format stream "    key <~A> { type[Group1]=\"~A\", symbols[Group1]=[ ~{~A~^, ~} ] };~%"
            (key-entry-code-for entry :xkb)
            (xkb-type-for-level-count
             (length (key-entry-outputs-for entry :xkb)))
            (key-entry-outputs-for entry :xkb)))
  (format stream "  };~%")
  (format stream "  xkb_geometry { include \"pc(pc105)\" };~%")
  (format stream "};~%"))

(defmethod validate-artifact ((backend xkb-backend) pathname)
  (declare (ignore backend))
  (let ((arguments (list "xkbcli" "compile-keymap" "--keymap"
                         (namestring pathname))))
    (handler-case
        (values t
                (uiop:run-program arguments
                                  :output :string
                                  :error-output :output)
                arguments)
      (error (condition)
        (values nil (princ-to-string condition) arguments)))))
