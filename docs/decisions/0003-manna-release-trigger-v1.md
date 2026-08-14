# 0003: Proposed Manna release-trigger v1 compatibility policy

- Status: Proposed
- Date: 2026-08-14

## Context and boundary

The frozen primary Manna Cadet Kanata files contain fourteen
`tap-hold-release` aliases. Their source records a finite set of physical
positions, tap actions, hold actions, and timeout pairs. It does not record a
frozen Kanata binary or version, an event-level trace, a total equal-time
scheduler, or a general multi-owner lifecycle. The evidence audit therefore
correctly leaves the aliases unimplemented and the current selected V1 policy
continues to refuse timed Manna-candidate priorities.

This ADR proposes a modern, explicit compatibility policy named
`manna-release-trigger-v1`. It is a design candidate for a future review. It
does not select the existing Manna fixture, generated output, or backend
behavior. The candidate is now represented by a source-decoded abstract test
fixture and executed by the reference simulator, using already-implemented
finite interaction forms; that is semantic evidence, not a selected migration
or lowering. In particular, this ADR is not evidence that the policy is
historically equivalent to Kanata.

The notation below uses current interaction source syntax. It does not add a
generic `tap-hold` form, a profile-supplied timing default, or a backend
spelling to the language.

## Post-proposal Kanata 1.12 evidence

The separately tagged [Kanata 1.12 oracle](../kanata-1.12-oracle.md) now gives
us a hash-pinned, source-state-machine trace for the current runtime family.
It confirms the equal-deadline tap/hold boundary, foreign-release hold,
same-modifier final-owner release, and final-owner function-layer lifetime.

It also demonstrates that Kanata 1.12 delays a pending foreign key until the
tap-hold owner resolves. That directly differs from this proposal's deliberate
"observed and unowned; never buffered, delayed, or replayed" rule. Therefore
the new evidence does not silently accept this ADR or turn it into a Kanata
compatibility claim. It sharpens the choice: accept this as an intentionally
modern no-delay policy whose Kanata lowering remains refused, or specify a
separate versioned compatibility profile with explicit buffering and ordered
release semantics.

## Proposed policy

For a tap-hold physical position `P`, hold deadline `H`, and tap deadline `R`,
the policy supplies exactly these three candidates:

| Candidate | Proposed match | Result when it wins |
| --- | --- | --- |
| `hold-timeout` | `(deadline H :after (down P) :while-down P)` | Commit the hold effect. |
| `hold-after-foreign-release` | `(sequence (down P) (capture foreign (down (other-than P))) (up (captured foreign)))` | Commit the hold effect. |
| `tap` | `(sequence (down P) (up P))` plus `(duration P :less-than R)` | Emit the tap output. |

The candidates have the fixed priority `hold-timeout` >
`hold-after-foreign-release` > `tap`. This priority resolves an equal-deadline
candidate set. No declaration order, lexical name, device position,
participant count, or accidental scheduler order is a tie breaker. A timer
deadline at physical time `T` is processed before a physical event at `T`;
physical inputs with the same timestamp retain the order supplied by the event
source. This defines a deterministic policy for this proposed profile, but does
not purport to recover the historical `concurrent-tap-hold` scheduler.

For the Manna compatibility route, only equal timer pairs are admitted:
`R = H = 200 ms`, and `R = H = 250 ms` for the left-side `a` alias. Mixed
tap/hold deadlines, named clocks, inferred defaults, repetition, and broader
capture patterns are outside this proposal.

## Candidate source and reference implementation

`tests/model/interaction-template-decoder.lisp` contains an explicit,
table-driven source-decoded 14+2 candidate fixture: all fourteen primary rows
plus the Delete/Enter alternate selectors. Each generated closed interaction
spells its literal target-neutral tap, semantic modifier or axis hold, and
200/200 timeout; only `a` spells 250/250. Every row has the three candidates
above, the same explicit priority, and `:effect-start on-commit` on both held
candidates. These are ordinary interaction forms, not a newly privileged
source form or an active Manna profile.

`tests/simulation/compile.lisp` then compiles those normalized interactions
through the reference machine. It covers every row's literal tap and deadline
hold, captured foreign release, early owner-up tap fallback, immutable capture
position/down index, deadline-before-equal-time physical release, supplied
foreign-event order with no synthetic replay, the 250/250 boundary, all five
semantic modifier families' first/final-owner release, both case owners, both
function-owner release orders, and the script/plane selector axes. The fixture
is intentionally outside the checked-in Manna layout: it neither selects these
rows nor assigns a device placement, backend spelling, or realization.

The whole-layout fixture also uses one proposed timed interaction as another's
observed foreign input.  The foreign candidate is armed by its own physical
down and, after the outer owner releases, later taps on its own up; the outer
uncommitted foreign-release candidate is cancelled with its owner's tap.  This
proves the no-delay/unowned disposition without assigning a policy to the
different prefix where a shared foreign up would make two disjoint candidates
eligible simultaneously; that ordering remains unselected.

This evidence establishes the bounded abstract contract only. Current
backends have no exact lowering proof for this interaction, so this ADR still
authorizes no artifact emission, Kanata configuration, deployment, or
historical-equivalence claim.

### Foreign capture and ownership

`capture foreign` binds the first eligible foreign `down` immutably to its
exact physical position and down-event index. Its completing `up` must be at
that same physical position. Later foreign input cannot rebind the capture.
The proposal intentionally permits only that finite direct sequence: it does
not add a capture-local requirement that `P` remain down during the foreign
release, nor a general nested, repeated, alternative, or reference-before-bind
capture form.

In the required complete three-candidate interaction, an `up P` before the
captured foreign `up` commits `tap`. That overlapping commitment cancels the
still-viable `hold-after-foreign-release` candidate before it acquires an
owner-scoped hold. The result is therefore a tap, never a no-op or delayed
hold. The generic finite-capture slice alone does not establish that fallback;
it must not be used for an active release-trigger profile without its required
tap and timeout candidates and direct tests.

`P` owns only `P`. The captured foreign input is observed and remains unowned:
it is never buffered, delayed, consumed, or replayed by this interaction. A
future realization needing the foreign input to be delayed, altered, or
replayed must refuse rather than call this policy compatible. An `up` of a
position other than the owning `P` cannot end `P`'s committed hold.

### Held effects and shared state

A winning hold starts its effect at commitment and releases precisely its own
owner contribution at `up P`, including cancellation after an active effect.
For a shared semantic modifier or axis state, the first active owner acquires
the effect and the final active owner releases it. Two concurrently held,
conflicting values of the same axis are a refusal, not a source-order choice.

The two Manna function aliases (`End` and `PgDn`) would use the same rule:
their winning hold contribution makes `function=active`, and the function
overlay remains active until the final function owner releases. This is a
proposed modern overlay lifetime, not a reconstruction of the historical
Kanata layer implementation.

## Why this is not a historical-equivalence claim

The frozen primary material establishes the aliases and their declared
timeouts, but not the Kanata version/pin or the complete operational behavior
of `tap-hold-release` together with `concurrent-tap-hold`. In particular it
does not establish equal-deadline scheduling, all interruption paths,
multi-owner release, or what happened to foreign key events in an end-to-end
historical configuration.

The policy therefore chooses explicit modern behavior only for the bounded
cases above. It must refuse a workload whose observed foreign key behavior
requires buffering, delay, transformation, or replay, and must not be cited as
proof of an exact historical Kanata/XKB trace. A historical-equivalence claim
would require a pinned executable and event-level oracle covering those cases.

## Alternatives considered

### Emulate historical Kanata without an oracle

Rejected for now. The frozen tree contains no pin or trace sufficient to
specify the required scheduler and foreign-event behavior, so an emulation
would be inference presented as migration evidence.

### Let source or scheduler order break ties

Rejected. It makes the result depend on incidental layout spelling or runtime
arrival details, contradicting the V1 refusal of implicit timed-candidate
priority.

### Own, delay, or replay the foreign key

Rejected. That would make a second physical input part of an interaction
without an independently specified dispatch and replay contract. It also
creates a false compatibility claim where a backend cannot preserve the exact
foreign event.

### Admit arbitrary capture and timer combinations

Rejected. General captures, mixed deadlines, repetitions, and nesting need a
larger lifecycle and scheduler contract. The proposed policy is deliberately
limited to the two source-observed equal timer pairs and one direct captured
foreign-release sequence.

### Materialize the 14+2 inventory in the active Manna layout immediately

Rejected. The candidate source/simulator fixture now has all sixteen
source-derived abstract instances, but it is not an active layout selection, a
selected realization, a lowerer, or an event-level backend proof. The aliases
remain explicit migration refusals until the acceptance conditions below are
met.

## Migration consequences if accepted

Acceptance would authorize a later, separately reviewed Manna slice to encode
the fourteen primary `tap-hold-release` rows and the Delete/Enter alternate
selector rows documented in the evidence audit: reviewed physical positions,
literal target-neutral taps, literal semantic holds, and the two equal deadline
pairs. It would not select the older chorded variants, invent modifier
meanings, decide `<LSGT>` placement, or establish a 360 game overlay policy.

That future slice must retain target-neutral tap/hold identities. A backend
may lower it only after proving the policy's ordering, owner release, foreign
input treatment, and function-overlay lifetime exactly; otherwise planning and
emission must refuse. No lossy fallback, delayed foreign event, or generated
replay is authorized by this proposal.

## Acceptance and revisit triggers

This ADR remains Proposed until all of the following occur:

- an owner explicitly selects this modern compatibility route and updates the
  selected V1 priority/refusal policy accordingly;
- the selected realization links the policy to its complete intended
  interaction-instance set, rather than applying a Manna-specific rule to
  every unrelated interaction in the composition;
- the existing closed source/model representation continues to validate the
  finite capture form and reject capture in alternatives, repetition, nesting,
  reference-before-bind, and rebind cases;
- the fixture-level inspection evidence is extended from its current complete
  14+2 inventory to every selected composition instance, preserving capture
  position/down-event index, candidate priority, and equal-time ordering;
- whole-layout traces cover every selected composition instance. The candidate
  fixture already covers every 14+2 tap/deadline row, no-delay foreign input,
  immutable foreign capture, early-`up P` tap fallback, all semantic modifier
  families, case, function, script, and plane owner lifetime; it does not
  substitute for a complete Manna trace, conflicting-axis review, or
  source-row/device projection; and
- each selected backend has an exact lowering proof and generated-artifact
  review, or explicitly refuses the interaction before emission.

The decision must be revisited if a frozen Kanata version or event trace is
recovered, if evidence establishes a required foreign-event delay/replay or a
different equal-time rule, if the proposed finite capture needs a `P`-still-down
conjunction, or if a backend exposes a materially different exact capability.
Such evidence may lead to a distinct historical profile rather than changing
this modern compatibility policy.
