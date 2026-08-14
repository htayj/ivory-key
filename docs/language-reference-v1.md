# Ivory Key language reference, version 1

## Status, scope, and conformance words

This is the normative reference for the version-1 source constructs represented
in [PLAN.md](../PLAN.md) section 5.2.  It deliberately separates three facts
that are easy to conflate:

- **Implemented** means the closed source decoder accepts the form and
  semantic validation and normalization define it.  Each subsection says
  separately whether the current reference-simulator adapter can execute the
  form exactly.
- **Decoded, but refused by the reference adapter** means the model has a
  representation and the decoder may accept the spelling, but the current
  simulator or conservative compiler refuses rather than inventing semantics.
  It is not an executable conformance claim.
- **Reserved** means version 1 has no source grammar or executable meaning for
  the spelling.  A conforming decoder rejects it; it must not reinterpret it
  as an approximate existing construct.

This reference defines source meaning and reference-simulator conformance.  It
does not define XKB, Kanata, QMK, or any other backend spelling or deployment.
Those are separately capability-checked realization concerns.

`identifier` below is a case-insensitive Ivory Key identifier, canonicalized
as text and never interned as a Common Lisp symbol.  `integer` is a non-negative
integer unless an individual rule explicitly permits another integer.  Every
source document begins with exactly this envelope:

```lisp
(ivory-key 1)
```

The safe lexical and concrete-syntax rules are specified in
[language.md](language.md#implemented-safe-syntax).  This document begins at
the semantic surface, after parsing has produced harmless source data.

## 1. Layout declarations

The implemented layout envelope is closed.  The clauses may appear in source
order, but names and semantic collections are canonicalized before validation
or planning:

```lisp
(define-layout layout-name
  (uses-topology topology-name)
  (axis axis-name
    (:states state ...)
    (:resolution product|behavioral|patch)
    [(:default state)]
    [(:precedence integer)]
    [(:valid-tuples (state ...) ...)])
  (level-order product-axis ...)
  (modifiers modifier ...)
  declaration-or-binding ...)
```

`uses-topology`, `level-order`, and `modifiers` occur at most once.  `axis`,
`binding`, `overlay`, `define-behavior`, `define-interaction-template`,
`interaction`, and `instantiate-interaction` may recur subject to their
identifier-uniqueness rules.  Unknown or duplicate closed options are errors;
source order is never a tie breaker.

### 1.1 Axes and canonical product coordinates

An axis has a unique nonempty state list and one resolution kind:

- `product` contributes a coordinate to the static table for only the behavior
  that depends on it.
- `behavioral` selects a whole abstract behavior and does not multiply an
  unrelated static table.
- `patch` selects sparse overlays.  It is not a base-table coordinate.

The default is the first declared state if `:default` is omitted; a supplied
default must be one of that axis's states.  `:precedence` is an integer metadata
field used by semantic resolution where applicable.  `:valid-tuples`, when
present, constrains product coordinates rather than silently filling omitted
ones.

**P-AXIS-ORDER-01 — product enumeration.**  A product table's coordinates are
ordered by the declared `level-order`; if it is absent, by the layout's product
axis declaration order.  The first axis varies fastest.  Each table records
the axes it actually depends on, so adding an unrelated behavioral axis has no
effect on its cardinality.  A `level-order` must name precisely the product
axes without duplicates; it cannot name behavioral or patch axes.

**P-AXIS-COVERAGE-01 — static totality.**  After inheritance and explicit
fallback resolution, every allowed coordinate of a base static table must hold
an abstract behavior or explicit `none`.  A missing coordinate is refused as
an incomplete level table; an inheritance cycle is refused rather than being
broken by source order.  `transparent` is not a base-table value.

**P-MODIFIER-01 — semantic modifiers.**  `(modifiers modifier ...)` declares
unique semantic names, not bit positions, XKB modifier names, or backend slots.
Any finite backend allocation is an obligation of a later realization.

### 1.2 Bindings and behavior tables

The three implemented binding shapes are:

```lisp
(binding position behavior)
(binding position (on-tap behavior))
(binding position
  (at (state ...) behavior|none|(inherit (state ...))) ...
  [(fallback behavior|none)])
```

`position` must be a topology position when topology validation is available.
The tuples in `at` use the binding's product axes in canonical axis order; a
tuple may not repeat.  `inherit` points to another explicit tuple and is
resolved before cardinality validation.  `fallback` materializes every still
missing allowed tuple and therefore must be a complete behavior or `none`, not
`inherit` or `transparent`.

`on-tap` is implemented binding shorthand, not an ordinary nested behavior.
It expands deterministically to a one-participant interaction named
`on-tap-POSITION`, whose finite match is `(sequence (down POSITION) (up
POSITION))`, whose commit point is `(up POSITION)`, and whose committed action
is the supplied behavior.  It has no hidden device timer or backend primitive.

Implemented behavior forms are:

```lisp
(unicode string)
(named-key identifier)
(named-symbol identifier)
(command identifier)
none
(sequence behavior ...)
(simultaneous behavior ...)
(hold-modifier modifier)
(hold-axis-state axis state)
(latch-axis-state axis state)
(lock-axis-state axis state)
(set-axis-state axis state)
(unlock-axis axis)
(cycle-axis axis)
(toggle-axis axis)
(by-axis axis (state behavior) ...)
(by-level ((state ...) behavior|none|(inherit (state ...))) ...)
(behavior-template-name argument ...)
```

`unicode` requires a string.  The three named output forms remain semantic
identities; when a selected target needs spellings, they must come from an
approved output vocabulary and are never guessed from their names.  `command`
is likewise semantic and is not permission to invoke a host command.  A
nonempty `sequence` applies its
abstract children in order; a nonempty `simultaneous` represents one abstract
composition without assigning target ordering.

`hold-modifier` means an owner-scoped semantic modifier hold, not a fixed host
mask.  `hold-axis-state` likewise names an owner-scoped abstract axis state.
Both forms are valid only in a candidate's `:while` list: their owning effect
acquires them on entry and releases them automatically on normal exit or
cancellation.  Multiple owners of the same modifier or the same axis/state
keep it active until the final owner releases.  `set-axis-state` remains an
ordinary direct/base transition; an active axis hold temporarily overlays it,
so one effect's reset cannot release another effect's hold.  Different held
states for the same axis are refused rather than ordered implicitly.  The axis
operations otherwise name abstract state transitions.  The reference adapter
only accepts the subset it can lower exactly for the chosen whole-layout path;
unsupported operations are an explicit refusal, never a silently ignored
transition.  `by-axis` supplies one behavior for each selected state after
validation.  `by-level` is a dependency-scoped static table and follows
P-AXIS-COVERAGE-01.

### 1.3 Behavior templates

```lisp
(define-behavior template-name (parameter ...) behavior)
```

Behavior templates are finite, declarative substitutions, evaluated nowhere as
Common Lisp.  A call has the template name in behavior position followed by
its arguments.  Template recursion, an unknown template, wrong arity, or a
parameter that cannot become a valid behavior value is refused.  Expansion
happens before semantic validation.

The typed behavior and normalized binding-entry IR retain optional immutable
source provenance.  A source-defined behavior records its body definition
span; after expansion it also records an ordered inner-to-outer list of the
template reference spans crossed to materialize it.  Programmatic model
objects legitimately have no origin.  This is model provenance for later
diagnostics, allocation reports, and source maps—not a backend spelling or a
host pathname contract.

The representative `(tap-hold ...)` used by the plan's illustrative
`tap-hold-shift-key` template is **reserved**.  There is no V1 source behavior
named `tap-hold`, no implicit duration named `thumb`, and no inferred mapping
from a template name to a backend tap-hold feature.  A behavior template is
implemented; a template whose body contains that reserved form is not an
implemented V1 layout.

### 1.4 Sparse overlays

```lisp
(overlay overlay-name
  (:axis patch-axis)
  (:state patch-state)
  (:precedence integer)
  (binding position behavior|transparent) ...)
```

The three options occur exactly once.  The named axis must be `patch`
resolution and must contain the selected state.  Overlay bindings are sparse;
`transparent` is an explicit fall-through, not an omitted binding.  For an
active position, non-transparent overlays apply in descending precedence.  An
equal-precedence conflict is an ambiguity and is refused.  If no overlay wins,
the base binding applies.  An overlay cannot contain an XKB key name, carrier,
layer, or other backend spelling.

## 2. Timed interactions

An interaction has a finite participant set, one or more named candidates, and
an explicit commitment boundary:

```lisp
(interaction interaction-name
  (:participants position ...)
  [(:observe participants|any-position)]
  [(:anchor position)]
  [(:arbitration (priority candidate-name candidate-name ...)
                 | (longest-match duration)
                 | (longest-match :deadline duration))]
  (case candidate-name
    (:match pattern)
    (:commit when-matched|when-unambiguous|pattern)
    (:do behavior)
    [(:enter behavior ...)]
    [(:commit-effect behavior ...)]
    [(:while behavior ...)]
    [(:exit behavior ...)]
    [(:cancel behavior ...)]
    [(:effect-start on-match|on-commit)]) ...)
```

The historical direct one-candidate spelling is also implemented:

```lisp
(interaction interaction-name
  (:participants position ...)
  [:observe ...] [:anchor ...] [:arbitration ...]
  (:match pattern) (:commit commitment) (:do behavior)
  [lifecycle-options ...])
```

It normalizes to a candidate named `default`.  Direct candidate options and
`case` clauses cannot be mixed.  Participant and candidate names are unique.
Every candidate, including a held candidate with lifecycle effects, has exactly
one `:match`, `:commit`, and `:do` clause; use `(:do none)` when the committed
candidate has no ordinary output.  The default observation scope is
`participants`; `any-position` is an explicit broader observation request.  An
explicit source anchor is accepted by the
model, but the current reference adapter can prove it only for a single
participant whose anchor is that participant; other anchor cases are refused.

`effect-start` defaults to `on-match`, preserving the original lifecycle
timing: a candidate's effects may begin as soon as its match is viable.  With
`on-commit`, effects begin only after that candidate wins and commits; they do
not acquire a held resource from a merely viable interpretation.  In the
current reference adapter, an effect still has one participant and exits on
that participant's `up`. If that `up` occurs while an `on-commit` candidate is
still viable, it is terminal cancellation rather than a later zero-lifetime
effect acquisition; a subsequent foreign event cannot revive or commit it.
Generated deadlines still precede an equal-time physical `up`, so a deadline
that commits first enters and then exits normally. Unsupported lifetime shapes
are refused.

### 2.1 Input events and time

The event-document surface used by the reference simulator is:

```lisp
(simulation
  (axis axis state) ...
  (latch axis state) ...
  (event millisecond down position) ...
  (event millisecond up position) ...
  [(until millisecond)])
```

Times are non-negative integer milliseconds and physical events are supplied
in nondecreasing timestamp order.  Only `down` and `up` are physical input;
an `up` without a preceding down and a duplicate down are malformed.  Deadline
events are generated by the machine and cannot be supplied by an event file.

**P-TIME-01 — equal-time deadline boundary.**  A generated deadline at time
`T` is processed before a physical event supplied at `T`.  Thus a release at
the precise deadline still observes its position as down at that deadline.
Events with the same physical timestamp otherwise retain their supplied order.
`until` advances only generated clocks after the final physical event.

### 2.2 Candidate state, context, and ownership

**P-CONTEXT-01 — anchor snapshot.**  On a participant `down`, the reference
machine starts each relevant candidate with the then-current axis context.  A
candidate's semantic dependency set is limited to the axes its match pattern,
behavior, or effects consult, and only latches in that set receive a latch
snapshot.  Candidate context therefore defaults to the anchor-down state.  A
latch snapshot contains its generation as well as its state, so a candidate
cannot consume a newer latch of the same axis.

The plan illustration's `(:context-at (down a))` is **reserved source syntax**:
V1 has no `:context-at` interaction option.  Its intended anchor-down case is
already P-CONTEXT-01; a different source-selected observation instant, including
commit-time context, must be rejected until it has a fully specified scheduler
and lowering proof.  The programmatic model's `:commit` policy is not a source
conformance claim and the current reference adapter refuses it.

**P-LATCH-01 — committed-only consumption.**  A latch is consumed immediately
before the committed candidate's actions, and only if that candidate both
consulted it and still holds the same captured generation.  Rejected,
cancelled, losing, or non-consulting candidates never consume it.  A candidate
may consequently consume a latch and set a replacement latch atomically.

**P-OWNERSHIP-01 — committed participant events.**  On commitment, the winner
claims every physical `down` and `up` for its declared participants from its
anchor through the current event prefix.  A committed winner cancels every
still-viable overlapping interpretation.  Those cancelled candidates execute
only their cancellation lifecycle, not their `:do` behavior.  There is no V1
event-replay form: a layout requiring a losing interpretation's events to be
replayed into an unrelated fallback is refused rather than assigned an
unwritten replay order.

### 2.3 Finite temporal-pattern algebra

These source patterns decode into a finite normalized pattern tree:

```lisp
(down position-selector)
(up position-selector)
(sequence pattern ...)
(all pattern ...)
(either pattern ...)
(and pattern ...)
(first pattern ...)
(duration position-selector [:at-least integer] [:less-than integer])
(deadline integer :after (down position-selector) [:while-down position])
(within integer occurrence occurrence)
(overlap position-selector ...)
(without occurrence :between occurrence occurrence)
(repeat occurrence :at-most integer [:at-least integer])
(capture identifier pattern)
(context-is axis state)
```

`position-selector` is a position identifier, `(other-than position ...)`,
`(any-position)`, or the lexical capture reference `(captured identifier)`.
`all`, `either`, and `and` are unordered finite predicates:
all children must match for `all`/`and`; any child may match for `either`.
`first` is source shorthand for `either`, not a separate clock rule.  In a
commit point such as `(first (up i) (up o))`, it becomes ready when either
release occurrence is present, so it represents the first observed release.
`sequence` requires ordered occurrence matches.  `duration` is the completed
press interval with bounds `[at-least, less-than)`.  `deadline` is a generated
tick after its `:after` down occurrence, optionally requiring the named
position still to be down.  `within` compares two occurrence timestamps using
an inclusive distance limit.  `overlap` requires a nonempty common press
interval.  `without` succeeds only once its second boundary occurs with no
forbidden occurrence strictly between the boundaries.  `repeat` requires a
finite `:at-most` bound; exceeding it fails.

For end-to-end reference-simulator conformance, `sequence`, `within`,
`without`, and `repeat` take atomic `down`/`up` occurrences in the places
marked `occurrence`; `within` has exactly two of them.  Composite nesting in
those occurrence slots decodes but is explicitly refused by the simulator,
rather than receiving speculative temporal meaning.

The first executable capture slice is deliberately smaller than the general
decoded pattern algebra:

```lisp
(sequence
  (down position-selector)
  (capture name (down position-selector))
  (up (captured name)))
```

It may occur only as a candidate's `:match`. `name` is an immutable lexical
binding to the first matching physical `down` for that candidate, and the
closing `up` must be for that same position. A capture name cannot be rebound,
and unbound references, nested captures, repeated captures, alternatives, and
unordered capture arrangements are rejected. This rule makes the captured
foreign-key identity explicit without assigning replay, ordinary-binding
suppression, or same-frontier ordering semantics. `context-is` is decoded and
executable: it compares the named axis/state with the candidate's
dependency-scoped anchor-down snapshot. A captured latch shadows the ordinary
axis value. Other context-observation instants remain refused.

**P-TIME-UNITS-01 — literal durations.**  The current source vocabulary uses
literal integer milliseconds.  `(deadline 200 :after (down a))` and `(within
45 (down i) (down o))` are the implemented spellings.  The plan illustration's
named `home-row` duration, `(milliseconds 45)` wrapper, and named `thumb`
timing are reserved; no profile, environment, or backend supplies a hidden
meaning for them.

### 2.4 Commitment, lifecycle, and arbitration

**P-COMMIT-01 — explicit irreversible boundary.**  `:do` is the candidate's
normal irreversible behavior and runs only after the candidate is both match-
valid and commit-ready.  `when-matched` commits when its `:match` becomes
matched.  A pattern commit commits when that separate pattern becomes matched.
`when-unambiguous` is decoded into the model but the reference adapter refuses
it: there is no proven V1 scheduler for waiting out all future alternatives.

Lifecycle options are syntactically decoded as explicit lists.  `:enter` and
`:while` begin a speculative effect, and irreversible output in either is
rejected by semantic validation.  The closed V1 source hold forms
`hold-modifier` and `hold-axis-state` are permitted only in `:while`; they use
the effect as their release owner, so no matching `:exit` release token is
written or inferred.  The simulator releases exactly that owner's holds on
both normal exit and cancellation.  `:exit` and `:cancel` may still contain
other direct behavior, including `set-axis-state`; that changes the base state
but is not a hold contribution.  A non-held `:while` behavior is refused
rather than assigned an invented teardown.  `:commit-effect` is performed with
`:do` at commitment by the reference adapter.  An adapter that cannot preserve
any requested effect lifetime refuses the layout; it must not turn a held
effect into a tap or drop its cancellation.

**P-ARBITRATION-01 — no accidental winner.**  Conflicting candidate commits
are invalid unless their explicit arbitration rule distinguishes them.  A
`priority` list is highest priority first and names candidates explicitly; it
never derives priority from source traversal.  Equal-priority incompatible
candidates are an ambiguity.  `longest-match` is decoded as a model policy but
is refused by the current reference adapter because its comparison has not
been proved for the model's full longest-match semantics.  Therefore a source
layout seeking current simulator conformance uses a complete `priority` list
where conflicting candidates can become ready together.

## 3. Interaction templates and materialization

```lisp
(define-interaction-template template-name (position-parameter ...)
  interaction-or-delegation)

;; top-level materialization
(instantiate-interaction instance-name template-name
  (:position-parameter logical-position) ...)

;; only inside a template body: delegation
(instantiate-interaction template-name
  (:position-parameter logical-position-or-outer-parameter) ...)
```

Template arguments are identifier-valued and named.  Headers may be forward
referenced; duplicate, unknown, missing, or cyclic references are errors.
Expansion precedes interaction validation.  A top-level materialization's
`instance-name` is the stable identity for diagnostics, traces, arbitration,
and source maps.  Nested delegation retains that outer concrete identity and
does not create another addressable interaction.  This is a surface identity
decision, not a new interaction semantic; see
[Decision 0001](decisions/0001-explicit-interaction-instance-names.md).

Interaction and candidate IR use the same optional provenance rule: the
candidate preserves the source `interaction`/`case` definition span plus every
nested delegation and final materialization use span, in that deterministic
inner-to-outer order.  Normalization preserves those origins unchanged for
later diagnostic or allocator consumers.

## 4. Section 5.2 representative-form disposition

The following table makes the PLAN's representative fragment reviewable
without treating illustration as an unqualified implementation claim.

| Section 5.2 fragment form | V1 status and exact disposition |
| --- | --- |
| `(ivory-key 1)` | Implemented required envelope. |
| `(define-layout manna-cadet ...)` and `(uses-topology kinesis-advantage)` | Implemented layout and topology-reference forms; topology resolution is supplied by the direct caller or project loader. |
| `case`, `script`, `plane` product axes and their `(:states ...)` / `(:resolution product)` options | Implemented; their canonical product enumeration follows P-AXIS-ORDER-01. |
| `shift-latch` with `(:resolution behavioral)` | Implemented; it does not create static product levels unless a behavior explicitly depends on it. |
| `(level-order case script plane)` | Implemented only when it names exactly the product axes once; `case` varies fastest. |
| `(modifiers control meta super hyper alt)` | Implemented semantic names only; no target slots are implied. |
| `(binding q (at ...))`, `(unicode "q")`, `(named-symbol up-caret)`, `none`, and `(inherit (...))` | Implemented table forms, subject to P-AXIS-COVERAGE-01 and output-vocabulary requirements at realization time. |
| `(interaction a-home-row ...)`, `:participants`, `:observe any-position`, `case`, `:match`, `:commit`, `:do`, `(down ...)`, `(up ...)`, `sequence`, `and`, `either`, `duration`, `without`, `(other-than ...)`, `(deadline integer ...)`, and `(hold-modifier super)` | Implemented source forms within the restrictions in sections 2.1–2.4.  The whole illustrated interaction is not currently conformant because it has reserved `:context-at` and named durations; its `hold` case has an owner-scoped `:while` release contract and does not need an explicit release form. |
| `(:context-at (down a))` | Reserved and rejected.  P-CONTEXT-01 supplies anchor-down capture without a surface option. |
| `(deadline home-row :after ...)` | Reserved because `home-row` is not an integer duration policy.  Use a literal integer millisecond value for current conformance. |
| `(:arbitration (priority hold tap))` | Implemented deterministic priority spelling, highest first, provided both names are candidates and semantic ambiguity validation accepts it. |
| `(binding latch-latch (on-tap (latch-axis-state shift-latch latch)))` | Implemented shorthand with the expansion and committed-only latch semantics in sections 1.2 and 2.2. |
| `(define-behavior tap-hold-shift-key ...)`, `by-axis`, `hold-axis-state`, `latch-axis-state`, and its template call | Template and listed axis forms are implemented.  The particular template is not executable because its body uses reserved `tap-hold`. |
| `(tap-hold (:tap ...) (:hold ...) (:timing timing))` | Reserved and rejected.  V1 does not infer its state machine, timing policy, commitment point, replay policy, or backend lowering. |
| `(binding greek-thumb (tap-hold-shift-key ... thumb))` | Rejected through the reserved template body; no semantic tap-hold behavior is claimed. |
| Direct `stop-output` interaction, `all`, `(first (up i) (up o))`, and `(command stop-output)` | Direct interaction, `all`, `first`/`either`, and semantic command output are implemented.  The command still needs an approved realization vocabulary and is never host execution. |
| `(within (milliseconds 45) (down i) (down o))` | Reserved wrapper spelling.  The current implemented equivalent is `(within 45 (down i) (down o))`; this has inclusive 45 ms distance under P-TIME-UNITS-01. |

## 5. Required refusal behavior

A conforming implementation must reject rather than guess whenever the source
asks for a reserved form, a duplicate or unknown closed option, an unknown
axis/state/position/template/candidate, a non-finite repetition, an incomplete
or cyclic table, equal-precedence overlay conflict, ambiguous candidate commit,
unproved `when-unambiguous` or `longest-match` scheduling, unrepresentable
capture/context matching, an unsupported effect lifetime, unknown output
spelling in the selected realization, or a target feature not proven by that
realization.  Parsing,
normalization, planning, and backend emission are separate evidence levels;
success at an earlier level does not weaken any later refusal.

The broader motivation and current implementation boundary are summarized in
[language.md](language.md), [semantics.md](semantics.md), and
[backend-contract.md](backend-contract.md).  New syntax is not V1 merely
because it resembles a construct in the representative PLAN fragment: it must
first acquire an explicit grammar, event rule, refusal behavior, and independent
lowering proof.  The approved default choices for the remaining PLAN section
16 policy questions are recorded in
[Decision 0002](decisions/0002-v1-policy-defaults.md).
