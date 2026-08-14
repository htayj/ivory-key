;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Deterministic, machine-readable output contract for emitted builds.

(in-package #:ivory-key.build-contract)

;;; This module deliberately accepts explicit compiler data rather than a
;;; compiler-unit.  That keeps the generated-output contract independent of a
;;; particular front-end and prevents this report layer from becoming another
;;; lowering path.

(defconstant +build-contract-schema-version+ 1)
(defconstant +ivory-key-language-version+ 1)
(defparameter +ivory-key-compiler-version+ "0.1.0")

(defstruct (source-hash-record
            (:constructor %make-source-hash-record (path sha256)))
  "One stable source identity and the SHA-256 digest of its observed bytes."
  path
  sha256)

(defstruct (build-contract
            (:constructor %make-build-contract
                (language-version compiler-version layout topology device profile
                 source-hashes pipeline-result validation-evidence)))
  "The data from which all Phase 6 contract files are rendered.

Every slot is immutable by convention.  VALIDATION-EVIDENCE is NIL unless a
caller actually ran and retained external validation results; compilation does
not manufacture either tool versions or validation claims.
"
  language-version
  compiler-version
  layout
  topology
  device
  profile
  source-hashes
  pipeline-result
  validation-evidence)

;;; SHA-256 -------------------------------------------------------------------

;; The contract must not depend on a host tool such as sha256sum, and the core
;; system deliberately has no cryptography dependency.  This small portable
;; implementation hashes source/artifact octets only; it is not a general
;; cryptographic API.

(defparameter +sha256-initial-state+
  #(#x6a09e667 #xbb67ae85 #x3c6ef372 #xa54ff53a
    #x510e527f #x9b05688c #x1f83d9ab #x5be0cd19))

(defparameter +sha256-round-constants+
  #(#x428a2f98 #x71374491 #xb5c0fbcf #xe9b5dba5 #x3956c25b #x59f111f1
    #x923f82a4 #xab1c5ed5 #xd807aa98 #x12835b01 #x243185be #x550c7dc3
    #x72be5d74 #x80deb1fe #x9bdc06a7 #xc19bf174 #xe49b69c1 #xefbe4786
    #x0fc19dc6 #x240ca1cc #x2de92c6f #x4a7484aa #x5cb0a9dc #x76f988da
    #x983e5152 #xa831c66d #xb00327c8 #xbf597fc7 #xc6e00bf3 #xd5a79147
    #x06ca6351 #x14292967 #x27b70a85 #x2e1b2138 #x4d2c6dfc #x53380d13
    #x650a7354 #x766a0abb #x81c2c92e #x92722c85 #xa2bfe8a1 #xa81a664b
    #xc24b8b70 #xc76c51a3 #xd192e819 #xd6990624 #xf40e3585 #x106aa070
    #x19a4c116 #x1e376c08 #x2748774c #x34b0bcb5 #x391c0cb3 #x4ed8aa4a
    #x5b9cca4f #x682e6ff3 #x748f82ee #x78a5636f #x84c87814 #x8cc70208
    #x90befffa #xa4506ceb #xbef9a3f7 #xc67178f2))

(declaim (inline %u32 %u32+ %rotate-right))

(defun %u32 (value)
  (ldb (byte 32 0) value))

(defun %u32+ (&rest values)
  (%u32 (reduce #'+ values :initial-value 0)))

(defun %rotate-right (value count)
  (%u32 (logior (ash value (- count))
                (ash value (- 32 count)))))

(defun %sha256-choice (first second third)
  (logxor (logand first second) (logand (lognot first) third)))

(defun %sha256-majority (first second third)
  (logxor (logand first second) (logand first third) (logand second third)))

(defun %sha256-big-sigma-0 (value)
  (logxor (%rotate-right value 2) (%rotate-right value 13)
          (%rotate-right value 22)))

(defun %sha256-big-sigma-1 (value)
  (logxor (%rotate-right value 6) (%rotate-right value 11)
          (%rotate-right value 25)))

(defun %sha256-small-sigma-0 (value)
  (logxor (%rotate-right value 7) (%rotate-right value 18) (ash value -3)))

(defun %sha256-small-sigma-1 (value)
  (logxor (%rotate-right value 17) (%rotate-right value 19) (ash value -10)))

(defun %utf8-octets (string)
  "Encode STRING as well-formed UTF-8 octets without implementation extensions."
  (unless (stringp string)
    (error "SHA-256 text input must be a string, got ~S." string))
  (let ((result (make-array 0 :element-type '(unsigned-byte 8)
                              :adjustable t :fill-pointer 0)))
    (labels ((push-octet (value) (vector-push-extend value result))
             (emit (code)
               (cond ((<= code #x7f) (push-octet code))
                     ((<= code #x7ff)
                      (push-octet (logior #xc0 (ash code -6)))
                      (push-octet (logior #x80 (logand code #x3f))))
                     ((<= code #xffff)
                      (push-octet (logior #xe0 (ash code -12)))
                      (push-octet (logior #x80 (logand (ash code -6) #x3f)))
                      (push-octet (logior #x80 (logand code #x3f))))
                     (t
                      (push-octet (logior #xf0 (ash code -18)))
                      (push-octet (logior #x80 (logand (ash code -12) #x3f)))
                      (push-octet (logior #x80 (logand (ash code -6) #x3f)))
                      (push-octet (logior #x80 (logand code #x3f)))))))
      (loop for character across string
            for code = (char-code character)
            do (when (<= #xd800 code #xdfff)
                 (error "SHA-256 text input contains a surrogate character."))
               (emit code)))
    result))

(defun %read-file-octets (pathname)
  "Read one file as exact octets, rejecting a detectable concurrent change."
  (with-open-file (stream pathname :direction :input
                                  :element-type '(unsigned-byte 8))
    (let ((length (file-length stream)))
      (unless (and (integerp length) (<= 0 length))
        (error "Could not determine byte length for source/artifact ~A." pathname))
      (let* ((octets (make-array length :element-type '(unsigned-byte 8)))
             (end (read-sequence octets stream)))
        (unless (= end length)
          (error "Source/artifact ~A changed while its hash was read." pathname))
        (when (read-byte stream nil nil)
          (error "Source/artifact ~A changed while its hash was read." pathname))
        octets))))

(defun %octets-for-sha256 (data)
  (cond ((stringp data) (%utf8-octets data))
        ((pathnamep data) (%read-file-octets data))
        ((and (vectorp data)
              (every (lambda (byte) (typep byte '(unsigned-byte 8))) data))
         (coerce data '(vector (unsigned-byte 8))))
        (t (error "SHA-256 input must be a string, pathname, or octet vector, got ~S."
                  data))))

(defun %sha256-padded-octets (octets)
  (let* ((length (length octets))
         (bit-length (* length 8)))
    (when (>= bit-length (expt 2 64))
      (error "SHA-256 input is too large for the SHA-256 length field."))
    (let* ((zero-count (mod (- 56 (mod (1+ length) 64)) 64))
           (padded (make-array (+ length 1 zero-count 8)
                               :element-type '(unsigned-byte 8)
                               :initial-element 0)))
      (replace padded octets)
      (setf (aref padded length) #x80)
      (dotimes (offset 8 padded)
        (setf (aref padded (+ length 1 zero-count offset))
              (ldb (byte 8 (* 8 (- 7 offset))) bit-length))))))

(defun %sha256-words->hex (words)
  (string-downcase
   (with-output-to-string (stream)
     (dotimes (word-index (length words))
       (format stream "~8,'0X" (aref words word-index))))))

(defun sha256-hex (data)
  "Return the lower-case SHA-256 hash of DATA.

DATA may be a Common Lisp string (encoded as UTF-8), a pathname (read as exact
octets), or an octet vector.  Source and artifact hashes use pathname input so
the contract records the bytes the toolchain observed.
"
  (let* ((padded (%sha256-padded-octets (%octets-for-sha256 data)))
         (state (copy-seq +sha256-initial-state+))
         (schedule (make-array 64 :element-type '(unsigned-byte 32))))
    (loop for offset from 0 below (length padded) by 64 do
      (dotimes (index 16)
        (let ((start (+ offset (* index 4))))
          (setf (aref schedule index)
                (logior (ash (aref padded start) 24)
                        (ash (aref padded (+ start 1)) 16)
                        (ash (aref padded (+ start 2)) 8)
                        (aref padded (+ start 3))))))
      (loop for index from 16 below 64 do
        (setf (aref schedule index)
              (%u32+ (%sha256-small-sigma-1 (aref schedule (- index 2)))
                     (aref schedule (- index 7))
                     (%sha256-small-sigma-0 (aref schedule (- index 15)))
                     (aref schedule (- index 16)))))
      (let ((a (aref state 0)) (b (aref state 1))
            (c (aref state 2)) (d (aref state 3))
            (e (aref state 4)) (f (aref state 5))
            (g (aref state 6)) (h (aref state 7)))
        (dotimes (index 64)
          (let* ((temporary-1
                   (%u32+ h (%sha256-big-sigma-1 e)
                          (%sha256-choice e f g)
                          (aref +sha256-round-constants+ index)
                          (aref schedule index)))
                 (temporary-2
                   (%u32+ (%sha256-big-sigma-0 a) (%sha256-majority a b c))))
            (setf h g
                  g f
                  f e
                  e (%u32+ d temporary-1)
                  d c
                  c b
                  b a
                  a (%u32+ temporary-1 temporary-2))))
        (setf (aref state 0) (%u32+ (aref state 0) a)
              (aref state 1) (%u32+ (aref state 1) b)
              (aref state 2) (%u32+ (aref state 2) c)
              (aref state 3) (%u32+ (aref state 3) d)
              (aref state 4) (%u32+ (aref state 4) e)
              (aref state 5) (%u32+ (aref state 5) f)
              (aref state 6) (%u32+ (aref state 6) g)
              (aref state 7) (%u32+ (aref state 7) h))))
    (%sha256-words->hex state)))

;;; Contract data -------------------------------------------------------------

(defun %hex-sha256-p (value)
  (and (stringp value) (= (length value) 64)
       (every (lambda (character)
                (or (digit-char-p character)
                    (find character "abcdef" :test #'char=)))
              value)))

(defun make-source-hash-record (path sha256)
  "Record PATH and one lower-case SHA-256 digest without normalizing either."
  (unless (and (stringp path) (plusp (length path)))
    (error "Build-contract source path must be a non-empty string, got ~S." path))
  (unless (%hex-sha256-p sha256)
    (error "Build-contract source hash for ~A is not lower-case SHA-256." path))
  (%make-source-hash-record path sha256))

(defun %canonical-name (value)
  (cond ((stringp value) value)
        ((symbolp value) (string-downcase (symbol-name value)))
        ((typep value 'ivory-key.model:identifier)
         (ivory-key.model:identifier-name value))
        (t (error "Build-contract name must be a string, symbol, or identifier, got ~S."
                  value))))

(defun %source-record< (left right)
  (string< (source-hash-record-path left) (source-hash-record-path right)))

(defun %canonical-source-hashes (records)
  (unless (every (lambda (record) (typep record 'source-hash-record)) records)
    (error "Every build-contract source hash must be a SOURCE-HASH-RECORD."))
  (let ((ordered (sort (copy-list records) #'%source-record<)))
    (loop for left on ordered
          for first = (first left)
          for second = (second left)
          while second
          when (string= (source-hash-record-path first)
                        (source-hash-record-path second))
            do (unless (string= (source-hash-record-sha256 first)
                                (source-hash-record-sha256 second))
                 (error "Conflicting hashes for source ~A."
                        (source-hash-record-path first)))
               (error "Duplicate source hash record for ~A."
                      (source-hash-record-path first)))
    ordered))

(defun make-build-contract (&key (language-version +ivory-key-language-version+)
                                 (compiler-version +ivory-key-compiler-version+)
                                 layout topology device profile source-hashes
                                 pipeline-result validation-evidence)
  "Construct data for a deterministic current-build output contract.

The selected names and source records are explicit inputs because a compiler
front end, not this serialization module, owns project loading and source-root
confinement.  NIL validation evidence is the normal compile-time state.
"
  (unless (and (integerp language-version) (plusp language-version))
    (error "Build-contract language version must be a positive integer."))
  (unless (and (stringp compiler-version) (plusp (length compiler-version)))
    (error "Build-contract compiler version must be a non-empty string."))
  ;; PIPELINE-RESULT is intentionally consumed through the public backend
  ;; readers below; the backend keeps its concrete result class private.
  (unless (listp validation-evidence)
    (error "Build-contract validation evidence must be a list or NIL."))
  (%make-build-contract
   language-version compiler-version
   (%canonical-name layout) (%canonical-name topology) (%canonical-name device)
   (%canonical-name profile) (%canonical-source-hashes source-hashes)
   pipeline-result (copy-list validation-evidence)))

;;; Restricted deterministic JSON ------------------------------------------------

(defstruct (json-object (:constructor %make-json-object (entries))) entries)
(defstruct (json-array (:constructor %make-json-array (values))) values)

(defun %object (&rest entries)
  (%make-json-object entries))

(defun %array (values)
  (%make-json-array values))

(defun %write-json-string (string stream)
  (write-char #\" stream)
  (loop for character across string do
    (case character
      (#\" (write-string "\\\"" stream))
      (#\\ (write-string "\\\\" stream))
      (#\Backspace (write-string "\\b" stream))
      (#\Page (write-string "\\f" stream))
      (#\Newline (write-string "\\n" stream))
      (#\Return (write-string "\\r" stream))
      (#\Tab (write-string "\\t" stream))
      (otherwise
       (if (< (char-code character) 32)
           (format stream "\\u~4,'0X" (char-code character))
           (write-char character stream)))))
  (write-char #\" stream))

(defun %json-object-entries (object)
  (let ((entries (sort (copy-list (json-object-entries object)) #'string< :key #'car)))
    (dolist (entry entries)
      (unless (and (consp entry) (stringp (car entry)))
        (error "Restricted JSON object entries must be (string . value), got ~S."
               entry)))
    (loop for left on entries
          for first = (first left)
          for second = (second left)
          while second
          when (string= (car first) (car second))
            do (error "Restricted JSON object repeats key ~S." (car first)))
    entries))

(defun %write-json-value (value stream)
  (cond ((typep value 'json-object)
         (write-char #\{ stream)
         (loop for entries on (%json-object-entries value)
               for entry = (first entries)
               do (%write-json-string (car entry) stream)
                  (write-char #\: stream)
                  (%write-json-value (cdr entry) stream)
                  (when (rest entries) (write-char #\, stream)))
         (write-char #\} stream))
        ((typep value 'json-array)
         (write-char #\[ stream)
         (loop for values on (json-array-values value)
               do (%write-json-value (first values) stream)
                  (when (rest values) (write-char #\, stream)))
         (write-char #\] stream))
        ((stringp value) (%write-json-string value stream))
        ((integerp value) (format stream "~D" value))
        ((eq value t) (write-string "true" stream))
        ((null value) (write-string "null" stream))
        (t (error "Restricted JSON cannot encode ~S." value))))

(defun %json-string (value)
  (with-output-to-string (stream)
    (%write-json-value value stream)
    (terpri stream)))

(defun %write-json-file (pathname value)
  (with-open-file (stream pathname :direction :output :if-exists :error
                                  :if-does-not-exist :create
                                  :external-format :utf-8)
    (write-string (%json-string value) stream)))

;;; Contract rendering --------------------------------------------------------

(defun %artifact< (left right)
  (string< (ivory-key.backend:pipeline-artifact-relative-path left)
           (ivory-key.backend:pipeline-artifact-relative-path right)))

(defun %entry< (left right)
  (string< (%canonical-name (ivory-key.backend:key-entry-position left))
           (%canonical-name (ivory-key.backend:key-entry-position right))))

(defun %realization< (left right)
  (string< (format nil "~A/~A/~A"
                   (%canonical-name (ivory-key.backend:realization-feature left))
                   (%canonical-name (ivory-key.backend:realization-grade left))
                   (ivory-key.backend:realization-detail left))
           (format nil "~A/~A/~A"
                   (%canonical-name (ivory-key.backend:realization-feature right))
                   (%canonical-name (ivory-key.backend:realization-grade right))
                   (ivory-key.backend:realization-detail right))))

(defun %source-json (record)
  (%object (cons "path" (source-hash-record-path record))
           (cons "sha256" (source-hash-record-sha256 record))))

(defun %artifact-json (artifact directory)
  (let* ((path (ivory-key.backend:pipeline-artifact-relative-path artifact))
         (pathname (merge-pathnames path directory)))
    (unless (probe-file pathname)
      (error "Cannot hash missing emitted artifact ~A." path))
    (%object (cons "kind" (%canonical-name
                            (ivory-key.backend:pipeline-artifact-kind artifact)))
             (cons "path" path)
             (cons "sha256" (sha256-hex pathname)))))

(defun %realization-json (result)
  (%object (cons "detail" (ivory-key.backend:realization-detail result))
           (cons "feature" (%canonical-name
                             (ivory-key.backend:realization-feature result)))
           (cons "grade" (%canonical-name
                           (ivory-key.backend:realization-grade result)))))

(defun %allocation-json (allocation)
  ;; The current conservative direct pipeline performs no carrier allocation.
  ;; Should a later pipeline forward target-neutral planner allocations here,
  ;; serialize that concrete, already-proven value—or fail rather than omit it.
  (unless (typep allocation 'ivory-key.backend:planner-allocation)
    (error "Cannot serialize an unrecognized pipeline allocation ~S." allocation))
  (let ((requirement
          (ivory-key.backend:planner-allocation-requirement allocation)))
    (%object
     (cons "kind" (%canonical-name
                    (ivory-key.backend:planner-resource-requirement-kind requirement)))
     (cons "owner" (%canonical-name
                     (ivory-key.backend:planner-resource-requirement-owner requirement)))
     (cons "pool" (%canonical-name
                    (ivory-key.backend:planner-allocation-pool-kind allocation)))
     (cons "value" (%canonical-name
                     (ivory-key.backend:planner-allocation-value allocation))))))

(defun %validation-evidence-json (evidence)
  "Encode only records supplied by an actual validator invocation.

Each record is a plist with :TOOL and :STATUS strings and optional :ARGUMENTS
and :OUTPUT strings.  No compiler path currently passes such records, so the
normal generated manifest omits the validation key altogether.
"
  (%array
   (mapcar
    (lambda (record)
      (unless (and (listp record)
                   (stringp (getf record :tool))
                   (stringp (getf record :status)))
        (error "Validation evidence must supply string :TOOL and :STATUS fields."))
      (let ((arguments (getf record :arguments))
            (output (getf record :output)))
        (unless (or (null arguments) (and (listp arguments) (every #'stringp arguments)))
          (error "Validation evidence :ARGUMENTS must be a list of strings."))
        (unless (or (null output) (stringp output))
          (error "Validation evidence :OUTPUT must be a string when present."))
        (apply #'%object
               (append (list (cons "status" (getf record :status))
                             (cons "tool" (getf record :tool)))
                       (and arguments (list (cons "arguments" (%array arguments))))
                       (and output (list (cons "output" output)))))))
    (sort (copy-list evidence) #'string< :key (lambda (record) (getf record :tool))))))

(defun %manifest-json (contract directory)
  (let* ((pipeline (build-contract-pipeline-result contract))
         (artifacts (sort (copy-list (ivory-key.backend:pipeline-result-artifacts pipeline))
                          #'%artifact<))
         (realizations
           (sort (copy-list (ivory-key.backend:pipeline-result-realizations pipeline))
                 #'%realization<))
         (entries
           (append
            (list
             (cons "artifacts" (%array (mapcar (lambda (artifact)
                                                  (%artifact-json artifact directory))
                                                artifacts)))
             (cons "compiler" (%object (cons "name" "ivory-key")
                                        (cons "version" (build-contract-compiler-version contract))))
             (cons "fidelity" (%array (mapcar #'%realization-json realizations)))
             (cons "language_version" (build-contract-language-version contract))
             (cons "schema_version" +build-contract-schema-version+)
             (cons "selected"
                   (%object (cons "device" (build-contract-device contract))
                            (cons "layout" (build-contract-layout contract))
                            (cons "profile" (build-contract-profile contract))
                            (cons "topology" (build-contract-topology contract))))
             (cons "sources" (%array (mapcar #'%source-json
                                              (build-contract-source-hashes contract)))))
            (and (build-contract-validation-evidence contract)
                 (list (cons "validation"
                             (%validation-evidence-json
                              (build-contract-validation-evidence contract))))))))
    (apply #'%object entries)))

(defun %allocations-json (contract)
  (let ((allocations
          (ivory-key.backend:pipeline-result-allocations
           (build-contract-pipeline-result contract))))
    (%object (cons "allocations" (%array (mapcar #'%allocation-json allocations)))
             (cons "schema_version" +build-contract-schema-version+))))

(defun %source-map-json (contract)
  (let* ((pipeline (build-contract-pipeline-result contract))
         (artifacts (sort (copy-list (ivory-key.backend:pipeline-result-artifacts pipeline))
                          #'%artifact<))
         (entries (sort (copy-list
                         (ivory-key.backend:lowering-request-entries
                          (ivory-key.backend:pipeline-result-request pipeline)))
                        #'%entry<)))
    (%object
     (cons "mappings"
           (%array
            (mapcan
             (lambda (artifact)
               (mapcar
                (lambda (entry)
                  (%object
                   (cons "artifact" (ivory-key.backend:pipeline-artifact-relative-path artifact))
                   (cons "backend" (%canonical-name
                                    (ivory-key.backend:pipeline-artifact-kind artifact)))
                   (cons "binding" (%canonical-name
                                    (ivory-key.backend:key-entry-position entry)))
                   (cons "mechanism" "direct-key-entry")))
                entries))
             artifacts)))
     (cons "schema_version" +build-contract-schema-version+))))

(defun %format-source-list (contract stream)
  (if (null (build-contract-source-hashes contract))
      (format stream "- No source hash records supplied.~%")
      (dolist (record (build-contract-source-hashes contract))
        (format stream "- `~A`: `~A`~%"
                (source-hash-record-path record)
                (source-hash-record-sha256 record)))))

(defun build-contract-report-string (contract directory)
  "Render the deterministic human-readable report for an already-emitted build."
  (unless (typep contract 'build-contract)
    (error "Build-contract report requires a BUILD-CONTRACT."))
  (let* ((pipeline (build-contract-pipeline-result contract))
         (artifacts (sort (copy-list (ivory-key.backend:pipeline-result-artifacts pipeline))
                          #'%artifact<))
         (realizations (sort (copy-list
                              (ivory-key.backend:pipeline-result-realizations pipeline))
                             #'%realization<))
         (allocations (ivory-key.backend:pipeline-result-allocations pipeline)))
    (with-output-to-string (stream)
      (format stream "# Ivory Key build report~%~%")
      (format stream "## Selected declarations~%~%")
      (format stream "- Layout: `~A`~%" (build-contract-layout contract))
      (format stream "- Topology: `~A`~%" (build-contract-topology contract))
      (format stream "- Device: `~A`~%" (build-contract-device contract))
      (format stream "- Profile: `~A`~%~%" (build-contract-profile contract))
      (format stream "## Source hashes~%~%")
      (%format-source-list contract stream)
      (format stream "~%## Fidelity grades~%~%")
      (dolist (result realizations)
        (format stream "- `~A`: **~A** — ~A~%"
                (%canonical-name (ivory-key.backend:realization-feature result))
                (%canonical-name (ivory-key.backend:realization-grade result))
                (ivory-key.backend:realization-detail result)))
      (format stream "~%## Generated artifacts~%~%")
      (dolist (artifact artifacts)
        (format stream "- `~A` (`~A`): `~A`~%"
                (ivory-key.backend:pipeline-artifact-relative-path artifact)
                (%canonical-name (ivory-key.backend:pipeline-artifact-kind artifact))
                (sha256-hex
                 (merge-pathnames
                  (ivory-key.backend:pipeline-artifact-relative-path artifact)
                  directory))))
      (format stream "~%## Allocations~%~%")
      (if allocations
          (dolist (allocation allocations)
            (let ((record (%allocation-json allocation)))
              (format stream "- `~A`~%" (%json-string record))))
          (format stream "No concrete resource allocations were made by the current direct pipeline.~%"))
      (format stream "~%## Validation~%~%")
      (if (build-contract-validation-evidence contract)
          (dolist (record (build-contract-validation-evidence contract))
            (format stream "- `~A`: ~A~%" (getf record :tool) (getf record :status)))
          (format stream "No external validation ran during compilation; no tool evidence is recorded.~%")))))

(defun write-build-contract-files (contract directory)
  "Write MANIFEST.JSON, ALLOCATIONS.JSON, SOURCE-MAP.JSON, and REPORT.MD.

DIRECTORY must already contain the backend artifacts named by CONTRACT.  The
caller owns atomic build-directory publication; this function only creates
contract files in that checked staging directory.
"
  (unless (typep contract 'build-contract)
    (error "Build-contract emission requires a BUILD-CONTRACT."))
  (let ((directory (uiop:ensure-directory-pathname directory)))
    (%write-json-file (merge-pathnames "manifest.json" directory)
                      (%manifest-json contract directory))
    (%write-json-file (merge-pathnames "allocations.json" directory)
                      (%allocations-json contract))
    (%write-json-file (merge-pathnames "source-map.json" directory)
                      (%source-map-json contract))
    (with-open-file (stream (merge-pathnames "REPORT.md" directory)
                            :direction :output :if-exists :error
                            :if-does-not-exist :create :external-format :utf-8)
      (write-string (build-contract-report-string contract directory) stream))
    contract))
