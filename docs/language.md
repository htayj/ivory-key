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

The compiler envelope separately decodes the checked-in topology, device, and
realization-profile vocabularies when their paths are supplied explicitly. It
does not yet implement source imports, `realize` composition, surface overlay
syntax, or source interaction-template declarations. `check` remains a syntax
command; `dump-ir`, `levels`, `explain`, and `compile` invoke later stages.

The authoritative long-term language design remains [PLAN.md](../PLAN.md).
This document draws the narrower, implemented boundary.
