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

;;; Semantic-model provenance ------------------------------------------------

;; The concrete parser owns SOURCE-SPAN.  Semantic objects need one additional
;; layer when a finite template body is materialized at one or more source
;; sites: the body keeps its declaration span and records each reference crossed
;; while reaching the concrete object.  Keep this data here, rather than in an
;; identity side table, so an allocator or diagnostic writer can consume the
;; typed IR long after the parser and decoder have returned.

(defstruct (source-origin
             (:constructor %make-source-origin (definition-span use-spans))
             (:copier nil)
             (:conc-name %source-origin-))
  "Immutable-by-convention provenance for one semantic IR object.

DEFINITION-SPAN identifies the concrete declaration or body form that supplied
the object.  USE-SPANS are ordered from the definition-nearest template use to
the outermost materializing use.  They are source spans, not pathnames or host
objects, so this record neither requires nor derives a physical checkout path.
"
  (definition-span nil :type (or null source-span) :read-only t)
  (use-spans nil :type list :read-only t))

(defun make-source-origin (&key definition-span use-spans)
  "Create immutable-by-convention semantic provenance.

Both fields are optional so programmatic model construction can remain
deliberately source-free.  The use list is copied on construction and returned
as a fresh list by SOURCE-ORIGIN-USE-SPANS; callers therefore cannot mutate an
origin's recorded template path through the public protocol.
"
  (when definition-span
    (check-type definition-span source-span))
  (dolist (span use-spans)
    (check-type span source-span))
  (%make-source-origin definition-span (copy-list use-spans)))

(defun source-origin-definition-span (origin)
  "Return ORIGIN's declaration/body span, or NIL for programmatic IR."
  (check-type origin source-origin)
  (%source-origin-definition-span origin))

(defun source-origin-use-spans (origin)
  "Return a fresh definition-nearest-to-outermost template-use span list."
  (check-type origin source-origin)
  (copy-list (%source-origin-use-spans origin)))

(defun source-origin-with-use-span (origin use-span)
  "Return a new origin with USE-SPAN appended as its outer template use."
  (check-type origin source-origin)
  (check-type use-span source-span)
  (make-source-origin
   :definition-span (%source-origin-definition-span origin)
   :use-spans (append (%source-origin-use-spans origin) (list use-span))))

(defun source-origin= (left right)
  "Compare semantic provenance without exposing mutable implementation state."
  (labels ((span= (left-span right-span)
             ;; SOURCE-SPAN= intentionally treats the concrete SOURCE-FILE
             ;; object as identity.  Origins instead need a structural value
             ;; comparison so separately parsed, byte-identical logical source
             ;; inputs have equal provenance without sharing host objects.
             (and (typep left-span 'source-span)
                  (typep right-span 'source-span)
                  (let ((left-source (source-span-source left-span))
                        (right-source (source-span-source right-span)))
                    (and (if left-source
                             (and right-source
                                  (string= (source-file-name left-source)
                                           (source-file-name right-source))
                                  (string= (source-file-text left-source)
                                           (source-file-text right-source)))
                             (null right-source))
                         (= (source-span-start-byte left-span)
                            (source-span-start-byte right-span))
                         (= (source-span-end-byte left-span)
                            (source-span-end-byte right-span))
                         (= (source-span-start-line left-span)
                            (source-span-start-line right-span))
                         (= (source-span-start-column left-span)
                            (source-span-start-column right-span))
                         (= (source-span-end-line left-span)
                            (source-span-end-line right-span))
                         (= (source-span-end-column left-span)
                            (source-span-end-column right-span))
                         (= (length (source-span-import-stack left-span))
                            (length (source-span-import-stack right-span)))
                         (every #'span=
                                (source-span-import-stack left-span)
                                (source-span-import-stack right-span)))))))
    (and (typep left 'source-origin)
         (typep right 'source-origin)
         (let ((left-definition (%source-origin-definition-span left))
               (right-definition (%source-origin-definition-span right))
               (left-uses (%source-origin-use-spans left))
               (right-uses (%source-origin-use-spans right)))
           (and (if left-definition
                    (and right-definition (span= left-definition right-definition))
                    (null right-definition))
                (= (length left-uses) (length right-uses))
                (every #'span= left-uses right-uses))))))
