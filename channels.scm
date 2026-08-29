;;; Reproducible Guix channel set for Ivory Key development.
;;; SPDX-License-Identifier: GPL-3.0-or-later

(list
 (channel
  (name 'guix)
  (url "https://git.guix.gnu.org/guix.git")
  (branch "master")
  (commit "637a34743d87b25d39f4a6c685b52b49b703e59a")
  (introduction
   (make-channel-introduction
    "9edb3f66fd807b096b48283debdcddccfea34bad"
    (openpgp-fingerprint
     "BBB0 2DDF 2CEA F6A8 0D1D  E643 A2A0 6DF2 A33A 54FA")))))
