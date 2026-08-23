;;; Reproducible Ivory Key development and external-validation environment.
;;; SPDX-License-Identifier: GPL-3.0-or-later

(use-modules (guix packages)
             (guix profiles)
             (gnu packages curl)
             (gnu packages rust)
             (ivory-key packages))

(manifest
 (cons (package->manifest-entry rust-1.88 "cargo")
       (map package->manifest-entry
            (cons* kanata-1.12 curl rust-1.88
                   (map specification->package
                        '("sbcl"
                          "ecl"
                          "coreutils"
                          "gcc-toolchain"
                          "pkg-config"
                          "libxkbcommon"
                          "qmk"))))))
