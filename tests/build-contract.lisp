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

(defun build-contract-test-contract (pipeline)
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
   :pipeline-result pipeline))

(defun build-contract-test-write (directory pipeline)
  (ivory-key.backend:write-pipeline-result pipeline directory)
  (ivory-key.build-contract:write-build-contract-files
   (build-contract-test-contract pipeline) directory))

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
        (is (search "\"schema_version\":1" manifest))
        (is (search "\"language_version\":1" manifest))
        (is (search "\"layout\":\"contract-layout\"" manifest))
        (is (search "\"path\":\"a.ivory\"" manifest))
        (is (< (search "\"path\":\"a.ivory\"" manifest)
               (search "\"path\":\"z.ivory\"" manifest)))
        (is (search xkb-hash manifest))
        (is (not (search "\"validation\"" manifest)))
        (is-equal (format nil "{\"allocations\":[],\"schema_version\":1}~%")
                  allocations)
        (is (search "\"artifact\":\"keymap.xkb\"" source-map))
        (is (search "\"backend\":\"xkb\"" source-map))
        (is (search "\"binding\":\"q\"" source-map))
        (is (search "No concrete resource allocations" report))
        (is (search "No external validation ran during compilation" report))))))

(deftest build-contract-is-byte-deterministic-for-identical-pipeline-data
  (with-build-contract-test-directory (first)
    (with-build-contract-test-directory (second)
      (let ((pipeline (build-contract-test-pipeline)))
        (build-contract-test-write first pipeline)
        (build-contract-test-write second pipeline)
        (dolist (name '("manifest.json" "allocations.json" "source-map.json" "REPORT.md"))
          (is-equal (uiop:read-file-string (merge-pathnames name first))
                    (uiop:read-file-string (merge-pathnames name second))))))))
