# 0002: Version-1 policy defaults and migration refusals

- Status: Accepted, but revisitable
- Date: 2026-08-14

## Context and problem

[PLAN.md](../../PLAN.md) section 16 listed fourteen content questions that
could otherwise leave version 1 with accidental defaults: an implementation
could mistake a historical spelling for an application meaning, source order
for arbitration, or a Kanata timing parameter for an Ivory Key interaction
rule.  The frozen Manna Cadet material now has a bounded evidence audit, but
that audit deliberately distinguishes transcribed static results from unresolved
timed, selector, and backend behavior.

This decision supplies a deterministic V1 policy for every section 16 item.
Where the source, model, and reference simulator establish a rule, the rule is
accepted.  Where the Manna material does not establish an abstract behavior,
the accepted policy is a fail-closed refusal, not an inferred migration.  The
result makes the language architecture determinate without claiming that the
current Manna Cadet fixtures are a complete migration or deployment.

The evidence classifications used here are defined by
[Manna Cadet evidence audit](../manna-cadet-evidence-audit.md): **transcribed**
records an exact source result in a target-neutral form; **unresolved** has no
proven operational equivalence; **regression-only** is historical evidence but
not an active selected variant; and **excluded** is not executable behavior.

## Decision summary

The policies below correspond one-for-one, and in the same order, to the
fourteen bullets in PLAN section 16.  “Fail closed” means a selected V1
simulation, lowering, or migration review must refuse the unsupported case;
it does not mean that a parser is permitted to silently delete source data.

| ID | Section 16 question | Accepted V1 disposition |
| --- | --- | --- |
| P-01 | Historical command and non-Unicode identities | Identity-only transcription; realization mapping is mandatory and otherwise refused. |
| P-02 | Shifted Top / Top+Greek holes | Literal `NoSymbol` is explicit `none`; no inheritance or invented meaning. |
| P-03 | 360 game layer scope | Excluded from the shared Manna layout; unresolved 360-specific work. |
| P-04 | Older chorded files | Regression-only, not a supported selected variant. |
| P-05 | Default arbitration | No implicit default; use explicit priority or refuse ambiguity. |
| P-06 | Losing-candidate replay | No replay; one candidate set owns and decides its events. |
| P-07 | Absence, clocks, and repetition | Only the finite literal-millisecond algebra below; reject all other forms. |
| P-08 | Cumulative milestone output | Commit-time output plus reversible effects only; no cumulative milestone semantics. |
| P-09 | Concurrent consumers of one latch | One reservation per anchor-time candidate set; an independent pending consumer of the same generation is refused. |
| P-10 | Context-observation time | Anchor-down snapshot only; no source override. |
| P-11 | Patch precedence and simultaneous activation | Explicit global precedence, transparent fall-through, and equal-precedence conflict refusal. |
| P-12 | Manna candidate priorities | No timed-candidate priority is selected; four exact immediate held interactions need no priority. |
| P-13 | Layout versus device/profile timing | Timings belong to an interaction declaration; no override/default mechanism exists. |
| P-14 | Left/right modifier distinction | Five modifier identities are source-neutral; side is not application-visible V1 meaning. |

## Policies

### P-01 — abstract historical command and non-Unicode identities

**Decision.**  A historical output may be represented only by the neutral
identity that the frozen source and evidence audit record: an abstract
`command`, `named-key`, `named-symbol`, or Unicode value.  A selected
realization must supply an explicit typed mapping for every named output it
uses and validate the resulting opaque spelling.  Without that mapping,
compilation refuses.

The current Manna evidence settles the identity inventory—not an
application-level interpretation.  It transcribes the 29 primary function
outputs and the static table's named symbols, while the historical carrier
numbers and XKB private-use values remain realization evidence.  In particular,
comments suggesting an `XF86*`, `Insert`, `Pause`, or `Help` alternative do not
establish an equivalent application action.  No Manna output vocabulary is
permitted to invent those meanings. The selected Linux realization now
declares the frozen typed XKB spellings and 29 paired Kanata carrier actions;
that records observed transport values, not an application-level reinterpretation.

**Evidence.**  The audit's commands-and-carriers table records each neutral
identity and its observed historical carrier/XKB result; it expressly requires
a realization-owned vocabulary before emission.  The frozen baseline records
the static table independently.  This decision preserves those identities
without treating either carrier number or XKB keysym as abstract content.

### P-02 — shifted Top and Top+Greek absence

**Decision.**  Every literal frozen `NoSymbol` cell is the abstract behavior
`none`.  It is not inherited, transparent, omitted, or an invitation to choose
a later symbol.  Static tables are total only because the absence is explicit.

This settles output absence, including the shifted Top and Top+Greek holes.
It does not settle how a later realization combines or exposes the Top and
Greek selectors.  A selected profile that needs a selector-consumption or
application-visibility rule not proved by its backend must refuse rather than
reinterpret a `none` cell.

**Evidence.**  The evidence audit counts 158 literal `NoSymbol` cells and
records their exact transcription as `none`; the frozen truth-table projection
also distinguishes observed Top symbols from modifier-consumption evidence.

### P-03 — Advantage 360 game layer

**Decision.**  The game layer is not part of the shared Manna Cadet layout and
is not a user overlay by default.  It is an unresolved, Advantage-360-specific
candidate overlay/profile.  It becomes selectable only through a later
explicit declaration that supplies its interaction, timing, lifecycle,
arbitration, output-vocabulary, and backend evidence.

Until then, project composition for the 360 chooses only its physical placement
of the shared static layout.  It does not activate, simulate, lower, or deploy
the game layer.

**Evidence.**  The audit identifies `layer-switch game`, `ExitGame`, ordered
multi actions, macro repeat, and tap-holds as 360-only unresolved behavior;
the checked-in 360 composition is explicitly placement-only.

### P-04 — older chorded variants

**Decision.**  The two older chorded Kanata files are regression-only evidence.
They are not supported Manna variants, do not contribute active interactions,
and cannot establish a default chord or command meaning.  An owner who wants a
chorded variant must select a new explicit profile and provide timing,
commitment, arbitration, output, and test evidence before it is executable.

**Evidence.**  The frozen audit records both hashes and their 29 chord rows,
but classifies them as regression-only.  In particular, the historical `i` +
`o` chord is not an active primary `stop-output` interaction.

### P-05 — arbitration defaults

**Decision.**  V1 has no implicit arbitration priority.  Candidate order,
declaration order, lexical name order, participant count, device position, and
arrival order are never default tie breakers.  An interaction whose conflicting
candidates are proven to share match and commitment requires an explicit
`(priority candidate ...)` rule; the first listed candidate has highest
priority.  Equal-priority incompatible candidates are an ambiguity.

`longest-match` has a decoded model representation but is not current
reference-simulator conformance because its complete comparison rule is
unproved.  Other conflicts the static validator cannot prove remain a runtime
reference-simulation ambiguity and therefore cannot support a migration or
lowering claim.

**Evidence.**  The model validates identical match/commit ambiguity unless
explicit priority resolves it, and the reference machine reports equal-priority
incompatible commitments as ambiguous.  The source grammar does not derive a
priority from declaration order.

### P-06 — losing candidates and event replay

**Decision.**  Event ownership is decided inside one candidate set.  When a
candidate commits, it claims its participant input from its anchor through the
current prefix and cancels still-viable overlapping interpretations.  A losing
candidate executes only cancellation lifecycle behavior; its input is not
replayed to a lower-priority interaction or ordinary binding.

There is no source form for replay, no replay queue, and no fallback ordering.
Any intended behavior that needs replay is outside V1 and is refused until an
explicit, independently tested replay contract exists.

**Evidence.**  The reference machine's commitment path claims participant
events and cancels viable overlap; the V1 language reference records the same
ownership policy.

### P-07 — absence predicates, clocks, and repetition

**Decision.**  V1 admits only the following finite source rules:

- absence is `(without occurrence :between occurrence occurrence)` and the
  forbidden occurrence must be strictly between its two explicit boundaries;
- physical event times, `deadline` durations, `within` windows, and duration
  bounds are non-negative integer milliseconds in source;
- a `duration` has at least one of `:at-least` or `:less-than`, and when both
  occur the lower bound is strictly less than the upper bound;
- `within` is exactly two atomic `down`/`up` occurrences and uses an inclusive
  distance bound;
- `repeat` contains an atomic occurrence and must spell finite
  `:at-most N`, with optional `:at-least M` satisfying `0 <= M <= N`; and
- `sequence`, `within`, `without`, and `repeat` reject composite patterns in
  their occurrence-only positions for reference-simulator conformance.

There is no source named-duration, clock profile, floating-point duration, or
implicit timeout.  V1 specifies no hidden global upper clock/repetition limit:
the source value must satisfy the finite non-negative rules above, while a
target with a stricter capability limit must report and refuse it explicitly.

**Evidence.**  The finite pattern model and reference compiler enforce atomic
occurrence slots, literal non-negative millisecond clocks, strict duration
ranges, and required bounded repetition.  The language reference records the
equal-time deadline-before-release boundary.

### P-08 — output milestones and lifecycle effects

**Decision.**  V1 permits ordinary output only at a candidate's explicit
commit: `:do` and any `:commit-effect` actions execute there.  Before commit,
`:enter` and `:while` may not emit irreversible text, named output, or command
output.  A source `hold-modifier` or `hold-axis-state` is permitted only in
`:while` and is owner-scoped: the simulator releases exactly that contribution
on normal exit or cancellation, so no manual release token or generated name
is required.  Direct `set-axis-state` remains a base-state transition and does
not release another owner's hold.  When cancellation needs additional distinct
behavior, it must be declared as `:cancel` rather than inferred.

There is no cumulative milestone-output declaration.  A feature that needs
output at several provisional milestones, output rollback, or cumulative
emission remains reserved and must be refused rather than encoded as a series
of premature taps.

**Evidence.**  Semantic validation rejects irreversible entry/while behaviors,
source holds outside `:while`, and non-held `:while` behavior without an exact
release contract.  The simulator executes `:do` and `:commit-effect` only
after commitment, maintains owner-scoped held contributions, and records
separately traceable effect entry, exit, and cancellation transitions.

### P-09 — multiple pending consumers of one latched axis

**Decision.**  One committed candidate may consume a latch only if it consulted
the captured generation; consumption occurs before its actions.  The selected
V1 conformance policy is one proven consumer per concurrently viable latch
generation.  A layout/profile that permits two independently pending candidate
sets to consult the same latched axis is refused until it supplies a proven
reservation/arbitration rule that chooses one consumer before either behavior
can observe the latch.

This is deliberately stricter than merely avoiding a double deletion.  The
reference machine now treats a latch snapshot as a pending candidate-set
reservation: before a second independent candidate set can capture the same
axis/generation, it signals `simulation-latch-reservation-conflict`.  Cases
from the same interaction and physical anchor remain one candidate set and
use their declared arbitration.  This is a runtime fail-closed check; it does
not claim static validation can decide every possible future event trace.

**Evidence.**  Candidate snapshots retain latch generation; only a committed
candidate consumes a matching current generation, before actions.  Focused
simulator coverage proves cancellation non-consumption and refusal of two
independent pending consumers before either can commit.

### P-10 — context-observation time

**Decision.**  The only V1 source context-observation instant is the
candidate's anchor-down snapshot.  Context is dependency-scoped, and a captured
latch shadows the ordinary axis value for that candidate.  There is no
`:context-at` option and no source spelling for commit-time observation.

The programmatic model's commit-time policy and decoded contextual patterns do
not widen this source contract: the current reference adapter refuses them.
Any construct requiring another observation instant is reserved and must be
rejected until it has a complete scheduler, trace rule, and lowering proof.

**Evidence.**  The V1 language reference specifies anchor-down capture; the
reference compiler explicitly refuses non-anchor context policy and has no
capture/context-predicate store.

### P-11 — patch precedence and simultaneous activation

**Decision.**  An overlay has an explicit integer precedence.  For a position,
all overlays whose patch-axis state matches the candidate's captured context
are considered together in descending precedence; the first active opaque
binding wins.  `transparent` falls through to the next active overlay and then
the base binding.  Source declaration order never breaks a tie.

Simultaneous activation of distinct patch axes is therefore defined by the
same global precedence ordering, not by nesting one axis inside another.
Disjoint position overrides combine.  Equal-precedence opaque overrides of the
same position are an ambiguity and are refused.  Conditional latch-driven
overlay dispatch is also refused where the current simulator cannot preserve
exact latch consumption.

**Evidence.**  Overlay decoding requires explicit precedence; normalization
sorts it descending; validation rejects equal-precedence conflicts; and the
whole-layout adapter walks active patches in that order with transparent
fall-through.  The adapter explicitly refuses unsupported overlay-latch
transitions.

### P-12 — Manna interaction-candidate priorities

**Decision.** There are no normative Manna home-row, thumb, function-activator,
Top/Greek tap-hold, game, or chord candidate priorities in V1. The current
Manna fixture has four exact immediate one-participant held interactions:
direct `lshift` / `rshift` case holders and direct `lctl` Greek / `rctl` Top
selectors. They use no timing or candidate priority. The two case holders use
owner-scoped held-axis lifetime, so either first release leaves the other
holder active. This does not select a priority for any timed interaction or
infer one from Kanata's `concurrent-tap-hold`, `tap-hold-release`,
`first-release`, or source order.

Any future Manna timed interaction must declare an explicit candidate policy
under P-05, satisfy P-06 through P-10, and be covered by event-trace tests
before a migration claim.  The 45 ms chord rows remain P-04 regression-only.

**Evidence.** The evidence audit records the unchanged direct Shift source
tokens and XKB `Shift_L` / `Shift_R` mapping, and the whole-layout simulator
checks both two-owner release orders. It separately lists the home-row, thumb,
selector tap-hold, and chord parameters as unresolved or regression-only.

### P-13 — timing ownership and overrides

**Decision.**  A V1 timing value belongs to the interaction declaration that
uses it and is a literal non-negative millisecond value under P-07.  There is
no V1 layout default, device override, profile override, named duration, or
environment-derived timing rule.  Device files describe physical placement;
realization profiles state capabilities and target policy, not semantic tap or
hold delays.

The observed Manna `200/200` values, the left-Super `250/250` exception, and
the older chord `45` window remain evidence only.  They must not be copied into
an active layout until an owner supplies an exact interaction with commitment,
cancellation, arbitration, effect lifetime, and trace proof.

**Evidence.**  The audit records those source parameters but classifies their
operational behavior as unresolved; the V1 language grammar accepts literal
durations and reserves named/profile timing forms.

### P-14 — left/right sources of semantic modifiers

**Decision.**  `control`, `meta`, `super`, `hyper`, and `alt` are five
source-neutral semantic modifier identities.  V1 gives no application-visible
meaning to whether the left or right physical source selected one of them.
Topology/device placement may preserve the physical source; it cannot turn
that distinction into a different abstract modifier or OS slot implicitly.

If a future requirement proves an application-visible side distinction, it
must introduce explicit distinct semantic identities and matching realization
evidence.  Reusing a single modifier identity while silently choosing different
application behavior by side is refused.  Current Manna home-row and thumb
activation is unresolved under P-12/P-13, so this policy does not claim that
either source has been operationally migrated.

**Evidence.**  The audit transcribes the five identities and their historical
left/right source aliases, while preserving the fact that their tap-hold
commitment and the left-Super timing exception are unresolved.  The model
represents modifiers as unbounded semantic identifier collections, not host
slot masks.

## Consequences

The current static Manna transcription remains valid evidence: literal table
outputs, explicit `none`, the common function output table, placements, and
reserved carriers retain their documented status.  It remains **not migrated**:
the selected output vocabulary and carrier proposal exist, but there is no
complete interaction set, selector/modifier/activation proof, complete
simulation, generated behavior comparison, or deployment.

These policies are architectural defaults, not a permission to fabricate
historical content.  A future change must add evidence, an explicit source
form/semantics where needed, focused simulator and lowering tests, and a
revision of this decision before it converts an unresolved Manna row into an
active migration feature.

## Alternatives considered

### Infer semantics from existing Kanata/XKB spelling

Rejected.  A carrier number, private-use keysym, runtime option, source order,
or timing literal does not by itself define an abstract application effect,
commitment rule, or precedence policy.

### Treat all section 16 questions as indefinitely open

Rejected.  That would leave accidental implementation defaults available.  The
fail-closed dispositions above provide deterministic behavior while preserving
the ability to revisit content after evidence arrives.

### Encode unresolved Manna behavior as generic templates

Rejected.  A template name cannot supply missing timing, arbitration, replay,
lifecycle, or target-realization semantics.  It would make an apparent feature
claim without an executable proof.

## Revisit triggers

Revisit this decision when any of the following arrives with focused evidence
and tests:

- an application-level interpretation, beyond the reviewed frozen transport
  vocabulary, that establishes a new typed command meaning without changing
  abstract identity accidentally;
- a complete, traceable interaction specification for a home-row, thumb,
  selector, game, or chord behavior;
- a proven scheduler for `when-unambiguous`, longest-match, replay, cumulative
  milestones, another context observation time, or concurrent latch
  reservation;
- a selected 360-only game or chorded profile with its own source-to-artifact
  evidence;
- a target capability limit that requires an explicit V1 maximum for a clock or
  repetition bound; or
- evidence that applications distinguish left/right instances of a semantic
  modifier and need explicit new identities.

Until then, preserve the explicit refusal boundaries and do not promote the
historical static transcription to a migration or deployment claim.
