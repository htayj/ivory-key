# Implemented semantic model

The normative V1 source grammar, event rules, policy parameters, and refusal
boundary are in [language-reference-v1.md](language-reference-v1.md).  This
document describes the current model and implementation evidence; it does not
silently promote a decoded form to an executable backend semantic.

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

An output-vocabulary registry maps typed named-key, named-symbol, and command
identities to opaque per-backend strings. Registries are realization-owned,
canonical, deterministic, and reject duplicate identities, ambiguous reverse
mappings, unknown backends/kinds, and missing mappings. Backend adapters still
validate their own spelling grammar. The registry is currently a programmatic
model API and a closed realization-owned project declaration; no Manna backend
spellings have been guessed or embedded in the layout.

The model includes sparse overlay-patch and finite behavior/interaction
template objects. Programmatic resolution expands behavior templates without
evaluating layout-provided Lisp and detects recursion. The v1 source decoder
also accepts closed `overlay` declarations: a patch axis/state, an explicit
integer precedence, and sparse complete/transparent bindings. An active
transparent binding falls through to the next lower-precedence active overlay
and then the base binding. Conflicting non-transparent bindings at equal
precedence are invalid; source order never supplies an implicit tie-break.
See [language.md](language.md) for the concrete grammar.

## Unified timed interactions

Tap, hold, combo, tap dance, roll, sequence, and one-shot are represented as
finite patterns over logical press intervals rather than unrelated primitives.
An interaction declares finite participants, the events it observes,
candidates, an explicit commitment point, optional lifecycle effects, and an
arbitration policy.

The model's pattern algebra includes ordered and unordered composition,
alternatives, duration bounds, deadlines, bounded proximity, overlap, absence
between explicit boundaries, bounded repetition, captures, and context tests.
The currently executable capture subset is one lexical, immutable binding in
`(sequence (down P) (capture NAME (down SELECTOR)) (up (captured NAME)))` in a
candidate match. The final `up` therefore denotes the same physical position
as the first captured `down`; rebinding, nesting, alternatives, and unordered
capture forms are refused. This does not yet assign replay, ordinary-binding
suppression, or same-frontier ordering semantics. Candidate effects have
separate entry, commit, while-active, exit, and cancellation lists, plus an
explicit start policy: `on-match` is the existing speculative default, while
`on-commit` starts effects only for the winning committed candidate. Validation
rejects irreversible output in speculative entry/while effects. Source
`hold-modifier` and `hold-axis-state` are valid
only in `:while`; each effect owns and automatically releases its own semantic
contribution at normal exit or cancellation.  Identical concurrent holders
remain effective until the final owner leaves.  Direct `set-axis-state` is a
separate base-state transition, overlaid while an axis hold remains active;
conflicting held states for one axis are refused.

For an `on-commit` effect, a participant release while its candidate is still
viable is terminal cancellation: it cannot later commit on an unrelated event
and acquire a zero-lifetime or stuck hold. A generated deadline remains ordered
before a physical release at the same timestamp, so a deadline that commits at
that boundary enters and exits normally.

Context is dependency-scoped. A candidate normally captures the axes it
consults at its anchor-down point; an explicit commit-time policy also exists
in the model. Latches are consumed only by a committed candidate that consults
their axis. A rejected candidate, or a key that does not consult that axis,
leaves the latch intact.

The executable `context-is` predicate compares its axis against that same
dependency-scoped anchor snapshot. A captured latch shadows the ordinary axis
value, and a committing contextual candidate consumes only the matching latch
generation. It never consults mutable commit-time state; context observation
times other than anchor-down remain explicit simulator refusals.

The reference simulator executes its own finite timed-event representation.
It covers deadline boundaries, distinct release orders, unordered combos,
priority conflicts, cancellation, latch non-consumption, and paired held
effects. Held modifier presses and releases occur only at first acquisition
and final release, while held-axis lookup reports the active held state before
the base state. A whole-layout adapter now normalizes an in-memory decoded layout and
combines disjoint ordinary bindings with supported compiled interactions.
Ordinary bindings commit on key-down and dispatch against captured context;
candidate ownership, trace records, and committed-only latch consumption stay
inside the same event machine.

Every candidate-owned observable trace record carries closed provenance for the
canonical source pattern, candidate transition, commit point, and responsible
lifecycle effect. Ordinary committed behavior is explicitly marked
`candidate-do`; entry, exit, and cancellation actions identify the effect and
its lifecycle phase. A final held effect is therefore justified by its recorded
entry transition rather than an inferred host-state mutation. When the finite
capture subset is used, the trace also records the canonical captured name,
physical position, and source-event index; it never serializes an event or
pattern host object.

The adapter applies already-normalized sparse overlays by declared precedence,
with transparent fall-through to lower patches and then the base binding. Patch
selection uses the candidate's captured axis state; ordinary or disjoint timed
actions may change later selections with an exact `set` transition. The trace
records the selected patch. It fails closed when overlay dispatch would depend
on consuming a latch, when an ordinary position also participates in an
interaction, for unknown or unbound event positions, caller-supplied deadline
events, invalid explicit context, and every behavior, pattern, arbitration, or
effect the existing model adapter cannot represent. It does not lower a backend
or deploy.

Both model-compiled and direct simulator IR refuse `longest-match`. The
reference machine has no participant-count shortcut: admitting that policy
requires the still-unproved comparison and latency scheduler described by the
language reference.

## Planning boundary and present limits

The target-neutral planner consumes a normalized layout and a model device
placement. It retains every static table entry in canonical order and reports
separate selector, semantic-modifier, and finite-resource requirements. It
does not use a modifier bitmask or turn an abstract selector into a backend
spelling. If finite resource pools are supplied, planning copies them before
reserving physical inputs and allocating deterministically, so collision or
exhaustion is explicit and does not mutate a reusable profile inventory.

With an XKB capability advertising the conventional eight native static levels,
dependency-scoped static product tables of up to eight states receive an
`exact` table grade. A twenty-state table remains twenty entries in the plan
and is partitioned canonically as `8+8+4`, with every context assigned to a
bank and native level. The plan records distinct bank-selector and carrier
obligations. It remains `unsupported` until another target or separately
proven emulation implements those transitions; advertised group capacity alone
is not proof. A table requiring more advertised banks is also retained in full
and refused. `require-planned-realizations` refuses these unproved plans.

Planner inspection is included in both explicit-file and project `explain`
paths. It reports canonical table sizes and selector, modifier, and resource
obligations before the stricter direct-emitter disposition. An exact XKB table
capacity grade is observational and does not authorize selector or output
lowering.

For a multi-bank table, inspection also prints every canonical context-to-bank
and native-level assignment, the `8+8+4`-style bank sizes, advertised bank
capacity, and the still-unproved selector/carrier obligation. A table needing
five banks against an advertised four remains complete in the report and is
explicitly over capacity; neither case authorizes emission.

No claim of semantic equivalence should be made for a fixture merely because
it parses, simulates a supported subset, or plans. Backend output is never used
to retroactively define abstract semantics.
