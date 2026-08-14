;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Target-neutral semantic-output vocabulary registries.

(in-package #:ivory-key.model)

;;; A vocabulary belongs to a realization profile, not to a layout.  Layouts
;;; name semantic outputs; this registry records how a selected backend spells
;;; them.  The model intentionally does not know whether a spelling is an XKB
;;; keysym, a Kanata token, a firmware code, or another future backend form.

(defparameter +semantic-output-vocabulary-kinds+
  '("named-key" "named-symbol" "command")
  "The closed set of typed semantic output kinds that need backend spellings.")

(defun %vocabulary-error (code control &rest arguments)
  (apply #'signal-semantic-error 'semantic-validation-error code control arguments))

(defun %vocabulary-identifier (value role)
  "Accept only source-safe strings or IDENTIFIER values for registry identity."
  (unless (or (stringp value) (typep value 'identifier))
    (%vocabulary-error :invalid-vocabulary-identifier
                       "~A must be a string or Ivory Key identifier, got ~S."
                       role value))
  (ensure-identifier value))

(defun %vocabulary-kind (value)
  (let ((kind (identifier-name (%vocabulary-identifier value "Vocabulary kind"))))
    (unless (member kind +semantic-output-vocabulary-kinds+ :test #'string=)
      (%vocabulary-error :unknown-vocabulary-output-kind
                         "Unknown semantic output kind ~S." kind))
    kind))

(defun %vocabulary-spelling (value)
  "Validate an opaque backend spelling without imposing a backend grammar.

Backend adapters own syntax validation.  The registry rejects only empty and
NUL-containing values, which cannot be a safe opaque spelling in a text-based
or byte-oriented realization.
"
  (unless (and (stringp value) (plusp (length value)))
    (%vocabulary-error :invalid-vocabulary-spelling
                       "A backend spelling must be a non-empty string, got ~S." value))
  (when (find #\Null value)
    (%vocabulary-error :invalid-vocabulary-spelling
                       "A backend spelling must not contain NUL."))
  value)

(defclass output-vocabulary-entry ()
  ((kind :initarg :kind :reader vocabulary-entry-kind)
   (identity :initarg :identity :reader vocabulary-entry-identity)
   (backend :initarg :backend :reader vocabulary-entry-backend)
   (spelling :initarg :spelling :reader vocabulary-entry-spelling)))

(defun make-output-vocabulary-entry (kind identity backend spelling)
  "Create one target spelling for a typed semantic output.

KIND is one of the strings NAMED-KEY, NAMED-SYMBOL, or COMMAND.  IDENTITY and
BACKEND remain canonical Ivory Key identifiers; SPELLING is an opaque string.
No source form is read, evaluated, or interned here.
"
  (make-instance 'output-vocabulary-entry
                 :kind (%vocabulary-kind kind)
                 :identity (%vocabulary-identifier identity "Vocabulary identity")
                 :backend (%vocabulary-identifier backend "Vocabulary backend")
                 :spelling (%vocabulary-spelling spelling)))

(defun vocabulary-entry-key (entry)
  "Return ENTRY's deterministic logical identity key as plain strings."
  (list (identifier-name (vocabulary-entry-backend entry))
        (vocabulary-entry-kind entry)
        (identifier-name (vocabulary-entry-identity entry))))

(defun vocabulary-entry-canonical-data (entry)
  "Return ENTRY in deterministic, serialization-safe string order.

The result is (BACKEND KIND IDENTITY SPELLING); callers need not inspect CLOS
slots or rely on implementation-specific printed-object syntax.
"
  (append (vocabulary-entry-key entry)
          (list (vocabulary-entry-spelling entry))))

(defun %vocabulary-entry< (left right)
  (loop for left-part in (vocabulary-entry-canonical-data left)
        for right-part in (vocabulary-entry-canonical-data right)
        when (string< left-part right-part) return t
        when (string< right-part left-part) return nil
        finally (return nil)))

(defclass output-vocabulary ()
  ((backends :initarg :backends :reader %output-vocabulary-backends)
   (entries :initarg :entries :reader %output-vocabulary-entries)))

(defun %canonical-vocabulary-backends (backends)
  (unless (listp backends)
    (%vocabulary-error :malformed-vocabulary-backends
                       "Vocabulary backends must be a list, got ~S." backends))
  (let ((canonical (mapcar (lambda (backend)
                             (%vocabulary-identifier backend "Vocabulary backend"))
                           backends)))
    (unless (unique-identifiers-p canonical)
      (%vocabulary-error :duplicate-vocabulary-backend
                         "A vocabulary declares the same backend more than once."))
    (sort canonical #'identifier<)))

(defun %validate-vocabulary-entries (backends entries)
  (unless (listp entries)
    (%vocabulary-error :malformed-vocabulary-entries
                       "Vocabulary entries must be a list, got ~S." entries))
  (let ((identity-keys (make-hash-table :test #'equal))
        (spelling-keys (make-hash-table :test #'equal)))
    (dolist (entry entries)
      (unless (typep entry 'output-vocabulary-entry)
        (%vocabulary-error :invalid-vocabulary-entry
                           "A vocabulary entry must be an OUTPUT-VOCABULARY-ENTRY, got ~S."
                           entry))
      (unless (identifier-member-p (vocabulary-entry-backend entry) backends)
        (%vocabulary-error :unknown-vocabulary-backend
                           "Vocabulary entry for backend ~A names no configured backend."
                           (identifier-name (vocabulary-entry-backend entry))))
      (let ((identity-key (vocabulary-entry-key entry))
            ;; Reverse lookup must never silently choose between two semantic
            ;; meanings.  This is deliberately cross-kind as well as within a
            ;; kind: a backend spelling has one observable output identity.
            (spelling-key (list (identifier-name (vocabulary-entry-backend entry))
                                (vocabulary-entry-spelling entry))))
        (when (gethash identity-key identity-keys)
          (%vocabulary-error :duplicate-vocabulary-entry
                             "Vocabulary repeats backend/kind/identity ~S." identity-key))
        (when (gethash spelling-key spelling-keys)
          (%vocabulary-error :ambiguous-vocabulary-spelling
                             "Vocabulary maps backend spelling ~S to more than one semantic output."
                             spelling-key))
        (setf (gethash identity-key identity-keys) entry
              (gethash spelling-key spelling-keys) entry)))
    (sort (copy-list entries) #'%vocabulary-entry<)))

(defun make-output-vocabulary (backends entries)
  "Create a deterministic, ambiguity-free output vocabulary registry.

BACKENDS is the finite set of backend identifiers available in this profile.
ENTRIES is an unordered list of OUTPUT-VOCABULARY-ENTRY values; it is copied
and canonically sorted before storage.  An empty entry list is valid and makes
all attempted lookups fail explicitly as missing mappings.
"
  (let ((canonical-backends (%canonical-vocabulary-backends backends)))
    (make-instance 'output-vocabulary
                   :backends canonical-backends
                   :entries (%validate-vocabulary-entries canonical-backends entries))))

(defun output-vocabulary-backends (vocabulary)
  "Return VOCABULARY backend identifiers in deterministic order."
  (copy-list (%output-vocabulary-backends vocabulary)))

(defun output-vocabulary-entries (vocabulary)
  "Return VOCABULARY entries in deterministic serialization order."
  (copy-list (%output-vocabulary-entries vocabulary)))

(defun output-vocabulary-canonical-data (vocabulary)
  "Return VOCABULARY as deterministic plain-string rows for serializers."
  (mapcar #'vocabulary-entry-canonical-data (output-vocabulary-entries vocabulary)))

(defun semantic-output-kind (output)
  "Return the registry kind for a typed semantic OUTPUT.

Only named-key, named-symbol, and command outputs have backend spelling
registry entries.  Unicode text, modifiers, axis operations, and compositions
are represented by other realization mechanisms and are rejected explicitly.
"
  (cond ((typep output 'named-key-output) "named-key")
        ((typep output 'named-symbol-output) "named-symbol")
        ((typep output 'command-output) "command")
        (t (%vocabulary-error :unsupported-vocabulary-output
                              "Output ~S has no backend vocabulary identity." output))))

(defun semantic-output-identity (output)
  "Return OUTPUT's abstract identifier for an output-vocabulary lookup."
  (cond ((typep output 'named-key-output) (named-key-name output))
        ((typep output 'named-symbol-output) (named-symbol-name output))
        ((typep output 'command-output) (command-name output))
        (t (%vocabulary-error :unsupported-vocabulary-output
                              "Output ~S has no backend vocabulary identity." output))))

(defun %require-vocabulary-backend (vocabulary backend)
  (let ((canonical (%vocabulary-identifier backend "Vocabulary backend")))
    (unless (identifier-member-p canonical (%output-vocabulary-backends vocabulary))
      (%vocabulary-error :unknown-vocabulary-backend
                         "Vocabulary has no configured backend named ~A."
                         (identifier-name canonical)))
    canonical))

(defun find-output-vocabulary-entry (vocabulary kind identity backend)
  "Return the matching entry, or NIL after validating vocabulary dimensions.

Use OUTPUT-VOCABULARY-SPELLING when a missing mapping must be a diagnostic.
"
  (let ((canonical-kind (%vocabulary-kind kind))
        (canonical-identity (%vocabulary-identifier identity "Vocabulary identity"))
        (canonical-backend (%require-vocabulary-backend vocabulary backend)))
    (find-if (lambda (entry)
               (and (string= canonical-kind (vocabulary-entry-kind entry))
                    (identifier= canonical-identity (vocabulary-entry-identity entry))
                    (identifier= canonical-backend (vocabulary-entry-backend entry))))
             (%output-vocabulary-entries vocabulary))))

(defun output-vocabulary-spelling (vocabulary kind identity backend)
  "Return a backend spelling or signal a stable missing-mapping diagnostic."
  (let ((entry (find-output-vocabulary-entry vocabulary kind identity backend)))
    (or (and entry (vocabulary-entry-spelling entry))
        (%vocabulary-error :missing-vocabulary-mapping
                           "Vocabulary has no ~A mapping for ~A on backend ~A."
                           (%vocabulary-kind kind)
                           (identifier-name (%vocabulary-identifier identity "Vocabulary identity"))
                           (identifier-name (%require-vocabulary-backend vocabulary backend))))))

(defun output-vocabulary-spelling-for-output (vocabulary output backend)
  "Resolve one typed semantic OUTPUT to its opaque BACKEND spelling."
  (output-vocabulary-spelling vocabulary (semantic-output-kind output)
                              (semantic-output-identity output) backend))
