;;;; SPDX-License-Identifier: GPL-3.0-or-later

(in-package #:ivory-key.syntax)

;;; This is intentionally not a wrapper around CL:READ.  In particular, # is
;;; just an invalid input character unless it begins a #| ... |# comment.

(defstruct (syntax-limits
            (:constructor make-syntax-limits
                (&key (max-bytes 1048576)
                      (max-token-bytes 65536)
                      (max-depth 1024)
                      (max-tokens 65536)
                      (max-diagnostics 128))))
  "Operational limits for untrusted source input, not language limits."
  (max-bytes 1048576 :type (integer 1 *) :read-only t)
  (max-token-bytes 65536 :type (integer 1 *) :read-only t)
  (max-depth 1024 :type (integer 1 *) :read-only t)
  (max-tokens 65536 :type (integer 1 *) :read-only t)
  (max-diagnostics 128 :type (integer 1 *) :read-only t))

(defparameter *default-syntax-limits* (make-syntax-limits)
  "Conservative defaults suitable for CLI input.  Callers may raise them.")

(defstruct syntax-token
  kind
  text
  value
  span)

(defstruct syntax-comment
  "Non-semantic trivia retained so the formatter can preserve it conservatively."
  style
  text
  span)

(defstruct syntax-lex-result
  tokens
  diagnostics
  comments)

(defstruct (%lexer-state (:constructor %make-lexer-state))
  source
  text
  (index 0 :type fixnum)
  (byte 0 :type integer)
  (line 1 :type integer)
  (column 1 :type integer)
  limits
  (token-count 0 :type integer)
  (diagnostic-count 0 :type integer)
  (diagnostics-suppressed-p nil)
  (diagnostics nil :type list)
  (comments nil :type list)
  (tokens nil :type list))

(defun %unicode-scalar-code-point-p (code-point)
  "True when CODE-POINT is a Unicode scalar value.

Surrogates are deliberately rejected even on implementations that expose them
as characters.  Treating them as UTF-8 source would make byte offsets and
formatter output implementation-dependent."
  (and (integerp code-point)
       (<= 0 code-point #x10FFFF)
       (not (<= #xD800 code-point #xDFFF))))

(defun %unicode-scalar-character-p (character)
  (and (characterp character)
       (%unicode-scalar-code-point-p (char-code character))))

(defun %ascii-letter-p (character)
  (and character
       (let ((code (char-code character)))
         (or (<= (char-code #\A) code (char-code #\Z))
             (<= (char-code #\a) code (char-code #\z))))))

(defun %ascii-digit-p (character)
  (and character
       (<= (char-code #\0) (char-code character) (char-code #\9))))

(defun %ascii-hex-digit-p (character)
  (and character
       (or (%ascii-digit-p character)
           (let ((code (char-code character)))
             (or (<= (char-code #\A) code (char-code #\F))
                 (<= (char-code #\a) code (char-code #\f)))))))

(defun %utf8-char-byte-count (character)
  "Return CHARACTER's UTF-8 width without relying on implementation encodings."
  (let ((code (char-code character)))
    (unless (%unicode-scalar-code-point-p code)
      (error "Non-Unicode-scalar character cannot occur in Ivory Key source."))
    (cond ((<= code #x7F) 1)
          ((<= code #x7FF) 2)
          ((<= code #xFFFF) 3)
          (t 4))))

(defun %utf8-string-byte-count (string)
  (loop for character across string
        sum (%utf8-char-byte-count character)))

(defun %at-end-p (state)
  (>= (%lexer-state-index state) (length (%lexer-state-text state))))

(defun %peek (state &optional (offset 0))
  (let ((index (+ (%lexer-state-index state) offset))
        (text (%lexer-state-text state)))
    (and (< index (length text)) (char text index))))

(defun %advance (state)
  "Consume one logical source character and update byte and display positions.

A CRLF pair is one line break but spans both bytes, matching common source
tools while retaining exact UTF-8 byte offsets."
  (unless (%at-end-p state)
    (let ((character (%peek state)))
      (incf (%lexer-state-index state))
      (incf (%lexer-state-byte state) (%utf8-char-byte-count character))
      (cond
        ((char= character #\Return)
         (when (and (%peek state) (char= (%peek state) #\Newline))
           (incf (%lexer-state-index state))
           (incf (%lexer-state-byte state) 1))
         (incf (%lexer-state-line state))
         (setf (%lexer-state-column state) 1))
        ((char= character #\Newline)
         (incf (%lexer-state-line state))
         (setf (%lexer-state-column state) 1))
        (t
         (incf (%lexer-state-column state))))
      character)))

(defun %span-from (state start-byte start-line start-column)
  (make-source-span :source (%lexer-state-source state)
                    :start-byte start-byte
                    :end-byte (%lexer-state-byte state)
                    :start-line start-line
                    :start-column start-column
                    :end-line (%lexer-state-line state)
                    :end-column (%lexer-state-column state)))

(defmacro %with-start ((state start-index start-byte start-line start-column)
                       &body body)
  `(let ((,start-index (%lexer-state-index ,state))
         (,start-byte (%lexer-state-byte ,state))
         (,start-line (%lexer-state-line ,state))
         (,start-column (%lexer-state-column ,state)))
     ,@body))

(defun %diagnose (state code message start-byte start-line start-column
                  &key hint)
  (let ((limit (syntax-limits-max-diagnostics
                (%lexer-state-limits state))))
    (cond
      ((< (%lexer-state-diagnostic-count state) limit)
       (incf (%lexer-state-diagnostic-count state))
       (push (make-diagnostic :code code
                              :message message
                              :span (%span-from state start-byte start-line
                                                start-column)
                              :hint hint)
             (%lexer-state-diagnostics state)))
      ((not (%lexer-state-diagnostics-suppressed-p state))
       ;; Keep the configured cap strict while making truncation explicit.
       ;; Replace the final detailed diagnostic with the sentinel instead of
       ;; letting hostile input allocate an unbounded condition list.
       (setf (%lexer-state-diagnostics-suppressed-p state) t)
       (when (%lexer-state-diagnostics state)
         (pop (%lexer-state-diagnostics state))
         (decf (%lexer-state-diagnostic-count state)))
       (incf (%lexer-state-diagnostic-count state))
       (push (make-diagnostic
              :code "IK010"
              :message "Too many syntax diagnostics; remaining input was not diagnosed."
              :span (%span-from state start-byte start-line start-column)
              :hint "Fix the earlier errors or raise the diagnostic limit for trusted input.")
             (%lexer-state-diagnostics state))))))

(defun %emit-token (state kind text value start-byte start-line start-column)
  (push (make-syntax-token :kind kind
                           :text text
                           :value value
                           :span (%span-from state start-byte start-line
                                             start-column))
        (%lexer-state-tokens state))
  (unless (eq kind :eof)
    (incf (%lexer-state-token-count state))))

(defun %emit-invalid-token (state start-index start-byte start-line start-column)
  (%emit-token state :invalid
               (subseq (%lexer-state-text state) start-index
                       (%lexer-state-index state))
               nil start-byte start-line start-column))

(defun %whitespacep (character)
  ;; Common Lisp strings have no C-style \n / \t escapes, so spell these as
  ;; characters rather than accidentally treating backslash and n as space.
  (and character
       (member character '(#\Space #\Tab #\Newline #\Return #\Page)
               :test #'char=)))

(defun %identifier-start-p (character)
  (and character
       (or (%ascii-letter-p character)
           (char= character #\_))))

(defun %identifier-continue-p (character)
  (and character
       (or (%identifier-start-p character)
           (%ascii-digit-p character)
           (find character "-.?!*+=<>/" :test #'char=))))

(defun %delimiterp (character)
  (or (null character)
      (%whitespacep character)
      (and character (find character "();\"" :test #'char=))
      (and character (char= character #\#))
      (and character (char= character #\:))))

(defun %token-too-large-p (state start-byte limits)
  (> (- (%lexer-state-byte state) start-byte)
     (syntax-limits-max-token-bytes limits)))

(defun %consume-line-comment (state)
  (%with-start (state start-index start-byte start-line start-column)
    (declare (ignore start-index))
    (%advance state)                    ; semicolon
    (let ((body-start (%lexer-state-index state)))
      (loop while (and (%peek state)
                       (not (or (char= (%peek state) #\Newline)
                                (char= (%peek state) #\Return))))
            do (%advance state))
      (push (make-syntax-comment
             :style :line
             :text (subseq (%lexer-state-text state) body-start
                           (%lexer-state-index state))
             :span (%span-from state start-byte start-line start-column))
            (%lexer-state-comments state)))))

(defun %consume-block-comment (state limits)
  (%with-start (state start-index start-byte start-line start-column)
    (declare (ignore start-index))
    (%advance state)                    ; #
    (%advance state)                    ; |
    (let ((body-start (%lexer-state-index state))
          (depth 1)
          (depth-reported-p nil))
      (loop while (and (plusp depth) (not (%at-end-p state))) do
        (cond
          ((and (char= (%peek state) #\#)
                (%peek state 1)
                (char= (%peek state 1) #\|))
           (incf depth)
           (when (and (> depth (syntax-limits-max-depth limits))
                      (not depth-reported-p))
             (setf depth-reported-p t)
             (%diagnose state "IK008" "Comment nesting exceeds the configured limit."
                        start-byte start-line start-column
                        :hint "Raise the parser nesting limit only for trusted input."))
           (%advance state)
           (%advance state))
          ((and (char= (%peek state) #\|)
                (%peek state 1)
                (char= (%peek state 1) #\#))
           (decf depth)
           (%advance state)
           (%advance state))
          (t (%advance state))))
      (if (plusp depth)
          (%diagnose state "IK006" "Unterminated block comment."
                     start-byte start-line start-column
                     :hint "Close the comment with |#.")
          (push (make-syntax-comment
                 :style :block
                 :text (subseq (%lexer-state-text state) body-start
                               (- (%lexer-state-index state) 2))
                 :span (%span-from state start-byte start-line start-column))
                (%lexer-state-comments state))))))

(defun %skip-trivia (state limits)
  (loop
    (cond
      ((%whitespacep (%peek state)) (%advance state))
      ((and (%peek state) (char= (%peek state) #\;))
       (%consume-line-comment state))
      ((and (%peek state)
            (char= (%peek state) #\#)
            (%peek state 1)
            (char= (%peek state 1) #\|))
       (%consume-block-comment state limits))
      (t (return)))))

(defun %append-string-character (buffer character)
  (vector-push-extend character buffer))

(defun %read-hex-escape (state digits start-byte start-line start-column)
  (let ((characters (make-string-output-stream))
        (valid t))
    (dotimes (index digits)
      (declare (ignorable index))
      (let ((character (%peek state)))
        (unless character
          (setf valid nil)
          (return))
        (%advance state)
        (write-char character characters)
        (unless (%ascii-hex-digit-p character)
          (setf valid nil))))
    (let ((text (get-output-stream-string characters)))
      (if (and valid (= (length text) digits))
          (let ((code-point (parse-integer text :radix 16)))
            (if (%unicode-scalar-code-point-p code-point)
                ;; CODE-CHAR is only called after scalar validation.  This
                ;; avoids implementation-specific handling of surrogates and
                ;; out-of-range values.
                (or (code-char code-point)
                    (progn
                      (%diagnose state "IK004"
                                 "String escape is not representable by this Common Lisp implementation."
                                 start-byte start-line start-column)
                      nil))
                (progn
                  (%diagnose state "IK004" "String escape is not a Unicode scalar value."
                             start-byte start-line start-column
                             :hint "Use a code point from U+0000 through U+10FFFF, excluding surrogates.")
                  nil)))
          (progn
            (%diagnose state "IK004" "Invalid Unicode string escape."
                       start-byte start-line start-column
                       :hint "Use exactly four or eight hexadecimal digits.")
            nil)))))

(defun %consume-string (state limits)
  (%with-start (state start-index start-byte start-line start-column)
    (%advance state)                    ; opening quote
    (let ((characters (make-array 32 :element-type 'character
                                  :adjustable t :fill-pointer 0))
          (valid t)
          (closed nil))
      (loop until (%at-end-p state) do
        (let ((character (%peek state)))
          (cond
            ((char= character #\")
             (%advance state)
             (setf closed t)
             (return))
            ((char= character #\\)
             (%advance state)
             (let ((escape (%peek state)))
               (if (null escape)
                   (setf valid nil)
                   (progn
                     (%advance state)
                     (let ((decoded
                             (case escape
                               (#\" #\")
                               (#\\ #\\)
                               (#\n #\Newline)
                               (#\r #\Return)
                               (#\t #\Tab)
                               (#\b (code-char 8))
                               (#\f (code-char 12))
                               (#\u (%read-hex-escape state 4 start-byte
                                                       start-line start-column))
                               (#\U (%read-hex-escape state 8 start-byte
                                                       start-line start-column))
                               (otherwise
                                (%diagnose state "IK004" "Invalid string escape."
                                           start-byte start-line start-column
                                           :hint "Use \\, \\\", \\n, \\r, \\t, \\uXXXX, or \\UXXXXXXXX.")
                                nil))))
                       (if decoded
                           (%append-string-character characters decoded)
                           (setf valid nil)))))))
            (t
             (%advance state)
             (if (%unicode-scalar-character-p character)
                 (%append-string-character characters character)
                 (progn
                   (%diagnose state "IK009"
                              "String literal contains a non-Unicode-scalar character."
                              start-byte start-line start-column)
                   (setf valid nil)))))))
      (unless closed
        (setf valid nil)
        (%diagnose state "IK003" "Unterminated string literal."
                   start-byte start-line start-column
                   :hint "Close the string with a double quote."))
      (if (%token-too-large-p state start-byte limits)
          (%diagnose state "IK002" "Token exceeds the configured byte limit."
                     start-byte start-line start-column)
          (when valid
            (%emit-token state :string
                         (subseq (%lexer-state-text state) start-index
                                 (%lexer-state-index state))
                         (coerce characters 'string)
                         start-byte start-line start-column)))
      (unless (and valid
                   (not (%token-too-large-p state start-byte limits)))
        (%emit-invalid-token state start-index start-byte start-line
                             start-column)))))

(defun %consume-identifier (state limits &key keyword)
  (%with-start (state start-index start-byte start-line start-column)
    (when keyword (%advance state))
    (loop while (%identifier-continue-p (%peek state)) do (%advance state))
    (let ((text (subseq (%lexer-state-text state) start-index
                        (%lexer-state-index state))))
      (if (%token-too-large-p state start-byte limits)
          (progn
            (%diagnose state "IK002" "Token exceeds the configured byte limit."
                       start-byte start-line start-column)
            (%emit-invalid-token state start-index start-byte start-line
                                 start-column))
          (%emit-token state (if keyword :keyword :identifier) text
                       (if keyword (subseq text 1) text)
                       start-byte start-line start-column)))))

(defun %consume-number (state limits &key negative)
  (%with-start (state start-index start-byte start-line start-column)
    (when negative (%advance state))
    (loop while (%ascii-digit-p (%peek state))
          do (%advance state))
    ;; A number followed by identifier punctuation would otherwise smuggle a
    ;; float, ratio-like spelling, or implementation-specific numeric syntax.
    (let ((malformed (%identifier-continue-p (%peek state))))
      (loop while (%identifier-continue-p (%peek state)) do (%advance state))
      (let ((text (subseq (%lexer-state-text state) start-index
                          (%lexer-state-index state))))
        (cond
          ((%token-too-large-p state start-byte limits)
           (%diagnose state "IK002" "Token exceeds the configured byte limit."
                      start-byte start-line start-column)
           (%emit-invalid-token state start-index start-byte start-line
                                start-column))
          ((or negative malformed)
           (%diagnose state "IK007"
                      "Only non-negative decimal integer literals are permitted."
                      start-byte start-line start-column)
           (%emit-invalid-token state start-index start-byte start-line
                                start-column))
          (t
           (%emit-token state :integer text (parse-integer text :radix 10)
                        start-byte start-line start-column)))))))

(defun %consume-invalid-character (state)
  (%with-start (state start-index start-byte start-line start-column)
    (let ((character (%advance state)))
      (%diagnose state "IK005"
                 (format nil "Character ~S is not permitted in Ivory Key source."
                         character)
                 start-byte start-line start-column)
      (%emit-invalid-token state start-index start-byte start-line start-column))))

(defun %validate-limits (limits)
  (unless (typep limits 'syntax-limits)
    (error 'type-error :datum limits :expected-type 'syntax-limits))
  limits)

(defun %invalid-source-character-result (source character-index)
  "Return one stable diagnostic for a programmatically supplied invalid char."
  (let* ((text (source-file-text source))
         (prefix (subseq text 0 character-index))
         (byte-offset (%utf8-string-byte-count prefix))
         (line 1)
         (column 1))
    (loop for previous across prefix do
      (if (or (char= previous #\Return) (char= previous #\Newline))
          (progn (incf line) (setf column 1))
          (incf column)))
    (let ((span (make-source-span :source source
                                  :start-byte byte-offset :end-byte byte-offset
                                  :start-line line :start-column column
                                  :end-line line :end-column column)))
      (make-syntax-lex-result
       :tokens (list (make-syntax-token :kind :eof :text "" :value nil :span span))
       :diagnostics
       (list (make-diagnostic :code "IK009"
                              :message "Source contains a non-Unicode-scalar character."
                              :span span
                              :hint "Supply source decoded as valid UTF-8 Unicode scalar values."))
       :comments nil))))

(defun %first-non-scalar-character-index (text)
  (position-if-not #'%unicode-scalar-character-p text))

(defun lex-source (source &key (limits *default-syntax-limits*))
  "Lex SOURCE into only the safe, declarative Ivory Key token vocabulary.

The result always carries diagnostics instead of entering the debugger for
layout mistakes.  No host reader operation is used anywhere in this path."
  (check-type source source-file)
  (%validate-limits limits)
  (let* ((text (source-file-text source))
         (invalid-character-index (%first-non-scalar-character-index text))
         (state (%make-lexer-state :source source :text text :limits limits)))
    (when invalid-character-index
      (return-from lex-source
        (%invalid-source-character-result source invalid-character-index)))
    (when (> (%utf8-string-byte-count text) (syntax-limits-max-bytes limits))
      (let ((span (make-source-span :source source
                                    :start-byte 0 :end-byte 0
                                    :start-line 1 :start-column 1
                                    :end-line 1 :end-column 1)))
        (return-from lex-source
          (make-syntax-lex-result
           :tokens (list (make-syntax-token :kind :eof :text "" :value nil
                                             :span span))
           :diagnostics
           (list (make-diagnostic
                  :code "IK001"
                  :message "Input exceeds the configured byte limit."
                  :span span
                  :hint "Raise the parser input limit only for trusted input."))
           :comments nil))))
    (loop until (%at-end-p state) do
      (%skip-trivia state limits)
      (unless (%at-end-p state)
        (when (>= (%lexer-state-token-count state)
                  (syntax-limits-max-tokens limits))
          (%diagnose state "IK011" "Input exceeds the configured token limit."
                     (%lexer-state-byte state) (%lexer-state-line state)
                     (%lexer-state-column state)
                     :hint "Raise the parser token limit only for trusted input.")
          (return))
        (let ((character (%peek state)))
          (cond
            ((char= character #\()
             (%with-start (state start-index start-byte start-line start-column)
               (%advance state)
               (%emit-token state :left-paren
                            (subseq text start-index (%lexer-state-index state))
                            nil start-byte start-line start-column)))
            ((char= character #\))
             (%with-start (state start-index start-byte start-line start-column)
               (%advance state)
               (%emit-token state :right-paren
                            (subseq text start-index (%lexer-state-index state))
                            nil start-byte start-line start-column)))
            ((char= character #\") (%consume-string state limits))
            ((%ascii-digit-p character) (%consume-number state limits))
            ((and (char= character #\-)
                  (%ascii-digit-p (%peek state 1)))
             (%consume-number state limits :negative t))
            ((char= character #\:)
             (%with-start (state start-index start-byte start-line start-column)
               (if (%identifier-start-p (%peek state 1))
                   (%consume-identifier state limits :keyword t)
                   (progn
                     (%advance state)
                     (%diagnose state "IK005" "A keyword needs an identifier after ':'."
                                start-byte start-line start-column)
                     (%emit-invalid-token state start-index start-byte start-line
                                          start-column)))))
            ((%identifier-start-p character) (%consume-identifier state limits))
            (t (%consume-invalid-character state))))))
    (%emit-token state :eof "" nil (%lexer-state-byte state)
                 (%lexer-state-line state) (%lexer-state-column state))
    (make-syntax-lex-result
     :tokens (nreverse (%lexer-state-tokens state))
     :diagnostics (diagnostics-in-source-order
                   (nreverse (%lexer-state-diagnostics state)))
     :comments (nreverse (%lexer-state-comments state)))))
