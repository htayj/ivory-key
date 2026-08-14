# Development conventions

Ivory Key keeps its runtime portable Common Lisp and UIOP only. Development
commands run through the checked-in Guix manifest:

```sh
direnv exec . sbcl --non-interactive \
  --eval '(require :asdf)' \
  --eval '(asdf:load-asd (truename "ivory-key.asd"))' \
  --eval '(asdf:test-system "ivory-key/tests")'

direnv exec . ecl -norc \
  -eval '(require :asdf)' \
  -eval '(asdf:load-asd (truename "ivory-key.asd"))' \
  -eval '(asdf:test-system "ivory-key/tests")' \
  -eval '(ext:quit 0)'
```

## Common Lisp style and checks

- Use two-space body indentation and the existing conventional Common Lisp
  layout; do not mechanically reformat unrelated forms.
- Put every source file in an explicit package and keep ASDF component order
  aligned with dependencies.
- Keep generated backend text out of the abstract language.
- Treat compiler warnings, reader errors, `git diff --check` failures, and a
  failing hermetic test as release blockers.
- Before a checkpoint, run both Lisp implementations, `git diff --check`, and
  a secret scan over the exact commit. Environmental validators and migration
  probes are reported separately from the hermetic suite.

No automatic Lisp formatter is normative in version 1: formatter differences
between implementations must not create repository churn. Review follows the
style above. The Ivory Key source language itself does have a normative
formatter; use `ivory-key fmt --check FILE` for checked-in `.ivory` files.

## Environmental checks

The installed-tool probe is deliberately outside `asdf:test-system`:

```sh
direnv exec . sbcl --script tests/external/xkb-kanata.lisp
direnv exec . ecl -norc -shell tests/external/xkb-kanata.lisp

direnv exec . sbcl --script tests/external/manna-xkb-group2-state.lisp \
  /home/tay/src/dotfiles/keyboard/manna-cadet
direnv exec . ecl -norc -shell tests/external/manna-xkb-group2-state.lisp \
  /home/tay/src/dotfiles/keyboard/manna-cadet
```

The frozen Manna Cadet inventory is verified separately against its preserved
source checkout:

```sh
direnv exec . sbcl --script tests/migration/manna-truth-table.lisp \
  /home/tay/src/dotfiles/keyboard/manna-cadet
```

The Kanata 1.12 state-machine oracle is more environmental still: it requires
the exact hash-pinned upstream source archive, the hash-frozen Manna checkout,
and a Rust nightly toolchain.  It neither belongs to ASDF nor touches a live
input device:

```sh
KANATA_CARGO_TOOLCHAIN=nightly \
  tests/external/kanata-1.12-manna-oracle.sh \
  PATH-TO-kanata-1.12.0.tar.gz \
  PATH-TO-FROZEN-MANNA-ROOT
```

See [the oracle contract and decision boundary](kanata-1.12-oracle.md) before
treating its version-specific evidence as a compatibility claim.
