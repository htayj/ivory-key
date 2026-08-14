;;;; SPDX-License-Identifier: GPL-3.0-or-later

(in-package #:ivory-key.syntax)

(defstruct syntax-atom
  "A safe atom.  Identifiers and keywords retain string values, never symbols."
  kind
  text
  value
  span)

(defstruct syntax-list
  "A parenthesized sequence of concrete forms."
  children
  span)

(defstruct syntax-parse-result
  source
  forms
  diagnostics
  comments
  language-version)

(defgeneric syntax-node-span (node)
  (:documentation "Return NODE's exact source span."))

(defmethod syntax-node-span ((node syntax-atom))
  (syntax-atom-span node))

(defmethod syntax-node-span ((node syntax-list))
  (syntax-list-span node))

(defun syntax-node-equal-p (left right)
  "Compare concrete syntax while intentionally ignoring spans and comments."
  (cond
    ((and (typep left 'syntax-atom) (typep right 'syntax-atom))
     (and (eq (syntax-atom-kind left) (syntax-atom-kind right))
          (equal (syntax-atom-value left) (syntax-atom-value right))))
    ((and (typep left 'syntax-list) (typep right 'syntax-list))
     (let ((left-children (syntax-list-children left))
           (right-children (syntax-list-children right)))
       (and (= (length left-children) (length right-children))
            (every #'syntax-node-equal-p left-children right-children))))
    (t nil)))

(defun syntax-form->datum (node)
  "Produce an explicitly tagged, reader-safe datum for inspection or debugging.

This helper is deliberately lossy with respect to source spans.  Semantic
decoders should use the concrete node accessors directly so their diagnostics
remain source-linked."
  (etypecase node
    (syntax-atom
     (list (syntax-atom-kind node) (syntax-atom-value node)))
    (syntax-list
     (cons :list (mapcar #'syntax-form->datum (syntax-list-children node))))))

(defun syntax-parse-result-complete-p (result)
  "True exactly when parsing and the required language header produced no errors."
  (and (typep result 'syntax-parse-result)
       (null (syntax-parse-result-diagnostics result))))

(defstruct (%parser-state (:constructor %make-parser-state))
  tokens
  limits
  eof-token
  (diagnostic-count 0 :type integer)
  (diagnostics-suppressed-p nil)
  (diagnostics nil :type list))

(defun %current-token (state)
  ;; Keeping the unconsumed suffix makes token traversal O(n).  NTH made a
  ;; syntactically valid file with many small forms quadratic to parse.
  (or (car (%parser-state-tokens state))
      (%parser-state-eof-token state)))

(defun %advance-token (state)
  (prog1 (%current-token state)
    (when (%parser-state-tokens state)
      (pop (%parser-state-tokens state)))))

(defun %parser-diagnose (state code message span &key hint)
  (let ((limit (syntax-limits-max-diagnostics
                (%parser-state-limits state))))
    (cond
      ((< (%parser-state-diagnostic-count state) limit)
       (incf (%parser-state-diagnostic-count state))
       (push (make-diagnostic :code code :message message :span span :hint hint)
             (%parser-state-diagnostics state)))
      ((not (%parser-state-diagnostics-suppressed-p state))
       (setf (%parser-state-diagnostics-suppressed-p state) t)
       (when (%parser-state-diagnostics state)
         (pop (%parser-state-diagnostics state))
         (decf (%parser-state-diagnostic-count state)))
       (incf (%parser-state-diagnostic-count state))
       (push (make-diagnostic
              :code "IK010"
              :message "Too many syntax diagnostics; remaining input was not diagnosed."
              :span span
              :hint "Fix the earlier errors or raise the diagnostic limit for trusted input.")
             (%parser-state-diagnostics state))))))

(defun %token-node (token)
  (make-syntax-atom :kind (syntax-token-kind token)
                    :text (syntax-token-text token)
                    :value (syntax-token-value token)
                    :span (syntax-token-span token)))

(defun %skip-nested-list (state)
  "Skip after an already-consumed left parenthesis without recursive descent."
  (let ((unclosed 1))
    (loop while (plusp unclosed) do
      (let ((token (%current-token state)))
        (case (syntax-token-kind token)
          (:eof (return))
          (:left-paren (incf unclosed))
          (:right-paren (decf unclosed)))
        (%advance-token state)))))

(defun %parse-list (state opening depth)
  (when (> depth (syntax-limits-max-depth (%parser-state-limits state)))
    (%parser-diagnose state "IK008" "Nesting exceeds the configured limit."
                      (syntax-token-span opening)
                      :hint "Raise the parser nesting limit only for trusted input.")
    (%skip-nested-list state)
    (return-from %parse-list nil))
  (let ((children nil))
    (loop
      (let ((token (%current-token state)))
        (case (syntax-token-kind token)
          (:eof
           (%parser-diagnose state "IK101" "Unterminated list."
                             (syntax-token-span opening)
                             :hint "Add a closing parenthesis.")
           (return (make-syntax-list
                    :children (nreverse children)
                    :span (source-span-merge (syntax-token-span opening)
                                             (syntax-token-span token)))))
          (:right-paren
           (%advance-token state)
           (return (make-syntax-list
                    :children (nreverse children)
                    :span (source-span-merge (syntax-token-span opening)
                                             (syntax-token-span token)))))
          (otherwise
           (let ((child (%parse-form state depth)))
             (when child (push child children)))))))))

(defun %parse-form (state depth)
  (let ((token (%current-token state)))
    (case (syntax-token-kind token)
      ((:identifier :keyword :string :integer)
       (%advance-token state)
       (%token-node token))
      (:left-paren
       (%advance-token state)
       (%parse-list state token (1+ depth)))
      (:invalid
       ;; Lexing already recorded a precise diagnostic.  Treat the invalid
       ;; token as one recoverable hole rather than compounding diagnostics.
       (%advance-token state)
       nil)
      (:right-paren
       (%parser-diagnose state "IK100" "Unexpected closing parenthesis."
                         (syntax-token-span token)
                         :hint "Remove this ')' or add a matching '('.")
       (%advance-token state)
       nil)
      (:eof nil)
      (otherwise
       (%parser-diagnose state "IK005" "Unexpected lexer token."
                         (syntax-token-span token))
       (%advance-token state)
       nil))))

(defun %language-header-version (forms state)
  "Validate only the version envelope; later phases own declaration schemas."
  (let ((header (first forms)))
    (unless header
      (%parser-diagnose state "IK102"
                        "An Ivory Key file must begin with (ivory-key 1)."
                        (syntax-token-span (%current-token state))
                        :hint "Add the explicit language-version header.")
      (return-from %language-header-version nil))
    (unless (and (typep header 'syntax-list)
                 (let ((name (first (syntax-list-children header))))
                   (and (typep name 'syntax-atom)
                        (eq (syntax-atom-kind name) :identifier)
                        (string= (syntax-atom-value name) "ivory-key"))))
      (%parser-diagnose state "IK102"
                        "An Ivory Key file must begin with (ivory-key 1)."
                        (syntax-node-span header)
                        :hint "Add the explicit language-version header.")
      (return-from %language-header-version nil))
    (unless (= (length (syntax-list-children header)) 2)
      (%parser-diagnose state "IK103" "Invalid Ivory Key language header."
                        (syntax-node-span header)
                        :hint "Use exactly (ivory-key 1).")
      (return-from %language-header-version nil))
    (destructuring-bind (name version) (syntax-list-children header)
      (if (and (typep name 'syntax-atom)
               (eq (syntax-atom-kind name) :identifier)
               (string= (syntax-atom-value name) "ivory-key")
               (typep version 'syntax-atom)
               (eq (syntax-atom-kind version) :integer)
               (= (syntax-atom-value version) 1))
          1
          (progn
            (%parser-diagnose state "IK103" "Invalid Ivory Key language header."
                              (syntax-node-span header)
                              :hint "Only language version 1 is supported; use (ivory-key 1).")
            nil)))))

(defun %input-limit-diagnostic-p (diagnostic)
  (string= (diagnostic-code diagnostic) "IK001"))

(defun parse-source (source &key (limits *default-syntax-limits*) (require-header t))
  "Parse SOURCE without evaluating it or interning any source identifier.

The return value contains every recoverable diagnostic.  REQUIRE-HEADER is
normally true for layout files; it may be false for parser fixtures and tools
which deliberately process a bare S-expression fragment."
  (check-type source source-file)
  (let* ((lexed (lex-source source :limits limits))
         (tokens (syntax-lex-result-tokens lexed))
         (state (%make-parser-state :tokens tokens
                                    :eof-token (car (last tokens))
                                    :limits limits))
         (forms nil))
    (loop until (eq (syntax-token-kind (%current-token state)) :eof) do
      (let ((form (%parse-form state 0)))
        (when form (push form forms))))
    (setf forms (nreverse forms))
    (let* ((lexical-diagnostics (syntax-lex-result-diagnostics lexed))
           (input-too-large (find-if #'%input-limit-diagnostic-p
                                     lexical-diagnostics))
           (language-version
             (and require-header
                  (not input-too-large)
                  (%language-header-version forms state)))
           (diagnostics
             (diagnostics-in-source-order
              (append lexical-diagnostics
                      (nreverse (%parser-state-diagnostics state))))))
      (make-syntax-parse-result
       :source source
       :forms forms
       :diagnostics diagnostics
       :comments (syntax-lex-result-comments lexed)
       :language-version language-version))))

(defun parse-string (text &key (name "<string>")
                           (limits *default-syntax-limits*) (require-header t))
  "Parse UTF-8 source represented as a Common Lisp string."
  (check-type text string)
  (parse-source (make-source-file :name name :text text)
                :limits limits :require-header require-header))

(defun %file-diagnostic-result (name code message hint)
  (let* ((source (make-source-file :name name :text ""))
         (span (make-source-span :source source
                                 :start-byte 0 :end-byte 0
                                 :start-line 1 :start-column 1
                                 :end-line 1 :end-column 1)))
    (make-syntax-parse-result
     :source source
     :forms nil
     :diagnostics (list (make-diagnostic :code code :message message
                                         :span span :hint hint))
     :comments nil
     :language-version nil)))

(defun %pathname-byte-length (pathname)
  "Return PATHNAME's octet length before allocating a decoded source string."
  (with-open-file (stream pathname :direction :input
                                  :element-type '(unsigned-byte 8))
    (file-length stream)))

(defun parse-file (pathname &key (limits *default-syntax-limits*)
                              (require-header t))
  "Read a bounded UTF-8 source file and return diagnostics for read failures.

The byte-size gate runs before UIOP decodes the complete file, so the parser
limit protects command-line use as well as in-memory PARSE-STRING callers."
  (%validate-limits limits)
  (handler-case
      (let* ((path (uiop:ensure-pathname pathname))
             (name (uiop:native-namestring path))
             (byte-length (%pathname-byte-length path)))
        (if (and byte-length
                 (> byte-length (syntax-limits-max-bytes limits)))
            (%file-diagnostic-result
             name "IK001" "Input exceeds the configured byte limit."
             "Raise the parser input limit only for trusted input.")
            (parse-string (uiop:read-file-string path :external-format :utf-8)
                          :name name
                          :limits limits
                          :require-header require-header)))
    (error ()
      (%file-diagnostic-result
       (if (pathnamep pathname) (namestring pathname) (princ-to-string pathname))
       "IK009" "Could not read source file as UTF-8."
       "Check that the path is readable and encoded as UTF-8."))))

(defun parse-source-or-signal (source &key (limits *default-syntax-limits*)
                                            (require-header t))
  "Parse SOURCE or signal one aggregate IVORY-KEY-SYNTAX-ERROR condition."
  (let ((result (parse-source source :limits limits :require-header require-header)))
    (if (syntax-parse-result-complete-p result)
        result
        (error 'ivory-key-syntax-error
               :diagnostics (syntax-parse-result-diagnostics result)))))
