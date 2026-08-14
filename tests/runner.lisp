;;;; SPDX-License-Identifier: GPL-3.0-or-later

(in-package #:ivory-key.tests)

(defvar *tests* nil)

(defmacro deftest (name &body body)
  `(push (cons ',name (lambda () ,@body)) *tests*))

(defmacro is (form &optional (message nil))
  `(unless ,form
     (error "Assertion failed~@[ (~A)~]: ~S" ,message ',form)))

(defmacro is-equal (expected actual &optional (test ''equal))
  `(let ((expected-value ,expected)
         (actual-value ,actual))
     (unless (funcall ,test expected-value actual-value)
       (error "Expected ~S, got ~S." expected-value actual-value))))

(defmacro signals (condition-type &body body)
  `(handler-case
       (progn
         ,@body
         (error "Expected condition ~S, but no condition was signaled."
                ',condition-type))
     (,condition-type () t)))

(defun delete-test-directory-tree (directory)
  "Delete one test-owned directory tree without spawning a host utility.

UIOP:DELETE-DIRECTORY-TREE delegates to `rm -rf` on some implementations.
Keeping cleanup in Lisp avoids an ECL/Guix subprocess crash and makes the test
harness independent of the host command set."
  (when (probe-file directory)
    (dolist (file (uiop:directory-files directory))
      (delete-file file))
    (dolist (subdirectory (uiop:subdirectories directory))
      (delete-test-directory-tree subdirectory))
    (uiop:delete-empty-directory directory)))

(defun make-test-symbolic-link (target link)
  "Create one test-owned symbolic link through an argument vector."
  (uiop:run-program (list "ln" "-s" (namestring target) (namestring link)))
  link)

(defun run-tests ()
  "Run the small dependency-free test suite, signaling if any test fails."
  (let ((failures nil)
        (passed 0))
    (dolist (entry (reverse *tests*))
      (handler-case
          (progn
            (funcall (cdr entry))
            (incf passed))
        (error (condition)
          (push (cons (car entry) condition) failures))))
    (if failures
        (progn
          (format *error-output* "~D / ~D Ivory Key tests failed:~%"
                  (length failures) (+ passed (length failures)))
          (dolist (failure (nreverse failures))
            (format *error-output* "  ~A: ~A~%" (car failure) (cdr failure)))
          (error "Ivory Key tests failed."))
        (progn
          (format t "~D Ivory Key tests passed.~%" passed)
          t))))
