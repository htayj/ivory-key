;;;; SPDX-License-Identifier: GPL-3.0-or-later

(in-package #:ivory-key.tests.syntax)

(defun parse-format-parse (source &key (width 88))
  (let* ((first (parse-string source))
         (formatted (format-parse-result first :width width))
         (second (parse-string formatted)))
    (values first formatted second)))

(deftest formatter-is-idempotent-and-preserves-the-concrete-tree
  (multiple-value-bind (first formatted second)
      (parse-format-parse
       (format nil "(ivory-key 1)~%(define-layout manna-cadet (axis case (:states plain shifted) (:resolution product)) (binding q (at (plain roman base) (unicode \"q\"))))"))
    (is (syntax-parse-result-complete-p first))
    (is (syntax-parse-result-complete-p second))
    (is-equal (length (syntax-parse-result-forms first))
              (length (syntax-parse-result-forms second)))
    (is (every #'syntax-node-equal-p
               (syntax-parse-result-forms first)
               (syntax-parse-result-forms second)))
    (is-equal formatted (format-parse-result second))))

(deftest formatter-emits-a-safe-canonical-string-spelling
  (let ((formatted (format-source
                    "(ivory-key 1) (binding text (unicode \"quote: \\\"; slash: \\\\; newline: \\n\"))")))
    (is (search "\\\"" formatted))
    (is (search "\\\\" formatted))
    (is (search "\\n" formatted))
    (is (syntax-parse-result-complete-p (parse-string formatted)))))

(deftest formatter-keeps-comments-conservatively
  (let* ((formatted (format-source
                     (format nil "; heading~%(ivory-key 1)~%(binding q #| note |# (unicode \"q\"))")))
         (reparsed (parse-string formatted)))
    (is (search "; heading" formatted))
    (is (search "#| note |#" formatted))
    (is (syntax-parse-result-complete-p reparsed))))

(deftest formatter-wraps-without-changing-meaning
  (multiple-value-bind (first formatted second)
      (parse-format-parse
       "(ivory-key 1) (define-layout manna-cadet (binding left-pinky-home (at (plain roman base) (unicode \"a\")) (at (shifted roman base) (unicode \"A\"))))"
       :width 30)
    (is (search (string #\Newline) formatted))
    (is (every #'syntax-node-equal-p
               (syntax-parse-result-forms first)
               (syntax-parse-result-forms second)))))

(deftest formatter-refuses-to-rewrite-invalid-input
  (signals ivory-key-syntax-error
    (format-source "(ivory-key 1")))
