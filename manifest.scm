;;; Reproducible Ivory Key development and external-validation environment.
;;; SPDX-License-Identifier: GPL-3.0-or-later

(use-modules (guix profiles))

(specifications->manifest
 '("sbcl"
   "ecl"
   "coreutils"
   "gcc-toolchain"
   "pkg-config"
   "libxkbcommon"
   "kanata"
   "qmk"
   "curl"))
