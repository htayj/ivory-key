# Ivory Key

Ivory Key is a Common Lisp implementation of a declarative keyboard-layout
compiler. Its source language describes logical positions, semantic output,
context state, and timed interaction rules without embedding XKB, Kanata,
evdev, or firmware spellings.

The project is GPL-3.0-or-later. The architecture and intended end state are
described in [PLAN.md](PLAN.md); this README describes the code that exists
now.

## Current status

The bootstrap currently provides:

- a dedicated, non-evaluating S-expression lexer, parser, diagnostics, and
  canonical formatter;
- typed model objects for axes, modifiers, positions, behaviors, bindings,
  overlays, and finite timed interactions, with resolution, validation, and
  normalization support for programmatic callers;
- a reference timed-event simulator and dependency-free simulation tests;
- constrained XKB and Kanata emitters driven by a backend-neutral
  `lowering-request`, plus optional external-tool validation;
- a conservative end-to-end compiler for exactly representable static layouts,
  with deterministic inspection, capability explanation, fresh build-directory
  emission, and explicit refusal of unsupported semantics; and
- a read-only Manna Cadet baseline inventory command.

The checked-in Manna Cadet fragment and twenty-level conformance fixture now
decode, validate, and normalize: the latter produces twenty abstract entries.
They are not yet exactly realizable by the bootstrap pipeline. Multi-context
selection, semantic modifiers, generic timed interactions, commands, named
symbols, and unregistered vocabulary are refused instead of approximated.
The CLI `simulate` command also remains unavailable for a complete layout;
the programmatic reference simulator and model adapter are implemented.

## Quick start

From this checkout, load the ASDF definition and run the hermetic tests:

```sh
sbcl --non-interactive \
  --eval '(require :asdf)' \
  --eval '(asdf:load-asd (truename "ivory-key.asd"))' \
  --eval '(asdf:test-system "ivory-key/tests")'
```

The CLI entry point supports:

```text
ivory-key check FILE...
ivory-key fmt [--check] FILE...
ivory-key inventory MANNA-CADET-CHECKOUT
ivory-key dump-ir --stage parsed|typed|normalized --layout FILE [--topology FILE]
ivory-key levels --layout FILE [--topology FILE]
ivory-key explain --layout FILE --topology FILE --device FILE --realization FILE
ivory-key compile --layout FILE --topology FILE --device FILE --realization FILE --output DIR
ivory-key validate-build DIR
```

`inventory` reads the supplied checkout, records the baseline commit, file
hashes, tool-version probes, and selected evidence lines. It does not change
the checkout or install any keyboard configuration.

## Documentation

- [Language syntax and decoder scope](docs/language.md)
- [Implemented semantic model and timed interactions](docs/semantics.md)
- [XKB/Kanata backend contract and fidelity rules](docs/backend-contract.md)
- [Manna Cadet migration status](docs/migration-manna-cadet.md)
- [Conceptual overview](docs/concepts-and-abstractions.md)

`compile` creates a new build directory and refuses to overwrite one; it never
deploys. Generated artifacts and live keyboard deployment remain separate.
A successful parse, normalization, in-process lowering, external tool check,
and observed live input are different kinds of evidence.
