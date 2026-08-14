# 0001: Explicit interaction instance names

- Status: Accepted, but revisitable
- Date: 2026-08-14

## Context and problem

Interaction templates make a finite interaction shape reusable.  A template
call still creates a distinct declared interaction in a layout: it needs an
identity for diagnostics, simulator traces, arbitration reports, source maps,
and later realization evidence.  Inferring that identity from the template
name, arguments, or source location would make those consumer-facing records
unstable and would invite an undocumented generated-name convention.

This is a question about the source identity of a template instantiation.  It
does not add a new temporal pattern, candidate, effect, arbitration rule, or
other interaction semantic.

## Decision

Every top-level interaction-template instantiation that materializes a layout
interaction declares its instance identity as the first argument:

```lisp
(instantiate-interaction INSTANCE TEMPLATE (:PARAM VALUE) ...)
```

`INSTANCE` is the declared name of the resulting interaction and `TEMPLATE`
selects the reusable template.  Parameter options remain explicit named
arguments.  The instance name participates in the same duplicate and
reference diagnostics as any other declared interaction name.

No implementation may synthesize an instance name from a template, a
parameter spelling, expansion order, or source span.  Expansion can remain a
finite, acyclic normalization step; it merely retains the explicitly declared
identity on the resulting interaction IR.

A template body may delegate to another template with the compact form:

```lisp
(instantiate-interaction TEMPLATE (:PARAM VALUE) ...)
```

This nested form does not materialize a second interaction and therefore does
not declare another identity. It inherits the eventual outer instance name.
Keeping the two forms context-sensitive is itself part of this revisitable
surface decision, not a new interaction semantic.

This decision governs the version 1 source surface. The existing programmatic
`interaction-template-reference` object remains a low-level delegation value
for compatibility; by itself it is not a named materialization contract. The
source decoder never leaves a bare reference at layout scope. Whether the
public model should gain a first-class materializing-instance object is an
explicit follow-up question, not silently decided here.

## Rationale

An explicit instance name provides a stable identity while retaining reusable
templates.  In particular, it gives diagnostics, simulator traces,
arbitration explanations, generated source maps, and validation evidence a
single human-chosen name to report.  It also keeps source-to-generated
provenance stable when a template changes internally or an argument is
renamed, without creating a generated-name convention that users would have
to reverse engineer.

## Alternatives considered

### Derive a name from the template and arguments

This makes identities sensitive to parameter ordering and spelling, needs an
escaping and collision convention, and causes unrelated template edits to
change diagnostic and source-map identities.

### Use a source span or expansion ordinal

Source locations and expansion order are not durable public identities.  They
change after formatting, import reordering, or refactoring and are unsuitable
for traces, arbitration reports, and migration tooling.

### Allow unnamed instantiations and name only expanded IR internally

This hides an important declaration identity from the author.  It forces
tools to expose a synthetic implementation detail and makes duplicate,
reference, and provenance diagnostics less clear.

### Introduce a new interaction semantic form

Rejected because no new semantics are needed.  The decision concerns only
surface identity at the template-instantiation boundary.

## Compatibility and migration

Existing direct `(interaction NAME ...)` declarations retain their names and
semantics unchanged. An older top-level template call shaped like:

```lisp
(instantiate-interaction TEMPLATE (:PARAM VALUE) ...)
```

must be migrated by choosing an explicit instance name:

```lisp
(instantiate-interaction INSTANCE TEMPLATE (:PARAM VALUE) ...)
```

There is intentionally no automatic generated-name compatibility mode.  A
migration tool may propose a name, but the source author must make the final
identity explicit so future diagnostics and source maps are stable.

The same compact call remains valid inside a template body as delegation. It
needs no migration because only the outer layout declaration materializes a
named interaction.

## Revisit triggers

Revisit this decision if evidence shows that any of the following requires a
different, still explicit identity model:

- one source declaration must materialize more than one independently
  addressable interaction;
- separately compiled modules need a qualified interaction namespace that a
  simple local instance identifier cannot express;
- interaction specialization, inheritance, or generated libraries require
  first-class provenance identities beyond one declared instance name; or
- programmatic callers need a public materializing-instance object rather than
  the existing low-level template-reference delegation; or
- the context-sensitive distinction between named top-level materialization
  and unnamed nested delegation proves confusing or hard to evolve; or
- real diagnostics, traces, arbitration displays, or source maps demonstrate
  that the declared name is insufficient or misleading.

Until such evidence exists, preserve the explicit two-name surface form and
avoid generated-name conventions.
