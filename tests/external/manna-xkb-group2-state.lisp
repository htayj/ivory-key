;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;;
;;;; Tagged, read-only frozen-Manna XKB state probe; not an ASDF component.
;;;;
;;;; Invoke from the Ivory Key checkout root:
;;;;   sbcl --script tests/external/manna-xkb-group2-state.lisp MANNA-ROOT
;;;;
;;;; This validates the hash-addressed frozen Manna inputs, then asks
;;;; libxkbcommon to compile the frozen XKB keymap and inspect its key/state
;;;; API behavior. It does not invoke Kanata, create a device, choose a
;;;; selector policy, or compile Ivory Key input.

(require "asdf")

(defpackage #:ivory-key.external-manna-xkb-group2-state
  (:use #:cl))

(in-package #:ivory-key.external-manna-xkb-group2-state)

(defparameter +external-validation-tag+ :external-manna-xkb-group2-state)

(defparameter +frozen-manna-inputs+
  '(("xkb/symbols/spacecadet"
     "b559d8832462556f990bee273b53a91ab2c6c81fc7e2fa9c9bb0cdfce739f3a0")
    ("xkb/keymap/spacecadet.xkb"
     "68dcb0f3c77fa2b88cfc2db04347b07089efad25a2bcf8b86324a5f283539fba")
    ("kanata/kinesis.advantage2.layered.kanata.kbd"
     "d36a93eab6e2355707f7a6bfbcfac2a4e3b0ea361cc399d388543f51e1f5226b")
    ("kanata/kinesis.advantage360.layered.kanata.kbd"
     "632a7574938b535a8d4b1d2e3ce1c5f711d0486298d2ce4d98adda702496df5a")
    ("space-cadet-layered-mnemonics.md"
     "8c4c975e0acee03f96f51ae144f2c12c1efc249672b4ef50e39a781e8f27bc7b")))

(defun repository-root ()
  "Return the Ivory Key root from this script's stable load pathname."
  (let* ((script (or *load-pathname* *compile-file-pathname*
                     (error "External validation needs a load pathname.")))
         (external-directory
           (uiop:pathname-directory-pathname (truename script)))
         (tests-directory
           (uiop:pathname-parent-directory-pathname external-directory)))
    (uiop:pathname-parent-directory-pathname tests-directory)))

(defun source-root (argument)
  "Resolve one existing Manna checkout directory without accepting a default."
  (let ((pathname (uiop:ensure-directory-pathname (pathname argument))))
    (unless (uiop:directory-exists-p pathname)
      (error "Frozen Manna checkout is not a directory: ~A" argument))
    (truename pathname)))

(defun require-frozen-inputs (root)
  "Reject any checkout whose reviewed source inputs differ in bytes."
  (dolist (entry +frozen-manna-inputs+)
    (destructuring-bind (relative expected) entry
      (let ((pathname (merge-pathnames relative root)))
        (unless (probe-file pathname)
          (error "Frozen Manna input is absent: ~A" pathname))
        (let* ((result (uiop:run-program
                        (list "sha256sum" (namestring pathname))
                        :output :string :error-output :output))
               (actual (subseq result 0 64)))
          (unless (string= actual expected)
            (error "Frozen Manna input hash differs for ~A: ~A"
                   relative actual)))))))

(defun split-tool-flags (text)
  "Split PKG-CONFIG flags without invoking a shell."
  (remove ""
          (uiop:split-string text
                             :separator '(#\Space #\Tab #\Newline #\Return))
          :test #'string=))

(defun temporary-directory ()
  (let ((directory
          (merge-pathnames
           (format nil "ivory-key-manna-xkb-group2-state-~A/"
                   (symbol-name (gensym "VALIDATION-")))
           (uiop:temporary-directory))))
    (ensure-directories-exist (merge-pathnames "placeholder" directory))
    directory))

(defun compile-probe (directory)
  "Compile the checked-in C probe with literal argv elements."
  (let* ((source (merge-pathnames "tests/external/manna-xkb-group2-state.c"
                                  (repository-root)))
         (binary (merge-pathnames "manna-xkb-group2-state" directory))
         (flags
           (split-tool-flags
            (uiop:run-program '("pkg-config" "--cflags" "--libs" "xkbcommon")
                              :output :string :error-output :output)))
         (arguments
           (append (list "gcc" "-std=c11" "-Wall" "-Wextra" "-Werror"
                         (namestring source) "-o" (namestring binary))
                   flags)))
    (uiop:run-program arguments :output :string :error-output :output)
    binary))

(defun run-probe (root)
  "Run the standalone state probe after its frozen source identity is checked."
  (require-frozen-inputs root)
  (let ((directory (temporary-directory)))
    (unwind-protect
         (let* ((binary (compile-probe directory))
                (keymap (merge-pathnames "xkb/keymap/spacecadet.xkb" root))
                (include-directory (merge-pathnames "xkb/" root))
                (output (uiop:run-program
                         (list (namestring binary) (namestring keymap)
                               (namestring include-directory))
                         :output :string :error-output :output)))
           (unless (search "MANNA-XKB-GROUP2-STATE: PASSED" output)
             (error "Frozen Manna Group-2 state probe did not pass:~%~A"
                    output))
           (format t "EXTERNAL-VALIDATION ~S: PASSED (hash-pinned frozen XKB state boundary inspected through libxkbcommon).~%"
                   +external-validation-tag+)
           :passed)
      (when (probe-file directory)
        (uiop:delete-directory-tree directory :validate t)))))

(defun external-command-line-arguments ()
  "Return script arguments on the two checked Common Lisp implementations."
  #+ecl
  (let ((shell (member "-shell" si:*command-args* :test #'string=)))
    (if shell
        (cddr shell)
        (uiop:command-line-arguments)))
  #-ecl
  (uiop:command-line-arguments))

(defun main ()
  (let ((arguments (external-command-line-arguments)))
    (unless (= (length arguments) 1)
      (error "Usage: manna-xkb-group2-state.lisp MANNA-ROOT"))
    (run-probe (source-root (first arguments)))))

(handler-case
    (progn
      (main)
      (uiop:quit 0))
  (error (condition)
    (format *error-output* "EXTERNAL-VALIDATION ~S: FAILED~%~A~%"
            +external-validation-tag+ condition)
    (uiop:quit 1)))
