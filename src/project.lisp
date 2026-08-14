;;;; Ivory Key -- deterministic declarative project/module loading.
;;;; SPDX-License-Identifier: GPL-3.0-or-later

(in-package #:ivory-key.project)

;;; This is deliberately a source-language loader, not an ASDF or Common Lisp
;;; module loader.  In particular, it only passes parser nodes to decoders; it
;;; never READs, EVALs, or INTERNs anything from an Ivory Key source file.

(define-condition project-error (error)
  ((code :initarg :code :reader project-error-code)
   (message :initarg :message :reader project-error-message)
   (path :initarg :path :initform nil :reader project-error-path)
   (import-stack :initarg :import-stack :initform nil
                 :reader project-error-import-stack))
  (:report (lambda (condition stream)
             (format stream "~A~@[ in ~A~]: ~A"
                     (project-error-code condition)
                     (project-error-path condition)
                     (project-error-message condition)))))

(defstruct (project-definition
            (:constructor %make-project-definition
                (kind name form span path)))
  ;; VALUE is assigned only after every import has been collected and the
  ;; relevant registry is available.  This makes forward references
  ;; deterministic and keeps the import traversal order from becoming semantic.
  kind
  name
  form
  span
  path
  value)

(defstruct (project-load-result
            (:constructor %make-project-load-result
                (definitions layouts topologies devices output-vocabularies
                 realizations compositions source-paths)))
  definitions
  layouts
  topologies
  devices
  output-vocabularies
  realizations
  compositions
  ;; Canonical physical source names for the complete successfully loaded
  ;; import graph, including legal header-only modules with no definitions.
  source-paths)

(defstruct (project-realization-composition
            (:constructor %make-project-realization-composition
                (name layout device realization)))
  name
  layout
  device
  realization)

(defstruct (%project-load-state (:constructor %make-project-load-state))
  roots
  (active nil)
  (loaded (make-hash-table :test #'equal))
  (definitions-by-key (make-hash-table :test #'equal))
  (definitions nil))

(defstruct (%project-context (:constructor %make-project-context
                                          (path import-stack)))
  path
  import-stack)

(defun %fail (context code control &rest arguments)
  (error 'project-error
         :code code
         :message (apply #'format nil control arguments)
         :path (and context (uiop:native-namestring
                             (%project-context-path context)))
         :import-stack (and context (%project-context-import-stack context))))

(defun %span-with-import-stack (span import-stack)
  (make-source-span
   :source (source-span-source span)
   :start-byte (source-span-start-byte span)
   :end-byte (source-span-end-byte span)
   :start-line (source-span-start-line span)
   :start-column (source-span-start-column span)
   :end-line (source-span-end-line span)
   :end-column (source-span-end-column span)
   :import-stack import-stack))

(defun %annotate-node-import-stack (node import-stack)
  "Give all nodes in NODE the immutable provenance of its import chain."
  (etypecase node
    (syntax-atom
     (setf (ivory-key.syntax::syntax-atom-span node)
           (%span-with-import-stack (syntax-node-span node) import-stack)))
    (syntax-list
     ;; SYNTAX-LIST-SPAN is not part of the public parsing protocol yet, but
     ;; preserving it here is necessary for import-stack source provenance.
     (setf (ivory-key.syntax::syntax-list-span node)
           (%span-with-import-stack (syntax-node-span node) import-stack))
     (dolist (child (syntax-list-children node))
       (%annotate-node-import-stack child import-stack))))
  node)

(defun %annotate-parse-result-import-stack (parsed import-stack)
  (dolist (form (syntax-parse-result-forms parsed))
    (%annotate-node-import-stack form import-stack))
  parsed)

(defun %atom-name= (node name)
  (and (typep node 'syntax-atom)
       (eq (syntax-atom-kind node) :identifier)
       (string= (string-downcase (syntax-atom-value node)) name)))

(defun %form-name (form)
  (and (typep form 'syntax-list)
       (let ((head (first (syntax-list-children form))))
         (and (typep head 'syntax-atom)
              (member (syntax-atom-kind head) '(:identifier :keyword))
              (string-downcase (syntax-atom-value head))))))

(defun %named-form-p (form name)
  (let ((form-name (%form-name form)))
    (and form-name (string= form-name name))))

(defun %form-children (context form minimum maximum description)
  (unless (typep form 'syntax-list)
    (%fail context :malformed-project-form "Malformed ~A." description))
  (let ((children (syntax-list-children form)))
    (unless (and (<= minimum (length children))
                 (or (null maximum) (<= (length children) maximum)))
      (%fail context :malformed-project-form "Malformed ~A." description))
    children))

(defun %identifier-node-name (context node description)
  (unless (and (typep node 'syntax-atom)
               (eq (syntax-atom-kind node) :identifier))
    (%fail context :invalid-project-identifier
           "~A must be an Ivory Key identifier." description))
  ;; ENSURE-IDENTIFIER canonicalizes a string and never interns it.
  (identifier-name (ensure-identifier (syntax-atom-value node))))

(defun %string-node-value (context node description)
  (unless (and (typep node 'syntax-atom)
               (eq (syntax-atom-kind node) :string))
    (%fail context :invalid-project-string "~A must be a string." description))
  (syntax-atom-value node))

(defun %text-node-value (context node description)
  (unless (and (typep node 'syntax-atom)
               (member (syntax-atom-kind node) '(:identifier :string)))
    (%fail context :invalid-project-text
           "~A must be an identifier or string." description))
  (syntax-atom-value node))

(defun %integer-node-value (context node description)
  (unless (and (typep node 'syntax-atom)
               (eq (syntax-atom-kind node) :integer))
    (%fail context :invalid-project-integer "~A must be an integer." description))
  (syntax-atom-value node))

(defun %node->safe-value (node)
  "Copy parser data into only strings, integers, and lists for opaque metadata."
  (etypecase node
    (syntax-atom (syntax-atom-value node))
    (syntax-list (mapcar #'%node->safe-value (syntax-list-children node)))))

(defun %captured-working-directory ()
  "Return one physical working-directory base for a project load.

Relative project and root pathnames must never rely on a later dynamic default
pathname.  Capturing this once also makes all lexical confinement decisions use
the same base directory.
"
  (uiop:ensure-directory-pathname (truename (uiop:getcwd))))

(defun %absolute-pathname (pathname working-directory)
  "Resolve PATHNAME against one captured, already physical directory."
  (uiop:ensure-absolute-pathname pathname working-directory))

(defun %canonical-directory (pathname)
  (let ((directory (uiop:ensure-directory-pathname pathname)))
    (or (probe-file directory)
        (error "Unreachable source-root directory ~A." pathname))
    (uiop:ensure-directory-pathname (truename directory))))

(defun %normal-directory-components (pathname)
  "Return a lexical pathname directory with :UP components reduced.

This lets the confinement gate reject a missing `../../outside.ivory` before
attempting to read it, and complements the later physical TRUENAME check that
blocks symlink escapes."
  (let* ((directory (pathname-directory pathname))
         (marker (first directory))
         (result nil))
    (dolist (component (rest directory))
      (cond
        ((member component '(:relative :absolute :current)) nil)
        ((member component '(:up :back))
         (if result
             (pop result)
             (push :up result)))
        (t (push component result))))
    (cons marker (nreverse result))))

(defun %pathname-under-root-p (pathname root)
  (let ((candidate (%normal-directory-components pathname))
        (root-components (%normal-directory-components root)))
    (and (<= (length root-components) (length candidate))
         (equal root-components
                (subseq candidate 0 (length root-components))))))

(defun %within-source-roots-p (pathname roots)
  (some (lambda (root) (%pathname-under-root-p pathname root)) roots))

(defun %same-physical-pathname-p (left right)
  "Compare already physical paths without pathname default ambiguity."
  (string= (uiop:native-namestring left)
           (uiop:native-namestring right)))

(defun %absolute-import-p (path)
  "Reject native and Windows-looking absolute spellings on every host."
  (or (zerop (length path))
      (member (char path 0) '(#\/ #\\))
      (and (>= (length path) 2)
           (alpha-char-p (char path 0))
           (char= (char path 1) #\:))))

(defun %resolve-import (state context spelling)
  (when (%absolute-import-p spelling)
    (%fail context :absolute-import
           "IMPORT path ~S must be non-empty and relative." spelling))
  (when (or (find #\\ spelling) (find #\Newline spelling) (find #\Return spelling))
    (%fail context :unsafe-import-path
           "IMPORT path ~S contains a disallowed path character." spelling))
  (let ((candidate
          (uiop:ensure-absolute-pathname
           (merge-pathnames spelling
                            (uiop:pathname-directory-pathname
                             (%project-context-path context))))))
    (unless (%within-source-roots-p candidate (%project-load-state-roots state))
      (%fail context :import-outside-source-root
             "IMPORT path ~S escapes every configured source root." spelling))
    (unless (probe-file candidate)
      (%fail context :unreadable-import "Could not read IMPORT path ~S." spelling))
    (let ((physical (truename candidate)))
      (unless (%within-source-roots-p physical (%project-load-state-roots state))
        (%fail context :import-outside-source-root
               "IMPORT path ~S resolves through a symlink outside every source root."
               spelling))
      physical)))

(defun %parse-file-or-fail (state context)
  "Read and parse one verified project source without a path reopen.

The initial resolution and after-read TRUENAME check detect symlink target
changes and other pathname changes that remain observable through portable
Common Lisp.  The source is captured through one open stream and parsed as
text, never reopened by the parser.  Portable Common Lisp has neither file
descriptors nor O_NOFOLLOW, so source roots must not be concurrently mutable
by an untrusted principal; replacing a file at the same pathname is not
reliably distinguishable on every supported host.
"
  (let* ((expected (%project-context-path context))
         (physical
           (handler-case
               (truename expected)
             (error (condition)
               (%fail context :source-path-changed
                      "Could not re-verify source path ~A: ~A" expected condition)))))
    (unless (and (%same-physical-pathname-p expected physical)
                 (%within-source-roots-p physical
                                         (%project-load-state-roots state)))
      (%fail context :source-path-changed
             "Source path changed after confinement verification."))
    ;; File length and UTF-8 decoding occur through the same open stream.  A
    ;; separate binary measurement followed by READ-FILE-STRING would recreate
    ;; precisely the loader reopen race this boundary is meant to avoid.
    (let ((text
            (handler-case
                (with-open-file (stream physical :direction :input
                                                  :external-format :utf-8)
                  (let ((byte-length (file-length stream)))
                    (unless (and (integerp byte-length) (<= 0 byte-length))
                      (%fail context :unreadable-project-source
                             "Could not determine the size of source ~A." physical))
                    (when (> byte-length
                             (ivory-key.syntax:syntax-limits-max-bytes
                              ivory-key.syntax:*default-syntax-limits*))
                      (%fail context :project-source-too-large
                             "Source exceeds the configured parser byte limit."))
                    ;; UTF-8 cannot decode to more characters than its byte
                    ;; count, so this bounds allocation before decoding.
                    (let* ((buffer (make-string byte-length))
                           (end (read-sequence buffer stream))
                           (text (if (= end byte-length)
                                     buffer
                                     (subseq buffer 0 end))))
                      ;; If the file grew after FILE-LENGTH, do not parse a
                      ;; prefix that could accidentally be a complete source.
                      (when (read-char stream nil nil)
                        (%fail context :source-path-changed
                               "Source changed while it was being read."))
                      text)))
              (project-error (condition)
                (error condition))
              (error (condition)
                (%fail context :unreadable-project-source
                       "Could not read source ~A: ~A" physical condition)))))
      (let ((after
              (handler-case
                  (truename physical)
                (error (condition)
                  (%fail context :source-path-changed
                         "Source path changed while reading ~A: ~A"
                         physical condition)))))
        (unless (and (%same-physical-pathname-p physical after)
                     (%within-source-roots-p after
                                             (%project-load-state-roots state)))
          (%fail context :source-path-changed
                 "Source path changed while reading."))
        (let ((parsed (ivory-key.syntax:parse-string
                       text :name (uiop:native-namestring physical))))
          (unless (and (syntax-parse-result-complete-p parsed)
                       (null (syntax-parse-result-diagnostics parsed)))
            (%fail context :project-syntax-error
                   "Source did not parse cleanly: ~{~A~^, ~}."
                   (mapcar #'diagnostic-code
                           (syntax-parse-result-diagnostics parsed))))
          (%annotate-parse-result-import-stack
           parsed (%project-context-import-stack context)))))))

(defun %definition-kind-for-form (form)
  (let ((name (%form-name form)))
    (cond ((string= (or name "") "define-layout") :layout)
          ((string= (or name "") "define-topology") :topology)
          ((string= (or name "") "define-device") :device)
          ((string= (or name "") "define-output-vocabulary") :output-vocabulary)
          ((string= (or name "") "define-realization") :realization)
          ((string= (or name "") "realize") :composition)
          (t nil))))

(defun %register-definition (state context kind form)
  (let* ((children (%form-children context form 2 nil "named declaration"))
         (name (%identifier-node-name context (second children) "Declaration name"))
         (key (list kind name)))
    (when (gethash key (%project-load-state-definitions-by-key state))
      (%fail context :duplicate-definition
             "Duplicate ~A definition named ~A." kind name))
    (let ((definition (%make-project-definition
                       kind name form (syntax-node-span form)
                       (%project-context-path context))))
      (setf (gethash key (%project-load-state-definitions-by-key state)) definition)
      (push definition (%project-load-state-definitions state)))))

(defun %import-spelling (context form)
  (let ((children (%form-children context form 2 2 "IMPORT declaration")))
    (%string-node-value context (second children) "IMPORT path")))

(defun %collect-source (state context)
  (let* ((key (uiop:native-namestring (%project-context-path context)))
         (active (%project-load-state-active state)))
    (when (member key active :test #'string=)
      (%fail context :import-cycle "Import cycle reaches ~A again." key))
    (when (gethash key (%project-load-state-loaded state))
      (return-from %collect-source nil))
    (push key (%project-load-state-active state))
    (unwind-protect
         (let* ((parsed (%parse-file-or-fail state context))
                (forms (syntax-parse-result-forms parsed))
                (header-count 0)
                (imports nil)
                (definitions nil))
           (dolist (form forms)
             (cond
               ((%named-form-p form "ivory-key")
                (incf header-count))
               ((%named-form-p form "import")
                (push form imports))
               ((%definition-kind-for-form form)
                (push form definitions))
               (t (%fail context :unknown-project-form
                         "Unknown project top-level form ~S." (%form-name form)))))
           (unless (= header-count 1)
             (%fail context :duplicate-language-header
                    "A project source must contain exactly one language header."))
           ;; Register before walking imports so definition order has no effect
           ;; on resolution; registries are decoded only after graph collection.
           (dolist (form (nreverse definitions))
             (%register-definition state context (%definition-kind-for-form form) form))
           (dolist (form (nreverse imports))
             (let* ((path (%resolve-import state context (%import-spelling context form)))
                    (child-stack
                      (append (%project-context-import-stack context)
                              (list (syntax-node-span form)))))
               (%collect-source state (%make-project-context path child-stack))))
           (setf (gethash key (%project-load-state-loaded state)) t))
      (setf (%project-load-state-active state)
            (rest (%project-load-state-active state))))))

(defun %option-name (option)
  (and (typep option 'syntax-list)
       (let ((head (first (syntax-list-children option))))
         (and (typep head 'syntax-atom)
              (eq (syntax-atom-kind head) :keyword)
              (string-downcase (syntax-atom-value head))))))

(defun %named-option (context options name description &key required)
  (let ((matches (remove-if-not (lambda (option)
                                  (string= (or (%option-name option) "") name))
                                options)))
    (when (and required (null matches))
      (%fail context :missing-project-option "~A requires :~A." description name))
    (when (rest matches)
      (%fail context :duplicate-project-option "~A repeats :~A." description name))
    (first matches)))

(defun %require-known-options (context options allowed description)
  (dolist (option options)
    (unless (member (%option-name option) allowed :test #'string=)
      (%fail context :unknown-project-option
             "~A has unsupported option ~S." description (%option-name option)))))

(defun %option-single-value (context option description predicate)
  (let ((children (%form-children context option 2 2 description)))
    (unless (funcall predicate (second children))
      (%fail context :invalid-project-option "Malformed ~A." description))
    (second children)))

(defun %decode-topology (definition)
  (let* ((context (%make-project-context (project-definition-path definition)
                                         (source-span-import-stack
                                          (project-definition-span definition))))
         (form (project-definition-form definition))
         (children (%form-children context form 3 nil "DEFINE-TOPOLOGY declaration"))
         (name (project-definition-name definition))
         (positions nil)
         (seen (make-hash-table :test #'equal)))
    (dolist (clause (cddr children))
      (unless (%named-form-p clause "position")
        (%fail context :unknown-topology-clause
               "Topology ~A has unsupported clause ~S." name (%form-name clause)))
      (let* ((position-children (%form-children context clause 2 nil "POSITION declaration"))
             (position-name (%identifier-node-name context (second position-children)
                                                   "Position name"))
             (options (cddr position-children)))
        (when (gethash position-name seen)
          (%fail context :duplicate-position
                 "Topology ~A defines position ~A more than once." name position-name))
        (setf (gethash position-name seen) t)
        (%require-known-options context options '("row" "column" "hand" "finger" "label")
                                "POSITION")
        (let* ((row (%named-option context options "row" "POSITION"))
               (column (%named-option context options "column" "POSITION"))
               (hand (%named-option context options "hand" "POSITION"))
               (finger (%named-option context options "finger" "POSITION"))
               (label (%named-option context options "label" "POSITION"))
               (row-value (and row (%integer-node-value
                                   context (%option-single-value context row "POSITION :row"
                                                                 (lambda (node)
                                                                   (and (typep node 'syntax-atom)
                                                                        (eq (syntax-atom-kind node) :integer))))
                                   "POSITION :row")))
               (column-value (and column (%integer-node-value
                                          context (%option-single-value context column "POSITION :column"
                                                                        (lambda (node)
                                                                          (and (typep node 'syntax-atom)
                                                                               (eq (syntax-atom-kind node) :integer))))
                                          "POSITION :column"))))
          (when (not (eq (null row) (null column)))
            (%fail context :incomplete-position-coordinates
                   "POSITION ~A must declare both :row and :column." position-name))
          (push (make-logical-position
                 position-name
                 :coordinates (and row (list row-value column-value))
                 :hand (and hand (%identifier-node-name
                                  context (%option-single-value context hand "POSITION :hand"
                                                                (lambda (node)
                                                                  (and (typep node 'syntax-atom)
                                                                       (eq (syntax-atom-kind node) :identifier))))
                                  "POSITION hand"))
                 :finger (and finger (%identifier-node-name
                                      context (%option-single-value context finger "POSITION :finger"
                                                                    (lambda (node)
                                                                      (and (typep node 'syntax-atom)
                                                                           (eq (syntax-atom-kind node) :identifier))))
                                      "POSITION finger"))
                 :label (and label (%string-node-value
                                    context (%option-single-value context label "POSITION :label"
                                                                  (lambda (node)
                                                                    (and (typep node 'syntax-atom)
                                                                         (eq (syntax-atom-kind node) :string))))
                                    "POSITION label")))
                positions))))
    (make-topology name (nreverse positions))))

(defun %definition-value (registry name)
  (gethash (identifier-name (ensure-identifier name)) registry))

(defun %decode-layout (definition topologies)
  (let* ((context (%make-project-context (project-definition-path definition)
                                         (source-span-import-stack
                                          (project-definition-span definition))))
         (form (project-definition-form definition)))
    ;; The model decoder is intentionally still the authority for layout
    ;; clauses, templates, and behaviors.  The small filtered parse result
    ;; keeps imports out of its closed top-level vocabulary.
    (handler-case
        (let ((layout
                (decode-layout-forms
                 (list form)
                 :topology-resolver
                 (lambda (topology-name)
                   (or (%definition-value topologies topology-name)
                       (%fail context :unknown-topology
                              "Layout ~A refers to unknown topology ~A."
                              (project-definition-name definition)
                              (identifier-name (ensure-identifier topology-name))))))))
          (validate-layout layout)
          layout)
      (semantic-error (condition)
        (%fail context (semantic-error-code condition)
               "Could not decode layout ~A: ~A"
               (project-definition-name definition)
               (semantic-error-message condition))))))

(defun %device-backend-code (context options backend position device-name)
  (let ((option (%named-option context options backend "PLACE" :required t)))
    (%text-node-value
     context
     (%option-single-value context option (format nil "PLACE :~A" backend)
                           (lambda (node)
                             (and (typep node 'syntax-atom)
                                  (member (syntax-atom-kind node) '(:identifier :string)))))
     (format nil "Device ~A placement for ~A" device-name position))))

(defun %decode-device (definition topologies)
  (let* ((context (%make-project-context (project-definition-path definition)
                                         (source-span-import-stack
                                          (project-definition-span definition))))
         (form (project-definition-form definition))
         (children (%form-children context form 3 nil "DEFINE-DEVICE declaration"))
         (name (project-definition-name definition))
         (clauses (cddr children))
         (topology-clause (find "uses-topology" clauses :test #'string=
                                :key #'%form-name))
         (placements nil)
         (backend-mappings nil)
         (reserved-carriers nil)
         (seen-positions (make-hash-table :test #'equal))
         (seen-physical (make-hash-table :test #'equal)))
    (unless topology-clause
      (%fail context :missing-device-topology
             "Device ~A requires USES-TOPOLOGY." name))
    (let* ((topology-children (%form-children context topology-clause 2 2
                                               "USES-TOPOLOGY declaration"))
           (topology-name (%identifier-node-name context (second topology-children)
                                                 "Device topology name"))
           (topology (%definition-value topologies topology-name)))
      (unless topology
        (%fail context :unknown-topology "Device ~A refers to unknown topology ~A."
               name topology-name))
      (dolist (clause clauses)
        (cond
          ((%named-form-p clause "uses-topology") nil)
          ((%named-form-p clause "reserve-carriers")
           (dolist (carrier (cdr (syntax-list-children clause)))
             (let ((value (%integer-node-value context carrier "Reserved carrier")))
               (when (minusp value)
                 (%fail context :invalid-reserved-carrier
                        "Reserved carrier ~D must be non-negative." value))
               (push value reserved-carriers))))
          ((%named-form-p clause "place")
           (let* ((place-children (%form-children context clause 4 nil "PLACE declaration"))
                  (position-name (%identifier-node-name context (second place-children)
                                                        "Placed logical position"))
                  (position (ensure-identifier position-name))
                  (options (cddr place-children)))
             (unless (find-position position topology)
               (%fail context :unknown-device-position
                      "Device ~A places unknown topology position ~A." name position-name))
             (when (gethash position-name seen-positions)
               (%fail context :duplicate-device-placement
                      "Device ~A places position ~A more than once." name position-name))
             (setf (gethash position-name seen-positions) t)
             (%require-known-options context options '("xkb" "kanata") "PLACE")
             (let ((xkb (%device-backend-code context options "xkb" position-name name))
                   (kanata (%device-backend-code context options "kanata" position-name name)))
               (dolist (entry (list (cons (format nil "xkb:~A" xkb) position)
                                    (cons (format nil "kanata:~A" kanata) position)))
                 (when (gethash (car entry) seen-physical)
                   (%fail context :duplicate-physical-placement
                          "Device ~A reuses physical input ~A." name (car entry)))
                 (setf (gethash (car entry) seen-physical) t)
                 (push entry placements))
               (push (cons position-name (list :xkb xkb :kanata kanata)) backend-mappings))))
          (t (%fail context :unknown-device-clause
                    "Device ~A has unsupported clause ~S." name (%form-name clause)))))
      (make-device-placement
       name topology (sort placements #'string< :key #'car)
       :metadata (list :backend-mappings
                       (sort backend-mappings #'string< :key #'car)
                       :reserved-carriers (sort (remove-duplicates reserved-carriers) #'<))))))

(defun %decode-output-vocabulary-entry (context vocabulary-name backends clause)
  "Decode one closed MAP-OUTPUT declaration into opaque model entries.

Only the declared vocabulary backends may appear as keyword options.  The
opaque spelling is deliberately a source string, never a reader form or host
symbol.
"
  (let* ((children (%form-children context clause 3 nil "MAP-OUTPUT declaration"))
         (kind (%identifier-node-name context (second children) "MAP-OUTPUT kind"))
         (identity (%identifier-node-name context (third children)
                                           "MAP-OUTPUT identity"))
         (options (cdddr children))
         (seen (make-hash-table :test #'equal))
         (entries nil))
    (dolist (option options)
      (let ((backend (%option-name option)))
        (unless backend
          (%fail context :invalid-output-vocabulary-option
                 "Vocabulary ~A MAP-OUTPUT options must have a backend keyword."
                 vocabulary-name))
        (unless (member backend backends :test #'string=)
          (%fail context :unknown-vocabulary-backend
                 "Vocabulary ~A MAP-OUTPUT refers to undeclared backend ~A."
                 vocabulary-name backend))
        (when (gethash backend seen)
          (%fail context :duplicate-vocabulary-backend-spelling
                 "Vocabulary ~A repeats a spelling for backend ~A."
                 vocabulary-name backend))
        (setf (gethash backend seen) t)
        (let ((spelling
                (%string-node-value
                 context
                 (%option-single-value context option
                                       (format nil "MAP-OUTPUT :~A" backend)
                                       (lambda (node)
                                         (and (typep node 'syntax-atom)
                                              (eq (syntax-atom-kind node) :string))))
                 (format nil "Vocabulary ~A spelling for ~A"
                         vocabulary-name backend))))
          (push (handler-case
                    (make-output-vocabulary-entry kind identity backend spelling)
                  (semantic-error (condition)
                    (%fail context (semantic-error-code condition)
                           "Could not decode output vocabulary ~A: ~A"
                           vocabulary-name (semantic-error-message condition))))
                entries))))
    (unless entries
      (%fail context :missing-vocabulary-entry-spelling
             "Vocabulary ~A MAP-OUTPUT ~A ~A needs at least one backend spelling."
             vocabulary-name kind identity))
    (nreverse entries)))

(defun %decode-output-vocabulary (definition)
  "Decode one named, realization-owned output-vocabulary declaration.

The closed surface grammar is:

  (define-output-vocabulary NAME
    (backends BACKEND...)
    (map-output KIND IDENTITY (:BACKEND \"opaque spelling\") ...))

Vocabulary values are separate project declarations because a realization can
refer to one independently of source/import ordering.  They are not layout
clauses and never participate in behavior decoding.
"
  (let* ((context (%make-project-context (project-definition-path definition)
                                         (source-span-import-stack
                                          (project-definition-span definition))))
         (form (project-definition-form definition))
         (children (%form-children context form 3 nil
                                   "DEFINE-OUTPUT-VOCABULARY declaration"))
         (name (project-definition-name definition))
         (clauses (cddr children))
         (backend-forms (remove-if-not (lambda (clause)
                                         (%named-form-p clause "backends"))
                                       clauses)))
    (dolist (clause clauses)
      (unless (member (%form-name clause) '("backends" "map-output") :test #'string=)
        (%fail context :unknown-output-vocabulary-clause
               "Output vocabulary ~A has unsupported clause ~S."
               name (%form-name clause))))
    (unless backend-forms
      (%fail context :missing-vocabulary-backends
             "Output vocabulary ~A requires BACKENDS." name))
    (when (rest backend-forms)
      (%fail context :duplicate-vocabulary-clause
             "Output vocabulary ~A repeats BACKENDS." name))
    (let* ((backends-form (first backend-forms))
           (backend-nodes (cdr (%form-children context backends-form 2 nil
                                               "BACKENDS declaration")))
           (backends (mapcar (lambda (node)
                               (%identifier-node-name context node
                                                      "Vocabulary backend"))
                             backend-nodes))
           (seen-identities (make-hash-table :test #'equal))
           (entries nil))
      ;; The form arity above makes BACKENDS non-empty.  Decode every mapping
      ;; before constructing the registry so model-level duplicate and
      ;; ambiguity detection sees the full declarative set.
      (dolist (clause clauses)
        (when (%named-form-p clause "map-output")
          (let* ((mapping-children
                   (%form-children context clause 3 nil "MAP-OUTPUT declaration"))
                 (kind (%identifier-node-name context (second mapping-children)
                                              "MAP-OUTPUT kind"))
                 (identity (%identifier-node-name context (third mapping-children)
                                                  "MAP-OUTPUT identity"))
                 (identity-key (list kind identity)))
            ;; A MAP-OUTPUT row is the single declarative owner of one typed
            ;; abstract identity.  Splitting one identity across source rows
            ;; would add surface-order questions without enabling a proven
            ;; lowering, so require all of its known spellings in one row.
            (when (gethash identity-key seen-identities)
              (%fail context :duplicate-vocabulary-identity
                     "Output vocabulary ~A repeats MAP-OUTPUT ~A ~A."
                     name kind identity))
            (setf (gethash identity-key seen-identities) t)
            (setf entries
                  (nconc entries
                         (%decode-output-vocabulary-entry
                          context name backends clause))))))
      (handler-case
          (make-output-vocabulary backends entries)
        (semantic-error (condition)
          (%fail context (semantic-error-code condition)
                 "Could not decode output vocabulary ~A: ~A"
                 name (semantic-error-message condition)))))))

(defun %selector-policy-enum (context node choices description)
  "Decode one closed selector-policy identifier without INTERNing it."
  (let* ((name (%identifier-node-name context node description))
         (choice (assoc name choices :test #'string=)))
    (unless choice
      (%fail context :unknown-realization-selector-policy-value
             "~A has unsupported value ~A." description name))
    (cdr choice)))

(defun %decode-realization-selector-policy (context form)
  "Decode a closed realization allocation policy from parser nodes only.

This intentionally accepts no opaque backend action string.  The resulting
model value carries typed selector controls and the two bounded carrier codes;
backend emitters select grammar only after compiler completeness checks.
"
  (let ((static-types nil) (selectors nil) (carriers nil))
    (dolist (clause (cdr (%form-children context form 1 nil
                                         "SELECTOR-POLICY declaration")))
      (let ((kind (%form-name clause)))
        (cond
          ((and kind (string= kind "static-type"))
           (let ((children (%form-children context clause 4 4
                                           "STATIC-TYPE selector policy clause")))
             (push (ivory-key.model::make-realization-static-type
                    (%identifier-node-name context (second children)
                                           "STATIC-TYPE position")
                    (%selector-policy-enum
                     context (third children)
                     '(("four-level" . :four-level)
                       ("four-level-alphabetic" . :four-level-alphabetic))
                     "STATIC-TYPE Group1 kind")
                    (%selector-policy-enum
                     context (fourth children) '(("two-level" . :two-level))
                     "STATIC-TYPE Group2 kind"))
                   static-types)))
          ((and kind (string= kind "selector"))
           (let ((children (%form-children context clause 6 6
                                           "SELECTOR policy clause")))
             (push (ivory-key.model::make-realization-context-selector
                    (%identifier-node-name context (second children) "SELECTOR axis")
                    (%identifier-node-name context (third children) "SELECTOR state")
                    (%selector-policy-enum
                     context (fourth children)
                     '(("shift" . :shift) ("level-three" . :level-three)
                       ("group-two" . :group-two))
                     "SELECTOR control")
                    (%selector-policy-enum
                     context (fifth children)
                     '(("consumed" . :consumed) ("group-action" . :group-action))
                     "SELECTOR consumption")
                    (%selector-policy-enum
                     context (sixth children)
                     '(("core-shift" . :core-shift)
                       ("consumed-level-three" . :consumed-level-three)
                       ("unproved-group-two" . :unproved-group-two))
                     "SELECTOR client semantics"))
                   selectors)))
          ((and kind (string= kind "carrier"))
           (let ((children (%form-children context clause 6 6
                                           "CARRIER selector policy clause")))
             (push (ivory-key.model::make-realization-direct-carrier
                    (%identifier-node-name context (second children) "CARRIER position")
                    (%identifier-node-name context (third children) "CARRIER axis")
                    (%identifier-node-name context (fourth children) "CARRIER state")
                    (%integer-node-value context (fifth children) "CARRIER Linux code")
                    (%selector-policy-enum
                     context (sixth children)
                     '(("zeha" . :zeha) ("lvl3" . :lvl3))
                     "CARRIER XKB key"))
                   carriers)))
          (t
           (%fail context :unknown-realization-selector-policy-clause
                  "SELECTOR-POLICY has unsupported clause ~S." kind)))))
    ;; The model constructor owns duplicate resource validation.  Keeping it
    ;; here rather than in an opaque profile plist gives programmatic callers
    ;; exactly the same closed resource contract as source declarations.
    (ivory-key.model::make-realization-selector-policy
     (nreverse static-types) (nreverse selectors) (nreverse carriers))))

(defun %decode-realization (definition output-vocabularies)
  (let* ((context (%make-project-context (project-definition-path definition)
                                         (source-span-import-stack
                                          (project-definition-span definition))))
         (form (project-definition-form definition))
         (children (%form-children context form 3 nil "DEFINE-REALIZATION declaration"))
         (name (project-definition-name definition))
         (clauses (cddr children)))
    (dolist (clause clauses)
      (unless (member (%form-name clause)
                      '("pipeline" "uses-output-vocabulary" "allow-grades"
                        "forbid-shell-actions" "validation" "selector-policy")
                      :test #'string=)
        (%fail context :unknown-realization-clause
               "Realization ~A has unsupported clause ~S." name (%form-name clause))))
    (let* ((pipeline-matches (remove-if-not (lambda (clause)
                                              (%named-form-p clause "pipeline"))
                                            clauses))
           (vocabulary-matches (remove-if-not (lambda (clause)
                                                (%named-form-p clause
                                                               "uses-output-vocabulary"))
                                              clauses))
           (grade-matches (remove-if-not (lambda (clause)
                                           (%named-form-p clause "allow-grades"))
                                         clauses))
           (shell-matches (remove-if-not (lambda (clause)
                                           (%named-form-p clause "forbid-shell-actions"))
                                         clauses))
           (selector-policy-matches
             (remove-if-not (lambda (clause)
                              (%named-form-p clause "selector-policy"))
                            clauses))
           (pipeline-form (first pipeline-matches))
           (vocabulary-form (first vocabulary-matches))
           (grades-form (first grade-matches))
           (shell-form (first shell-matches))
           (selector-policy-form (first selector-policy-matches))
           (validation-forms (remove-if-not (lambda (clause)
                                              (%named-form-p clause "validation"))
                                            clauses)))
      (unless pipeline-form
        (%fail context :missing-realization-pipeline
               "Realization ~A requires PIPELINE." name))
      (when (or (rest pipeline-matches) (rest vocabulary-matches)
                (rest grade-matches) (rest shell-matches)
                (rest selector-policy-matches))
        ;; The exact identity tests above deliberately reject duplicate closed
        ;; policy forms without converting their source names into symbols.
        (%fail context :duplicate-realization-clause
               "Realization ~A repeats a singleton policy clause." name))
      (let ((pipeline
              (mapcar (lambda (node) (%identifier-node-name context node "Pipeline backend"))
                      (cdr (syntax-list-children pipeline-form))))
            (vocabulary-name
              (and vocabulary-form
                   (%identifier-node-name
                    context
                    (second (%form-children context vocabulary-form 2 2
                                            "USES-OUTPUT-VOCABULARY declaration"))
                    "USES-OUTPUT-VOCABULARY name")))
            (grades (and grades-form
                         (mapcar (lambda (node) (%identifier-node-name context node "Allowed grade"))
                                 (cdr (syntax-list-children grades-form)))))
            (forbid-shell
              (and shell-form
                   (%identifier-node-name
                    context
                    (second (%form-children context shell-form 2 2
                                            "FORBID-SHELL-ACTIONS declaration"))
                    "FORBID-SHELL-ACTIONS value")))
            (selector-policy
              (and selector-policy-form
                   (handler-case
                       (%decode-realization-selector-policy context selector-policy-form)
                     (semantic-error (condition)
                       (%fail context (semantic-error-code condition)
                              "Could not decode selector policy for realization ~A: ~A"
                              name (semantic-error-message condition)))))))
        (when (null pipeline)
          (%fail context :empty-realization-pipeline
                 "Realization ~A needs at least one pipeline backend." name))
        (dolist (grade grades)
          (unless (member grade '("exact" "emulated" "lossy" "unsupported") :test #'string=)
            (%fail context :unknown-realization-grade
                   "Realization ~A allows unknown grade ~A." name grade)))
        (let ((vocabulary (and vocabulary-name
                               (%definition-value output-vocabularies vocabulary-name))))
          (when (and vocabulary-name (null vocabulary))
            (%fail context :unknown-output-vocabulary
                   "Realization ~A refers to unknown output vocabulary ~A."
                   name vocabulary-name))
          (handler-case
              (make-realization-profile
               name :pipeline pipeline :vocabulary vocabulary :permitted-losses grades
               :selector-policy selector-policy
               :metadata (list :forbid-shell-actions forbid-shell
                               :validation (mapcar #'%node->safe-value validation-forms)))
            (semantic-error (condition)
              (%fail context (semantic-error-code condition)
                     "Could not decode realization ~A: ~A"
                     name (semantic-error-message condition)))))))))

(defun %composition-option (context clauses name)
  (let ((matches (remove-if-not (lambda (clause)
                                  (string= (or (%option-name clause) "") name))
                                clauses)))
    (unless (= (length matches) 1)
      (%fail context :malformed-realize
             "REALIZE requires exactly one :~A option." name))
    (%identifier-node-name context
                           (%option-single-value context (first matches)
                                                 (format nil "REALIZE :~A" name)
                                                 (lambda (node)
                                                   (and (typep node 'syntax-atom)
                                                        (eq (syntax-atom-kind node)
                                                            :identifier))))
                           (format nil "REALIZE :~A target" name))))

(defun %decode-composition (definition layouts devices realizations)
  (let* ((context (%make-project-context (project-definition-path definition)
                                         (source-span-import-stack
                                          (project-definition-span definition))))
         (children (%form-children context (project-definition-form definition) 5 5
                                   "REALIZE declaration"))
         (clauses (cddr children)))
    (%require-known-options context clauses '("layout" "device" "profile") "REALIZE")
    (let* ((layout-name (%composition-option context clauses "layout"))
           (device-name (%composition-option context clauses "device"))
           (profile-name (%composition-option context clauses "profile"))
           (layout (%definition-value layouts layout-name))
           (device (%definition-value devices device-name))
           (profile (%definition-value realizations profile-name)))
      (unless layout
        (%fail context :unknown-layout "REALIZE refers to unknown layout ~A." layout-name))
      (unless device
        (%fail context :unknown-device "REALIZE refers to unknown device ~A." device-name))
      (unless profile
        (%fail context :unknown-realization
               "REALIZE refers to unknown realization ~A." profile-name))
      (unless (identifier= (topology-name (layout-topology layout))
                           (topology-name (placement-topology device)))
        (%fail context :incompatible-realize-topology
               "REALIZE layout ~A and device ~A use incompatible topologies."
               layout-name device-name))
      (%make-project-realization-composition
       (project-definition-name definition) layout device profile))))

(defun %kind-rank (kind)
  (ecase kind
    (:topology 0) (:layout 1) (:device 2) (:output-vocabulary 3)
    (:realization 4) (:composition 5)))

(defun %sorted-definitions (definitions)
  (sort (copy-list definitions)
        (lambda (left right)
          (let ((left-rank (%kind-rank (project-definition-kind left)))
                (right-rank (%kind-rank (project-definition-kind right))))
            (if (= left-rank right-rank)
                (string< (project-definition-name left)
                         (project-definition-name right))
                (< left-rank right-rank))))))

(defun %kind-definitions (definitions kind)
  (remove kind definitions :test-not #'eq :key #'project-definition-kind))

(defun %registry-from-definitions (definitions)
  (let ((registry (make-hash-table :test #'equal)))
    (dolist (definition definitions registry)
      (setf (gethash (project-definition-name definition) registry)
            (project-definition-value definition)))))

(defun %result-registry-alist (definitions kind)
  (mapcar (lambda (definition)
            (cons (project-definition-name definition)
                  (project-definition-value definition)))
          (%kind-definitions definitions kind)))

(defun %source-roots (pathname source-roots working-directory)
  (let ((roots (or source-roots
                   (list (uiop:pathname-directory-pathname pathname)))))
    (unless (listp roots)
      (setf roots (list roots)))
    (handler-case
        (let* ((lexical-roots
                 (sort (remove-duplicates
                        (mapcar (lambda (root)
                                  (uiop:ensure-directory-pathname
                                   (%absolute-pathname root working-directory)))
                                roots)
                        :test #'equal)
                       #'string< :key #'uiop:native-namestring))
               (physical-roots
                 (sort (remove-duplicates (mapcar #'%canonical-directory lexical-roots)
                                          :test #'equal)
                       #'string< :key #'uiop:native-namestring)))
          (values physical-roots lexical-roots))
      (error (condition)
        (error 'project-error :code :unreadable-source-root
               :message (format nil "Could not use a source root: ~A" condition))))))

(defun load-project (pathname &key source-roots)
  "Load PATHNAME and its explicit relative imports as a deterministic project.

SOURCE-ROOTS confines imports both lexically and after symlink resolution.  A
missing value defaults only to PATHNAME's directory, which is useful for a
single-file project but deliberately never grants access to the process CWD.
The returned registries are canonical name-sorted alists; import traversal
order is therefore not a semantic input."
  (let* ((working-directory (%captured-working-directory))
         (candidate (%absolute-pathname pathname working-directory)))
    (multiple-value-bind (roots lexical-roots)
        (%source-roots candidate source-roots working-directory)
      (let* ((entry (handler-case
                    (progn
                      ;; A configured root may itself be a symlink.  Allow the
                      ;; requested entry under that lexical authority, then
                      ;; require its physical target under the canonical root.
                      (unless (%within-source-roots-p candidate roots)
                        (unless (%within-source-roots-p candidate lexical-roots)
                          (error 'project-error :code :source-outside-root
                                 :message "Project entry is outside every configured source root.")))
                      (unless (probe-file candidate)
                        (error 'project-error :code :unreadable-project-source
                               :message "Could not read project entry source."))
                      (let ((physical (truename candidate)))
                        (unless (%within-source-roots-p physical roots)
                          (error 'project-error :code :source-outside-root
                                 :message "Project entry resolves outside every configured source root."))
                        physical))
                  (project-error (condition) (error condition))
                  (error (condition)
                    (error 'project-error :code :unreadable-project-source
                           :message (format nil "Could not read project entry: ~A" condition)))))
             (state (%make-project-load-state :roots roots)))
        (%collect-source state (%make-project-context entry nil))
        (let* ((definitions (%sorted-definitions (%project-load-state-definitions state)))
           (topology-definitions (%kind-definitions definitions :topology)))
      (dolist (definition topology-definitions)
        (setf (project-definition-value definition) (%decode-topology definition)))
      (let ((topologies (%registry-from-definitions topology-definitions)))
        (dolist (definition (%kind-definitions definitions :layout))
          (setf (project-definition-value definition) (%decode-layout definition topologies)))
        (let ((layouts (%registry-from-definitions (%kind-definitions definitions :layout))))
          (dolist (definition (%kind-definitions definitions :device))
            (setf (project-definition-value definition) (%decode-device definition topologies)))
          (let ((devices (%registry-from-definitions (%kind-definitions definitions :device))))
            (let ((output-vocabulary-definitions
                    (%kind-definitions definitions :output-vocabulary)))
              (dolist (definition output-vocabulary-definitions)
                (setf (project-definition-value definition)
                      (%decode-output-vocabulary definition)))
              (let ((output-vocabularies
                      (%registry-from-definitions output-vocabulary-definitions)))
                (dolist (definition (%kind-definitions definitions :realization))
                  (setf (project-definition-value definition)
                        (%decode-realization definition output-vocabularies)))
                (let ((realizations
                        (%registry-from-definitions
                         (%kind-definitions definitions :realization))))
                  (dolist (definition (%kind-definitions definitions :composition))
                    (setf (project-definition-value definition)
                          (%decode-composition definition layouts devices realizations)))
                  (%make-project-load-result
                   definitions
                   (%result-registry-alist definitions :layout)
                   (%result-registry-alist definitions :topology)
                   (%result-registry-alist definitions :device)
                   (%result-registry-alist definitions :output-vocabulary)
                   (%result-registry-alist definitions :realization)
                   (%result-registry-alist definitions :composition)
                   (sort (loop for path being the hash-keys of
                                 (%project-load-state-loaded state)
                               collect path)
                         #'string<)))))))))))))

(defun project-definition-by-name (result kind name &key (errorp nil))
  "Look up one canonical KIND/NAME declaration in RESULT."
  (unless (typep result 'project-load-result)
    (error 'type-error :datum result :expected-type 'project-load-result))
  (unless (member kind '(:layout :topology :device :output-vocabulary
                         :realization :composition))
    (error 'type-error :datum kind
           :expected-type '(member :layout :topology :device :output-vocabulary
                                   :realization :composition)))
  (let ((definition
          (find-if (lambda (candidate)
                     (and (eq kind (project-definition-kind candidate))
                          (string= (identifier-name (ensure-identifier name))
                                   (project-definition-name candidate))))
                   (project-load-result-definitions result))))
    (or definition
        (when errorp
          (error 'project-error :code :unknown-project-definition
                 :message (format nil "Project has no ~A named ~A." kind name))))))

(defun %project-value (result kind name errorp)
  (let ((definition (project-definition-by-name result kind name :errorp errorp)))
    (and definition (project-definition-value definition))))

(defun project-layout (result name &key (errorp nil))
  (%project-value result :layout name errorp))

(defun project-topology (result name &key (errorp nil))
  (%project-value result :topology name errorp))

(defun project-device (result name &key (errorp nil))
  (%project-value result :device name errorp))

(defun project-output-vocabulary (result name &key (errorp nil))
  (%project-value result :output-vocabulary name errorp))

(defun project-realization (result name &key (errorp nil))
  (%project-value result :realization name errorp))

(defun project-composition (result name &key (errorp nil))
  (%project-value result :composition name errorp))
