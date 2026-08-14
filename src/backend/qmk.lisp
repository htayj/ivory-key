;;;; SPDX-License-Identifier: GPL-3.0-or-later

(in-package #:ivory-key.backend)

(defclass qmk-backend (backend) ())

(defclass qmk-plan ()
  ((name :initarg :name :reader qmk-plan-name)
   (keyboard :initarg :keyboard :reader qmk-plan-keyboard)
   (layout :initarg :layout :reader qmk-plan-layout)
   (layers :initarg :layers :reader qmk-plan-layers)
   (realizations :initarg :realizations :reader qmk-plan-realizations)))

(defun make-qmk-backend ()
  (make-instance 'qmk-backend :name "qmk"))

(defmethod capabilities ((backend qmk-backend))
  (declare (ignore backend))
  ;; QMK documents a maximum of 32 keymap layers.  Individual firmware builds
  ;; may provide that capacity, but Ivory Key does not yet lower an abstract
  ;; selector into a QMK layer key.  Advertising one exact level prevents an
  ;; unreachable emitted layer from being graded as exact.
  (make-instance 'backend-capabilities
                 :input-identities '(:qmk-layout-position)
                 :native-level-limit 1
                 :native-group-limit nil
                 :modifier-slots nil
                 :interaction-features nil
                 :output-features '(:keycode)
                 :validation-program "qmk"
                 :platform-assumptions '(:qmk-configurator-json
                                         :qmk-firmware-checkout)))

(defun safe-qmk-name-p (value &key slash)
  (and (stringp value)
       (plusp (length value))
       (every (lambda (character)
                (let ((code (char-code character)))
                  (or (<= (char-code #\A) code (char-code #\Z))
                      (<= (char-code #\a) code (char-code #\z))
                      (<= (char-code #\0) code (char-code #\9))
                      (find character (if slash "_-/" "_-")))))
              value)
       (not (search ".." value))
       (or (not slash)
           (and (char/= (char value 0) #\/)
                (char/= (char value (1- (length value))) #\/)
                (not (search "//" value))))))

(defun safe-qmk-token-p (value)
  "Accept one opaque QMK identifier, not an arbitrary C expression."
  (and (stringp value)
       (plusp (length value))
       (let ((first (char-code (char value 0))))
         (or (<= (char-code #\A) first (char-code #\Z))
             (<= (char-code #\a) first (char-code #\z))
             (char= (char value 0) #\_)))
       (every (lambda (character)
                (let ((code (char-code character)))
                  (or (<= (char-code #\A) code (char-code #\Z))
                      (<= (char-code #\a) code (char-code #\z))
                      (<= (char-code #\0) code (char-code #\9))
                      (char= character #\_))))
              value)))

(defun qmk-metadata-value (request key)
  (getf (lowering-request-metadata request) key))

(defun qmk-ordered-entries (request order)
  (unless (and (listp order) order (every #'stringp order))
    (error "QMK lowering requires a non-empty :QMK-POSITION-ORDER list."))
  (unless (= (length order) (length (remove-duplicates order :test #'equal)))
    (error "QMK :QMK-POSITION-ORDER contains duplicate physical positions."))
  (let ((by-code (make-hash-table :test #'equal)))
    (dolist (entry (lowering-request-entries request))
      (let ((code (key-entry-code-for entry :qmk)))
        (unless (safe-qmk-token-p code)
          (error "Unsafe QMK physical position ~S." code))
        (when (gethash code by-code)
          (error "Duplicate QMK physical position ~S." code))
        (setf (gethash code by-code) entry)))
    (unless (= (hash-table-count by-code) (length order))
      (error "QMK position order does not cover every lowering entry exactly once."))
    (mapcar (lambda (code)
              (or (gethash code by-code)
                  (error "QMK position order names unknown physical position ~S." code)))
            order)))

(defun qmk-entry-outputs (entry)
  (let ((outputs (key-entry-outputs-for entry :qmk)))
    (unless (and (listp outputs) outputs (every #'safe-qmk-token-p outputs))
      (error "QMK entry ~S needs one or more safe keycode identifiers."
             (key-entry-position entry)))
    outputs))

(defun transpose-qmk-layers (entries)
  (let ((width (length (qmk-entry-outputs (first entries)))))
    (dolist (entry (rest entries))
      (unless (= width (length (qmk-entry-outputs entry)))
        (error "Every QMK entry must provide the same finite layer count.")))
    (loop for layer below width
          collect (mapcar (lambda (entry) (nth layer (qmk-entry-outputs entry)))
                          entries))))

(defmethod lower-request ((backend qmk-backend) (request lowering-request))
  (declare (ignore backend))
  (let* ((keyboard (qmk-metadata-value request :qmk-keyboard))
         (layout (qmk-metadata-value request :qmk-layout))
         (order (qmk-metadata-value request :qmk-position-order)))
    (unless (safe-qmk-name-p (lowering-request-name request))
      (error "Unsafe QMK keymap name ~S." (lowering-request-name request)))
    (unless (safe-qmk-name-p keyboard :slash t)
      (error "QMK lowering requires a safe :QMK-KEYBOARD name."))
    (unless (safe-qmk-token-p layout)
      (error "QMK lowering requires a safe :QMK-LAYOUT identifier."))
    (let* ((entries (qmk-ordered-entries request order))
           (layers (transpose-qmk-layers entries))
           (entry-results
             (mapcar (lambda (entry)
                       (make-realization-result
                        (key-entry-position entry) :exact
                        :detail "Direct QMK Configurator keycode table entry."))
                     entries))
           (other-results nil))
      (when (> (length layers) 1)
        (error "QMK multi-layer output needs an explicit, proven layer selector policy."))
      (dolist (modifier (lowering-request-modifiers request))
        (push (make-realization-result
               modifier :unsupported
               :detail "Semantic modifier lowering needs an explicit QMK policy.")
              other-results))
      (dolist (interaction (lowering-request-interactions request))
        (push (make-realization-result
               interaction :unsupported
               :detail "Timed interaction lowering needs an explicit QMK action policy.")
              other-results))
      (make-instance 'qmk-plan
                     :name (lowering-request-name request)
                     :keyboard keyboard :layout layout :layers layers
                     :realizations (append entry-results
                                           (nreverse other-results))))))

(defun write-qmk-json-string (value stream)
  (write-char #\" stream)
  (loop for character across value
        do (case character
             (#\" (write-string "\\\"" stream))
             (#\\ (write-string "\\\\" stream))
             (#\Newline (write-string "\\n" stream))
             (#\Return (write-string "\\r" stream))
             (#\Tab (write-string "\\t" stream))
             (otherwise
              (when (< (char-code character) 32)
                (error "Control character is not valid in QMK JSON text."))
              (write-char character stream))))
  (write-char #\" stream))

(defun write-qmk-string-array (values stream)
  (write-char #\[ stream)
  (loop for value in values
        for first = t then nil
        do (unless first (write-string ", " stream))
           (write-qmk-json-string value stream))
  (write-char #\] stream))

(defmethod emit-plan ((backend qmk-backend) (plan qmk-plan) stream)
  (declare (ignore backend))
  (require-permitted-realizations (qmk-plan-realizations plan))
  (format stream "{~%  \"version\": 1,~%  \"notes\": ")
  (write-qmk-json-string "Generated deterministically by Ivory Key." stream)
  (format stream ",~%  \"documentation\": \"https://docs.qmk.fm/\",~%  \"keyboard\": ")
  (write-qmk-json-string (qmk-plan-keyboard plan) stream)
  (format stream ",~%  \"keymap\": ")
  (write-qmk-json-string (qmk-plan-name plan) stream)
  (format stream ",~%  \"layout\": ")
  (write-qmk-json-string (qmk-plan-layout plan) stream)
  (format stream ",~%  \"layers\": [~%")
  (loop for layer in (qmk-plan-layers plan)
        for first = t then nil
        do (unless first (format stream ",~%"))
           (write-string "    " stream)
           (write-qmk-string-array layer stream))
  (format stream "~%  ]~%}~%"))

(defun qmk-validation-arguments (pathname)
  ;; An absolute positional argument cannot be parsed as a CLI option.  Avoid
  ;; relying on whether a particular QMK/Click release accepts `--` here.
  (list "qmk" "compile"
        (namestring (uiop:ensure-absolute-pathname pathname (uiop:getcwd)))))

(defmethod validate-artifact ((backend qmk-backend) pathname)
  (declare (ignore backend))
  ;; QMK documents configurator JSON as a direct input to QMK COMPILE.  This
  ;; is a real firmware build when a configured QMK checkout is available.
  (let ((arguments (qmk-validation-arguments pathname)))
    (handler-case
        (values t
                (uiop:run-program arguments :output :string :error-output :output)
                arguments)
      (error (condition)
        (values nil (princ-to-string condition) arguments)))))
