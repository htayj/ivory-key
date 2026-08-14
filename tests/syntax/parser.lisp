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

(defparameter *parser-source-evaluation-sentinel* nil
  "Test-only sentinel proving byte-oriented input is never reader-evaluated.")

(defun parser-test-pathname (label)
  (merge-pathnames
   (format nil "ivory-key-~A-~36R-~36R.ivory"
           label (get-universal-time) (random most-positive-fixnum))
   (uiop:temporary-directory)))

(defun parser-write-octets (pathname octets)
  (with-open-file (stream pathname :direction :output
                                  :element-type '(unsigned-byte 8)
                                  :if-exists :supersede
                                  :if-does-not-exist :create)
    (map nil (lambda (octet) (write-byte octet stream)) octets))
  pathname)

(defun parser-deterministic-octets (seed count)
  "Generate COUNT raw octets from a fixed, implementation-independent LCG."
  (let ((state seed)
        (octets (make-array count :element-type '(unsigned-byte 8))))
    (dotimes (index count octets)
      (setf state (mod (+ (* state 1664525) 1013904223) #x100000000)
            (aref octets index) (ldb (byte 8 16) state)))))

(defun parser-generated-nested-form (seed depth)
  "Produce one deterministic, syntactically valid nested source form."
  (let ((state seed))
    (with-output-to-string (stream)
      (loop repeat depth do
        (setf state (mod (+ (* state 1103515245) 12345) #x80000000))
        (format stream "(node-~D " (mod state 97)))
      (format stream "leaf-~D" (mod state 97))
      (loop repeat depth do (write-char #\) stream)))))

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

(deftest parser-fuzzes-arbitrary-raw-file-octets-without-evaluation
  "Raw byte input must terminate with repeatable diagnostics, never READ/EVAL."
  (let ((pathname (parser-test-pathname "raw-byte-fuzz"))
        (limits (make-syntax-limits :max-bytes 128 :max-diagnostics 8)))
    (unwind-protect
         (progn
           (loop for seed from 1 to 32
                 for octets = (parser-deterministic-octets seed
                                                            (+ 17 (mod seed 79)))
                 do (parser-write-octets pathname octets)
                    (let ((first (ivory-key.syntax:parse-file
                                  pathname :limits limits :require-header nil))
                          (second (ivory-key.syntax:parse-file
                                   pathname :limits limits :require-header nil)))
                      (is (syntax-parse-result-p first))
                      (is (syntax-parse-result-p second))
                      (is-equal (diagnostic-codes
                                 (syntax-parse-result-diagnostics first))
                                (diagnostic-codes
                                 (syntax-parse-result-diagnostics second)))))
           ;; This reader-dispatch payload is deliberately written as bytes.
           ;; A host reader would mutate the sentinel; the Ivory Key reader
           ;; instead reports it as invalid syntax.
           (setf *parser-source-evaluation-sentinel* nil)
           (parser-write-octets
            pathname
            (map 'vector #'char-code
                 "#.(setf ivory-key.tests.syntax::*parser-source-evaluation-sentinel* t)"))
           (let ((result (ivory-key.syntax:parse-file pathname :limits limits
                                                       :require-header nil)))
             (is (member "IK005"
                         (diagnostic-codes
                          (syntax-parse-result-diagnostics result))
                         :test #'string=))
             (is (null *parser-source-evaluation-sentinel*))))
      (when (probe-file pathname)
        (delete-file pathname)))))

(deftest parser-fuzzes-generated-nesting-under-depth-and-size-limits
  "Generated nested forms must remain bounded with stable depth/size diagnostics."
  (loop for seed from 1 to 32
        for depth = (+ 4 (mod (* seed 7) 29))
        for source = (parser-generated-nested-form seed depth)
        for ordinary-limits = (make-syntax-limits :max-bytes 4096 :max-depth 64)
        for depth-limits = (make-syntax-limits :max-bytes 4096
                                                :max-depth (1- depth))
        for size-limits = (make-syntax-limits :max-bytes (1- (length source))
                                               :max-depth 64)
        do (let ((first (parse-string source :require-header nil
                                      :limits ordinary-limits))
                 (second (parse-string source :require-header nil
                                       :limits ordinary-limits))
                 (depth-first (parse-string source :require-header nil
                                            :limits depth-limits))
                 (depth-second (parse-string source :require-header nil
                                             :limits depth-limits))
                 (size-first (parse-string source :require-header nil
                                           :limits size-limits))
                 (size-second (parse-string source :require-header nil
                                            :limits size-limits)))
             (is (syntax-parse-result-complete-p first))
             (is-equal (diagnostic-codes (syntax-parse-result-diagnostics first))
                       (diagnostic-codes (syntax-parse-result-diagnostics second)))
             (is (member "IK008"
                         (diagnostic-codes (syntax-parse-result-diagnostics depth-first))
                         :test #'string=))
             (is-equal (diagnostic-codes (syntax-parse-result-diagnostics depth-first))
                       (diagnostic-codes (syntax-parse-result-diagnostics depth-second)))
             (is-equal '("IK001")
                       (diagnostic-codes (syntax-parse-result-diagnostics size-first)))
             (is-equal (diagnostic-codes (syntax-parse-result-diagnostics size-first))
                       (diagnostic-codes (syntax-parse-result-diagnostics size-second))))))

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
