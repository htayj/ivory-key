# 0004: Kanata 1.12 buffered compatibility contract

- Status: Accepted, but revisitable
- Date: 2026-08-14

## Context and status

The hash-pinned [Kanata 1.12 oracle](../kanata-1.12-oracle.md) establishes a
runtime-family contract that differs materially from the proposed modern
[`manna-release-trigger-v1`](0003-manna-release-trigger-v1.md) policy.  A
pending `tap-hold-release` owner delays a foreign press and later releases it
in an observable order.  The frozen Manna Cadet source commit does not itself
pin Kanata 1.12, so this is **not** a source-era equivalence claim.

This records one selected, non-default policy identity:

```lisp
(interaction-compatibility kanata-1-12-buffered
  (instances tap-hold-case-f tap-hold-case-j))
```

The spelling is a closed project/realization-policy reference; it is not an
interaction clause, backend action, or embedded Kanata form.  It is absent
from generic realizations and selected explicitly by the Manna Linux
realization. An absent compatibility policy remains unselected, and this
decision does not add a default. The required nonempty
`instances` set prevents this Manna-specific policy from silently governing an
unrelated interaction in the same composition.  Unlisted interactions retain
their ordinary generic refusal.

The checked-in Manna Linux realization selects the policy for the exact sixteen
source instances and records typed alias, tap, modifier/layer, carrier, and
bounded direct-route allocations. The model derives a typed, backend-neutral
contract only from the exact normalized three-candidate shape, and the
reference simulator executes its finite dispatch barrier when that realization
is selected. Selection records the intended compatibility semantics; it does
not upgrade backend fidelity. The compiler and Kanata backend continue to
refuse artifact publication until the native input-domain and end-to-end
differential gates below are complete.

## Provenance and frozen alias inventory

The oracle harness refuses an archive other than Kanata `v1.12.0` with source
archive SHA-256
`7081073d1d22fe4e404cf8e7d1dfa3f72562fb2d96538367c07f64877dcbf87a`, and it
uses the frozen Advantage 2 primary configuration SHA-256
`d36a93eab6e2355707f7a6bfbcfac2a4e3b0ea361cc399d388543f51e1f5226b`.
It has no keyboard, uinput, service, or deployment boundary.  Its exact
checked event strings live in
[`tests/external/kanata-1.12-manna-oracle.patch`](../../tests/external/kanata-1.12-manna-oracle.patch).

Both primary frozen `normal` layers select these sixteen aliases. This is the
complete candidate inventory for this proposed policy; it does not add
the direct physical Shift holders, inactive historical aliases, game layer, or
older chorded variants.

| Family | Alias / owner position | Tap / hold deadline | Literal tap | Literal held result |
|---|---|---:|---|---|
| case | `@Sf` / `f` | 200 / 200 ms | `f` | `lshift` |
| case | `@Sj` / `j` | 200 / 200 ms | `j` | `lshift` |
| control | `@Cd` / `d` | 200 / 200 ms | `d` | `lctl` |
| control | `@Ck` / `k` | 200 / 200 ms | `k` | `lctl` |
| meta | `@Ms` / `s` | 200 / 200 ms | `s` | `lalt` |
| meta | `@Ml` / `l` | 200 / 200 ms | `l` | `lalt` |
| super | `@sa` / `a` | 250 / 250 ms | `a` | `lmet` |
| super | `@s;` / `;` | 200 / 200 ms | `;` | `lmet` |
| hyper | `@eoam` / `esc` | 200 / 200 ms | `esc` | `rmet` |
| hyper | `@qoam` / `'` | 200 / 200 ms | `'` | `rmet` |
| alt | `@Hro` / `bspc` | 200 / 200 ms | `bspc` | `ralt` |
| alt | `@Hsp` / `spc` | 200 / 200 ms | `spc` | `ralt` |
| function | `@HscL` / `end` | 200 / 200 ms | `end` | `(layer-while-held fun)` |
| function | `@HscR` / `pgdn` | 200 / 200 ms | `pgdn` | `(layer-while-held fun)` |
| script selector | `@gdel` / `del` | 200 / 200 ms | `del` | `@gr` |
| plane selector | `@rtop` / `ent` | 200 / 200 ms | `ent` | `@top` |

The inventory contains fifteen `200/200` pairs and one `250/250` pair.  It
records literal source actions, not target-neutral modifier, selector, or
function semantics.  The two device primary files have the same alias rows;
the actual configuration exercised by the external oracle is Advantage 2.
The oracle's actual-configuration traces cover `f`/`j`, all five semantic
modifier pairs, `end`/`pgdn`, and direct early-tap plus foreign-release rows
for `gdel`/`rtop`; its small synthetic configurations cover the two equal
timeout shapes. The sixteen-row list is a complete frozen source inventory
and positive structural evidence boundary, but not proof of the remaining
whole-device queue and backend obligations.

The frozen mechanical ledger now closes all 68 Advantage2 and 72
Advantage360 primary input positions. C7/game differences remain separately
classified; they do not expand this policy's route domain.

The generated profile also makes one deliberate fail-closed correction to the
frozen configuration boundary. The frozen files use
`process-unmapped-keys yes`, which admits physical events outside their
`defsrc` ledgers. The selected Ivory Key allocation uses
`close-unmapped-input yes`, emitted as `process-unmapped-keys no`, and names
every binding-free pass-through position explicitly. This makes the generated
hardware-input surface reviewable and prevents an unknown key from silently
entering Kanata's pending queue. Revisit this choice if live device evidence
shows a required input outside `defsrc`; do not broaden it implicitly.

## Required abstract contract

For policy-selected owners with their explicit deadlines, the reference model
uses one opaque per-layout dispatch barrier, not a backend event string or a
per-owner foreign slot. It records ordered pending foreign **press intervals**,
each with physical `down`/paired `up`, selected direct route, dispatch frontier,
participating owners, and closed disposition. An interval is withheld once and
routed once; no physical edge is dropped, cloned, transformed, or dispatched
twice.

The profile must keep these output-order requirements distinct from the
existing no-delay policy:

| Observed input prefix | Required externally observable order |
|---|---|
| `down P`; release immediately before `D` | emit the literal tap only. |
| `down P`; reach `D`; `up P` | acquire the held result at the deadline, then release that owner at `up P`. |
| `down P`; `down B`; `up B`; `up P` | withhold `B` on its `down`; when `up B` resolves the hold, first acquire the held result, then redispatch the buffered `B down`, then its buffered `B up`; release `P`'s held contribution only at `up P`. |
| `down P`; `down B`; `up P`; `up B` | withhold `B` on its `down`; `up P` resolves the tap, then the observed order is tap press, redispatched `B down`, tap release, then the later `B up`. |

At the timeout boundary the oracle distinguishes an immediately-before-
deadline tap from the deadline hold.  A future profile must make its equal-time
ordering explicit and test it; it must not obtain a tie breaker from source
form order.  The reference simulator's existing deadline-before-physical rule
is not by itself an implementation of the buffered contract.

The oracle further proves only these shared-lifetime cases:

- two committed owners of the same held modifier retain it until the final
  owner release, in either release order, for case plus all five semantic
  modifier families; and
- two committed `End`/`PgDn` owners keep the function layer effective until
  the final owner releases, in either release order.

An eventual representation must apply first-acquire/final-release accounting
to the settled held effect, not to a pending candidate.  A pending foreign
interval must never acquire a hold speculatively.  A post-commit owner
cancellation must release exactly its contribution.

## Selected implementation boundary

The implementation uses a finite, opaque per-plan dispatch barrier at the
boundary between physical evidence and logical binding dispatch. It is not an
interaction effect and not a general replay queue. Effects begin too late to
withhold a speculative foreign press; making `B` a participant would falsely
claim it; and cloning a physical event would let deadlines, pressed-state
validation, or another timed interaction observe input that never occurred.

Physical `down`/`up` events therefore remain immutable and appear exactly once
in the pattern evidence stream. A routed dispatch notice refers back to the
original physical index and records a separate dispatch-frontier sequence.
Redispatch may start an authorized output-only ordinary binding or sparse
output-only overlay route, but it must not advance time, mutate physical
pressed state, re-feed the simulator, or start a foreign timed interaction.
The foreign interval is in temporary dispatch custody, not in the committed
candidate's participant claims.

The barrier records closed state per ordered interval: armed owners, withheld
`down`, routed `down` awaiting its matching physical `up`, and completion with
disposition and the paired physical positions, indices, and times. Multiple
eligible owners attach to an interval. When one owner reaches its deadline,
Kanata 1.12's checked concurrent queue commits the other attached owners at
that same frontier even when their configured deadlines differ.

A deadline reached in `withheld-down` has a bounded reference path: the timeout
candidates commit/acquire their held results and the simulator routes the
foreign logical down at the deadline dispatch frontier. Its later physical up
and the owner ups retain their observed order without cloning the physical
interval. This follows the pinned Advantage 2 raw trace, which emits `LShift`
at `t:199ms` and the buffered `B` down one millisecond later across the nominal
200 ms owner deadline. A two-owner `f`/`j` prefix with that foreign input has
one exact raw trace. The reference barrier attaches every eligible owner with
the same deadline to one interval, preserves deterministic owner order, and
preserves shared held-effect reference counting. It also proves ordered multiple
and repeated direct intervals, pairing reverse-order physical `up` edges with
their own prior `down` interval. Two pinned unequal-deadline traces prove both
foreign release before the first deadline and custody crossing that deadline;
the reference barrier commits the peers in deterministic deadline order.
Policy-selected owner positions remain outside the foreign domain.

The early-owner-release prefix also exposes a limitation in the former output
model: one atomic `(:named-key ...)` cannot prove the required tap press,
foreign press, tap release ordering. The bounded contract therefore records
typed semantic named-key `press` and `release` transitions with transaction
identity and provenance. Existing non-policy named-key behaviors remain
atomic; source authors do not receive a generic press/release or replay macro.
The old output list may remain a compatibility projection, but the ordered
transitions are normative for this policy.

The reference simulator's redispatch domain remains output-only, but now
includes complete context tables and sparse output-only overlay selection at
the dispatch frontier. The selected Manna whole-layout regression covers
plain/shifted text, a function-patch command, shared modifiers, and distinct
unequal-deadline modifiers. An active overlay route suppresses the otherwise
selected base-layer owner at the same position. Stateful or latch-sensitive
routes, foreign timed-interaction participants, arbitrary sequences, unknown
positions, and unbound positions still refuse. No backend lowering is exact
on account of this simulator boundary; the boundary grows only with separate
semantic and differential evidence.

## Explicit refusal boundary

The barrier is deliberately not a general event queue. It admits only closed
output-only ordinary/context/overlay routes authorized by the same opaque
layout token. It refuses C7/game or unmapped domains, stateful/latch-sensitive routes,
foreign timed interactions, nested/arbitrary replay, and any backend that
cannot preserve the listed order. It also does not prove a 360 state-machine
trace, live keyboard events, XKB/client semantics, or the historic source-era
Kanata scheduler.

The public source language still deliberately has no `buffer` or `replay`
behavior. The representation is a derived normalized compatibility contract,
and the dispatch transaction exists only at the reference simulator's
physical-to-logical routing frontier. Proposed source forms requesting replay
continue to fail closed rather than silently acquiring this policy.

## Consequences and acceptance gates

The selected realization names
`kanata-1-12-buffered` and its concrete interaction instances explicitly.  It must be a
separate policy route from `manna-release-trigger-v1`; no compatibility mode
may inherit from or silently replace the other.  The selected realization
remains unlowerable until each pipeline stage proves the same pending-input
and output-order contract.

This decision is accepted but remains revisitable. The typed policy, positive sixteen-instance
evidence ledger, strict structural gate, and per-plan barrier reference
transaction implement a reviewed subset of the model/reference work below.
They do not by themselves satisfy the whole-layout, cancellation, backend, or
migration-equivalence gates. Acceptance records the compatibility choice; the
following remain mandatory gates before an exact backend grade or migration
completion:

- the typed policy clause is decoded and resolved without creating a default;
- the model gains a closed pending-input/replay representation and rejects all
  shapes outside the bounded contract above;
- the realization policy names its applicable interaction instances and
  rejects unrelated, missing, or partially covered interactions rather than
  applying a Manna-specific rule to every interaction in a composition;
- whole-layout traces prove the four listed prefixes, both shared-release
  orders, candidate cancellation, and no duplication/drop of the foreign
  interval;
- an explicit analysis records what happens when the redispatched input would
  meet a binding, overlay, selector, or interaction; and
- every selected backend either has an exact lowering/differential proof or
  refuses before artifact emission. The selected Manna realization now meets
  this gate; partial and generic realizations still refuse.

Revisit this decision if a source-era Kanata version/trace is recovered, if a
new 1.12 oracle path proves a different queue or ordering rule, or if the
owner selects the modern no-delay policy instead.
