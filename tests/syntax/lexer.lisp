;;;; SPDX-License-Identifier: GPL-3.0-or-later

(in-package #:ivory-key.tests.syntax)

(defun diagnostic-codes (diagnostics)
  (mapcar #'diagnostic-code diagnostics))

(defun non-eof-tokens (lexed)
  (remove :eof (syntax-lex-result-tokens lexed)
          :key #'syntax-token-kind))

(deftest lexer-accepts-only-safe-token-kinds
  (let* ((lexed (lex-source
                 (make-source-file
                  :name "safe.ivory"
                  :text (format nil
                                "(ivory-key 1) ; keep this~%(axis case (:states plain shifted))~%"))))
         (tokens (non-eof-tokens lexed)))
    (is (null (syntax-lex-result-diagnostics lexed)))
    (is-equal '(:left-paren :identifier :integer :right-paren
                :left-paren :identifier :identifier :left-paren :keyword
                :identifier :identifier :right-paren :right-paren)
              (mapcar #'syntax-token-kind tokens))
    (is-equal "states" (syntax-token-value (nth 8 tokens)))
    (is-equal 1 (length (syntax-lex-result-comments lexed)))
    (is-equal :line (syntax-comment-style
                      (first (syntax-lex-result-comments lexed))))
    (is-equal " keep this" (syntax-comment-text
                              (first (syntax-lex-result-comments lexed))))))

(deftest lexer-accepts-a-multiline-file-ending-in-a-newline
  (let ((lexed (lex-source
                (make-source-file
                 :text (format nil "(ivory-key 1)~%; comment~%(binding q (unicode \"q\"))~%")))))
    (is (null (syntax-lex-result-diagnostics lexed)))
    (is-equal 1 (length (syntax-lex-result-comments lexed)))
    (is-equal :line (syntax-comment-style
                       (first (syntax-lex-result-comments lexed))))))

(deftest lexer-uses-utf8-byte-offsets-for-spans
  (let* ((lexed (lex-source
                 (make-source-file :name "unicode.ivory"
                                   :text "(ivory-key 1) (unicode \"θ\")")))
         (string-token (find :string (non-eof-tokens lexed)
                             :key #'syntax-token-kind))
         (span (syntax-token-span string-token)))
    (is-equal "θ" (syntax-token-value string-token))
    ;; The string token includes its quotes: byte 23 through byte 27.
    (is-equal 23 (source-span-start-byte span))
    (is-equal 27 (source-span-end-byte span))))

(deftest lexer-rejects-reader-dispatch-and-negative-numbers
  (let ((reader-dispatch (lex-source
                          (make-source-file :text "#.(progn (error \"no\"))")))
        (negative (lex-source
                   (make-source-file :text "-1"))))
    (is (member "IK005" (diagnostic-codes
                           (syntax-lex-result-diagnostics reader-dispatch))
                :test #'string=))
    (is (member "IK007" (diagnostic-codes
                           (syntax-lex-result-diagnostics negative))
                :test #'string=))))

(deftest lexer-accepts-unicode-escapes-without-reader-help
  (let* ((lexed (lex-source
                 (make-source-file :text "\"\\u03B8\\U0001F642\"")))
         (token (first (non-eof-tokens lexed))))
    (is (null (syntax-lex-result-diagnostics lexed)))
    (is-equal "θ🙂" (syntax-token-value token))))

(deftest lexer-rejects-non-scalar-unicode-escapes
  (dolist (escape '("\\uD800" "\\uDFFF" "\\U00110000"))
    (let ((lexed (lex-source
                  (make-source-file :text (format nil "\"~A\"" escape)))))
      (is (member "IK004" (diagnostic-codes
                            (syntax-lex-result-diagnostics lexed))
                  :test #'string=)))))

(deftest lexer-uses-ascii-only-identifiers-for-portability
  (let ((lexed (lex-source (make-source-file :text "lambda λ"))))
    (is-equal '(:identifier :invalid)
              (mapcar #'syntax-token-kind (non-eof-tokens lexed)))
    (is (member "IK005" (diagnostic-codes
                          (syntax-lex-result-diagnostics lexed))
                :test #'string=))))

(deftest lexer-supports-nested-block-comments
  (let ((lexed (lex-source
                (make-source-file :text "#| outer #| inner |# tail |# answer"))))
    (is (null (syntax-lex-result-diagnostics lexed)))
    (is-equal 1 (length (syntax-lex-result-comments lexed)))
    (is-equal :block (syntax-comment-style
                       (first (syntax-lex-result-comments lexed))))
    (is-equal "answer" (syntax-token-value
                          (first (non-eof-tokens lexed))))))

(deftest lexer-enforces-configurable-resource-limits
  (let ((lexed (lex-source
                (make-source-file :text "(ivory-key 1)")
                :limits (make-syntax-limits :max-bytes 8))))
    (is-equal '("IK001") (diagnostic-codes
                            (syntax-lex-result-diagnostics lexed)))))

(deftest lexer-bounds-token-comment-and-diagnostic-growth
  (let ((token-limited
          (lex-source
           (make-source-file :text "a b c d")
           :limits (make-syntax-limits :max-tokens 3)))
        (comment-limited
          (lex-source
           (make-source-file :text "#| #| #| nested |# |# |#")
           :limits (make-syntax-limits :max-depth 2)))
        (diagnostic-limited
          (lex-source
           (make-source-file :text "# # # # #")
           :limits (make-syntax-limits :max-diagnostics 3))))
    (is-equal 3 (length (non-eof-tokens token-limited)))
    (is (member "IK011" (diagnostic-codes
                          (syntax-lex-result-diagnostics token-limited))
                :test #'string=))
    (is (member "IK008" (diagnostic-codes
                          (syntax-lex-result-diagnostics comment-limited))
                :test #'string=))
    (is-equal 3 (length (syntax-lex-result-diagnostics diagnostic-limited)))
    (is-equal "IK010" (car (last (diagnostic-codes
                                   (syntax-lex-result-diagnostics
                                    diagnostic-limited)))))))
