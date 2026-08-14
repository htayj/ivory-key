# Language syntax and decoder scope

Ivory Key source is deliberately Lisp-shaped declarative data, not executable
Common Lisp. The lexer and parser never call `read`, intern source identifiers
into a package, or evaluate source forms.

## Implemented safe syntax

Every parsed source file starts with the version envelope:

```lisp
(ivory-key 1)
```

The parser accepts lists, ASCII identifiers, keyword-like identifiers, strings,
non-negative integers, `;` line comments, and nested `#| ... |#` block
comments. String escapes include the normal quoted-string escapes and Unicode
`\u`/`\U` forms. It records UTF-8 byte spans and line/column locations, can
recover from common parenthesis errors, and enforces configurable byte, token,
diagnostic, nested-comment, and nesting limits. Invalid UTF-8 and non-scalar
Unicode input produce stable diagnostics rather than implementation reader
behavior.

Reader dispatch, reader evaluation, package syntax, ratios, floats, circular
labels, and host objects are not source-language features. The implementation
rejects them rather than passing them to a Common Lisp reader.

Identifiers are case-insensitive in version 1 and are represented as canonical
strings in the semantic model. They are not Common Lisp symbols.

## Formatter and syntax CLI

The formatter operates on the parsed concrete tree. For syntactically valid
input, its required property is:

```text
parse(format(parse(source))) = parse(source)
```

where equality ignores whitespace and comment placement. The CLI exposes
`fmt` and `fmt --check` for this parser/formatter layer.

`ivory-key check FILE...` currently reports lexer/parser diagnostics only. It
does not yet invoke schema decoding, cross-file import resolution, semantic
validation, normalization, simulation, capability planning, or backend
emission. A syntactically valid `.ivory` fixture must therefore not be read as
proof that it is fully implemented or compilable.

## Current typed-layout decoder

The programmatic `decode-layout-forms` bridge decodes one `define-layout`
form. It supports the implemented subset below:

```lisp
(define-layout name
  (uses-topology topology-name) ; resolved only if a caller supplies a resolver
  (axis axis-name
    (:states state ...)
    (:resolution product|behavioral|patch)
    (:default state)
    (:precedence integer)
    (:valid-tuples (...)))
  (level-order product-axis ...)
  (modifiers modifier ...)
  (binding position behavior-or-table)
  (overlay overlay-name
    (:axis patch-axis)
    (:state patch-state)
    (:precedence integer)
    (binding position behavior-or-transparent) ...)
  (define-interaction-template template-name (position-parameter ...)
    interaction-or-template-call)
  (interaction name ...)
  (instantiate-interaction instance-name template-name
    (:position-parameter logical-position) ...))
```

Implemented behavior forms include `unicode`, `named-key`, `named-symbol`,
`command`, `sequence`, `simultaneous`, `hold-modifier`, axis operations,
`by-axis`, `by-level`, and explicit `none`, `inherit`, and `transparent`
entries where applicable. Implemented temporal patterns include `down`, `up`,
`sequence`, `all`, `either`, `and`, `duration`, `deadline`, `within`,
`overlap`, `without`, `repeat`, the finite immutable `capture` slice, and
`context-is`.

`hold-modifier` and `hold-axis-state` are lifecycle behaviors, not ordinary
bindings: V1 accepts them only in an interaction candidate's `:while` list.
The owning effect acquires the semantic resource on entry and releases its own
contribution on exit or cancellation.  Identical concurrent holders are
reference-counted in the reference simulator; `set-axis-state` stays a direct
base-state operation and cannot release another owner.

The decoder also implements binding `fallback`, finite source behavior
templates and calls, `on-tap` expansion, and direct single-candidate
interaction shorthand. Unknown, cyclic, duplicate, ambiguous, and malformed
forms are rejected without interning their names. Both checked-in layout
fixtures decode, validate, and normalize; the twenty-level fixture materializes
all twenty dependency-scoped entries.

Interaction templates use identifier-only named arguments, may forward a
position parameter through an acyclic template call, and expand before layout
validation. Every top-level `instantiate-interaction` materialization supplies
an explicit `instance-name` before its template name; this is the stable source
identity for diagnostics, traces, arbitration, and source maps, not a new
interaction semantic. Inside a template body, the compact
`(instantiate-interaction template-name ...)` form is an unnamed delegation
that inherits the eventual outer instance identity. Forward declaration
references are deterministic. Missing,
duplicate, or unknown arguments, arity errors, cycles, unresolved parameters,
and expansions that collide on one interaction name are explicit errors. See
[Decision 0001](decisions/0001-explicit-interaction-instance-names.md) for the
accepted, revisitable rationale and migration boundary.

An `overlay` is a closed sparse-patch declaration. `:axis`, `:state`, and
`:precedence` occur exactly once; the axis must exist, use `patch` resolution,
and contain the selected state. A patch binding has exactly one logical
position and either a complete abstract behavior or the literal
`transparent`. Transparency is explicit fall-through, not a missing binding.
Duplicate overlay names, duplicate options, duplicate patched positions,
unknown clauses, invalid states, non-integer precedence, and backend spellings
such as XKB keysyms are rejected. Normalization orders active overlays by
descending declared precedence; equal-precedence conflicting overrides are a
semantic ambiguity rather than source-order behavior.

## Project files and confined imports

The project loader adds a separate, deliberately small cross-file envelope.
Each project file has one `(ivory-key 1)` header and may contain top-level
`(import "relative-path.ivory")`, `define-layout`, `define-topology`,
`define-device`, `define-realization`, and:

```lisp
(realize name
  (:layout layout-name)
  (:device device-name)
  (:profile realization-name))
```

Imports are source-language data, not ASDF or Common Lisp modules. They are
relative, confined to configured source roots both lexically and after symlink
resolution, and reject absolute paths, traversal escapes, malformed imports,
cycles, and duplicate definitions. Registries are canonical name-sorted, so
import traversal order is not semantic. A `realize` composition names exactly
one compatible layout, device, and realization profile.

The CLI's `dump-ir`, `levels`, `simulate`, `explain`, and `compile` commands
support either their explicit single-file inputs or
`--project PROJECT --composition NAME`.
The modes cannot be mixed. Project `dump-ir` supports typed, normalized,
planned, and backend stages, not raw parsed output. `planned` reports the
canonical capability plan—obligations, grades, and finite allocations—without
backend lowering. `backend` accepts only an all-exact direct request and shows
the in-memory XKB/Kanata plans; it writes no artifacts, invokes no validators,
and refuses unresolved behavior before any pipeline emission. `check` remains
a syntax command; it does not load a project graph.

Projects may declare realization-owned output spellings without putting them
in layout bindings:

```lisp
(define-output-vocabulary linux-outputs
  (backends xkb kanata)
  (map-output named-key return (:xkb "Return") (:kanata "ret")))

(define-realization linux
  (pipeline kanata xkb)
  (uses-output-vocabulary linux-outputs))
```

Kinds and backends are closed identifiers; spellings are opaque strings whose
target grammar is validated later by the backend. Imports may forward-reference
the named vocabulary. Duplicate identities, ambiguous spellings, undeclared
backends, missing options, and unknown references are errors.

Project compilation and explanation carry the selected realization's
vocabulary into conservative static-output analysis. A typed named key or
named symbol must have explicit spellings for both selected direct backends;
the backend adapters then validate those opaque spellings before emission.
Missing mappings and command outputs are refusals, not guessed translations.
A standalone realization file cannot resolve project vocabulary declarations,
so selecting one there is also an explicit refusal.

## Simulation event documents

`simulate --layout FILE [--topology FILE] --events FILE` reads another
restricted Ivory document, never host Lisp:

```lisp
(ivory-key 1)
(simulation
  (axis case shifted)
  (latch shift-latch latch)
  (event 0 down q)
  (event 10 up q)
  (until 10))
```

Times are nondecreasing non-negative integer milliseconds. Physical source may
contain only `down` and `up`; deadlines are generated by the simulator.
Unknown, duplicate, malformed, decreasing, and out-of-range forms fail before
simulation. The deterministic result dump contains outputs, ordered trace,
latches, axes, and active effects. Every candidate-owned observable trace
record carries a closed `provenance` value: its canonical source pattern,
candidate transition, commit point, and responsible lifecycle effect (or
`candidate-do` for ordinary committed behavior). Thus each emitted output and
each held-effect entry can be traced without printing host objects or backend
spellings.

`simulate --project PROJECT --composition NAME --events FILE` selects the
composition's resolved layout and otherwise uses the identical event document
and simulator boundary. It does not lower or execute the selected realization,
and it rejects mixed project and direct-layout arguments.

The authoritative long-term language design remains [PLAN.md](../PLAN.md).
For the normative V1 disposition of every representative section 5.2 form,
event boundary, and explicit refusal, see
[language-reference-v1.md](language-reference-v1.md).  This document draws the
narrower, implemented decoder boundary.
