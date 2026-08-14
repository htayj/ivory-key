# 0004: Proposed Kanata 1.12 buffered compatibility contract

- Status: Proposed
- Date: 2026-08-14

## Context and status

The hash-pinned [Kanata 1.12 oracle](../kanata-1.12-oracle.md) establishes a
runtime-family contract that differs materially from the proposed modern
[`manna-release-trigger-v1`](0003-manna-release-trigger-v1.md) policy.  A
pending `tap-hold-release` owner delays a foreign press and later releases it
in an observable order.  The frozen Manna Cadet source commit does not itself
pin Kanata 1.12, so this is **not** a source-era equivalence claim.

This records one future, non-default policy identity:

```lisp
(interaction-compatibility kanata-1-12-buffered
  (instances tap-hold-case-f tap-hold-case-j))
```

The spelling is a closed project/realization-policy reference; it is not an
interaction clause, backend action, or embedded Kanata form.  It is absent
from every current realization.  An absent compatibility policy remains
unselected, and this decision does not add a default.  The required nonempty
`instances` set prevents this Manna-specific policy from silently governing an
unrelated interaction in the same composition.  Unlisted interactions retain
their ordinary generic refusal.

No `.ivory` profile is checked in for this policy yet. The model now derives a
typed, backend-neutral contract only from the exact normalized three-candidate
shape, and the reference simulator can execute its bounded finite dispatch
transaction when a caller explicitly supplies the policy. This is reference
semantics, not a source construct or a positive backend realization. Creating
a Manna realization declaration now would still falsely imply that Kanata
lowering and full migration equivalence are proven.

## Provenance and frozen alias inventory

The oracle harness refuses an archive other than Kanata `v1.12.0` with source
archive SHA-256
`7081073d1d22fe4e404cf8e7d1dfa3f72562fb2d96538367c07f64877dcbf87a`, and it
uses the frozen Advantage 2 primary configuration SHA-256
`d36a93eab6e2355707f7a6bfbcfac2a4e3b0ea361cc399d388543f51e1f5226b`.
It has no keyboard, uinput, service, or deployment boundary.  Its exact
checked event strings live in
[`tests/external/kanata-1.12-manna-oracle.patch`](../../tests/external/kanata-1.12-manna-oracle.patch).

Both primary frozen `normal` layers select these fourteen aliases.  The two
alternate selector aliases are declared in the same primary sources.  This is
the complete candidate inventory for this proposed policy; it does not add
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
modifier pairs, and `end`/`pgdn`; its small synthetic configurations cover the
two equal timeout shapes.  It does not separately exercise a buffered foreign
interval for every source row, and it has no direct `gdel`/`rtop` trace.  The
14+2 list is therefore a complete frozen source inventory, not permission to
instantiate every row under this policy.

## Required abstract contract

For an owner position `P` admitted by a later evidence review, one foreign
position `B`, and equal deadline `D`, the future model must represent a typed
pending foreign **press interval**, not a backend event string.  The pending
record needs the captured physical position, its `down` event index and time,
its later `up` (if received while pending), and a closed disposition.  `P`
owns its tap-hold interpretation; `B` is temporarily withheld from ordinary
dispatch while pending.  Neither event may be dropped, duplicated,
transformed, or accidentally dispatched twice.

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

The first implementation uses a finite dispatch transaction at the boundary
between physical evidence and logical binding dispatch. It is not an
interaction effect and not a general replay queue. Effects begin too late to
withhold a speculative foreign press; making `B` a participant would falsely
claim it; and cloning a physical event would let deadlines, pressed-state
validation, or another timed interaction observe input that never occurred.

Physical `down`/`up` events therefore remain immutable and appear exactly once
in the pattern evidence stream. A routed dispatch notice refers back to the
original physical index and records a separate dispatch-frontier sequence.
Redispatch may start exactly one eligible direct ordinary named-key binding,
but it must not advance time, mutate physical pressed state, re-feed the
simulator, or start an overlay or timed interaction. The foreign interval is
in temporary dispatch custody, not in the committed candidate's participant
claims.

The finite transaction has these closed states:

- `armed`: the selected owner interaction is pending and no foreign input is
  withheld;
- `withheld-down`: the first eligible foreign `down` is recorded and ordinary
  dispatch is suppressed; and
- `down-redispatched-awaiting-up`: an early owner release has redispatched the
  foreign `down`, but the corresponding physical `up` has not arrived; and
- `complete`: the transaction records its disposition and, when custody was
  acquired, the original foreign `down` and terminal `up` positions, indices,
  and times.

A deadline reached in `withheld-down` is deliberately refused. The oracle does
not establish whether Kanata flushes, holds, cancels, or reclassifies that
prefix, so choosing one would invent compatibility semantics. Likewise, every
policy-selected owner position is excluded from the eligible foreign domain.
This permits the separately proven multiple-owner modifier/function lifetime
while preventing one selected owner from accidentally becoming another
owner's single buffered `B`. If one ordinary foreign `down` would be eligible
for more than one armed transaction, the simulator refuses rather than using
layout, interaction, or host iteration order.

The early-owner-release prefix also exposes a limitation in the former output
model: one atomic `(:named-key ...)` cannot prove the required tap press,
foreign press, tap release ordering. The bounded contract therefore records
typed semantic named-key `press` and `release` transitions with transaction
identity and provenance. Existing non-policy named-key behaviors remain
atomic; source authors do not receive a generic press/release or replay macro.
The old output list may remain a compatibility projection, but the ordered
transitions are normative for this policy.

The initial redispatch domain is intentionally small: one direct,
context-free ordinary binding whose result is a single named key. Text,
symbols, no-output, overlays, timed-interaction participants, selector or state
changes, modifier operations, commands, arbitrary sequences, unknown
positions, and unbound positions refuse. This is the only route exercised by
the pinned Kanata differential. The boundary can grow only with separate
semantic and differential evidence.

## Explicit refusal boundary

The oracle does not authorize a general event queue.  Until separately proven,
the profile must refuse `gdel` and `rtop`, multiple foreign positions, repeated
foreign presses, foreign timed interactions, state-changing or latch-sensitive
overlays, nested buffering, a new owner while a foreign interval is pending,
replay into another timed interaction, source forms that request arbitrary
replay, and any backend that cannot preserve the listed order.  It also does
not prove a 360 state-machine trace, live keyboard events, XKB/client semantics,
or the historic source-era Kanata scheduler.

The public source language still deliberately has no `buffer` or `replay`
behavior. The representation is a derived normalized compatibility contract,
and the dispatch transaction exists only at the reference simulator's
physical-to-logical routing frontier. Proposed source forms requesting replay
continue to fail closed rather than silently acquiring this policy.

## Consequences and acceptance gates

If selected later, a realization must name
`kanata-1-12-buffered` and its concrete interaction instances explicitly.  It must be a
separate policy route from `manna-release-trigger-v1`; no compatibility mode
may inherit from or silently replace the other.  The selected realization
remains unlowerable until each pipeline stage proves the same pending-input
and output-order contract.

This decision remains Proposed. The typed policy, positive fourteen-instance
evidence ledger, strict structural gate, and bounded named-key reference
transaction implement a reviewed subset of the model/reference work below.
They do not by themselves satisfy the whole-layout, cancellation, backend, or
selected-profile gates. It becomes Accepted only when all of the following are
true:

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
  refuses before artifact emission.

Revisit this decision if a source-era Kanata version/trace is recovered, if a
new 1.12 oracle path proves a different queue or ordering rule, or if the
owner selects the modern no-delay policy instead.
