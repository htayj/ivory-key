;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Separately tagged installed-Kanata validation for closed Manna proposals.

(require :asdf)
(asdf:load-asd (truename "ivory-key.asd"))
(asdf:load-system "ivory-key")

(defun external-manna-kanata-request (composition)
  (multiple-value-bind (unit placement realization)
      (ivory-key.cli:load-project-composition-for-compilation
       "manna-cadet-project.ivory" composition)
    (multiple-value-bind (request issues)
        (ivory-key.cli::analyze-normalized-layout
         (ivory-key.cli::compiler-unit-normalized unit) placement
         :vocabulary
         (ivory-key.cli::compiler-realization-vocabulary realization)
         :selector-policy
         (ivory-key.cli::compiler-realization-selector-policy realization)
         :interaction-compatibility-policy
         (ivory-key.cli::compiler-realization-interaction-compatibility-policy
          realization)
         :kanata-buffered-allocation-policy
         (ivory-key.cli::compiler-realization-kanata-buffered-allocation-policy
          realization))
      (unless issues
        (error "Manna proposal unexpectedly has no compiler refusal gates."))
      request)))

(defun validate-external-manna-kanata-proposal
    (composition expected-sources &key runtime-archive manna-root)
  (let* ((backend (ivory-key.backend:make-kanata-backend))
         (request (external-manna-kanata-request composition))
         (plan (ivory-key.backend:lower-request backend request))
         (config (ivory-key.backend:kanata-plan-buffered-config plan))
         (first (ivory-key.backend:kanata-plan-proposal-string plan))
         (second (ivory-key.backend:kanata-plan-proposal-string plan)))
    (unless (and config
                 (ivory-key.backend:kanata-buffered-config-native-domain-closed-p
                  config)
                 (= expected-sources
                    (length (ivory-key.backend::kanata-plan-sources plan)))
                 (string= first second)
                 (search "process-unmapped-keys no" first))
      (error "~A did not produce one deterministic closed native proposal."
             composition))
    (uiop:with-temporary-file (:pathname pathname :stream stream
                               :prefix "ivory-key-manna-" :suffix ".kbd"
                               :keep t)
      (unwind-protect
           (progn
             (write-string first stream)
             (finish-output stream)
             (close stream)
             (multiple-value-bind (success output arguments)
                 (ivory-key.backend:validate-artifact backend pathname)
               (unless success
                 (error "Kanata rejected ~A via ~S:~%~A"
                        composition arguments output)))
             (when runtime-archive
               (unless manna-root
                 (error "Generated runtime validation requires the frozen Manna root."))
               (let ((oracle (merge-pathnames
                              "tests/external/kanata-1.12-manna-oracle.sh"
                              (truename "./"))))
                 (multiple-value-bind (oracle-output ignored-output status)
                     (uiop:run-program
                      (list (namestring oracle) runtime-archive manna-root
                            (namestring pathname))
                      :output :string :error-output :output
                      :ignore-error-status t)
                   (declare (ignore ignored-output))
                   (unless (and (eql status 0)
                                (search "KANATA-1.12-MANNA-ORACLE: PASSED"
                                        oracle-output))
                     (error "Generated Kanata runtime oracle failed for ~A:~%~A"
                            composition oracle-output))
                   (format t "Generated Kanata 1.12 runtime oracle passed for ~A.~%"
                           composition)))))
        (when (probe-file pathname)
          (delete-file pathname))))))

(let ((arguments (uiop:command-line-arguments)))
  (cond
    ((null arguments)
     (validate-external-manna-kanata-proposal "manna-cadet-linux" 68)
     (validate-external-manna-kanata-proposal
      "manna-cadet-advantage360-linux" 72))
    ((and (= (length arguments) 3)
          (string= (first arguments) "--runtime-oracle"))
     (validate-external-manna-kanata-proposal
      "manna-cadet-linux" 68
      :runtime-archive (second arguments)
      :manna-root (third arguments))
     (validate-external-manna-kanata-proposal
      "manna-cadet-advantage360-linux" 72
      :runtime-archive (second arguments)
      :manna-root (third arguments)))
    (t
     (error "usage: manna-kanata-generated.lisp [--runtime-oracle ARCHIVE MANNA-ROOT]"))))
(format t "Manna generated Kanata proposals passed installed validation.~%")
