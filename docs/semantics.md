# Implemented semantic model

The model separates keyboard meaning from backend mechanisms. Logical
positions belong to a topology; physical-device placement, XKB key names,
Kanata tokens, evdev codes, modifier slots, and carrier allocation belong to a
realization or backend layer.

## Context and output

A context axis has an ordered state set, a default, and one of three
resolution kinds:

- `product` contributes coordinates to a behavior table;
- `behavioral` chooses a complete behavior; and
- `patch` is reserved for sparse overlay resolution.

Product tuples are ordinary canonical axis/state associations, never a fixed
width bitmask. The first declared product axis varies fastest during Cartesian
enumeration. A table names the axes it depends on, so an unrelated behavioral
axis does not multiply every table.

Semantic modifiers are also canonical identifier collections, not host integer
masks. This keeps the abstract representation independent of the number of
modifier slots an operating system exposes.

Implemented behavior objects can emit text, a named key, a named non-Unicode
symbol, a semantic command, an explicit no-output result, a semantic modifier
operation, or a context-axis operation. Behaviors may be ordered sequences,
simultaneous compositions, axis choices, or context tables. Missing table
entries are errors during semantic validation: a table must explicitly provide
a behavior, `none`, inheritance, or—only for a patch table—transparency.

The model includes sparse overlay-patch and finite behavior/interaction
template objects. Programmatic resolution expands behavior templates without
evaluating layout-provided Lisp and detects recursion. Source decoding for
those constructs is not implemented yet; see [language.md](language.md).

## Unified timed interactions

Tap, hold, combo, tap dance, roll, sequence, and one-shot are represented as
finite patterns over logical press intervals rather than unrelated primitives.
An interaction declares finite participants, the events it observes,
candidates, an explicit commitment point, optional lifecycle effects, and an
arbitration policy.

The model's pattern algebra includes ordered and unordered composition,
alternatives, duration bounds, deadlines, bounded proximity, overlap, absence
between explicit boundaries, bounded repetition, captures, and context tests.
Candidate effects have separate entry, commit, while-active, exit, and
cancellation lists. Validation rejects irreversible output in speculative
entry/while effects and rejects an unpaired held effect.

Context is dependency-scoped. A candidate normally captures the axes it
consults at its anchor-down point; an explicit commit-time policy also exists
in the model. Latches are consumed only by a committed candidate that consults
their axis. A rejected candidate, or a key that does not consult that axis,
leaves the latch intact.

The reference simulator executes its own finite timed-event representation.
It covers deadline boundaries, distinct release orders, unordered combos,
priority conflicts, cancellation, latch non-consumption, and paired held
effects. It is meaningful implementation evidence for those simulation
objects, but it is not yet wired to decoded `.ivory` layouts or backend
generation.

## Present limits

The plan specifies one unified source-to-normalized-to-simulation pipeline.
The current repository has substantial model, validation, normalization, and
simulation pieces, but no complete public source front end that connects all
of them. In particular, no claim of semantic equivalence should be made for a
fixture merely because it parses, and no backend output should be treated as
the semantic oracle. That role belongs to the reference simulator once the
end-to-end frontend is connected.
