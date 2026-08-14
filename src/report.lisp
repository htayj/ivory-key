;;;; SPDX-License-Identifier: GPL-3.0-or-later

(in-package #:ivory-key.report)

(defun write-realization-report (pipeline-result stream)
  (format stream "Ivory Key realization report~%")
  (format stream "Layout: ~A~%~%"
          (ivory-key.backend:lowering-request-name
           (ivory-key.backend:pipeline-result-request pipeline-result)))
  (format stream "Features:~%")
  (dolist (result (ivory-key.backend:pipeline-result-realizations
                   pipeline-result))
    (format stream "  ~A: ~A -- ~A~%"
            (ivory-key.backend:realization-feature result)
            (string-downcase
             (symbol-name (ivory-key.backend:realization-grade result)))
            (ivory-key.backend:realization-detail result)))
  (format stream "~%Artifacts:~%")
  (dolist (artifact (ivory-key.backend:pipeline-result-artifacts
                     pipeline-result))
    (format stream "  ~A: ~A~%"
            (ivory-key.backend:pipeline-artifact-kind artifact)
            (ivory-key.backend:pipeline-artifact-relative-path artifact))))

(defun realization-report-string (pipeline-result)
  (with-output-to-string (stream)
    (write-realization-report pipeline-result stream)))
