;;;; Frozen Manna Cadet baseline regression check.
;;;; SPDX-License-Identifier: GPL-3.0-or-later
;;;;
;;;; This is intentionally a separately invoked integration test: it requires
;;;; the read-only Manna Cadet checkout rather than making the normal Ivory Key
;;;; test system depend on a machine-local path.
;;;;
;;;; Run:
;;;;   sbcl --script tests/migration/manna-truth-table.lisp \
;;;;     /home/tay/src/dotfiles/keyboard/manna-cadet

(require :asdf)

(defun test-directory ()
  (uiop:pathname-directory-pathname
   (or *load-truename*
       (error "Cannot determine the migration-test path."))))

(defun repository-root ()
  (merge-pathnames "../../" (test-directory)))

(defun truth-table-tool ()
  (merge-pathnames "tools/manna-truth-table.lisp" (repository-root)))

(defun tool-output (command root)
  (uiop:run-program (list "sbcl" "--script" (namestring (truth-table-tool)) command root)
                    :output :string :error-output :output))

(defun required-root (arguments)
  (or (first arguments)
      (error "Supply the frozen Manna Cadet checkout root as the only argument.")))

(defun main (&optional (arguments (uiop:command-line-arguments)))
  (unless (= (length arguments) 1)
    (error "Usage: sbcl --script tests/migration/manna-truth-table.lisp ROOT"))
  (let* ((root (required-root arguments))
         (verification (tool-output "verify" root))
         (first-render (tool-output "render" root))
         (second-render (tool-output "render" root)))
    (unless (search "Manna Cadet frozen baseline verified" verification)
      (error "Frozen baseline verification did not report success: ~A" verification))
    (unless (search "3ef72eabdd26d2154481c1b8fd0becba50dfbb9a0ba50d0d37556930f92dc807"
                    verification)
      (error "Verification did not report the expected truth-table digest: ~A" verification))
    (unless (string= first-render second-render)
      (error "Truth-table rendering is not deterministic."))
    (unless (and (search "| `<AE01>` | `1` | `exclam` |" first-render)
                 (search "| `<LSGT>` | `less` | `greater` |" first-render))
      (error "Rendered table lost required frozen evidence."))
    (format t "Manna Cadet frozen truth-table migration test passed.~%")
    t))

(main)
