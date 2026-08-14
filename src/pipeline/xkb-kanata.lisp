;;;; SPDX-License-Identifier: GPL-3.0-or-later

(in-package #:ivory-key.backend)

(defclass pipeline-artifact ()
  ((kind :initarg :kind :reader pipeline-artifact-kind)
   (relative-path :initarg :relative-path :reader pipeline-artifact-relative-path)
   (content :initarg :content :reader pipeline-artifact-content)))

(defclass pipeline-result ()
  ((request :initarg :request :reader pipeline-result-request)
   (artifacts :initarg :artifacts :reader pipeline-result-artifacts)
   (realizations :initarg :realizations :reader pipeline-result-realizations)
   (allocations :initarg :allocations :initform nil
                :reader pipeline-result-allocations)))

(defun %artifact-output-pathname (artifact output-directory)
  "Resolve ARTIFACT below OUTPUT-DIRECTORY, rejecting path traversal.

Artifact paths are compiler data today, but keeping this check at the final
write/validation boundary prevents a future backend or deserialized plan from
escaping the requested build directory."
  (let* ((base (uiop:ensure-directory-pathname
                (uiop:ensure-absolute-pathname output-directory)))
         (relative (pathname (pipeline-artifact-relative-path artifact)))
         (directory (pathname-directory relative)))
    (unless (and (uiop:relative-pathname-p relative)
                 (pathname-name relative)
                 (not (wild-pathname-p relative))
                 (notany (lambda (component)
                           (member component '(:up :back :absolute)
                                   :test #'eq))
                         directory))
      (error "Unsafe pipeline artifact path ~S."
             (pipeline-artifact-relative-path artifact)))
    (let ((candidate (uiop:subpathname base relative)))
      (unless (and candidate (uiop:subpathp candidate base))
        (error "Pipeline artifact path ~S escapes output directory ~A."
               (pipeline-artifact-relative-path artifact) base))
      candidate)))

(defun compile-xkb-kanata-request (request &key allow-lossy)
  (let* ((xkb (make-xkb-backend))
         (kanata (make-kanata-backend))
         (xkb-plan (lower-request xkb request))
         (kanata-plan (lower-request kanata request))
         (realizations (append (xkb-plan-realizations xkb-plan)
                               (kanata-plan-realizations kanata-plan))))
    (require-permitted-realizations realizations :allow-lossy allow-lossy)
    (make-instance
     'pipeline-result
     :request request
     :realizations realizations
     :artifacts
     (list (make-instance 'pipeline-artifact
                          :kind :xkb
                          :relative-path "keymap.xkb"
                          :content (emit-plan-to-string xkb xkb-plan))
           (make-instance 'pipeline-artifact
                          :kind :kanata
                          :relative-path "layout.kbd"
                          :content (emit-plan-to-string kanata kanata-plan))))))

(defun write-pipeline-result (result output-directory)
  (ensure-directories-exist
   (merge-pathnames "placeholder" (uiop:ensure-directory-pathname output-directory)))
  (dolist (artifact (pipeline-result-artifacts result) result)
    (let ((pathname (%artifact-output-pathname artifact output-directory)))
      (ensure-directories-exist pathname)
      (with-open-file (stream pathname
                              :direction :output
                              :if-exists :supersede
                              :if-does-not-exist :create)
        (write-string (pipeline-artifact-content artifact) stream)))))

(defun validate-pipeline-result (result output-directory)
  (loop for artifact in (pipeline-result-artifacts result)
        for pathname = (%artifact-output-pathname artifact output-directory)
        for backend = (ecase (pipeline-artifact-kind artifact)
                        (:xkb (make-xkb-backend))
                        (:kanata (make-kanata-backend)))
        collect
        (multiple-value-bind (success output arguments)
            (validate-artifact backend pathname)
          (list :kind (pipeline-artifact-kind artifact)
                :success success :output output :arguments arguments))))
