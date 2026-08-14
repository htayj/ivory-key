;;;; SPDX-License-Identifier: GPL-3.0-or-later

(in-package #:ivory-key.conditions)

(define-condition ivory-key-diagnostic (condition)
  ((code :initarg :code :reader diagnostic-code)
   (severity :initarg :severity :initform :error :reader diagnostic-severity)
   (message :initarg :message :reader diagnostic-message)
   (span :initarg :span :initform nil :reader diagnostic-span)
   (related-spans :initarg :related-spans :initform nil
                  :reader diagnostic-related-spans)
   (hint :initarg :hint :initform nil :reader diagnostic-hint))
  (:report
   (lambda (condition stream)
     (format stream "~A~@[ at ~A~]: ~A"
             (diagnostic-code condition)
             (let ((span (diagnostic-span condition)))
               (and span (source-span-location-string span)))
             (diagnostic-message condition)))))

(defun make-diagnostic (&key code (severity :error) message span
                          related-spans hint)
  "Construct a diagnostic with a stable machine-readable CODE."
  (make-condition 'ivory-key-diagnostic
                  :code code
                  :severity severity
                  :message message
                  :span span
                  :related-spans related-spans
                  :hint hint))

(defun diagnostics-in-source-order (diagnostics)
  "Return DIAGNOSTICS sorted stably by their primary span.

Diagnostics without a span follow span-bearing diagnostics in their original
order.  This gives command-line clients a deterministic report order."
  (stable-sort (copy-list diagnostics)
               (lambda (left right)
                 (let ((left-span (diagnostic-span left))
                       (right-span (diagnostic-span right)))
                   (cond ((and left-span right-span)
                          (< (source-span-start-byte left-span)
                             (source-span-start-byte right-span)))
                         (left-span t)
                         (right-span nil)
                         (t nil))))))

(define-condition ivory-key-syntax-error (error)
  ((diagnostics :initarg :diagnostics :reader syntax-error-diagnostics))
  (:report
   (lambda (condition stream)
     (format stream "~D Ivory Key syntax error~:P:~%"
             (length (syntax-error-diagnostics condition)))
     (dolist (diagnostic (syntax-error-diagnostics condition))
       (format stream "  ~A~%" diagnostic)))))
