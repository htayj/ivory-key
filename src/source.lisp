;;;; SPDX-License-Identifier: GPL-3.0-or-later

(in-package #:ivory-key.source)

;;; Layout input is decoded as UTF-8 by PARSE-FILE.  Byte offsets are therefore
;;; UTF-8 byte offsets, zero based and half open; lines and columns are one
;;; based and columns count Common Lisp characters.  The latter makes locations
;;; useful to people even when a character occupies more than one UTF-8 byte.

(defstruct (source-file
            (:constructor make-source-file (&key (name "<string>")
                                                  (text ""))))
  (name "<string>" :type string :read-only t)
  (text "" :type string :read-only t))

(defstruct (source-span
            (:constructor make-source-span
                (&key source
                      (start-byte 0)
                      (end-byte 0)
                      (start-line 1)
                      (start-column 1)
                      (end-line 1)
                      (end-column 1)
                      import-stack)))
  "A half-open source range.  IMPORT-STACK contains outer import-site spans."
  source
  (start-byte 0 :type integer :read-only t)
  (end-byte 0 :type integer :read-only t)
  (start-line 1 :type integer :read-only t)
  (start-column 1 :type integer :read-only t)
  (end-line 1 :type integer :read-only t)
  (end-column 1 :type integer :read-only t)
  (import-stack nil :type list :read-only t))

(defun source-span= (left right)
  "Compare source locations, including import provenance."
  (and (typep left 'source-span)
       (typep right 'source-span)
       (eq (source-span-source left) (source-span-source right))
       (= (source-span-start-byte left) (source-span-start-byte right))
       (= (source-span-end-byte left) (source-span-end-byte right))
       (= (source-span-start-line left) (source-span-start-line right))
       (= (source-span-start-column left) (source-span-start-column right))
       (= (source-span-end-line left) (source-span-end-line right))
       (= (source-span-end-column left) (source-span-end-column right))
       (equal (source-span-import-stack left)
              (source-span-import-stack right))))

(defun source-span-merge (first last)
  "Return a span beginning at FIRST and ending at LAST.

Both spans must come from the same source and import context.  Merging spans
from different files would make diagnostics lie, so this is an ordinary
programmer error rather than a recoverable layout diagnostic."
  (check-type first source-span)
  (check-type last source-span)
  (unless (and (eq (source-span-source first) (source-span-source last))
               (equal (source-span-import-stack first)
                      (source-span-import-stack last)))
    (error "Cannot merge source spans from different sources or import stacks."))
  (make-source-span :source (source-span-source first)
                    :start-byte (source-span-start-byte first)
                    :end-byte (source-span-end-byte last)
                    :start-line (source-span-start-line first)
                    :start-column (source-span-start-column first)
                    :end-line (source-span-end-line last)
                    :end-column (source-span-end-column last)
                    :import-stack (source-span-import-stack first)))

(defun source-span-location-string (span)
  "Render the start of SPAN in a concise, implementation-independent form."
  (check-type span source-span)
  (let ((source (source-span-source span)))
    (format nil "~A:~D:~D"
            (if source (source-file-name source) "<unknown>")
            (source-span-start-line span)
            (source-span-start-column span))))
