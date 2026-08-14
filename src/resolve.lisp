;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Pure name/template resolution for the abstract semantic model.

(in-package #:ivory-key.model)

(defun %resolution-error (code control &rest arguments)
  (apply #'signal-semantic-error 'semantic-resolution-error code control arguments))

(defun %environment-behavior (name environment)
  (let ((entry (lookup-identifier name environment)))
    (and entry (cdr entry))))

(defun %template-value (value environment)
  "Resolve one declarative template placeholder without evaluating source data."
  (if (typep value 'behavior-template-parameter)
      (or (%environment-behavior (behavior-parameter-name value) environment)
          (%resolution-error :unbound-template-parameter
                             "No argument was supplied for behavior parameter ~A."
                             (identifier-name (behavior-parameter-name value))))
      value))

(defun %template-identifier (value environment what)
  "Resolve VALUE as an identifier-valued template argument."
  (let ((resolved (%template-value value environment)))
    (unless (or (typep resolved 'identifier) (stringp resolved) (symbolp resolved))
      (%resolution-error :invalid-template-argument
                         "~A needs an identifier argument, got ~S." what resolved))
    (ensure-identifier resolved)))

(defun %template-string (value environment what)
  "Resolve VALUE as a string-valued template argument."
  (let ((resolved (%template-value value environment)))
    (unless (stringp resolved)
      (%resolution-error :invalid-template-argument
                         "~A needs a string argument, got ~S." what resolved))
    resolved))

(defun %copy-table-entry-with-behavior (entry behavior)
  (ecase (behavior-entry-disposition entry)
    (:behavior (make-behavior-entry (behavior-entry-tuple entry) behavior))
    (:none (make-none-entry (behavior-entry-tuple entry)))
    (:transparent (make-transparent-entry (behavior-entry-tuple entry)))
    (:inherit (make-inherit-entry (behavior-entry-tuple entry)
                                  (behavior-entry-inherit-tuple entry)))))

(defun resolve-behavior (behavior layout &key environment stack)
  "Expand finite, named behavior templates in BEHAVIOR.

The resolver never CALLs a layout-provided function.  A template body is model
data and parameters are replaced by model behavior objects.  STACK makes a
recursive template edge a stable, explicit error rather than a stack overflow."
  (labels ((resolve* (node environment stack)
             (typecase node
               (behavior-template-parameter
                (let ((value (%template-value node environment)))
                  (unless (typep value 'behavior)
                    (%resolution-error :invalid-template-argument
                                       "Behavior parameter ~A needs a behavior argument, got ~S."
                                       (identifier-name (behavior-parameter-name node)) value))
                  (resolve* value environment stack)))
               (behavior-template-reference
                (let* ((name (behavior-reference-name node))
                       (key (identifier-key name))
                       (template (layout-behavior-template layout name)))
                  (when (member key stack :test #'string=)
                    (%resolution-error :recursive-behavior-template
                                       "Behavior template cycle includes ~A."
                                       (identifier-name name)))
                  (unless template
                    (%resolution-error :unknown-behavior-template
                                       "Unknown behavior template ~A."
                                       (identifier-name name)))
                  (let ((parameters (behavior-template-parameters template))
                        (arguments (behavior-reference-arguments node)))
                    (unless (= (length parameters) (length arguments))
                      (%resolution-error :template-arity
                                         "Behavior template ~A expects ~D arguments, got ~D."
                                         (identifier-name name) (length parameters)
                                         (length arguments)))
                    (let ((bindings
                            (mapcar (lambda (parameter argument)
                                      (cons parameter
                                            (cond
                                              ;; A placeholder can stand for an
                                              ;; identifier-valued argument in a
                                              ;; nested template call; it is not
                                              ;; necessarily a complete behavior.
                                              ((typep argument 'behavior-template-parameter)
                                               (%template-value argument environment))
                                              ((typep argument 'behavior)
                                               (resolve* argument environment stack))
                                              (t (%template-value argument environment)))))
                                    parameters arguments)))
                      (resolve* (behavior-template-body template) bindings
                                (cons key stack))))))
               (text-output
                (make-text-output (%template-string (output-text node) environment
                                                    "UNICODE")))
               (named-key-output
                (make-named-key-output
                 (%template-identifier (named-key-name node) environment "NAMED-KEY")))
               (named-symbol-output
                (make-named-symbol-output
                 (%template-identifier (named-symbol-name node) environment "NAMED-SYMBOL")))
               (command-output
                (make-command-output
                 (%template-identifier (command-name node) environment "COMMAND")))
               (modifier-operation-behavior
                (make-modifier-operation
                 (modifier-operation node)
                 (%template-identifier (modifier-operation-modifier node) environment
                                       "modifier operation")))
               (axis-operation-behavior
                (make-axis-operation
                 (axis-operation node)
                 (%template-identifier (axis-operation-axis node) environment
                                       "axis operation")
                 (let ((state (axis-operation-state node)))
                   (and state (%template-identifier state environment "axis operation")))))
               (ordered-behavior
                (make-sequence-behavior
                 (mapcar (lambda (child) (resolve* child environment stack))
                         (ordered-behaviors node))))
               (simultaneous-behavior
                (make-simultaneous-behavior
                 (mapcar (lambda (child) (resolve* child environment stack))
                         (simultaneous-behaviors node))))
               (axis-choice-behavior
                (make-axis-choice-behavior
                 (%template-identifier (choice-axis node) environment "BY-AXIS")
                 (mapcar (lambda (choice)
                           (cons (%template-identifier (car choice) environment
                                                       "BY-AXIS choice")
                                 (resolve* (cdr choice) environment stack)))
                         (choice-behaviors node))))
               (behavior-table
                (make-behavior-table
                 (behavior-table-axes node)
                 (mapcar (lambda (entry)
                           (%copy-table-entry-with-behavior
                            entry
                            (let ((child (behavior-entry-behavior entry)))
                              (and child (resolve* child environment stack)))))
                         (behavior-table-entries node))
                 :allowed-tuples (behavior-table-allowed-tuples node)))
               (behavior node)
               (t (%resolution-error :invalid-behavior
                                      "Expected a behavior, got ~S." node)))))
    (resolve* behavior environment stack)))

(defun %interaction-template-value (value environment)
  "Resolve one interaction placeholder through nested template environments.

Nested template calls may forward an outer parameter as their argument.  Walk
that finite binding chain rather than leaving an outer placeholder in the
concrete interaction.  This remains declarative data substitution: it neither
reads nor evaluates source text.
"
  (labels ((resolve* (node seen)
             (if (typep node 'interaction-template-parameter)
                 (let* ((name (interaction-parameter-name node))
                        (key (identifier-key name)))
                   (when (member key seen :test #'string=)
                     (%resolution-error :recursive-interaction-template-parameter
                                        "Interaction template parameter cycle includes ~A."
                                        (identifier-name name)))
                   (let ((entry (lookup-identifier name environment)))
                     (unless entry
                       (%resolution-error :unbound-interaction-template-parameter
                                          "No argument was supplied for interaction parameter ~A."
                                          (identifier-name name)))
                     (resolve* (cdr entry) (cons key seen))))
                 node)))
    (resolve* value nil)))

(defun %resolve-position-selector (selector environment)
  (apply #'make-position-selector (position-selector-kind selector)
         (mapcar (lambda (position)
                   (%interaction-template-value position environment))
                 (position-selector-positions selector))))

(defun %resolve-temporal-pattern (pattern environment)
  (labels ((resolve-value (value)
             (cond ((typep value 'temporal-pattern) (%resolve-temporal-pattern value environment))
                   ((typep value 'position-selector) (%resolve-position-selector value environment))
                   ((typep value 'interaction-template-parameter)
                    (%interaction-template-value value environment))
                   ((consp value) (mapcar #'resolve-value value))
                   (t value))))
    (%make-temporal-pattern (temporal-pattern-kind pattern)
                            (mapcar #'resolve-value (temporal-pattern-arguments pattern))
                            (mapcar #'resolve-value (temporal-pattern-options pattern)))))

(defun resolve-interaction-candidate (candidate layout &key environment)
  "Resolve templates in a candidate's behavior and lifecycle effects."
  (labels ((resolve-effects (effects)
             (make-interaction-effects
              :entry (mapcar (lambda (behavior)
                               (resolve-behavior behavior layout :environment environment))
                             (effect-entry-behaviors effects))
              :commit (mapcar (lambda (behavior)
                                (resolve-behavior behavior layout :environment environment))
                              (effect-commit-behaviors effects))
              :while (mapcar (lambda (behavior)
                               (resolve-behavior behavior layout :environment environment))
                             (effect-while-behaviors effects))
              :exit (mapcar (lambda (behavior)
                              (resolve-behavior behavior layout :environment environment))
                            (effect-exit-behaviors effects))
              :cancel (mapcar (lambda (behavior)
                                (resolve-behavior behavior layout :environment environment))
                              (effect-cancel-behaviors effects)))))
    (make-interaction-candidate
     (candidate-name candidate)
     (%resolve-temporal-pattern (candidate-match candidate) environment)
     (let ((commit (candidate-commit candidate)))
       (if (typep commit 'temporal-pattern)
           (%resolve-temporal-pattern commit environment)
           commit))
     (resolve-behavior (candidate-behavior candidate) layout :environment environment)
     :effects (resolve-effects (candidate-effects candidate))
     :context-axes (candidate-context-axes candidate)
     :context-policy (candidate-context-policy candidate)
     :metadata (candidate-metadata candidate))))

(defun resolve-interaction (interaction layout &key environment)
  (make-interaction (interaction-name interaction)
                    (mapcar (lambda (participant)
                              (%interaction-template-value participant environment))
                            (interaction-participants interaction))
                    (mapcar (lambda (candidate)
                              (resolve-interaction-candidate candidate layout
                                                             :environment environment))
                            (interaction-candidates interaction))
                    :observe (interaction-observe interaction)
                    :anchor (let ((anchor (interaction-anchor interaction)))
                              (and anchor (%interaction-template-value anchor environment)))
                    :arbitration (interaction-arbitration interaction)
                    :metadata (interaction-metadata interaction)))

(defun resolve-interaction-form (form layout &key environment stack)
  "Expand an interaction template reference into a concrete finite interaction."
  (typecase form
    (interaction (resolve-interaction form layout :environment environment))
    (interaction-template-reference
     (let* ((name (interaction-reference-name form))
            (key (identifier-key name))
            (template (layout-interaction-template layout name)))
       (when (member key stack :test #'string=)
         (%resolution-error :recursive-interaction-template
                            "Interaction template cycle includes ~A."
                            (identifier-name name)))
       (unless template
         (%resolution-error :unknown-interaction-template
                            "Unknown interaction template ~A." (identifier-name name)))
       (let ((parameters (interaction-template-parameters template))
             (arguments (interaction-reference-arguments form)))
         (unless (= (length parameters) (length arguments))
           (%resolution-error :template-arity
                              "Interaction template ~A expects ~D arguments, got ~D."
                              (identifier-name name) (length parameters) (length arguments)))
         (let ((bindings (mapcar (lambda (parameter argument)
                                   ;; Resolve a forwarded outer parameter at
                                   ;; the call boundary, so each callee gets a
                                   ;; complete identifier argument rather than
                                   ;; a dangling lexical placeholder.
                                   (cons parameter
                                         (%interaction-template-value argument environment)))
                                 parameters arguments)))
           (resolve-interaction-form (interaction-template-body template) layout
                                     :environment (append bindings environment)
                                     :stack (cons key stack))))))
    (t (%resolution-error :invalid-interaction
                         "Expected an interaction or interaction-template reference, got ~S."
                         form))))

(defun %resolve-layout-interactions (layout)
  "Expand interactions and reject two source forms claiming one result name."
  (let ((interactions
          (mapcar (lambda (interaction)
                    (resolve-interaction-form interaction layout))
                  (layout-interactions layout))))
    ;; Template references carry no second, implicit instance name.  Letting
    ;; two expansions retain one body name would make downstream arbitration
    ;; and reporting refer to an ambiguous interaction, so fail before a
    ;; later phase can choose one by incidental source order.
    (unless (unique-identifiers-p (mapcar #'interaction-name interactions))
      (%resolution-error :ambiguous-interaction-template-expansion
                         "Interaction template expansion produced duplicate interaction names."))
    interactions))

(defun resolve-layout (layout)
  "Return a copy of LAYOUT with all named behavior-template references expanded.

Imports are resolved by the source/frontend layer.  This semantic resolver
handles the references whose target is a typed model declaration."
  (make-layout (layout-name layout) (layout-topology layout) (layout-axes layout)
               (layout-modifiers layout)
               :bindings
               (mapcar (lambda (binding)
                         (make-binding (binding-position binding)
                                       (resolve-behavior (binding-behavior binding) layout)
                                       :metadata (binding-metadata binding)))
                       (layout-bindings layout))
               :overlays
               (mapcar (lambda (overlay)
                         (make-overlay-patch
                          (overlay-patch-name overlay) (overlay-patch-axis overlay)
                          (overlay-patch-state overlay)
                          (mapcar (lambda (patch-binding)
                                    (if (eq (patch-binding-disposition patch-binding)
                                            :transparent)
                                        (make-transparent-patch-binding
                                         (patch-binding-position patch-binding))
                                        (make-patch-binding
                                         (patch-binding-position patch-binding)
                                         (resolve-behavior
                                          (patch-binding-behavior patch-binding) layout))))
                                  (overlay-patch-bindings overlay))
                          :precedence (overlay-patch-precedence overlay)))
                       (layout-overlays layout))
               :interactions (%resolve-layout-interactions layout)
               :behavior-templates (layout-behavior-templates layout)
               :interaction-templates (layout-interaction-templates layout)
               :metadata (layout-metadata layout)))

;;; Small schema decoder -----------------------------------------------------
;;;
;;; This decoder accepts the concrete syntax tree produced by ivory-key.syntax
;;; but only inspects its typed atoms; it never evaluates reader data or interns
;;; source identifiers.  It deliberately owns a closed v1 surface vocabulary:
;;; accepting a clause here means that it has an unambiguous typed-model meaning.

(defparameter +decoder-layout-clauses+
  '("uses-topology" "axis" "level-order" "modifiers" "binding"
    "overlay" "define-behavior" "define-interaction-template"
    "interaction" "instantiate-interaction")
  "The complete currently-decoded DEFINE-LAYOUT clause vocabulary.")

(defparameter +decoder-behavior-forms+
  '("unicode" "named-key" "named-symbol" "command" "sequence" "simultaneous"
    "hold-modifier" "hold-axis-state" "latch-axis-state" "lock-axis-state"
    "unlock-axis" "set-axis-state" "cycle-axis" "toggle-axis" "by-axis" "by-level"
    "on-tap")
  "Reserved behavior spellings, including the source-only ON-TAP shorthand.")

(defun %decode-value (node)
  (cond ((syntax-atom-p node) (syntax-atom-value node))
        ((syntax-list-p node) (mapcar #'%decode-value (syntax-list-children node)))
        ;; Useful for tests and embedding clients that already have a harmless
        ;; declarative datum; layout sources still always go through the lexer.
        ((or (stringp node) (integerp node)) node)
        ((symbolp node) (symbol-name node))
        ((consp node) (mapcar #'%decode-value node))
        (t (%resolution-error :invalid-schema-form "Invalid schema value ~S." node))))

(defun %form-name (form)
  (when (consp form)
    (let ((head (first form)))
      (and (stringp head) (string-downcase head)))))

(defun %named-form-p (form name)
  (and (consp form) (string= (%form-name form) name)))

(defun %require-identifier (value what)
  (unless (or (stringp value) (typep value 'identifier))
    (%resolution-error :invalid-identifier "~A must be an identifier, got ~S." what value))
  (ensure-identifier value))

(defun %require-form-arity (form minimum maximum code description)
  (unless (and (consp form) (<= minimum (length form))
               (or (null maximum) (<= (length form) maximum)))
    (%resolution-error code "Malformed ~A: ~S." description form))
  form)

(defun %require-unique-identifiers (values kind &key (code :duplicate-declaration))
  (let ((identifiers (mapcar (lambda (value) (%require-identifier value kind)) values)))
    (unless (unique-identifiers-p identifiers)
      (%resolution-error code "Duplicate ~A declaration." kind))
    identifiers))

(defun %forms-named (forms name)
  (remove-if-not (lambda (form) (%named-form-p form name)) forms))

(defun %single-form (forms name context &key required)
  (let ((matches (%forms-named forms name)))
    (when (and required (null matches))
      (%resolution-error :missing-required-option "~A requires :~A." context name))
    (when (rest matches)
      (%resolution-error :duplicate-option "~A has duplicate :~A options." context name))
    (first matches)))

(defun %assert-known-forms (forms allowed context)
  (dolist (form forms)
    (unless (and (consp form) (member (%form-name form) allowed :test #'string=))
      (%resolution-error :unknown-form "Unknown ~A form ~S." context
                         (and (consp form) (%form-name form))))))

(defun %identifier-in-p (value identifiers)
  (find (%require-identifier value "Identifier") identifiers :test #'identifier=))

(defun %template-parameter-value (value parameters what)
  (let ((identifier (%require-identifier value what)))
    (if (find identifier parameters :test #'identifier=)
        (make-behavior-template-parameter identifier)
        identifier)))

(defun %decode-axis-resolution (value)
  "Decode one closed vocabulary item without INTERNing source text."
  (cond ((and (stringp value) (string= (string-downcase value) "product")) :product)
        ((and (stringp value) (string= (string-downcase value) "behavioral")) :behavioral)
        ((and (stringp value) (string= (string-downcase value) "patch")) :patch)
        (t (%resolution-error :unknown-axis-resolution
                              "Unknown axis resolution style ~S." value))))

(defun %decode-axis (form)
  (%require-form-arity form 3 nil :malformed-axis "AXIS declaration")
  (let* ((name (%require-identifier (second form) "Axis name"))
         (options (cddr form)))
    (%assert-known-forms options '("states" "resolution" "default" "precedence" "valid-tuples")
                         "AXIS option")
    (let* ((states-form (%single-form options "states" "AXIS" :required t))
           (resolution-form (%single-form options "resolution" "AXIS" :required t))
           (default-form (%single-form options "default" "AXIS"))
           (precedence-form (%single-form options "precedence" "AXIS"))
           (tuples-form (%single-form options "valid-tuples" "AXIS"))
           (states (rest states-form)))
      (when (null states)
        (%resolution-error :axis-without-states "Axis ~A has no states." (identifier-name name)))
      (%require-unique-identifiers states "axis state" :code :duplicate-axis-state)
      (%require-form-arity resolution-form 2 2 :malformed-axis-option ":RESOLUTION option")
      (when default-form
        (%require-form-arity default-form 2 2 :malformed-axis-option ":DEFAULT option")
        (unless (find (%require-identifier (second default-form) "Axis default state")
                      (%require-unique-identifiers states "axis state") :test #'identifier=)
          (%resolution-error :unknown-axis-state
                             "Axis ~A has no default state ~A."
                             (identifier-name name) (second default-form))))
      (when precedence-form
        (%require-form-arity precedence-form 2 2 :malformed-axis-option ":PRECEDENCE option")
        (unless (integerp (second precedence-form))
          (%resolution-error :invalid-axis-precedence "Axis precedence must be an integer.")))
      (when tuples-form
        (dolist (tuple (rest tuples-form))
          (unless (and (consp tuple) (every #'stringp tuple))
            (%resolution-error :malformed-valid-tuples
                               "Each :VALID-TUPLES entry must be a state list: ~S." tuple))))
      (make-context-axis name states
                         :default-state (and default-form (second default-form))
                         :resolution (%decode-axis-resolution (second resolution-form))
                         :precedence (if precedence-form (second precedence-form) 0)
                         :valid-tuples (and tuples-form (rest tuples-form))))))

(defun %decode-tuple (states axes)
  (unless (listp states)
    (%resolution-error :malformed-context-tuple "Context tuple must be a list, got ~S." states))
  (unless (= (length states) (length axes))
    (%resolution-error :tuple-arity
                       "Context tuple ~S has ~D entries; expected ~D."
                       states (length states) (length axes)))
  (make-context-tuple
   (mapcar (lambda (axis state)
             (cons (axis-name axis) (%require-identifier state "Context state")))
           axes states)))

(defun %template-aware-instance (class initarg value parameters what constructor)
  (let ((decoded (%template-parameter-value value parameters what)))
    (if (typep decoded 'behavior-template-parameter)
        (make-instance class initarg decoded)
        (funcall constructor decoded))))

(defun %decode-template-argument (argument axes template-names parameters)
  (cond ((and (stringp argument)
              (find (%require-identifier argument "Template argument") parameters
                    :test #'identifier=))
         (make-behavior-template-parameter argument))
        ((consp argument) (%decode-behavior argument axes :template-names template-names
                                              :parameters parameters))
        ((stringp argument) argument)
        (t (%resolution-error :invalid-template-argument
                              "Template argument must be an identifier or behavior, got ~S."
                              argument))))

(defun %decode-table-value (value axes template-names parameters &key allow-transparent)
  (cond ((and (stringp value) (string= (string-downcase value) "none"))
         (values :none +no-output+))
        ((and (stringp value) (string= (string-downcase value) "transparent"))
         (if allow-transparent
             (values :transparent nil)
             (%resolution-error :transparent-base-entry
                                "TRANSPARENT is valid only for a sparse overlay patch.")))
        ((and (consp value) (string= (%form-name value) "inherit"))
         (%require-form-arity value 2 2 :malformed-inherit "INHERIT entry")
         (values :inherit (%decode-tuple (second value) axes)))
        (t (values :behavior (%decode-behavior value axes :template-names template-names
                                                :parameters parameters)))))

(defun %make-decoded-table-entry (tuple value axes template-names parameters
                                  &key allow-transparent)
  (multiple-value-bind (disposition content)
      (%decode-table-value value axes template-names parameters
                           :allow-transparent allow-transparent)
    (ecase disposition
      (:none (make-none-entry tuple))
      (:transparent (make-transparent-entry tuple))
      (:inherit (make-inherit-entry tuple content))
      (:behavior (make-behavior-entry tuple content)))))

(defun %decode-behavior (form axes &key template-names parameters)
  (cond
    ((and (stringp form) (string= (string-downcase form) "none")) +no-output+)
    ((and (stringp form)
          (find (%require-identifier form "Behavior parameter") parameters :test #'identifier=))
     (make-behavior-template-parameter form))
    ((not (consp form))
     (%resolution-error :malformed-behavior "Malformed behavior ~S." form))
    ((string= (%form-name form) "unicode")
     (%require-form-arity form 2 2 :malformed-behavior "UNICODE behavior")
     (let ((text (second form)))
       (if (and (stringp text)
                (find (%require-identifier text "UNICODE parameter") parameters
                      :test #'identifier=))
           (make-instance 'text-output :text (make-behavior-template-parameter text))
           (progn
             (unless (stringp text)
               (%resolution-error :invalid-unicode-output "UNICODE requires a string."))
             (make-text-output text)))))
    ((string= (%form-name form) "named-key")
     (%require-form-arity form 2 2 :malformed-behavior "NAMED-KEY behavior")
     (%template-aware-instance 'named-key-output :name (second form) parameters "NAMED-KEY"
                               #'make-named-key-output))
    ((string= (%form-name form) "named-symbol")
     (%require-form-arity form 2 2 :malformed-behavior "NAMED-SYMBOL behavior")
     (%template-aware-instance 'named-symbol-output :name (second form) parameters "NAMED-SYMBOL"
                               #'make-named-symbol-output))
    ((string= (%form-name form) "command")
     (%require-form-arity form 2 2 :malformed-behavior "COMMAND behavior")
     (%template-aware-instance 'command-output :name (second form) parameters "COMMAND"
                               #'make-command-output))
    ((string= (%form-name form) "sequence")
     (when (null (rest form))
       (%resolution-error :empty-behavior-composition "SEQUENCE needs at least one behavior."))
     (make-sequence-behavior
      (mapcar (lambda (child) (%decode-behavior child axes :template-names template-names
                                                     :parameters parameters))
              (rest form))))
    ((string= (%form-name form) "simultaneous")
     (when (null (rest form))
       (%resolution-error :empty-behavior-composition "SIMULTANEOUS needs at least one behavior."))
     (make-simultaneous-behavior
      (mapcar (lambda (child) (%decode-behavior child axes :template-names template-names
                                                     :parameters parameters))
              (rest form))))
    ((string= (%form-name form) "hold-modifier")
     (%require-form-arity form 2 2 :malformed-behavior "HOLD-MODIFIER behavior")
     (%template-aware-instance 'modifier-operation-behavior :modifier (second form) parameters
                               "HOLD-MODIFIER"
                               (lambda (modifier) (make-modifier-operation :press modifier))))
    ((member (%form-name form) '("hold-axis-state" "latch-axis-state" "lock-axis-state"
                                 "set-axis-state") :test #'string=)
     (%require-form-arity form 3 3 :malformed-behavior "axis-state operation")
     (let ((operation (cdr (assoc (%form-name form)
                                  '(("hold-axis-state" . :hold)
                                    ("latch-axis-state" . :latch)
                                    ("lock-axis-state" . :lock)
                                    ("set-axis-state" . :set)) :test #'string=))))
       (let ((axis (%template-parameter-value (second form) parameters "Axis operation"))
             (state (%template-parameter-value (third form) parameters "Axis operation")))
         (if (or (typep axis 'behavior-template-parameter)
                 (typep state 'behavior-template-parameter))
             (make-instance 'axis-operation-behavior :operation operation :axis axis :state state)
             (make-axis-operation operation axis state)))))
    ((member (%form-name form) '("unlock-axis" "cycle-axis" "toggle-axis") :test #'string=)
     (%require-form-arity form 2 2 :malformed-behavior "axis operation")
     (let ((operation (cdr (assoc (%form-name form)
                                  '(("unlock-axis" . :unlock)
                                    ("cycle-axis" . :cycle)
                                    ("toggle-axis" . :toggle)) :test #'string=))))
       (%template-aware-instance 'axis-operation-behavior :axis (second form) parameters
                                 "Axis operation"
                                 (lambda (axis) (make-axis-operation operation axis)))))
    ((string= (%form-name form) "by-axis")
     (%require-form-arity form 4 nil :malformed-behavior "BY-AXIS behavior")
     (let ((axis (%template-parameter-value (second form) parameters "BY-AXIS"))
           (choices
             (mapcar
              (lambda (choice)
                (%require-form-arity choice 2 2 :malformed-axis-choice "BY-AXIS choice")
                (cons (%template-parameter-value (first choice) parameters "BY-AXIS state")
                      (%decode-behavior (second choice) axes :template-names template-names
                                                      :parameters parameters)))
              (cddr form))))
       (if (or (typep axis 'behavior-template-parameter)
               (some (lambda (choice) (typep (car choice) 'behavior-template-parameter)) choices))
           (make-instance 'axis-choice-behavior :axis axis :choices choices)
           (make-axis-choice-behavior axis choices))))
    ((string= (%form-name form) "by-level")
     (when (null (rest form))
       (%resolution-error :empty-level-table "BY-LEVEL needs at least one entry."))
     (let ((seen (make-hash-table :test #'equal)))
       (make-behavior-table
        (mapcar #'axis-name axes)
        (mapcar
         (lambda (entry)
           (%require-form-arity entry 2 2 :malformed-level-entry "BY-LEVEL entry")
           (let ((tuple (%decode-tuple (first entry) axes)))
             (when (gethash (context-tuple-key tuple) seen)
               (%resolution-error :duplicate-context-entry
                                  "BY-LEVEL repeats tuple ~A." (context-tuple-key tuple)))
             (setf (gethash (context-tuple-key tuple) seen) t)
             (%make-decoded-table-entry tuple (second entry) axes template-names parameters)))
         (rest form)))))
    ((find (%require-identifier (%form-name form) "Behavior form") template-names :test #'identifier=)
     (make-behavior-template-reference
      (%form-name form)
      (mapcar (lambda (argument)
                (%decode-template-argument argument axes template-names parameters))
              (rest form))))
    ((string= (%form-name form) "on-tap")
     (%resolution-error :on-tap-outside-binding
                        "ON-TAP is a binding shorthand, not a nested behavior."))
    (t (%resolution-error :unknown-behavior-form "Unknown behavior form ~S." (%form-name form)))))

(defun %decode-binding (form product-axes template-names)
  "Return two values: a base BINDING or NIL, and any shorthand INTERACTIONS."
  (%require-form-arity form 3 nil :malformed-binding "BINDING declaration")
  (let* ((position (%require-identifier (second form) "Binding position"))
         (clauses (cddr form)))
    (when (and (= (length clauses) 1) (%named-form-p (first clauses) "on-tap"))
      (let ((shorthand (first clauses)))
        (%require-form-arity shorthand 2 2 :malformed-on-tap "ON-TAP shorthand")
        (return-from %decode-binding
          (values nil
                  (list (make-interaction
                         (format nil "on-tap-~A" (identifier-name position))
                         (list position)
                         (list (make-interaction-candidate
                                "tap"
                                (pattern-sequence (pattern-down position) (pattern-up position))
                                (pattern-up position)
                                (%decode-behavior (second shorthand) product-axes
                                                  :template-names template-names)))
                         :anchor position))))))
    (cond
      ((= (length clauses) 1)
       (values (make-binding position (%decode-behavior (first clauses) product-axes
                                                :template-names template-names)) nil))
      (t
       (%assert-known-forms clauses '("at" "fallback") "BINDING clause")
       (let* ((fallback-form (%single-form clauses "fallback" "BINDING"))
              (at-forms (%forms-named clauses "at"))
              (seen (make-hash-table :test #'equal))
              (entries
                (mapcar
                 (lambda (clause)
                   (%require-form-arity clause 3 3 :malformed-binding-entry "AT entry")
                   (let ((tuple (%decode-tuple (second clause) product-axes)))
                     (when (gethash (context-tuple-key tuple) seen)
                       (%resolution-error :duplicate-context-entry
                                          "BINDING ~A repeats tuple ~A."
                                          (identifier-name position) (context-tuple-key tuple)))
                     (setf (gethash (context-tuple-key tuple) seen) t)
                     (%make-decoded-table-entry tuple (third clause) product-axes template-names nil)))
                 at-forms)))
         (when (and (null at-forms) (null fallback-form))
           (%resolution-error :empty-binding-table "BINDING ~A has no behavior entries."
                              (identifier-name position)))
         (when fallback-form
           (%require-form-arity fallback-form 2 2 :malformed-fallback "FALLBACK clause")
           (multiple-value-bind (disposition content)
               (%decode-table-value (second fallback-form) product-axes template-names nil)
             (when (member disposition '(:inherit :transparent))
               (%resolution-error :invalid-fallback
                                  "FALLBACK must be a complete behavior or NONE, not ~A."
                                  disposition))
             (dolist (tuple (allowed-product-tuples product-axes))
               (unless (gethash (context-tuple-key tuple) seen)
                 (push (ecase disposition
                         (:none (make-none-entry tuple))
                         (:behavior (make-behavior-entry tuple content)))
                       entries)))))
         (values (make-binding position
                               (make-behavior-table (mapcar #'axis-name product-axes)
                                                    (nreverse entries)))
                 nil))))))

(defun %decode-overlay (form axes product-axes template-names)
  "Decode one closed-vocabulary sparse patch declaration.

The surface form is deliberately small:

  (overlay NAME (:axis AXIS) (:state STATE) (:precedence INTEGER)
    (binding POSITION BEHAVIOR-OR-TRANSPARENT) ...)

Unlike a base binding, each overlay binding is sparse and may explicitly be
TRANSPARENT.  It may not spell a backend key, carrier, or layer; its behavior
is decoded through the same abstract behavior vocabulary as an ordinary
binding.
"
  ;; Check the name here, then let the required-option checks identify which
  ;; semantic declaration is absent.  That produces useful stable diagnostics
  ;; for a partially written overlay rather than one generic arity failure.
  (%require-form-arity form 2 nil :malformed-overlay "OVERLAY declaration")
  (let* ((name (%require-identifier (second form) "Overlay name"))
         (clauses (cddr form)))
    (%assert-known-forms clauses '("axis" "state" "precedence" "binding")
                         "OVERLAY clause")
    (let* ((axis-form (%single-form clauses "axis" "OVERLAY" :required t))
           (state-form (%single-form clauses "state" "OVERLAY" :required t))
           (precedence-form (%single-form clauses "precedence" "OVERLAY" :required t))
           (binding-forms (%forms-named clauses "binding")))
      (%require-form-arity axis-form 2 2 :malformed-overlay-option "OVERLAY :AXIS option")
      (%require-form-arity state-form 2 2 :malformed-overlay-option "OVERLAY :STATE option")
      (%require-form-arity precedence-form 2 2 :malformed-overlay-option
                           "OVERLAY :PRECEDENCE option")
      (let* ((axis-name (%require-identifier (second axis-form) "Overlay axis"))
             (axis (find-axis axis-name axes)))
        (unless axis
          (%resolution-error :unknown-context-axis
                             "Overlay ~A uses unknown axis ~A."
                             (identifier-name name) (identifier-name axis-name)))
        (unless (eq (axis-resolution axis) :patch)
          (%resolution-error :wrong-axis-resolution
                             "Overlay ~A must be selected by a patch axis."
                             (identifier-name name)))
        (let ((state (%require-identifier (second state-form) "Overlay state"))
              (precedence (second precedence-form)))
          (unless (axis-state-p axis state)
            (%resolution-error :unknown-axis-state
                               "Overlay ~A selects unknown state ~A for axis ~A."
                               (identifier-name name) (identifier-name state)
                               (identifier-name (axis-name axis))))
          (unless (integerp precedence)
            (%resolution-error :invalid-overlay-precedence
                               "Overlay ~A precedence must be an integer."
                               (identifier-name name)))
          (let ((bindings
                  (mapcar
                   (lambda (binding-form)
                     (%require-form-arity binding-form 3 3 :malformed-overlay-binding
                                          "OVERLAY BINDING clause")
                     (let ((position (%require-identifier (second binding-form)
                                                         "Overlay binding position"))
                           (value (third binding-form)))
                       (if (and (stringp value)
                                (string= (string-downcase value) "transparent"))
                           (make-transparent-patch-binding position)
                           (make-patch-binding
                            position
                            (%decode-behavior value product-axes
                                              :template-names template-names)))))
                   binding-forms)))
            (%require-unique-identifiers (mapcar #'patch-binding-position bindings)
                                         "overlay binding"
                                         :code :duplicate-overlay-binding)
            (make-overlay-patch name axis-name state bindings :precedence precedence)))))))

(defun %decode-interaction-template-argument-value (value parameters what)
  "Decode one identifier-valued interaction-template argument.

The existing interaction-template model substitutes parameters only where an
interaction names logical positions (participants, anchors, and temporal
selectors).  Keeping this surface identifier-only prevents a source template
from smuggling timing, callbacks, or a backend token through a generic
argument slot.
"
  (let ((identifier (%require-identifier value what)))
    (if (find identifier parameters :test #'identifier=)
        (make-interaction-template-parameter identifier)
        identifier)))

(defun %decode-position-pattern-argument (value &key parameters)
  (cond ((and (consp value) (string= (%form-name value) "other-than"))
         (when (null (rest value))
           (%resolution-error :malformed-position-selector
                              "OTHER-THAN needs at least one position."))
         (apply #'other-than-selector
                (mapcar (lambda (position)
                          (%decode-interaction-template-argument-value
                           position parameters "OTHER-THAN position"))
                        (rest value))))
        ((and (consp value) (string= (%form-name value) "any-position"))
         (%require-form-arity value 1 1 :malformed-position-selector "ANY-POSITION selector")
         (any-position-selector))
        ((consp value)
         (%resolution-error :unknown-position-selector
                            "Unknown position selector ~S." (%form-name value)))
        (t (position-selector
            (%decode-interaction-template-argument-value
             value parameters "Pattern position")))))

(defun %keyword-options (values allowed context)
  "Return an alist for alternating inline keyword/value syntax, rejecting extras."
  (let ((result nil))
    (loop for tail on values do
      (unless (and (stringp (first tail)) (rest tail))
        (%resolution-error :malformed-pattern-option
                           "Malformed ~A option sequence ~S." context values))
      (let ((name (string-downcase (first tail)))
            (value (second tail)))
        (unless (member name allowed :test #'string=)
          (%resolution-error :unknown-pattern-option "Unknown ~A option ~S." context name))
        (when (assoc name result :test #'string=)
          (%resolution-error :duplicate-pattern-option "Duplicate ~A option ~S." context name))
        (push (cons name value) result)
        (setf tail (rest tail))))
    (nreverse result)))

(defun %pattern-option (options name &key required context)
  (let ((entry (assoc name options :test #'string=)))
    (when (and required (null entry))
      (%resolution-error :missing-pattern-option "~A requires :~A." context name))
    (cdr entry)))

(defun %decode-pattern (form &key parameters)
  (unless (consp form)
    (%resolution-error :malformed-pattern "Expected a temporal pattern form, got ~S." form))
  (let ((name (%form-name form)) (arguments (rest form)))
    (cond
      ((member name '("down" "up") :test #'string=)
       (%require-form-arity form 2 2 :malformed-pattern name)
       (funcall (if (string= name "down") #'pattern-down #'pattern-up)
                (%decode-position-pattern-argument (second form) :parameters parameters)))
      ((member name '("sequence" "all" "either" "and" "first") :test #'string=)
       (when (null arguments)
         (%resolution-error :empty-pattern "~A needs at least one pattern." name))
       (apply (cond ((string= name "sequence") #'pattern-sequence)
                    ((string= name "all") #'pattern-all)
                    ((string= name "and") #'pattern-conjunction)
                    ;; FIRST is source shorthand for the first of a finite set
                    ;; of event candidates; EITHER is the corresponding IR node.
                    (t #'pattern-either))
              (mapcar (lambda (argument) (%decode-pattern argument :parameters parameters))
                      arguments)))
      ((string= name "duration")
       (when (null arguments)
         (%resolution-error :malformed-pattern "DURATION needs a position."))
       (let ((options (%keyword-options (rest arguments) '("at-least" "less-than") "DURATION")))
         (pattern-duration (%decode-position-pattern-argument (first arguments)
                                                           :parameters parameters)
                           :at-least (%pattern-option options "at-least")
                           :less-than (%pattern-option options "less-than"))))
      ((string= name "deadline")
       (%require-form-arity form 4 nil :malformed-pattern "DEADLINE")
       (let ((options (%keyword-options (rest arguments) '("after" "while-down") "DEADLINE")))
         (pattern-deadline (first arguments)
                           :after (%decode-pattern
                                   (%pattern-option options "after" :required t :context "DEADLINE")
                                   :parameters parameters)
                           :while-down (let ((position (%pattern-option options "while-down")))
                                         (and position
                                              (%decode-interaction-template-argument-value
                                               position parameters "DEADLINE :WHILE-DOWN"))))))
      ((string= name "within")
       (%require-form-arity form 3 nil :malformed-pattern "WITHIN")
       (apply #'pattern-within (first arguments)
              (mapcar (lambda (argument) (%decode-pattern argument :parameters parameters))
                      (rest arguments))))
      ((string= name "overlap")
       (when (null arguments)
         (%resolution-error :empty-pattern "OVERLAP needs at least one position."))
       (apply #'pattern-overlap
              (mapcar (lambda (argument)
                        (%decode-position-pattern-argument argument :parameters parameters))
                      arguments)))
      ((string= name "without")
       (%require-form-arity form 5 nil :malformed-pattern "WITHOUT")
       (unless (and (= (length arguments) 4)
                    (stringp (second arguments))
                    (string= (second arguments) "between"))
         (%resolution-error :malformed-pattern-option
                            "WITHOUT needs exactly :BETWEEN and two boundary patterns."))
       (pattern-without (%decode-pattern (first arguments) :parameters parameters)
                        :between (mapcar (lambda (argument)
                                           (%decode-pattern argument :parameters parameters))
                                         (cddr arguments))))
      ((string= name "repeat")
       (%require-form-arity form 4 nil :malformed-pattern "REPEAT")
       (let ((options (%keyword-options (rest arguments) '("at-most" "at-least") "REPEAT")))
         (pattern-repeat (%decode-pattern (first arguments) :parameters parameters)
                         :at-most (%pattern-option options "at-most" :required t :context "REPEAT")
                         :at-least (or (%pattern-option options "at-least") 0))))
      ((string= name "capture")
       (%require-form-arity form 3 3 :malformed-pattern "CAPTURE")
       (pattern-capture (%require-identifier (second form) "CAPTURE name")
                        (%decode-pattern (third form) :parameters parameters)))
      ((string= name "context-is")
       (%require-form-arity form 3 3 :malformed-pattern "CONTEXT-IS")
       (pattern-context-is (%require-identifier (second form) "CONTEXT-IS axis")
                           (%require-identifier (third form) "CONTEXT-IS state")))
      (t (%resolution-error :unknown-pattern-form "Unknown temporal pattern form ~S." name)))))

(defun %decode-commit (form &key parameters)
  (cond ((and (stringp form) (string= (string-downcase form) "when-matched")) :when-matched)
        ((and (stringp form) (string= (string-downcase form) "when-unambiguous")) :when-unambiguous)
        ((consp form) (%decode-pattern form :parameters parameters))
        (t (%resolution-error :malformed-commit "Invalid candidate commitment ~S." form))))

(defun %decode-effect-list (forms product-axes template-names)
  (mapcar (lambda (form) (%decode-behavior form product-axes :template-names template-names)) forms))

(defun %decode-effect-option (options name product-axes template-names)
  (let ((form (%single-form options name "interaction candidate")))
    (if form
        (%decode-effect-list (rest form) product-axes template-names)
        nil)))

(defun %decode-candidate (name options product-axes template-names &key parameters)
  (%assert-known-forms options '("match" "commit" "do" "enter" "commit-effect" "while" "exit" "cancel")
                       "interaction candidate option")
  (let* ((match-form (%single-form options "match" "interaction candidate" :required t))
         (commit-form (%single-form options "commit" "interaction candidate" :required t))
         (do-form (%single-form options "do" "interaction candidate" :required t)))
    (dolist (option (list match-form commit-form do-form))
      (%require-form-arity option 2 2 :malformed-interaction-case "interaction candidate option"))
    (make-interaction-candidate
     (%require-identifier name "Candidate name")
     (%decode-pattern (second match-form) :parameters parameters)
     (%decode-commit (second commit-form) :parameters parameters)
     (%decode-behavior (second do-form) product-axes :template-names template-names)
     :effects (make-interaction-effects
               :entry (%decode-effect-option options "enter" product-axes template-names)
               :commit (%decode-effect-option options "commit-effect" product-axes template-names)
               :while (%decode-effect-option options "while" product-axes template-names)
               :exit (%decode-effect-option options "exit" product-axes template-names)
               :cancel (%decode-effect-option options "cancel" product-axes template-names)))))

(defun %decode-arbitration (form)
  (when form
    (%require-form-arity form 2 2 :malformed-arbitration "ARBITRATION option")
    (let ((rule (second form)))
      (unless (consp rule)
        (%resolution-error :malformed-arbitration "ARBITRATION needs a rule."))
      (cond
        ((string= (%form-name rule) "priority")
         (when (< (length rule) 3)
           (%resolution-error :malformed-arbitration
                              "PRIORITY arbitration needs at least two candidates."))
         (apply #'priority-arbitration
                (mapcar (lambda (name) (%require-identifier name "PRIORITY candidate"))
                        (rest rule))))
        ((string= (%form-name rule) "longest-match")
         (cond ((= (length rule) 2) (longest-match-arbitration :deadline (second rule)))
               ((and (= (length rule) 3) (string= (second rule) "deadline"))
                (longest-match-arbitration :deadline (third rule)))
               (t (%resolution-error :malformed-arbitration
                                     "LONGEST-MATCH needs one :DEADLINE value."))))
        (t (%resolution-error :unknown-arbitration "Unknown arbitration ~S." (%form-name rule)))))))

(defun %decode-interaction (form product-axes template-names &key parameters)
  (%require-form-arity form 3 nil :malformed-interaction "INTERACTION declaration")
  (let* ((name (%require-identifier (second form) "Interaction name"))
         (clauses (cddr form))
         (case-forms (%forms-named clauses "case"))
         (direct-option-names '("match" "commit" "do" "enter" "commit-effect" "while" "exit" "cancel"))
         (direct-options (remove-if-not (lambda (clause)
                                          (member (%form-name clause) direct-option-names
                                                  :test #'string=)) clauses))
         (common-option-names '("participants" "observe" "anchor" "arbitration"))
         (allowed (append common-option-names direct-option-names '("case"))))
    (%assert-known-forms clauses allowed "INTERACTION clause")
    (when (and case-forms direct-options)
      (%resolution-error :mixed-interaction-candidate-spellings
                         "INTERACTION ~A mixes CASE clauses with direct candidate options."
                         (identifier-name name)))
    (let ((participants-form (%single-form clauses "participants" "INTERACTION" :required t))
          (observe-form (%single-form clauses "observe" "INTERACTION"))
          (anchor-form (%single-form clauses "anchor" "INTERACTION"))
          (arbitration-form (%single-form clauses "arbitration" "INTERACTION")))
      (%require-form-arity participants-form 2 nil :malformed-interaction "PARTICIPANTS option")
      (let* ((participants
               (mapcar (lambda (participant)
                         (%decode-interaction-template-argument-value
                          participant parameters "Interaction participant"))
                       (rest participants-form)))
             (observe (cond ((null observe-form) :participants)
                            (t (%require-form-arity observe-form 2 2 :malformed-interaction
                                                    "OBSERVE option")
                               (cond ((string= (second observe-form) "participants") :participants)
                                     ((string= (second observe-form) "any-position") :any-position)
                                     (t (%resolution-error :unknown-observe-scope
                                                          "Unknown OBSERVE scope ~S."
                                                          (second observe-form)))))))
             (anchor (when anchor-form
                       (%require-form-arity anchor-form 2 2 :malformed-interaction "ANCHOR option")
                       (%decode-interaction-template-argument-value
                        (second anchor-form) parameters "ANCHOR position")))
             (candidates
               (cond
                 (case-forms
                  (mapcar (lambda (case-form)
                            (%require-form-arity case-form 3 nil :malformed-interaction-case "CASE clause")
                            (%decode-candidate (second case-form) (cddr case-form)
                                               product-axes template-names
                                               :parameters parameters))
                          case-forms))
                 (direct-options
                  ;; The historical one-candidate spelling is normalized to a
                  ;; real named candidate.  There is no special interaction path.
                  (list (%decode-candidate "default" direct-options product-axes template-names
                                           :parameters parameters)))
                 (t (%resolution-error :interaction-without-candidates
                                       "INTERACTION ~A has no CASE or direct candidate."
                                       (identifier-name name))))))
        (when (every (lambda (participant) (typep participant 'identifier)) participants)
          (%require-unique-identifiers participants "interaction participant"
                                       :code :duplicate-interaction-participant))
        (%require-unique-identifiers (mapcar #'candidate-name candidates) "interaction candidate"
                                     :code :duplicate-interaction-candidate)
        (make-interaction name participants candidates :observe observe :anchor anchor
                          :arbitration (%decode-arbitration arbitration-form))))))

(defun %decode-interaction-template-header (form)
  "Return the declaration's name, unique parameter identifiers, and one body.

The body is kept as harmless parser data until every header is known.  That
allows deterministic forward references without evaluating or interning any
source spelling.
"
  (%require-form-arity form 4 4 :malformed-interaction-template
                       "DEFINE-INTERACTION-TEMPLATE declaration")
  (let ((name (%require-identifier (second form) "Interaction template name"))
        (parameters (third form)))
    (unless (listp parameters)
      (%resolution-error :malformed-interaction-template
                         "DEFINE-INTERACTION-TEMPLATE parameters must be a list."))
    (values name
            (%require-unique-identifiers
             parameters "interaction-template parameter"
             :code :duplicate-interaction-template-parameter)
            (fourth form))))

(defun %find-interaction-template-header (name headers)
  (find (%require-identifier name "Interaction template name") headers
        :test #'identifier= :key #'first))

(defun %decode-interaction-template-reference (form headers &key parameters)
  "Decode one named-argument template call into the existing model reference.

The model reference stores arguments in declaration order.  The source surface
uses explicit argument names so a typo, duplicate, or omitted parameter cannot
change meaning through incidental position.
"
  (%require-form-arity form 2 nil :malformed-interaction-template-reference
                       "INSTANTIATE-INTERACTION declaration")
  (let* ((name (%require-identifier (second form) "Interaction template name"))
         (header (%find-interaction-template-header name headers)))
    (unless header
      (%resolution-error :unknown-interaction-template
                         "Unknown interaction template ~A." (identifier-name name)))
    (let* ((target-parameters (second header))
           (argument-forms (cddr form))
           (argument-names nil))
      (dolist (argument-form argument-forms)
        (%require-form-arity argument-form 2 2
                             :malformed-interaction-template-argument
                             "interaction-template argument")
        (let ((argument-name
                (%require-identifier (first argument-form)
                                     "Interaction template argument name")))
          (unless (find argument-name target-parameters :test #'identifier=)
            (%resolution-error :unknown-interaction-template-argument
                               "Interaction template ~A has no parameter ~A."
                               (identifier-name name) (identifier-name argument-name)))
          (push argument-name argument-names)))
      ;; Check duplicate source keys before arity.  It gives the author the
      ;; actionable cause rather than merely counting an unusable argument.
      (%require-unique-identifiers argument-names "interaction-template argument"
                                   :code :duplicate-interaction-template-argument)
      (unless (= (length target-parameters) (length argument-forms))
        (%resolution-error :template-arity
                           "Interaction template ~A expects ~D arguments, got ~D."
                           (identifier-name name) (length target-parameters)
                           (length argument-forms)))
      (make-interaction-template-reference
       name
       (mapcar
        (lambda (parameter)
          (let ((argument-form
                  (find parameter argument-forms :test #'identifier=
                        :key (lambda (candidate)
                               (%require-identifier (first candidate)
                                                    "Interaction template argument name")))))
            ;; The lookup is total after the arity/unknown checks above.
            (%decode-interaction-template-argument-value
             (second argument-form) parameters "Interaction template argument")))
        target-parameters)))))

(defun %decode-interaction-template-body (body product-axes behavior-template-names
                                           headers parameters)
  (cond ((%named-form-p body "interaction")
         (%decode-interaction body product-axes behavior-template-names
                              :parameters parameters))
        ((%named-form-p body "instantiate-interaction")
         (%decode-interaction-template-reference body headers :parameters parameters))
        (t (%resolution-error :invalid-interaction-template-body
                              "Interaction template body must be INTERACTION or INSTANTIATE-INTERACTION, got ~S."
                              (%form-name body)))))

(defun %assert-acyclic-interaction-template-graph (templates)
  "Reject cycles even when no source instantiation reaches them."
  (let ((visiting (make-hash-table :test #'equal))
        (visited (make-hash-table :test #'equal)))
    (labels ((walk (template)
               (let ((key (identifier-key (interaction-template-name template))))
                 (cond ((gethash key visiting)
                        (%resolution-error :recursive-interaction-template
                                           "Interaction template cycle includes ~A."
                                           (identifier-name
                                            (interaction-template-name template))))
                       ((not (gethash key visited))
                        (setf (gethash key visiting) t)
                        (let ((body (interaction-template-body template)))
                          (when (typep body 'interaction-template-reference)
                            (let ((target (find (interaction-reference-name body) templates
                                                :test #'identifier=
                                                :key #'interaction-template-name)))
                              ;; Bodies were decoded against every header, so
                              ;; an absent target cannot become an implicit
                              ;; empty expansion here.
                              (unless target
                                (%resolution-error :unknown-interaction-template
                                                   "Unknown interaction template ~A."
                                                   (identifier-name
                                                    (interaction-reference-name body))))
                              (walk target))))
                        (remhash key visiting)
                        (setf (gethash key visited) t))))))
      (dolist (template templates)
        (walk template))))
  templates)

(defun %decode-interaction-templates (forms product-axes behavior-template-names)
  "Decode all template declarations after collecting their closed headers."
  (let ((headers
          (mapcar (lambda (form)
                    (multiple-value-list
                     (%decode-interaction-template-header form)))
                  forms)))
    (%require-unique-identifiers (mapcar #'first headers) "interaction-template"
                                 :code :duplicate-interaction-template)
    (let ((templates
            (mapcar
             (lambda (header)
               (make-interaction-template
                (first header) (second header)
                (%decode-interaction-template-body
                 (third header) product-axes behavior-template-names headers
                 (second header))))
             headers)))
      (%assert-acyclic-interaction-template-graph templates)
      (values templates headers))))

(defun %decode-behavior-template-header (form)
  (%require-form-arity form 4 4 :malformed-behavior-template "DEFINE-BEHAVIOR declaration")
  (let ((name (%require-identifier (second form) "Behavior template name"))
        (parameters (third form)))
    (unless (listp parameters)
      (%resolution-error :malformed-behavior-template
                         "DEFINE-BEHAVIOR parameters must be a list."))
    (values name (%require-unique-identifiers parameters "behavior-template parameter"
                                                :code :duplicate-template-parameter)
            (fourth form))))

(defun %decode-behavior-templates (forms product-axes)
  (let ((headers (mapcar (lambda (form)
                           (multiple-value-list (%decode-behavior-template-header form))) forms)))
    (%require-unique-identifiers (mapcar #'first headers) "behavior-template"
                                 :code :duplicate-behavior-template)
    (dolist (header headers)
      (when (member (identifier-name (first header)) +decoder-behavior-forms+ :test #'string=)
        (%resolution-error :reserved-behavior-template-name
                           "DEFINE-BEHAVIOR name ~A is reserved." (identifier-name (first header)))))
    (let ((names (mapcar #'first headers)))
      (mapcar (lambda (header)
                (make-behavior-template (first header) (second header)
                                        (%decode-behavior (third header) product-axes
                                                          :template-names names
                                                          :parameters (second header))))
              headers))))

(defun %decode-layout-axes (clauses)
  (let ((axes (mapcar #'%decode-axis (%forms-named clauses "axis"))))
    (%require-unique-identifiers (mapcar #'axis-name axes) "axis" :code :duplicate-axis)
    (let ((level-order (%single-form clauses "level-order" "DEFINE-LAYOUT")))
      (if (null level-order)
          axes
          (let* ((names (rest level-order))
                 (products (mapcar (lambda (axis-name)
                                     (or (find-axis axis-name axes)
                                         (%resolution-error :unknown-level-axis
                                                            "LEVEL-ORDER names unknown axis ~A."
                                                            axis-name)))
                                   names)))
            (unless (and (every (lambda (axis) (eq (axis-resolution axis) :product)) products)
                         (= (length products) (length (product-axes axes)))
                         (unique-identifiers-p (mapcar #'axis-name products)))
              (%resolution-error :invalid-level-order
                                 "LEVEL-ORDER must list every product axis exactly once."))
            (append products (remove-if (lambda (axis) (member axis products)) axes)))))))

(defun %decode-layout-topology (topology topology-resolver uses-topology bindings overlays interactions)
  (or topology
      (and uses-topology topology-resolver
           (funcall topology-resolver (%require-identifier (second uses-topology) "Topology name")))
      (let ((positions
              (remove-duplicates
               (append (mapcar #'binding-position bindings)
                       (mapcan (lambda (overlay)
                                 (mapcar #'patch-binding-position
                                         (overlay-patch-bindings overlay)))
                               overlays)
                       (mapcan (lambda (interaction)
                                 (cond ((typep interaction 'interaction)
                                        ;; MAPCAN destructively splices its
                                        ;; result lists.  Never hand it a model
                                        ;; slot directly: that would change a
                                        ;; later resolver view of the layout.
                                        (copy-list (interaction-participants interaction)))
                                       ;; A top-level template call exposes its
                                       ;; actual identifier arguments, which is
                                       ;; useful for the existing inferred
                                       ;; topology convenience.  A template
                                       ;; body with additional literal
                                       ;; positions still needs USES-TOPOLOGY,
                                       ;; just like any cross-file reference.
                                       ((typep interaction 'interaction-template-reference)
                                        (copy-list
                                         (remove-if-not (lambda (argument)
                                                          (typep argument 'identifier))
                                                        (interaction-reference-arguments
                                                         interaction))))
                                       (t nil)))
                               interactions))
               :test #'identifier=)))
        (make-topology (if uses-topology (second uses-topology) "inferred")
                       (mapcar #'make-logical-position positions)))))

(defun decode-layout-forms (parsed &key topology topology-resolver)
  "Decode one closed-vocabulary v1 DEFINE-LAYOUT form into a typed LAYOUT.

PARSED may be a SYNTAX-PARSE-RESULT, its harmless datum representation, or a
form list supplied by a test.  TOPOLOGY may be supplied directly; otherwise a
TOPOLOGY-RESOLVER receives the declared topology identifier.  Cross-file
topology/import loading is deliberately outside this decoder."
  (let* ((forms (%decode-value (if (syntax-parse-result-p parsed)
                                   (syntax-parse-result-forms parsed) parsed)))
         (layout-forms (%forms-named forms "define-layout")))
    (unless layout-forms
      (%resolution-error :missing-layout "Input contains no DEFINE-LAYOUT form."))
    (when (rest layout-forms)
      (%resolution-error :duplicate-layout "Input contains more than one DEFINE-LAYOUT form."))
    (dolist (form forms)
      (unless (or (%named-form-p form "ivory-key") (%named-form-p form "define-layout"))
        (%resolution-error :unsupported-top-level-form
                           "Unsupported top-level form ~S." (%form-name form))))
    (let* ((layout-form (first layout-forms)))
      (%require-form-arity layout-form 3 nil :malformed-layout "DEFINE-LAYOUT declaration")
      (let* ((name (%require-identifier (second layout-form) "Layout name"))
             (clauses (cddr layout-form)))
        (%assert-known-forms clauses +decoder-layout-clauses+ "DEFINE-LAYOUT clause")
        (let* ((uses-topology (%single-form clauses "uses-topology" "DEFINE-LAYOUT"))
               (modifiers-form (%single-form clauses "modifiers" "DEFINE-LAYOUT"))
               (axes (%decode-layout-axes clauses))
               (product-axes (product-axes axes))
               (templates (%decode-behavior-templates (%forms-named clauses "define-behavior")
                                                      product-axes))
               (template-names (mapcar #'behavior-template-name templates))
               (interaction-template-forms
                 (%forms-named clauses "define-interaction-template"))
               (binding-results
                 (mapcar (lambda (binding-form)
                           (multiple-value-list
                            (%decode-binding binding-form product-axes template-names)))
                         (%forms-named clauses "binding")))
               (bindings (remove nil (mapcar #'first binding-results)))
               (on-tap-interactions (mapcan #'second binding-results))
               (overlays
                 (mapcar (lambda (overlay-form)
                           (%decode-overlay overlay-form axes product-axes template-names))
                         (%forms-named clauses "overlay")))
               (direct-interactions
                 (append (mapcar (lambda (interaction-form)
                                   (%decode-interaction interaction-form product-axes template-names))
                                 (%forms-named clauses "interaction"))
                         on-tap-interactions)))
          (%require-unique-identifiers (mapcar #'binding-position bindings) "binding"
                                       :code :duplicate-binding)
          (%require-unique-identifiers (mapcar #'overlay-patch-name overlays) "overlay"
                                       :code :duplicate-overlay)
          (%require-unique-identifiers (mapcar #'interaction-name direct-interactions) "interaction"
                                       :code :duplicate-interaction)
          (when uses-topology
            (%require-form-arity uses-topology 2 2 :malformed-layout "USES-TOPOLOGY option")
            (%require-identifier (second uses-topology) "Topology name"))
          (when modifiers-form
            (%require-unique-identifiers (rest modifiers-form) "semantic modifier"
                                         :code :duplicate-semantic-modifier))
          (multiple-value-bind (interaction-templates interaction-template-headers)
              (%decode-interaction-templates interaction-template-forms product-axes template-names)
            (let ((interactions
                    (append direct-interactions
                            (mapcar
                             (lambda (form)
                               (%decode-interaction-template-reference
                                form interaction-template-headers))
                             (%forms-named clauses "instantiate-interaction")))))
              ;; Source template calls are a surface shorthand: callers of this
              ;; decoder receive a layout that is already safe to validate.
              (resolve-layout
               (make-layout name
                            (%decode-layout-topology topology topology-resolver uses-topology
                                                     bindings overlays interactions)
                            axes (if modifiers-form (rest modifiers-form) nil)
                            :bindings bindings :overlays overlays :interactions interactions
                            :behavior-templates templates
                            :interaction-templates interaction-templates)))))))))
