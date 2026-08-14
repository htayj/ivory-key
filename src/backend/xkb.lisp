;;;; SPDX-License-Identifier: GPL-3.0-or-later

(in-package #:ivory-key.backend)

(defclass xkb-backend (backend) ())

(defclass xkb-plan ()
  ((name :initarg :name :reader xkb-plan-name)
   (entries :initarg :entries :reader xkb-plan-entries)
   ;; A non-NIL value is a closed, evidence-backed XKB-only selector slice.
   ;; It is deliberately separate from ordinary static entries so emitting a
   ;; Group2 table cannot accidentally turn every eight-level table into a
   ;; group action.
   (selector-static-entries :initarg :selector-static-entries :initform nil
                            :reader xkb-plan-selector-static-entries)
   (realizations :initarg :realizations :reader xkb-plan-realizations)))

(defstruct (xkb-selector-static-entry
            (:constructor %make-xkb-selector-static-entry
                (entry group-one-type group-one-symbols group-two-symbols)))
  entry
  group-one-type
  group-one-symbols
  group-two-symbols)

(defparameter +xkb-selector-carrier-specifications+
  '((84 :lvl3 "LVL3" 92 "Mode_switch" :none)
    (85 :zeha "ZEHA" 93 "ISO_Level3_Shift" :mod5))
  "The sole evidence-backed Linux-to-XKB carrier map for this XKB slice.

The explicit XKB keycodes use the evdev XKB offset but are constants here: no
backend derives a carrier number from an arbitrary profile value.  In
particular, ZEHA is keycode 93, not an alias of LVL5 or LVL3.")

(defun make-xkb-backend ()
  (make-instance 'xkb-backend :name "xkb"))

(defmethod capabilities ((backend xkb-backend))
  (declare (ignore backend))
  (make-instance 'backend-capabilities
                 :input-identities '(:xkb-key-name)
                 :native-level-limit 8
                 :native-group-limit 4
                 :modifier-slots '("Shift" "Lock" "Control"
                                   "Mod1" "Mod2" "Mod3" "Mod4" "Mod5")
                 :interaction-features nil
                 :output-features '(:keysym :unicode :modifier :group-selector)
                 :carrier-channels '(:xkb-keycode-input)
                 :validation-program "xkbcli"
                 :platform-assumptions '(:xkb-keymap)))

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

(defun %selector-policy-metadata (request)
  (getf (lowering-request-metadata request) :selector-policy))

(defun %selector-policy-with-observed-group-two-p (policy)
  (and policy
       (some (lambda (selector)
               (eq (ivory-key.model:realization-selector-client-semantics selector)
                   :libxkbcommon-depressed-group-two-with-visible-level-three))
             (ivory-key.model:realization-selector-policy-selectors policy))))

(defun %require-single-selector-control (policy control client-semantics)
  (let ((matches
          (remove-if-not
           (lambda (selector)
             (and (eq (ivory-key.model:realization-selector-control selector) control)
                  (eq (ivory-key.model:realization-selector-client-semantics selector)
                      client-semantics)))
           (ivory-key.model:realization-selector-policy-selectors policy))))
    (unless (= (length matches) 1)
      (error "XKB selector realization requires exactly one ~S / ~S selector."
             control client-semantics))
    (first matches)))

(defun %carrier-matches-selector-p (carrier selector)
  (and (ivory-key.model:identifier=
        (ivory-key.model:realization-carrier-axis carrier)
        (ivory-key.model:realization-selector-axis selector))
       (ivory-key.model:identifier=
        (ivory-key.model:realization-carrier-state carrier)
        (ivory-key.model:realization-selector-state selector))))

(defun %carrier-specification (carrier)
  (let ((specification
          (find (ivory-key.model:realization-carrier-linux-code carrier)
                +xkb-selector-carrier-specifications+ :key #'first)))
    (unless (and specification
                 (eq (ivory-key.model:realization-carrier-xkb-key carrier)
                     (second specification)))
      (error "Carrier ~S is not one of the closed XKB selector carriers."
             carrier))
    specification))

(defun %require-selector-carriers (policy level-three group-two entries)
  "Validate both carrier identities and their collision-free emitted names."
  (let ((carriers (ivory-key.model:realization-selector-policy-carriers policy)))
    (unless (= (length carriers) (length +xkb-selector-carrier-specifications+))
      (error "XKB selector realization requires exactly the 84/LVL3 and 85/ZEHA carriers."))
    (let ((by-key (make-hash-table :test #'eq)))
      (dolist (carrier carriers)
        (let ((specification (%carrier-specification carrier)))
          (when (gethash (second specification) by-key)
            (error "XKB selector realization repeats carrier key ~S."
                   (second specification)))
          (setf (gethash (second specification) by-key) carrier)))
      (let ((lvl3 (gethash :lvl3 by-key))
            (zeha (gethash :zeha by-key)))
        (unless (and lvl3 zeha
                     (%carrier-matches-selector-p lvl3 group-two)
                     (%carrier-matches-selector-p zeha level-three))
          (error "XKB selector carrier owners do not match the closed selector axes/states."))
        (dolist (entry entries)
          (when (member (key-entry-code-for entry :xkb) '("LVL3" "ZEHA")
                        :test #'string=)
            (error "Ordinary XKB entry ~S collides with a selector carrier key name."
                   (key-entry-position entry))))
        (list (%carrier-specification lvl3) (%carrier-specification zeha))))))

(defun %selector-context-state (context selector)
  (unless (typep context 'ivory-key.model:context-tuple)
    (error "XKB selector static table lacks normalized context provenance."))
  (let ((state
          (ivory-key.model:context-tuple-state
           context (ivory-key.model:realization-selector-axis selector))))
    (unless state
      (error "XKB selector static table omits selector axis ~A from a context."
             (ivory-key.model:identifier-name
              (ivory-key.model:realization-selector-axis selector))))
    state))

(defun %selector-active-p (context selector)
  (ivory-key.model:identifier=
   (%selector-context-state context selector)
   (ivory-key.model:realization-selector-state selector)))

(defun %require-binary-selector-contexts (sources selectors)
  "Ensure a table has exactly the three closed two-state selector dimensions."
  (let ((selector-axes
          (mapcar #'ivory-key.model:realization-selector-axis selectors)))
    (dolist (source sources)
      (let ((context (key-entry-source-context source)))
        (unless (and (typep context 'ivory-key.model:context-tuple)
                     (= (length (ivory-key.model:context-tuple-pairs context))
                        (length selector-axes))
                     (every (lambda (axis)
                              (ivory-key.model:context-tuple-state context axis))
                            selector-axes))
          (error "XKB selector realization requires exactly its three context axes."))))
    (dolist (selector selectors)
      (let ((states
              (remove-duplicates
               (mapcar (lambda (source)
                         (%selector-context-state (key-entry-source-context source)
                                                  selector))
                       sources)
               :test #'ivory-key.model:identifier=)))
        (unless (and (= (length states) 2)
                     (member (ivory-key.model:realization-selector-state selector)
                             states :test #'ivory-key.model:identifier=))
          (error "XKB selector axis ~A does not have one active and one inactive state."
                 (ivory-key.model:identifier-name
                  (ivory-key.model:realization-selector-axis selector))))))))

(defun %selector-group-one-type (static-type)
  (ecase (ivory-key.model:realization-static-type-type static-type)
    (:four-level "FOUR_LEVEL")
    (:four-level-alphabetic "FOUR_LEVEL_ALPHABETIC")))

(defun %selector-static-entry (entry static-type shift level-three group-two)
  "Split one fully-proven eight-state table into Group1 and Group2 symbols."
  (let ((outputs (key-entry-outputs-for entry :xkb))
        (sources (key-entry-sources entry))
        (group-one (make-array 4 :initial-element nil))
        (group-two-values (make-array 2 :initial-element nil))
        (group-two-counts (make-array 2 :initial-element 0)))
    (unless (and (= (length outputs) 8) (= (length sources) 8))
      (error "XKB selector table ~S must have eight outputs with eight normalized contexts."
             (key-entry-position entry)))
    (%require-binary-selector-contexts sources (list shift level-three group-two))
    (loop for output in outputs
          for source in sources
          for context = (key-entry-source-context source)
          for shift-active = (%selector-active-p context shift)
          for level-three-active = (%selector-active-p context level-three)
          for group-two-active = (%selector-active-p context group-two)
          do (if group-two-active
                 (let ((level (if shift-active 1 0)))
                   (if (aref group-two-values level)
                       (unless (string= output (aref group-two-values level))
                         (error "XKB Group2 table ~S varies with Level3."
                                (key-entry-position entry)))
                       (setf (aref group-two-values level) output))
                   (incf (aref group-two-counts level)))
                 (let ((level (+ (if shift-active 1 0)
                                 (if level-three-active 2 0))))
                   (when (aref group-one level)
                     (error "XKB Group1 table ~S repeats level ~D."
                            (key-entry-position entry) level))
                   (setf (aref group-one level) output))))
    (unless (every #'identity (coerce group-one 'list))
      (error "XKB Group1 table ~S is incomplete." (key-entry-position entry)))
    (unless (and (every #'identity (coerce group-two-values 'list))
                 (every (lambda (count) (= count 2))
                        (coerce group-two-counts 'list)))
      (error "XKB Group2 table ~S is incomplete." (key-entry-position entry)))
    (%make-xkb-selector-static-entry
     entry (%selector-group-one-type static-type)
     (coerce group-one 'list) (coerce group-two-values 'list))))

(defun %typed-unreachable-input-coverage-p (input-coverage position)
  "Return true only for one closed UNREACHABLE coverage record for POSITION.

The selector static-type inventory is normally an all-or-nothing declaration:
each declared table must be emitted.  The sole exception is a table which the
compiler has already typed as unreachable at the input boundary.  In
particular, an absent record, a physical record, or multiple records must not
turn a missing XKB entry into an implicit omission.
"
  (unless (listp input-coverage)
    (error "XKB selector static type ~A lacks typed input coverage metadata."
           position))
  (let ((records
          (remove-if-not
           (lambda (record)
             (and (listp record)
                  (stringp (getf record :position))
                  (string= position (getf record :position))))
           input-coverage)))
    (unless (= (length records) 1)
      (error "XKB selector static type ~A requires exactly one typed input coverage record."
             position))
    (let ((record (first records)))
      (unless (and (= (length record) 4)
                   (member :position record :test #'eq)
                   (member :disposition record :test #'eq)
                   (stringp (getf record :position))
                   (eq (getf record :disposition) :unreachable))
        (error "XKB selector static type ~A is missing from emitted entries but is not typed :UNREACHABLE."
               position))
      t)))

(defun %xkb-observed-selector-static-entries (policy entries input-coverage)
  "Return deterministic emitted tables only for the evidence-named policy."
  (ivory-key.model:validate-realization-selector-policy policy)
  (unless (= (length (ivory-key.model:realization-selector-policy-selectors policy)) 3)
    (error "XKB selector realization requires exactly Shift, Level3, and Group2 selectors."))
  (let* ((shift (%require-single-selector-control policy :shift :core-shift))
         (level-three
           (%require-single-selector-control policy :level-three :consumed-level-three))
         (group-two
           (%require-single-selector-control
            policy :group-two
            :libxkbcommon-depressed-group-two-with-visible-level-three))
         (carriers (%require-selector-carriers policy level-three group-two entries))
         (static-types (ivory-key.model:realization-selector-policy-static-types policy))
         (selector-table-entries
           (remove-if-not
            (lambda (entry)
              (= (length (key-entry-outputs-for entry :xkb)) 8))
            entries))
         (result nil))
    (unless static-types
      (error "XKB selector realization requires one static type per emitted table."))
    ;; Do not permit an eight-context table to fall through to the generic
    ;; EIGHT_LEVEL emitter merely because a partial programmatic policy named
    ;; some other table.  Selector-table coverage is all-or-nothing.
    (dolist (entry selector-table-entries)
      (unless (= (length (key-entry-sources entry)) 8)
        (error "XKB selector realization lacks eight normalized contexts for table ~S."
               (key-entry-position entry)))
      (unless (find (key-entry-position entry) static-types
                    :test #'string=
                    :key (lambda (static-type)
                           (ivory-key.model:identifier-name
                            (ivory-key.model:realization-static-type-position
                             static-type))))
        (error "XKB selector realization lacks a static type for eight-context table ~S."
               (key-entry-position entry))))
    (dolist (static-type static-types)
      (let ((entry
              (find (ivory-key.model:identifier-name
                     (ivory-key.model:realization-static-type-position static-type))
                    entries :test #'string= :key #'key-entry-position)))
        (let ((position
                (ivory-key.model:identifier-name
                 (ivory-key.model:realization-static-type-position static-type))))
          (if entry
              (push (%selector-static-entry entry static-type shift level-three group-two)
                    result)
              (%typed-unreachable-input-coverage-p input-coverage position)))))
    (values (sort result #'string<
                  :key (lambda (static-entry)
                         (key-entry-code-for
                          (xkb-selector-static-entry-entry static-entry) :xkb)))
            carriers)))

(defmethod lower-request ((backend xkb-backend) (request lowering-request))
  (declare (ignore backend))
  (unless (safe-xkb-identifier-p (lowering-request-name request))
    (error "Unsafe XKB layout name ~S." (lowering-request-name request)))
  (let ((results nil)
        (selector-static-entries nil)
        (entries (append (lowering-request-entries request)
                         (getf (lowering-request-metadata request)
                               :xkb-carrier-entries))))
    (unless (every (lambda (entry) (typep entry 'key-entry)) entries)
      (error "XKB carrier entries must be KEY-ENTRY values."))
    (ensure-distinct-xkb-key-names entries)
    (dolist (entry entries)
      (ensure-safe-xkb-entry entry)
      (let ((levels (length (key-entry-outputs-for entry :xkb))))
        (push (make-realization-result
               (key-entry-position entry)
               (if (<= levels 8) :exact :unsupported)
               :detail (if (<= levels 8)
                           "Representable in the selected conventional XKB type."
                           "More than eight levels require pipeline planning."))
              results)))
    ;; A static XKB type records a level table, but it is not an abstract
    ;; semantic-modifier or timed-interaction realization.  Those mechanisms
    ;; need an explicit, profile-owned action/selection policy; accepting the
    ;; request field merely because this backend has physical modifier support
    ;; would misgrade an omitted lowering as exact.
    (dolist (modifier (lowering-request-modifiers request))
      (push (make-realization-result
             modifier :unsupported
             :detail "Semantic modifier lowering needs an explicit XKB policy.")
            results))
    (dolist (interaction (lowering-request-interactions request))
      (push (make-realization-result
             interaction :unsupported
             :detail "Timed interaction lowering needs an explicit XKB action policy.")
            results))
    ;; The evidence-named Group2 client boundary is the sole selector policy
    ;; that may become an XKB result.  The construction below checks the
    ;; complete three-axis binary table, the two non-colliding carriers, and
    ;; the observable group split before assigning :EXACT.  The older
    ;; :UNPROVED-GROUP-TWO value remains a visible refusal.
    (let ((selector-policy (%selector-policy-metadata request)))
      (when selector-policy
        (if (%selector-policy-with-observed-group-two-p selector-policy)
            (progn
              (setf selector-static-entries
                    (nth-value 0
                               (%xkb-observed-selector-static-entries
                                selector-policy entries
                                (getf (lowering-request-metadata request)
                                      :input-coverage))))
              (push (make-realization-result
                     :selector-policy :exact
                     :detail
                     "Generated XKB proves depressed Group2, consumed Group1 Level3, and visible Group2 Level3 through libxkbcommon state APIs.")
                    results))
            (push (make-realization-result
                   :selector-policy :unsupported
                   :detail "Typed selector allocation lacks proven XKB client consumption semantics.")
                  results))))
    (make-instance 'xkb-plan
                   :name (lowering-request-name request)
                   :entries (copy-list entries)
                   :selector-static-entries selector-static-entries
                   :realizations (nreverse results))))

(defun xkb-type-for-level-count (count)
  (cond
    ((<= count 1) "ONE_LEVEL")
    ((<= count 2) "TWO_LEVEL")
    ((<= count 4) "FOUR_LEVEL")
    ((<= count 8) "EIGHT_LEVEL")
    (t (error "No conventional XKB type allocated for ~D levels." count))))

(defun %selector-static-entry-for-entry (entry selector-static-entries)
  (find entry selector-static-entries
        :key #'xkb-selector-static-entry-entry :test #'eq))

(defun %emit-xkb-selector-keycodes (stream)
  "Emit the closed carrier names in Linux-code order.

The emitted constants are intentionally duplicated from no source data: the
model policy merely selects one of these two verified carrier identities.
"
  (dolist (specification +xkb-selector-carrier-specifications+)
    (format stream "    <~A> = ~D;~%"
            (third specification) (fourth specification))))

(defun %emit-xkb-selector-carrier-symbols (stream)
  (dolist (specification +xkb-selector-carrier-specifications+)
    (destructuring-bind (linux-code xkb-key key-name xkb-code keysym modifier)
        specification
      (declare (ignore linux-code xkb-key xkb-code))
      (format stream
              "    replace key <~A> { type[Group1]=\"ONE_LEVEL\", symbols[Group1]=[ ~A ] };~%"
              key-name keysym)
      (format stream "    modifier_map ~A { <~A> };~%"
              (ecase modifier
                (:none "None")
                (:mod5 "Mod5"))
              key-name))))

(defun %emit-xkb-selector-static-entry (stream static-entry)
  (let ((entry (xkb-selector-static-entry-entry static-entry)))
    (format stream "    key <~A> { type[Group1]=\"~A\", symbols[Group1]=[ ~{~A~^, ~} ], type[Group2]=\"TWO_LEVEL\", symbols[Group2]=[ ~{~A~^, ~} ] };~%"
            (key-entry-code-for entry :xkb)
            (xkb-selector-static-entry-group-one-type static-entry)
            (xkb-selector-static-entry-group-one-symbols static-entry)
            (xkb-selector-static-entry-group-two-symbols static-entry))))

(defmethod emit-plan ((backend xkb-backend) (plan xkb-plan) stream)
  (declare (ignore backend))
  (require-permitted-realizations (xkb-plan-realizations plan))
  (format stream "xkb_keymap {~%")
  (if (xkb-plan-selector-static-entries plan)
      (progn
        (format stream "  xkb_keycodes {~%    include \"evdev+aliases(qwerty)\"~%")
        (%emit-xkb-selector-keycodes stream)
        (format stream "  };~%"))
      (format stream "  xkb_keycodes { include \"evdev+aliases(qwerty)\" };~%"))
  (format stream "  xkb_types { include \"complete\" };~%")
  (format stream "  xkb_compatibility { include \"complete\" };~%")
  (format stream "  xkb_symbols {~%")
  (format stream "    include \"pc+us\"~%")
  (format stream "    name[Group1] = \"~A\";~%" (xkb-plan-name plan))
  (dolist (entry (sort (copy-list (xkb-plan-entries plan))
                       #'string<
                       :key (lambda (entry) (key-entry-code-for entry :xkb))))
    (let ((selector-static-entry
            (%selector-static-entry-for-entry
             entry (xkb-plan-selector-static-entries plan))))
      (if selector-static-entry
          (%emit-xkb-selector-static-entry stream selector-static-entry)
          (format stream "    key <~A> { type[Group1]=\"~A\", symbols[Group1]=[ ~{~A~^, ~} ] };~%"
                  (key-entry-code-for entry :xkb)
                  (xkb-type-for-level-count
                   (length (key-entry-outputs-for entry :xkb)))
                  (key-entry-outputs-for entry :xkb)))))
  (when (xkb-plan-selector-static-entries plan)
    (%emit-xkb-selector-carrier-symbols stream))
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
