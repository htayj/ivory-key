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
  (interaction name ...))
```

Implemented behavior forms include `unicode`, `named-key`, `named-symbol`,
`command`, `sequence`, `simultaneous`, `hold-modifier`, axis operations,
`by-axis`, `by-level`, and explicit `none`, `inherit`, and `transparent`
entries where applicable. Implemented temporal patterns include `down`, `up`,
`sequence`, `all`, `either`, `and`, `duration`, `deadline`, `within`,
`overlap`, `without`, `repeat`, and `context-is`.

The decoder also implements binding `fallback`, finite source behavior
templates and calls, `on-tap` expansion, and direct single-candidate
interaction shorthand. Unknown, cyclic, duplicate, ambiguous, and malformed
forms are rejected without interning their names. Both checked-in layout
fixtures decode, validate, and normalize; the twenty-level fixture materializes
all twenty dependency-scoped entries.

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

The CLI's `dump-ir`, `levels`, `explain`, and `compile` commands support either
their explicit single-file inputs or `--project PROJECT --composition NAME`.
The modes cannot be mixed. Project `dump-ir` supports typed and normalized
stages, not raw parsed output. `check` remains a syntax command; it does not
load a project graph. Source interaction-template declarations remain outside
the implemented surface subset. The semantic output-vocabulary registry is
also programmatic in this slice; a future realization-profile surface form
will supply backend spellings without placing them in layout bindings.

The authoritative long-term language design remains [PLAN.md](../PLAN.md).
This document draws the narrower, implemented boundary.
