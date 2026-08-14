;;;; SPDX-License-Identifier: GPL-3.0-or-later

(in-package #:ivory-key.tests.syntax)

(deftest parser-builds-string-backed-safe-concrete-forms
  (let* ((result (parse-string
                  (format nil "(ivory-key 1)~%(binding q (at (plain roman base) (unicode \"q\")))")))
         (header (first (syntax-parse-result-forms result)))
         (header-name (first (syntax-list-children header))))
    (is (syntax-parse-result-complete-p result))
    (is-equal 1 (syntax-parse-result-language-version result))
    (is-equal :identifier (syntax-atom-kind header-name))
    (is-equal "ivory-key" (syntax-atom-value header-name))
    (is-equal 2 (length (syntax-parse-result-forms result)))))

(deftest parser-requires-the-explicit-language-envelope
  (let ((missing (parse-string "(axis case (:states plain shifted))"))
        (wrong (parse-string "(ivory-key 2)")))
    (is-equal '("IK102") (diagnostic-codes
                            (syntax-parse-result-diagnostics missing)))
    (is-equal '("IK103") (diagnostic-codes
                            (syntax-parse-result-diagnostics wrong)))))

(deftest parser-recovers-after-a-common-parenthesis-error
  (let ((result (parse-string "(ivory-key 1) ) (axis case (:states plain shifted))")))
    (is (member "IK100" (diagnostic-codes
                           (syntax-parse-result-diagnostics result))
                :test #'string=))
    (is-equal 2 (length (syntax-parse-result-forms result)))))

(deftest parser-reports-an-unterminated-list-with-a-stable-code
  (let ((result (parse-string "(ivory-key 1) (binding q")))
    (is (member "IK101" (diagnostic-codes
                           (syntax-parse-result-diagnostics result))
                :test #'string=))))

(deftest parser-bounds-nesting-without-host-reader-recursion
  (let ((result (parse-string "(a (b (c)))" :require-header nil
                              :limits (make-syntax-limits :max-depth 2))))
    (is (member "IK008" (diagnostic-codes
                           (syntax-parse-result-diagnostics result))
                :test #'string=))))

(deftest parser-signals-an-aggregate-condition-only-on-request
  (signals ivory-key-syntax-error
    (parse-source-or-signal
     (make-source-file :text "(ivory-key 1"))))

(deftest parser-fuzz-smoke-terminates-on-arbitrary-ascii
  (let ((seed 17))
    (loop repeat 128 do
      (let ((text
              (with-output-to-string (stream)
                (loop repeat 64 do
                  (setf seed (mod (+ (* seed 1103515245) 12345) 2147483648))
                  (write-char (code-char (mod seed 128)) stream)))))
        (is (syntax-parse-result-p
             (parse-string text :require-header nil)))))))

(deftest parser-remains-linear-over-many-small-forms
  (let* ((count 4000)
         (text (with-output-to-string (stream)
                 (loop repeat count do (write-string "(a)" stream))))
         (result (parse-string text :require-header nil
                                     :limits (make-syntax-limits
                                              :max-tokens (* count 3)))))
    (is (syntax-parse-result-complete-p result))
    (is-equal count (length (syntax-parse-result-forms result)))))

(deftest parser-bounds-structural-diagnostic-growth
  (let ((result (parse-string ")))))" :require-header nil
                              :limits (make-syntax-limits :max-diagnostics 3))))
    (is-equal 3 (length (syntax-parse-result-diagnostics result)))
    (is-equal "IK010"
              (car (last (diagnostic-codes
                          (syntax-parse-result-diagnostics result)))))))

(deftest parser-gates-file-size-before-utf8-decoding
  (let* ((pathname
           (merge-pathnames
            (format nil "ivory-key-parser-limit-~36R-~36R.ivory"
                    (get-universal-time) (random most-positive-fixnum))
            (uiop:temporary-directory))))
    (unwind-protect
         (progn
           (with-open-file (stream pathname :direction :output
                                           :element-type '(unsigned-byte 8)
                                           :if-exists :error
                                           :if-does-not-exist :create)
             (loop repeat 64 do (write-byte (char-code #\A) stream)))
           (is-equal '("IK001")
                     (diagnostic-codes
                      (syntax-parse-result-diagnostics
                       (ivory-key.syntax:parse-file
                        pathname :limits (make-syntax-limits :max-bytes 8))))))
      (when (probe-file pathname)
        (delete-file pathname)))))

(deftest parser-reports-malformed-utf8-as-a-diagnostic
  (let* ((pathname
           (merge-pathnames
            (format nil "ivory-key-parser-utf8-~36R-~36R.ivory"
                    (get-universal-time) (random most-positive-fixnum))
            (uiop:temporary-directory))))
    (unwind-protect
         (progn
           (with-open-file (stream pathname :direction :output
                                           :element-type '(unsigned-byte 8)
                                           :if-exists :error
                                           :if-does-not-exist :create)
             ;; A leading byte cannot begin a UTF-8 sequence, regardless of
             ;; locale or host reader settings.
             (write-byte #xFF stream))
           (is-equal '("IK009")
                     (diagnostic-codes
                      (syntax-parse-result-diagnostics
                       (ivory-key.syntax:parse-file pathname)))))
      (when (probe-file pathname)
        (delete-file pathname)))))
