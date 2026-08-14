;;;; SPDX-License-Identifier: GPL-3.0-or-later

(defpackage #:ivory-key.tests
  (:use #:cl)
  (:export #:deftest #:is #:is-equal #:signals #:run-tests))

(defpackage #:ivory-key.tests.syntax
  (:use #:cl #:ivory-key.tests)
  (:import-from #:ivory-key.conditions
                #:diagnostic-code
                #:ivory-key-syntax-error)
  (:import-from #:ivory-key.source
                #:make-source-file
                #:source-span-start-byte
                #:source-span-end-byte)
  (:import-from #:ivory-key.syntax
                #:make-syntax-limits
                #:syntax-token-kind
                #:syntax-token-value
                #:syntax-token-span
                #:syntax-comment-style
                #:syntax-comment-text
                #:syntax-lex-result-comments
                #:syntax-lex-result-diagnostics
                #:syntax-lex-result-tokens
                #:syntax-parse-result-forms
                #:syntax-parse-result-diagnostics
                #:syntax-parse-result-language-version
                #:syntax-parse-result-p
                #:syntax-parse-result-complete-p
                #:syntax-list-children
                #:syntax-atom-kind
                #:syntax-atom-value
                #:syntax-node-equal-p
                #:lex-source
                #:parse-string
                #:parse-source-or-signal
                #:format-parse-result
                #:format-source))
