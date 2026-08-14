;;;; SPDX-License-Identifier: GPL-3.0-or-later

(in-package #:ivory-key.syntax)

(defun %escape-string (string)
  (with-output-to-string (stream)
    (write-char #\" stream)
    (loop for character across string
          for code = (char-code character)
          do (unless (%unicode-scalar-character-p character)
               (error "Cannot format a non-Unicode-scalar string character."))
             (case character
               (#\" (write-string "\\\"" stream))
               (#\\ (write-string "\\\\" stream))
               (#\Newline (write-string "\\n" stream))
               (#\Return (write-string "\\r" stream))
               (#\Tab (write-string "\\t" stream))
               (otherwise
                (cond
                  ((or (< code #x20) (= code #x7F))
                   (if (<= code #xFFFF)
                       (format stream "\\u~4,'0X" code)
                       (format stream "\\U~8,'0X" code)))
                  (t (write-char character stream))))))
    (write-char #\" stream)))

(defun %format-atom (atom)
  (case (syntax-atom-kind atom)
    ((:identifier :keyword) (syntax-atom-text atom))
    (:integer (format nil "~D" (syntax-atom-value atom)))
    (:string (%escape-string (syntax-atom-value atom)))
    (otherwise
     (error "Cannot format unknown Ivory Key atom kind ~S."
            (syntax-atom-kind atom)))))

(defun %inline-syntax (node)
  (etypecase node
    (syntax-atom (%format-atom node))
    (syntax-list
     (with-output-to-string (stream)
       (write-char #\( stream)
       (loop for child in (syntax-list-children node)
             for firstp = t then nil
             do (unless firstp (write-char #\Space stream))
                (write-string (%inline-syntax child) stream))
       (write-char #\) stream)))))

(defun %contains-list-p (node)
  (and (typep node 'syntax-list)
       (some (lambda (child) (typep child 'syntax-list))
             (syntax-list-children node))))

(defun %write-indent (stream count)
  (loop repeat count do (write-char #\Space stream)))

(defun %write-syntax (node stream indent width)
  (let ((inline (%inline-syntax node)))
    (if (or (typep node 'syntax-atom)
            (not (%contains-list-p node))
            (<= (+ indent (length inline)) width))
        (write-string inline stream)
        (let ((children (syntax-list-children node)))
          (write-char #\( stream)
          (when children
            ;; A list's head shares its line; its remaining children each own
            ;; a line.  That rule is small, deterministic, and works for both
            ;; declarations and nested behavior expressions.
            (%write-syntax (first children) stream (1+ indent) width)
            (dolist (child (rest children))
              (terpri stream)
              (%write-indent stream (+ indent 2))
              (%write-syntax child stream (+ indent 2) width))
            (terpri stream)
            (%write-indent stream indent))
          (write-char #\) stream)))))

(defun format-syntax (node &key (width 88))
  "Return a canonical serialization of one concrete syntax NODE.

WIDTH changes line wrapping only.  It never changes the tree that reparses.
Comments are not nodes; use FORMAT-PARSE-RESULT to retain them."
  (check-type width (integer 20 *))
  (with-output-to-string (stream)
    (%write-syntax node stream 0 width)))

(defun %write-comment (comment stream)
  (case (syntax-comment-style comment)
    (:line
     (write-char #\; stream)
     (write-string (syntax-comment-text comment) stream))
    (:block
     (write-string "#|" stream)
     (write-string (syntax-comment-text comment) stream)
     (write-string "|#" stream))
    (otherwise
     (error "Unknown comment style ~S." (syntax-comment-style comment)))))

(defun format-parse-result (result &key (width 88) (preserve-comments t))
  "Format a successful parse RESULT into canonical Ivory Key source.

Comments are retained in source order in a leading comment block.  Concrete
syntax currently does not associate comments with individual nodes, so moving
them is preferable to silently deleting them; comments do not affect semantic
round trips."
  (check-type result syntax-parse-result)
  (unless (syntax-parse-result-complete-p result)
    (error 'ivory-key-syntax-error
           :diagnostics (syntax-parse-result-diagnostics result)))
  (with-output-to-string (stream)
    (let ((comments (and preserve-comments
                         (syntax-parse-result-comments result)))
          (forms (syntax-parse-result-forms result)))
      (dolist (comment comments)
        (%write-comment comment stream)
        (terpri stream))
      (when (and comments forms) (terpri stream))
      (loop for form in forms
            for firstp = t then nil
            do (unless firstp (terpri stream))
               (%write-syntax form stream 0 width))
      (when forms (terpri stream)))))

(defun format-source (source &key (name "<string>")
                                 (limits *default-syntax-limits*)
                                 (width 88)
                                 (require-header t)
                                 (preserve-comments t))
  "Parse and canonically format SOURCE.

SOURCE may be a string, SOURCE-FILE, or successful SYNTAX-PARSE-RESULT.
Malformed input signals one aggregate IVORY-KEY-SYNTAX-ERROR rather than
returning a partially reformatted file."
  (let ((result
          (etypecase source
            (string (parse-string source :name name :limits limits
                                  :require-header require-header))
            (source-file (parse-source source :limits limits
                                       :require-header require-header))
            (syntax-parse-result source))))
    (format-parse-result result :width width :preserve-comments preserve-comments)))
