;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Focused deterministic generated-output-contract regressions.

(in-package #:ivory-key.tests)

(defun build-contract-test-directory ()
  (let ((directory
          (merge-pathnames
           (format nil "ivory-key-contract-~A/" (symbol-name (gensym "TEST-")))
           (uiop:temporary-directory))))
    (ensure-directories-exist (merge-pathnames "placeholder" directory))
    directory))

(defmacro with-build-contract-test-directory ((directory) &body body)
  `(let ((,directory (build-contract-test-directory)))
     (unwind-protect
          (progn ,@body)
       (when (probe-file ,directory)
         (delete-test-directory-tree ,directory)))))

(defun build-contract-test-pipeline ()
  (ivory-key.backend:compile-xkb-kanata-request
   (make-instance
    'ivory-key.backend:lowering-request
    :name "contract-test"
    :entries
    (list
     (make-instance 'ivory-key.backend:key-entry
                    :position "t"
                    :physical-code (list :xkb "AD02" :kanata "t")
                    :outputs (list :xkb '("t") :kanata '("t")))
     (make-instance 'ivory-key.backend:key-entry
                    :position "q"
                    :physical-code (list :xkb "AD01" :kanata "q")
                    :outputs (list :xkb '("q") :kanata '("q")))))))

(defun build-contract-test-contract (pipeline &key validation-evidence)
  (ivory-key.build-contract:make-build-contract
   :layout "contract-layout" :topology "contract-topology"
   :device "contract-device" :profile "contract-profile"
   ;; Deliberately reversed: the contract must sort sources without accepting
   ;; the caller's incidental construction order as output semantics.
   :source-hashes
   (list
    (ivory-key.build-contract:make-source-hash-record
     "z.ivory" (ivory-key.build-contract:sha256-hex "z"))
   (ivory-key.build-contract:make-source-hash-record
     "a.ivory" (ivory-key.build-contract:sha256-hex "a")))
   :input-coverage
   (list (list :position "t" :disposition :unreachable)
         (list :position "q" :disposition :physical))
   :pipeline-result pipeline
   :validation-evidence validation-evidence))

(defun build-contract-test-write (directory pipeline)
  (ivory-key.backend:write-pipeline-result pipeline directory)
  (ivory-key.build-contract:write-build-contract-files
   (build-contract-test-contract pipeline) directory))

(defun build-contract-test-rewrite-file (pathname transformation)
  "Replace one test-owned file with TRANSFORMATION of its current text."
  (let ((rewritten (funcall transformation (uiop:read-file-string pathname))))
    (with-open-file (stream pathname :direction :output :if-exists :supersede
                                    :external-format :utf-8)
      (write-string rewritten stream))))

(deftest build-contract-sha256-matches-standard-vector-and-uses-utf8
  (is-equal "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
            (ivory-key.build-contract:sha256-hex "abc"))
  ;; U+00E9 is the two octet UTF-8 sequence C3 A9, whose SHA-256 is stable
  ;; across the supported Common Lisp implementations.
  (is-equal "4a99557e4033c3539de2eb65472017cad5f9557f7a0625a09f1c3f6e2ba69c4c"
            (ivory-key.build-contract:sha256-hex "é")))

(deftest build-contract-writes-sorted-machine-readable-files-without-tool-claims
  (with-build-contract-test-directory (directory)
    (let* ((pipeline (build-contract-test-pipeline))
           (contract (build-contract-test-contract pipeline)))
      (ivory-key.backend:write-pipeline-result pipeline directory)
      (ivory-key.build-contract:write-build-contract-files contract directory)
      (dolist (name '("manifest.json" "allocations.json" "source-map.json" "REPORT.md"))
        (is (probe-file (merge-pathnames name directory))))
      (let* ((manifest (uiop:read-file-string (merge-pathnames "manifest.json" directory)))
             (allocations (uiop:read-file-string (merge-pathnames "allocations.json" directory)))
             (source-map (uiop:read-file-string (merge-pathnames "source-map.json" directory)))
             (report (uiop:read-file-string (merge-pathnames "REPORT.md" directory)))
             (xkb (merge-pathnames "keymap.xkb" directory))
             (xkb-hash (ivory-key.build-contract:sha256-hex xkb)))
        (is (search "\"schema_version\":5" manifest))
        (is (search "\"language_version\":1" manifest))
        (is (search "\"layout\":\"contract-layout\"" manifest))
        (is (search "\"path\":\"a.ivory\"" manifest))
        (is (< (search "\"path\":\"a.ivory\"" manifest)
               (search "\"path\":\"z.ivory\"" manifest)))
        (is (search xkb-hash manifest))
        (is (search "\"input_coverage\":[{\"disposition\":\"physical\",\"position\":\"q\"},{\"disposition\":\"unreachable\",\"position\":\"t\"}]"
                    manifest))
        (is (not (search "\"validation\"" manifest)))
        (is-equal (format nil "{\"allocations\":[],\"schema_version\":5}~%")
                  allocations)
        (is (search "\"artifact\":\"keymap.xkb\"" source-map))
        (is (search "\"backend\":\"xkb\"" source-map))
        (is (search "\"binding\":\"q\"" source-map))
        ;; Legacy programmatic entries remain explicitly unknown; no host
        ;; source is inferred merely because the contract has input hashes.
        (is (search "\"origin\":null" source-map))
        (is (search "No concrete resource allocations" report))
        (is (search "## Device input coverage" report))
        (is (search "`t`: unreachable" report))
        (is (search "No external validation ran during compilation" report))))))

(deftest build-contract-refuses-non-physical-coverage-states
  (signals error
    (ivory-key.build-contract:make-build-contract
     :layout "layout" :topology "topology" :device "device" :profile "profile"
     :source-hashes nil
     :input-coverage (list (list :position "q" :disposition :missing))
     :pipeline-result (build-contract-test-pipeline))))

(deftest build-contract-is-byte-deterministic-for-identical-pipeline-data
  (with-build-contract-test-directory (first)
    (with-build-contract-test-directory (second)
      (let ((pipeline (build-contract-test-pipeline)))
        (build-contract-test-write first pipeline)
        (build-contract-test-write second pipeline)
        (dolist (name '("manifest.json" "allocations.json" "source-map.json" "REPORT.md"))
          (is-equal (uiop:read-file-string (merge-pathnames name first))
                    (uiop:read-file-string (merge-pathnames name second))))))))

(deftest build-contract-renders-closed-versioned-validation-evidence
  (with-build-contract-test-directory (directory)
    (let* ((pipeline (build-contract-test-pipeline))
           ;; Deliberately reversed to prove that artifact/tool identity, not
           ;; caller construction order, fixes the immutable observation order.
           (kanata-version (format nil "kanata 1.12.0~%"))
           (xkb-version (format nil "xkbcli 1.13.2~%"))
           (kanata-result (format nil "configuration accepted~%"))
           (xkb-result (format nil "keymap accepted~%"))
           (evidence
             (list
              (list :artifact "layout.kbd" :tool "kanata"
                    :version "kanata 1.12.0"
                    :version-sha256 (ivory-key.build-contract:sha256-hex kanata-version)
                    :status "passed"
                    :result-sha256 (ivory-key.build-contract:sha256-hex kanata-result))
              (list :artifact "keymap.xkb" :tool "xkbcli"
                    :version "xkbcli 1.13.2"
                    :version-sha256 (ivory-key.build-contract:sha256-hex xkb-version)
                    :status "passed"
                    :result-sha256 (ivory-key.build-contract:sha256-hex xkb-result))))
           (contract (build-contract-test-contract
                      pipeline :validation-evidence evidence)))
      (ivory-key.backend:write-pipeline-result pipeline directory)
      (ivory-key.build-contract:write-build-contract-files contract directory)
      (let ((manifest (uiop:read-file-string (merge-pathnames "manifest.json" directory)))
            (report (uiop:read-file-string (merge-pathnames "REPORT.md" directory))))
        (is (search "\"validation\":[{\"artifact\":\"keymap.xkb\"" manifest))
        (is (< (search "\"artifact\":\"keymap.xkb\"" manifest)
               (search "\"artifact\":\"layout.kbd\"" manifest)))
        (is (search "\"version\":\"xkbcli 1.13.2\"" manifest))
        (is (search (ivory-key.build-contract:sha256-hex xkb-result) manifest))
        (is (not (search "keymap accepted" manifest)))
        (is (search "`xkbcli` (`keymap.xkb`): passed" report))
        (is (search "Version JSON: \"xkbcli 1.13.2\"" report))
        (is (search (ivory-key.build-contract:sha256-hex xkb-result) report))
        (is (not (search "keymap accepted" report)))))))

(deftest build-contract-refuses-ambiguous-or-incomplete-validation-evidence
  (let ((pipeline (build-contract-test-pipeline)))
    (signals error
      (build-contract-test-contract
       pipeline
       :validation-evidence
       (list (list :artifact "keymap.xkb" :tool "xkbcli"
                   :status "passed"
                   :result-sha256 (ivory-key.build-contract:sha256-hex "accepted")))))
    (signals error
      (build-contract-test-contract
       pipeline
       :validation-evidence
       (list (list :artifact "keymap.xkb" :tool "xkbcli"
                   :version "1" :version-sha256 (ivory-key.build-contract:sha256-hex "1")
                   :status "passed"
                   :result-sha256 (ivory-key.build-contract:sha256-hex "accepted"))
             (list :artifact "keymap.xkb" :tool "xkbcli"
                   :version "1" :version-sha256 (ivory-key.build-contract:sha256-hex "1")
                   :status "passed"
                   :result-sha256 (ivory-key.build-contract:sha256-hex "accepted")))))))

(defun build-contract-provenance-origin (source-name)
  (let ((source (ivory-key.source:make-source-file :name source-name :text "")))
    (ivory-key.source:make-source-origin
     :definition-span
     (ivory-key.source:make-source-span
      :source source :start-line 7 :start-column 9)
     ;; Definition-nearest first is semantic order, not a filename sort.
     :use-spans
     (list (ivory-key.source:make-source-span
            :source source :start-line 21 :start-column 4)
           (ivory-key.source:make-source-span
            :source source :start-line 34 :start-column 6)))))

(defun build-contract-provenance-pipeline (origin)
  (let* ((requirement
           (ivory-key.backend:make-planner-resource-requirement
            :named-key "escape" :detail "Test allocation."
            :origins (list origin)))
         (allocation
           (ivory-key.backend:make-planner-allocation
            requirement :named-key "Escape"))
         (request
           (make-instance
            'ivory-key.backend:lowering-request
            :name "provenance"
            :entries
            (list
             (make-instance 'ivory-key.backend:key-entry
                            :position "q"
                            :physical-code (list :xkb "AD01" :kanata "q")
                            :outputs (list :xkb '("q") :kanata '("q"))
                            :sources
                            (list (ivory-key.backend:make-key-entry-source
                                   nil :origin origin))))
            :metadata (list :allocations (list allocation)))))
    (ivory-key.backend:compile-xkb-kanata-request request)))

(defun build-contract-provenance-contract (pipeline source-name)
  (ivory-key.build-contract:make-build-contract
   :layout "provenance-layout" :topology "provenance-topology"
   :device "provenance-device" :profile "provenance-profile"
   :source-hashes
   (list (ivory-key.build-contract:make-source-hash-record
          "source/layout.ivory" (ivory-key.build-contract:sha256-hex "layout")))
   ;; SOURCE-NAME is local parser state.  Only its stable right-hand identity
   ;; may appear in generated JSON.
   :source-name-identities (list (cons source-name "source/layout.ivory"))
   :input-coverage (list (list :position "q" :disposition :physical))
   :pipeline-result pipeline))

(deftest build-contract-renders-relocatable-entry-and-allocation-provenance
  (with-build-contract-test-directory (directory)
    (let* ((source-name "/private/checkout-a/layout.ivory")
           (origin (build-contract-provenance-origin source-name))
           (pipeline (build-contract-provenance-pipeline origin))
           (contract (build-contract-provenance-contract pipeline source-name)))
      (ivory-key.backend:write-pipeline-result pipeline directory)
      (ivory-key.build-contract:write-build-contract-files contract directory)
      (let ((source-map (uiop:read-file-string (merge-pathnames "source-map.json" directory)))
            (allocations (uiop:read-file-string (merge-pathnames "allocations.json" directory))))
        (is (search "\"schema_version\":5" source-map))
        (is (search "\"source\":\"source/layout.ivory\"" source-map))
        (is (search "\"line\":7" source-map))
        (is (search "\"column\":9" source-map))
        (is (< (search "\"line\":21" source-map)
               (search "\"line\":34" source-map)))
        (is (not (search source-name source-map)))
        (is (search "\"origins\":[{\"definition\"" allocations))
        (is (search "\"source\":\"source/layout.ivory\"" allocations))
        (is (not (search source-name allocations)))))))

(deftest build-contract-provenance-is-relocation-equivalent
  (with-build-contract-test-directory (first-directory)
    (with-build-contract-test-directory (second-directory)
      (let* ((first-name "/worktree-one/definitions/layout.ivory")
             (second-name "/worktree-two/definitions/layout.ivory")
             (first-pipeline
               (build-contract-provenance-pipeline
                (build-contract-provenance-origin first-name)))
             (second-pipeline
               (build-contract-provenance-pipeline
                (build-contract-provenance-origin second-name)))
             (first-contract
               (build-contract-provenance-contract first-pipeline first-name))
             (second-contract
               (build-contract-provenance-contract second-pipeline second-name)))
        (ivory-key.backend:write-pipeline-result first-pipeline first-directory)
        (ivory-key.backend:write-pipeline-result second-pipeline second-directory)
        (ivory-key.build-contract:write-build-contract-files first-contract first-directory)
        (ivory-key.build-contract:write-build-contract-files second-contract second-directory)
        (dolist (name '("source-map.json" "allocations.json"))
          (is-equal (uiop:read-file-string (merge-pathnames name first-directory))
                    (uiop:read-file-string (merge-pathnames name second-directory))))))))

(deftest build-contract-refuses-unmapped-or-ambiguous-non-nil-provenance
  (with-build-contract-test-directory (directory)
    (let* ((origin (build-contract-provenance-origin "/outside/layout.ivory"))
           (pipeline (build-contract-provenance-pipeline origin))
           (contract (build-contract-provenance-contract
                      pipeline "/different/layout.ivory")))
      (ivory-key.backend:write-pipeline-result pipeline directory)
      (signals error
        (ivory-key.build-contract:write-build-contract-files contract directory))))
  (signals error
    (ivory-key.build-contract:make-build-contract
     :layout "layout" :topology "topology" :device "device" :profile "profile"
     :source-hashes
     (list (ivory-key.build-contract:make-source-hash-record
            "one.ivory" (ivory-key.build-contract:sha256-hex "one"))
           (ivory-key.build-contract:make-source-hash-record
            "two.ivory" (ivory-key.build-contract:sha256-hex "two")))
     :source-name-identities '( ("same-source" . "one.ivory")
                                ("same-source" . "two.ivory"))
     :input-coverage nil
     :pipeline-result (build-contract-test-pipeline))))

(deftest build-contract-preflight-verifies-a-published-build-without-writing
  (with-build-contract-test-directory (directory)
    (let* ((pipeline (build-contract-test-pipeline))
           (artifacts-before nil)
           (contract-before nil))
      (build-contract-test-write directory pipeline)
      (setf artifacts-before
            (mapcar (lambda (name)
                      (cons name (uiop:read-file-string (merge-pathnames name directory))))
                    '("keymap.xkb" "layout.kbd" "source-map.json" "allocations.json"))
            contract-before
            (uiop:read-file-string (merge-pathnames "manifest.json" directory)))
      (let ((result
              (ivory-key.build-contract:preflight-build-contract-directory directory)))
        (is-equal 5 (getf result :schema-version))
        (is-equal '("keymap.xkb" "layout.kbd")
                  (mapcar (lambda (artifact) (getf artifact :path))
                          (getf result :artifacts)))
        (is-equal 4 (getf result :mapping-count))
        (is-equal 0 (getf result :allocation-count))
        (is-equal :absent (getf result :validation-evidence)))
      ;; Preflight is an observation: all published bytes remain untouched.
      (dolist (entry artifacts-before)
        (is-equal (cdr entry)
                  (uiop:read-file-string (merge-pathnames (car entry) directory))))
      (is-equal contract-before
                (uiop:read-file-string (merge-pathnames "manifest.json" directory))))))

(deftest build-contract-preflight-refuses-tampering-and-host-reader-syntax
  (with-build-contract-test-directory (directory)
    (let ((pipeline (build-contract-test-pipeline)))
      (build-contract-test-write directory pipeline)
      (with-open-file (stream (merge-pathnames "keymap.xkb" directory)
                              :direction :output :if-exists :supersede
                              :external-format :utf-8)
        (write-string "tampered" stream))
      (signals error
        (ivory-key.build-contract:preflight-build-contract-directory directory)))
  (with-build-contract-test-directory (directory)
    (let ((pipeline (build-contract-test-pipeline)))
      (build-contract-test-write directory pipeline)
      ;; This is not JSON.  The restricted decoder must reject it as data;
      ;; it must never hand the generated file to the host Lisp reader.
      (with-open-file (stream (merge-pathnames "manifest.json" directory)
                              :direction :output :if-exists :supersede
                              :external-format :utf-8)
        (write-string "#.(error \"host reader must not run\")" stream))
      (signals error
        (ivory-key.build-contract:preflight-build-contract-directory directory))))))

(deftest build-contract-preflight-requires-relocatable-allocation-origins
  (with-build-contract-test-directory (directory)
    (let* ((source-name "/private/checkout/layout.ivory")
           (pipeline
             (build-contract-provenance-pipeline
              (build-contract-provenance-origin source-name)))
           (contract (build-contract-provenance-contract pipeline source-name)))
      (ivory-key.backend:write-pipeline-result pipeline directory)
      (ivory-key.build-contract:write-build-contract-files contract directory)
      (let ((result
              (ivory-key.build-contract:preflight-build-contract-directory directory)))
        (is-equal 2 (getf result :mapping-count))
        (is-equal 1 (getf result :allocation-count))))))

(deftest build-contract-preflight-bounds-untrusted-json-resources
  (with-build-contract-test-directory (directory)
    (let ((pathname (merge-pathnames "untrusted.json" directory)))
      (flet ((rejects (text)
               (with-open-file (stream pathname :direction :output :if-exists :supersede
                                                :if-does-not-exist :create
                                                :external-format :utf-8)
                 (write-string text stream))
               (signals error
                 (ivory-key.build-contract::%preflight-json-file
                  pathname directory "untrusted.json"))))
        ;; Every case is valid enough to reach its explicit parser bound.
        (rejects (concatenate 'string
                              (make-string ivory-key.build-contract::+build-contract-preflight-max-depth+
                                           :initial-element #\[)
                              "0"
                              (make-string ivory-key.build-contract::+build-contract-preflight-max-depth+
                                           :initial-element #\])))
        (rejects (with-output-to-string (stream)
                   (write-char #\[ stream)
                   (dotimes (index (1+ ivory-key.build-contract::+build-contract-preflight-max-container-members+))
                     (when (plusp index) (write-char #\, stream))
                     (write-char #\0 stream))
                   (write-char #\] stream)))
        (rejects (format nil "\"~A\""
                         (make-string (1+ ivory-key.build-contract::+build-contract-preflight-max-string-characters+)
                                      :initial-element #\x)))
        (rejects (make-string (1+ ivory-key.build-contract::+build-contract-preflight-max-integer-digits+)
                              :initial-element #\1))))))

(deftest build-contract-preflight-refuses-unknown-duplicate-and-malformed-shapes
  (with-build-contract-test-directory (directory)
    (let ((pipeline (build-contract-test-pipeline)))
      (build-contract-test-write directory pipeline)
      (build-contract-test-rewrite-file
       (merge-pathnames "manifest.json" directory)
       (lambda (text)
         (let ((trimmed (string-right-trim '(#\Newline #\Return) text)))
           (concatenate 'string (subseq trimmed 0 (1- (length trimmed)))
                        ",\"unknown\":true}"))))
      (signals error
        (ivory-key.build-contract:preflight-build-contract-directory directory))))
  (with-build-contract-test-directory (directory)
    (let ((pipeline (build-contract-test-pipeline)))
      (build-contract-test-write directory pipeline)
      (with-open-file (stream (merge-pathnames "manifest.json" directory)
                              :direction :output :if-exists :supersede
                              :external-format :utf-8)
        (write-string "{\"schema_version\":5,\"schema_version\":5}" stream))
      (signals error
        (ivory-key.build-contract:preflight-build-contract-directory directory))))
  (with-build-contract-test-directory (directory)
    (let ((pipeline (build-contract-test-pipeline)))
      (build-contract-test-write directory pipeline)
      (with-open-file (stream (merge-pathnames "source-map.json" directory)
                              :direction :output :if-exists :supersede
                              :external-format :utf-8)
        (write-string "{\"mappings\":[{\"artifact\":\"keymap.xkb\"}],\"schema_version\":5}" stream))
      (signals error
        (ivory-key.build-contract:preflight-build-contract-directory directory)))))

(deftest build-contract-preflight-refuses-invalid-evidence-digests
  (with-build-contract-test-directory (directory)
    (let* ((pipeline (build-contract-test-pipeline))
           (evidence
             (list (list :artifact "keymap.xkb" :tool "xkbcli" :version "xkbcli test"
                         :version-sha256 (ivory-key.build-contract:sha256-hex "xkbcli test\n")
                         :status "passed"
                         :result-sha256 (ivory-key.build-contract:sha256-hex "accepted\n"))))
           (contract (build-contract-test-contract pipeline :validation-evidence evidence)))
      (ivory-key.backend:write-pipeline-result pipeline directory)
      (ivory-key.build-contract:write-build-contract-files contract directory)
      (build-contract-test-rewrite-file
       (merge-pathnames "manifest.json" directory)
       (lambda (text)
         (let* ((marker "\"version_sha256\":\"")
                (start (+ (search marker text) (length marker))))
           (setf (char text start) #\Z)
           text)))
      (signals error
        (ivory-key.build-contract:preflight-build-contract-directory directory)))))

(deftest build-contract-preflight-refuses-symlinked-child-escape
  (with-build-contract-test-directory (directory)
    (with-build-contract-test-directory (outside-directory)
      (let* ((pipeline (build-contract-test-pipeline))
             (artifact (merge-pathnames "layout.kbd" directory))
             (outside (merge-pathnames "outside.kbd" outside-directory)))
        (build-contract-test-write directory pipeline)
        (with-open-file (stream outside :direction :output :if-does-not-exist :create
                                        :external-format :utf-8)
          (write-string "outside build root" stream))
        (delete-file artifact)
        (make-test-symbolic-link outside artifact)
        (signals error
          (ivory-key.build-contract:preflight-build-contract-directory directory))
        ;; The generic test cleanup intentionally avoids traversing symlinks;
        ;; unlink this test-owned escape before its enclosing temporary tree.
        (delete-file artifact)))))

(deftest build-contract-preflight-detects-replacement-during-observation
  (with-build-contract-test-directory (directory)
    (let ((pipeline (build-contract-test-pipeline)))
      (build-contract-test-write directory pipeline)
      (let ((ivory-key.build-contract::*preflight-after-initial-digest-hook*
              (lambda (pathname)
                (when (string= (file-namestring pathname) "manifest.json")
                  (with-open-file (stream pathname :direction :output :if-exists :supersede
                                                  :external-format :utf-8)
                    (write-string "{}" stream))))))
        (signals error
          (ivory-key.build-contract:preflight-build-contract-directory directory))))))
