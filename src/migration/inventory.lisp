;;;; SPDX-License-Identifier: GPL-3.0-or-later

(in-package #:ivory-key.migration)

(defparameter +manna-cadet-baseline-files+
  '("xkb/symbols/spacecadet"
    "xkb/keymap/spacecadet.xkb"
    "kanata/kinesis.advantage2.layered.kanata.kbd"
    "kanata/kinesis.advantage360.layered.kanata.kbd"
    "space-cadet-layered-mnemonics.md"))

(defclass manna-cadet-inventory ()
  ((root :initarg :root :reader inventory-root)
   (source-commit :initarg :source-commit :reader inventory-source-commit)
   (files :initarg :files :reader inventory-files)
   (tools :initarg :tools :reader inventory-tools)
   (evidence :initarg :evidence :reader inventory-evidence)))

(defun run-command-output (arguments &key directory)
  (handler-case
      (string-trim '(#\Space #\Tab #\Newline #\Return)
                   (uiop:run-program arguments :directory directory
                                     :output :string :error-output :output))
    (error (condition)
      (format nil "unavailable: ~A" condition))))

(defun sha256-pathname (pathname)
  (let ((output (run-command-output (list "sha256sum" (namestring pathname)))))
    (let ((separator (position-if (lambda (character)
                                    (member character '(#\Space #\Tab)))
                                  output)))
      (if separator (subseq output 0 separator) output))))

(defun collect-matching-lines (pathname needles)
  (with-open-file (stream pathname :direction :input)
    (loop for line = (read-line stream nil nil)
          for line-number from 1
          while line
          when (some (lambda (needle) (search needle line :test #'char-equal))
                     needles)
            collect (list :line line-number :text line))))

(defun inventory-manna-cadet (root)
  "Collect a read-only, hash-addressed inventory of a Manna Cadet checkout."
  (let* ((directory (uiop:ensure-directory-pathname root))
         (files
           (loop for relative in +manna-cadet-baseline-files+
                 for pathname = (merge-pathnames relative directory)
                 do (unless (probe-file pathname)
                      (error "Missing Manna Cadet baseline file ~A." pathname))
                 collect (list :relative-path relative
                               :sha256 (sha256-pathname pathname)
                               :bytes (with-open-file (stream pathname
                                                              :element-type '(unsigned-byte 8))
                                        (file-length stream)))))
         (evidence
           (list
            :xkb (collect-matching-lines
                  (merge-pathnames "xkb/symbols/spacecadet" directory)
                  '("key <" "modifier_map" "SetGroup" "NoSymbol"))
            :kanata-advantage2
            (collect-matching-lines
             (merge-pathnames
              "kanata/kinesis.advantage2.layered.kanata.kbd" directory)
             '("tap-hold" "defalias" "deflayer" "arbitrary-code"))
            :kanata-advantage360
            (collect-matching-lines
             (merge-pathnames
              "kanata/kinesis.advantage360.layered.kanata.kbd" directory)
             '("tap-hold" "defalias" "deflayer" "arbitrary-code")))))
    (make-instance
     'manna-cadet-inventory
     :root directory
     :source-commit (run-command-output '("git" "rev-parse" "HEAD")
                                        :directory directory)
     :files files
     :tools (list :sbcl (lisp-implementation-version)
                  :kanata (run-command-output '("kanata" "--version"))
                  :xkbcli (run-command-output '("xkbcli" "--version")))
     :evidence evidence)))

(defun write-inventory-report (inventory stream)
  (format stream "Manna Cadet baseline inventory~%")
  (format stream "Root: ~A~%Commit: ~A~%~%"
          (inventory-root inventory)
          (inventory-source-commit inventory))
  (format stream "Tools:~%")
  (loop for (name version) on (inventory-tools inventory) by #'cddr
        do (format stream "  ~A: ~A~%" name version))
  (format stream "~%Files:~%")
  (dolist (file (inventory-files inventory))
    (format stream "  ~A  ~A  ~D bytes~%"
            (getf file :sha256)
            (getf file :relative-path)
            (getf file :bytes)))
  (format stream "~%Evidence counts:~%")
  (loop for (kind entries) on (inventory-evidence inventory) by #'cddr
        do (format stream "  ~A: ~D matching lines~%" kind (length entries)))
  inventory)
