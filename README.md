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
  sparse overlays, and finite timed interactions, with resolution, validation,
  and normalization support;
- a deterministic project loader for explicitly imported layout, topology,
  device, realization, and `realize` composition declarations. Imports are
  confined to configured source roots and reject cycles, traversal escapes,
  and symlink escapes;
- a reference timed-event simulator, including a fail-closed adapter for
  disjoint normalized ordinary bindings, sparse overlays, and supported timed
  interactions;
- a realization-owned semantic output-vocabulary registry for deterministic
  named-key, named-symbol, and command spellings;
- a target-neutral capability planner that preserves normalized static product
  tables, lists selector/modifier/resource requirements, and deterministically
  detects allocation collisions or exhaustion;
- constrained XKB and Kanata emitters driven by a backend-neutral
  `lowering-request`, plus optional external-tool validation;
- a separate QMK protocol backend for deterministic, explicitly ordered static
  Configurator JSON and optional firmware compilation; and
- a conservative end-to-end compiler for exactly representable static layouts,
  with deterministic inspection, capability explanation, fresh build-directory
  emission, machine-readable manifests/source maps, and explicit refusal of
  unsupported semantics.

The checked-in Manna Cadet layout now contains a frozen 52-key static-symbol
transcription, plus separately identified selector/timed-interaction evidence.
It is an auditable transcription, not a claim that Ivory Key has generated,
installed, or activated an equivalent keyboard configuration. The twenty-level
conformance fixture remains expressible in the abstract model but is not
silently reduced to eight states. The CLI `simulate` command accepts a
restricted declarative event stream for the whole-layout adapter's exact
supported slice. It honors normalized sparse-overlay precedence and transparent
fall-through for ordinary bindings, while refusing latch-dependent overlay
dispatch, binding/interaction position overlap, and model patterns or actions
the event machine cannot represent.

## Quick start

The checked-in `manifest.scm` provides SBCL, ECL, XKB validation and state-test
development files, Kanata, QMK, a C toolchain, pkg-config, and curl through
Guix. With direnv installed, approve the checkout once with
`direnv allow`; `.envrc` then evaluates the manifest through direnv's built-in
Guix integration. The equivalent one-shot environment is
`guix shell -m manifest.scm`.

From this checkout, load the ASDF definition and run the hermetic tests:

```sh
sbcl --non-interactive \
  --eval '(require :asdf)' \
  --eval '(asdf:load-asd (truename "ivory-key.asd"))' \
  --eval '(asdf:test-system "ivory-key/tests")'
```

The CLI entry point supports:

```text
./bin/ivory-key check FILE...
./bin/ivory-key fmt [--check] FILE...
./bin/ivory-key inventory MANNA-CADET-CHECKOUT
./bin/ivory-key dump-ir --stage parsed|typed|normalized --layout FILE [--topology FILE]
./bin/ivory-key dump-ir --stage planned|backend --layout FILE --device FILE --realization FILE [--topology FILE]
./bin/ivory-key dump-ir --stage typed|normalized|planned|backend --project PROJECT --composition NAME
./bin/ivory-key levels --layout FILE [--topology FILE]
./bin/ivory-key levels --project PROJECT --composition NAME
./bin/ivory-key simulate --layout FILE [--topology FILE] --events FILE
./bin/ivory-key simulate --project PROJECT --composition NAME --events FILE
./bin/ivory-key explain --layout FILE --topology FILE --device FILE --realization FILE
./bin/ivory-key explain --project PROJECT --composition NAME
./bin/ivory-key compile [--validate-before-publish] --layout FILE --topology FILE --device FILE --realization FILE --output DIR
./bin/ivory-key compile [--validate-before-publish] --project PROJECT --composition NAME --output DIR
./bin/ivory-key validate-build DIR
```

`inventory` reads the supplied checkout, records the baseline commit, file
hashes, tool-version probes, and selected evidence lines. It does not change
the checkout or install any keyboard configuration.

Project-mode commands select one named `realize` composition. They do not
accept a mixture of `--project`/`--composition` and independent layout/device/
profile paths, because that would make the selected meaning and placement
ambiguous. `dump-ir` project mode exposes typed, normalized, planned, and
backend stages; raw parsed inspection remains a single-file mode. `planned`
lists canonical requirements, allocation dispositions, and every fidelity
grade without lowering. `backend` lowers only an all-exact direct request into
in-memory XKB and Kanata plans; it neither emits artifact text/files nor runs
validators, and refuses unsupported layouts before that later pipeline work.

Project simulation selects the composition's already resolved layout and runs
the same restricted, backend-neutral event adapter as direct layout mode. The
composition's device and realization remain context only: simulation does not
lower a backend, prove physical equivalence, emit files, or deploy anything.

The checked-in `manna-cadet-project.ivory` is the auditable import graph for
the frozen Manna layout, Kinesis Advantage 2 placement, Linux profile, and
named `manna-cadet-linux` composition. Inspection works today; compilation is
expected to refuse until every required selector, modifier, named output, and
timed interaction has an exact approved realization.

When a project realization selects an output vocabulary, exact static
named-key and named-symbol bindings use its explicit XKB and Kanata spellings.
Missing backend mappings, missing identities, commands without an approved
semantic lowering, and unsafe backend tokens refuse before any build is
written. No spellings are inferred from the Manna transcription.

## Documentation

- [PLAN.md completion audit](docs/plan-status.md)
- [Development, formatting, and validation conventions](docs/development.md)
- [Language syntax and decoder scope](docs/language.md)
- [Implemented semantic model and timed interactions](docs/semantics.md)
- [XKB/Kanata backend contract and fidelity rules](docs/backend-contract.md)
- [QMK backend validation evidence](docs/qmk-validation.md)
- [Controlled integration runbook](docs/controlled-integration-runbook.md)
- [Frozen Manna Cadet baseline and truth table](docs/manna-cadet-baseline.md)
- [Manna Cadet migration status](docs/migration-manna-cadet.md)
- [Conceptual overview](docs/concepts-and-abstractions.md)

`compile` creates a new build beneath an existing trusted output parent and
refuses to overwrite one. Exact builds contain `manifest.json`,
`allocations.json`, `source-map.json`, and `REPORT.md` alongside backend
artifacts; source identities are relocatable and source/artifact hashes are
SHA-256. Direct mappings and concrete allocations retain typed relocatable
origins (or explicit programmatic unknown), never checkout paths. Compilation
records no external validation claim unless validation actually ran, and it
never deploys. Because portable Common Lisp lacks
an atomic non-replacing directory rename, that parent must not be concurrently
writable by an untrusted process. Generated artifacts and live keyboard
deployment remain separate.
A successful parse, normalization, in-process lowering, external tool check,
and observed live input are different kinds of evidence.

The separately tagged external XKB/Kanata probe is intentionally not part of
the hermetic ASDF suite:

```sh
direnv exec . sbcl --script tests/external/xkb-kanata.lisp
direnv exec . ecl -norc -shell tests/external/xkb-kanata.lisp
```

Besides parser acceptance, it compiles a focused XKB plan and checks its
compiled groups, levels, symbols, actions, and consumed/unconsumed Shift state
through libxkbcommon. It does not claim Kanata interaction simulation, live
device behavior, or Manna equivalence.
