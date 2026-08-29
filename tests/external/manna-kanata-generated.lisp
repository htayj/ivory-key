;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;; Separately tagged installed-Kanata validation for emitted Manna artifacts.

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
      (when issues
        (error "Manna compilation retained refusal gates: ~S"
               (mapcar #'ivory-key.cli::compiler-fidelity-issue-code issues)))
      request)))

(defun validate-external-manna-kanata-artifact
    (composition expected-sources expected-input-endpoint expected-output-name
     &key runtime-archive manna-root)
  (let* ((backend (ivory-key.backend:make-kanata-backend))
         (request (external-manna-kanata-request composition))
         (plan (ivory-key.backend:lower-request backend request))
         (config (ivory-key.backend:kanata-plan-buffered-config plan))
         (first (ivory-key.backend:emit-plan-to-string backend plan))
         (second (ivory-key.backend:emit-plan-to-string backend plan)))
    (unless (and config
                 (ivory-key.backend:kanata-buffered-config-native-domain-closed-p
                  config)
                 (= expected-sources
                    (length (ivory-key.backend::kanata-plan-sources plan)))
                 (string= first second)
                 (= 1 (length
                       (ivory-key.backend:kanata-buffered-config-input-endpoints
                        config)))
                 (string= expected-input-endpoint
                          (ivory-key.model:device-input-endpoint-locator
                           (first
                            (ivory-key.backend:kanata-buffered-config-input-endpoints
                             config))))
                 (search (format nil "linux-dev ~A" expected-input-endpoint)
                         first)
                 (search
                  (format nil "linux-output-device-name \"~A\""
                          expected-output-name)
                  first)
                 (search "process-unmapped-keys no" first))
      (error "~A did not produce one deterministic closed native artifact."
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
     (validate-external-manna-kanata-artifact
      "manna-cadet-linux" 68
      "/dev/input/by-id/usb-Kinesis_Advantage2_Keyboard_314159265359-if01-event-kbd"
      "ivory-key-manna-advantage2")
     (validate-external-manna-kanata-artifact
      "manna-cadet-advantage360-linux" 72
      "/dev/input/by-id/usb-Kinesis_Kinesis_Adv360_360555127546-if01-event-kbd"
      "ivory-key-manna-advantage360"))
    ((and (= (length arguments) 3)
          (string= (first arguments) "--runtime-oracle"))
     (validate-external-manna-kanata-artifact
      "manna-cadet-linux" 68
      "/dev/input/by-id/usb-Kinesis_Advantage2_Keyboard_314159265359-if01-event-kbd"
      "ivory-key-manna-advantage2"
      :runtime-archive (second arguments)
      :manna-root (third arguments))
     (validate-external-manna-kanata-artifact
      "manna-cadet-advantage360-linux" 72
      "/dev/input/by-id/usb-Kinesis_Kinesis_Adv360_360555127546-if01-event-kbd"
      "ivory-key-manna-advantage360"
      :runtime-archive (second arguments)
      :manna-root (third arguments)))
    (t
     (error "usage: manna-kanata-generated.lisp [--runtime-oracle ARCHIVE MANNA-ROOT]"))))
(format t "Manna generated Kanata artifacts passed installed validation.~%")
