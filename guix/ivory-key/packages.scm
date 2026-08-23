;;; Reproducible package overrides used by Ivory Key.
;;; SPDX-License-Identifier: GPL-3.0-or-later

(define-module (ivory-key packages)
  #:use-module (guix build-system cargo)
  #:use-module (guix download)
  #:use-module (guix gexp)
  #:use-module (guix git-download)
  #:use-module (guix packages)
  #:use-module (gnu packages rust)
  #:use-module (gnu packages rust-apps)
  #:export (kanata-1.12))

(define (crate-origin name version hash)
  (origin
    (method url-fetch)
    (uri (crate-uri name version))
    (file-name (string-append "rust-" name "-" version ".tar.gz"))
    (sha256 (base32 hash))))

(define kanata-1.12-extra-crates
  (list
   (crate-origin "karabiner-driverkit" "0.3.1"
                 "1sd9djgham4nqpxz89gfvcqlkfm0a4m51j85yz5sb93q9xvgrr4p")
   (crate-origin "patricia_tree" "0.9.0"
                 "1jpvwy8mljbqqx3abr1i7bw99awjx01kfh99k96bbnxv65impd7d")
   (crate-origin "widestring" "1.1.0"
                 "048kxd6iykzi5la9nikpc5hvpp77hmjf1sw43sl3z2dcdrmx66bj")
   (crate-origin "win_dbg_logger" "0.1.0"
                 "0yd7b73rww8bqbppgw8hq180xcnnxz1nybqyv0s7bhjd4hi4q6vx")))

(define-public kanata-1.12
  (package
    (inherit kanata)
    (version "1.12.0")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/jtroo/kanata")
             (commit "v1.12.0")))
       (file-name (git-file-name "kanata" version))
       (sha256
        (base32 "01jsdwp1yxg5kc40wdnx2awizs98b9ncky546v88v8hc0676cdss"))))
    (arguments
     (list
      #:rust rust-1.88
      #:cargo-build-flags '(list "--release" "--package" "kanata")
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'unpack 'limit-workspace
            (lambda _
              ;; The release workspace contains platform/demo members
              ;; that are not needed by the Linux kanata executable and
              ;; would unnecessarily enlarge the vendored crate closure.
              (substitute* "Cargo.toml"
                (("\t\"example_tcp_client\",")
                 "")
                (("\t\"windows_key_tester\",")
                 "")
                (("\t\"simulated_input\",")
                 "")
                (("\t\"simulated_passthru\",")
                 "")
                (("\t\"wasm\",")
                 ""))))
          (replace 'check
            (lambda* (#:key tests? #:allow-other-keys)
              (when tests?
                ;; These upstream tests instantiate a real Linux uinput
                ;; device even though they parse an in-memory fixture.
                ;; The isolated Guix build cannot provide /dev/uinput;
                ;; all other kanata package tests remain enabled.
                (invoke "cargo"
                        "test"
                        "--offline"
                        "--package"
                        "kanata"
                        "--lib"
                        "--bins"
                        "--"
                        "--skip"
                        "tcp_layer_change_tests")))))
      #:install-source? #f))
    (inputs (append kanata-1.12-extra-crates
                    (cargo-inputs 'kanata)))))
