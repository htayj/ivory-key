# Kanata 1.12 Manna release oracle

This is separately tagged environmental evidence for the current Manna
`tap-hold-release` question. It does not select a policy, change the abstract
layout, authorize lowering, or prove live-device behavior.

## Frozen oracle input

The surrounding dotfiles audit identifies Kanata 1.12.0 as the installed
runtime. The locally retained AUR source package identifies upstream tag
`v1.12.0` and records this source-archive SHA-256:

```text
7081073d1d22fe4e404cf8e7d1dfa3f72562fb2d96538367c07f64877dcbf87a
```

The actual frozen Advantage 2 configuration used by the oracle has SHA-256:

```text
d36a93eab6e2355707f7a6bfbcfac2a4e3b0ea361cc399d388543f51e1f5226b
```

The external harness refuses any other archive or configuration. It copies the
hash-verified configuration into a temporary unpacked Kanata source tree,
applies only the checked-in test patch, and invokes Kanata's own
simulated-output state machine with default features disabled. No keyboard,
uinput device, service, or installed configuration is opened or changed.

Run it with an explicitly selected Cargo toolchain:

```sh
KANATA_CARGO_TOOLCHAIN=nightly \
  tests/external/kanata-1.12-manna-oracle.sh \
  PATH-TO-kanata-1.12.0.tar.gz \
  PATH-TO-FROZEN-MANNA-ROOT
```

Cargo dependencies must already be available or may be fetched according to
the caller's Cargo configuration, so this remains outside the hermetic ASDF
suite and the Guix-only core proof.

## Observed state-machine contract

The checked tests use both small synthetic configurations and the actual
hash-frozen Advantage 2 configuration. They exercise its two equal timer
shapes, 200/200 ms and 250/250 ms, with `concurrent-tap-hold yes`, and assert:

- release immediately before the deadline produces only the tap;
- the deadline produces the hold and releasing the owner releases it;
- a foreign press followed by its release commits the hold;
- releasing the tap-hold owner before the foreign release produces the tap;
- two owners of the same modifier retain the modifier until the final owner
  releases, in either release order, including all five frozen semantic
  modifier pairs; and
- two owners of `layer-while-held` retain the function layer until the final
  owner releases, in either release order.

The hash-frozen Advantage 2 configuration now also records the pending foreign
key across the owner deadline.  In each row `f` is pressed at zero, `b` is
pressed at 50 ms, and the 200 ms `f` deadline is crossed before the first
listed release.  These are raw `simulated_output` strings, not a normalized
model interpretation:

| Label | Input events | Observed output |
|---|---|---|
| foreign-up after deadline, owner last | `d:f t:50 d:b t:151 u:b t:50 u:f t:10` | `t:199ms dn:LShift t:1ms dn:B t:1ms up:B t:50ms up:LShift` |
| owner-up after deadline, foreign last | `d:f t:50 d:b t:151 u:f t:50 u:b t:10` | `t:199ms dn:LShift t:1ms dn:B t:1ms up:LShift t:50ms up:B` |
| foreign input after owner hold | `d:f t:200 d:b t:50 u:b t:50 u:f t:10` | `t:199ms dn:LShift t:1ms dn:B t:50ms up:B t:50ms up:LShift` |
| two owners plus foreign input | `d:f t:10 d:j t:50 d:b t:151 u:b t:50 u:f t:10 u:j t:10` | `t:199ms dn:LShift t:11ms dn:B t:1ms up:B t:60ms up:LShift` |

The last row is only an observed precedence result for this exact configuration
and scheduler.  It does not define an arbitration rule for an abstract
multi-owner buffered transaction.  Likewise, post-hold owner release is an
observable release, not evidence for an unmodeled cancellation operation.

## Advantage 2 native input-domain edge order

The native-domain matrix keeps the same hash-frozen Advantage 2 configuration and uses
`f`/`@Sf` as the pending owner.  It converts Kanata's simulated output to its
ASCII edge spelling and removes only `t:...ms` records.  The remaining strings
below are therefore exact normalized output-edge order: key and carrier
presses/releases are neither projected into abstract bindings nor interpreted
through XKB.

| Native input class | Input events | Normalized Kanata output edges |
|---|---|---|
| owner releases before context-table key | `d:f t:50 d:q t:10 u:f t:10 u:q t:10` | `dn:F dn:Q up:F up:Q` |
| context-table key completes while owner remains down | `d:f t:50 d:q t:50 u:q t:50 u:f t:10` | `dn:LShift dn:Q up:Q up:LShift` |
| another tap-hold owner plus foreign key | `d:f t:10 d:j t:50 d:b t:151 u:b t:50 u:f t:10 u:j t:10` | `dn:LShift dn:B up:B up:LShift` |
| direct Greek-selector carrier | `d:f t:50 d:lctl t:50 u:lctl t:50 u:f t:10` | `dn:LShift out-code:85;Press out-code:85;Release up:LShift` |
| direct held modifier | `d:f t:50 d:rmet t:50 u:rmet t:50 u:f t:10` | `dn:LShift dn:RGui up:RGui up:LShift` |
| active function-layer target | `d:end t:200 d:f t:50 d:q t:50 u:q t:50 u:f t:10 u:end t:10` | `dn:LShift out-code:185;Press out-code:185;Release up:LShift` |
| active function-layer transparent key | `d:end t:200 d:f t:50 d:left t:50 u:left t:50 u:f t:10 u:end t:10` | `dn:LShift dn:Left up:Left up:LShift` |
| repeated foreign intervals | `d:f t:20 d:b t:20 u:b t:20 d:b t:20 u:b t:20 u:f t:10` | `dn:LShift dn:B up:B dn:B up:B up:LShift` |
| two foreign downs, reverse release order | `d:f t:20 d:b t:20 d:c t:20 u:c t:20 u:b t:20 u:f t:10` | `dn:LShift dn:B dn:C up:C up:B up:LShift` |
| Delete selector owner, early tap | `d:del t:50 d:q t:10 u:del t:10 u:q t:10` | `dn:Delete dn:Q up:Delete up:Q` |
| Delete selector owner, foreign-release hold | `d:del t:50 d:q t:50 u:q t:50 u:del t:10` | `out-code:85;Press dn:Q up:Q out-code:85;Release` |
| Enter selector owner, early tap | `d:ent t:50 d:q t:10 u:ent t:10 u:q t:10` | `dn:Enter dn:Q up:Enter up:Q` |
| Enter selector owner, foreign-release hold | `d:ent t:50 d:q t:50 u:q t:50 u:ent t:10` | `out-code:84;Press dn:Q up:Q out-code:84;Release` |

These rows establish that the native pending domain is broader than one direct
ordinary named-key binding.  On this exact runtime/configuration it includes a
selector carrier, a direct modifier, an active function-layer action, a
transparent action, another pending owner, and more than one foreign interval.
The multiple-down row preserves press order and the supplied reverse release
order.  The active-function rows also show that the queued physical key is
routed under the layer state active when Kanata releases it.

This is not an exhaustive proof over all 68 Advantage 2 `defsrc` positions or
over arbitrary queue depth.  In particular, `dn:Q` and `dn:F` are raw Linux
key edges, `out-code:85` and `out-code:185` are literal carrier edges, and this
oracle does not establish which XKB symbols, modifier visibility, or client
events result.  The broader observations therefore create model/lowering test
obligations; they do not authorize a generic replay source construct or make
the current bounded reference transaction a whole-device implementation.

## Frozen native-route source partition

A separate hash-gated, non-runtime ledger now closes the source inventory that
the representative oracle deliberately does not. Run:

```sh
sbcl --script tools/manna-truth-table.lisp routes \
  PATH-TO-FROZEN-MANNA-ROOT
```

The canonical render has SHA-256
`24079ae79cb1792b2f866a50dc829cbcccee6d58f4114dc3b4b31bb71a6aeb0a`.
It preserves all ordered A2 68 and A360 72 `defsrc` rows and pairs each with
its exact `normal` and `fun` action. The normal partition is C1 context/direct
identity (39/39), C2 physical modifier (3/3), C3 residual named key (7/7), C4
renamed 360 local key (0/4), C5 source-selected tap-hold owner (16/16), C6
direct carrier selector (2/2), and C7 stateful/control-plane (1/1). The
function partition is F1 carrier output (29/29) and F2 transparent-to-normal
(39/43).

C5 includes `@gdel` and `@rtop` because the frozen normal layers select them;
the direct rows above now establish their early-tap and foreign-release hold
edge order on the hash-pinned Advantage 2 configuration.
C7 is explicitly unresolved/refused. The complete 72-row Advantage 360
`game` layer is arity-checked and explicitly unresolved/refused rather than
folded into the normal/function classes.

This is source coverage, not runtime queue closure. Both frozen configs say
`process-unmapped-keys yes`, so a physical input outside `defsrc` may still be
processed by Kanata but is outside the canonical ledger and remains refused.
Nor does one class representative prove every member's routing, overlay,
state, XKB, client, or live-device behavior.

## Carrier lifetime boundary

The same pinned oracle has a ten-row carrier-lifetime matrix for direct
`lctl → out-code:85` and `rctl → out-code:84`.  Every row has an identical
trailing 10 ms settling interval after carrier-up, so a release cannot be
mistaken for an unflushed terminal event.  The exact normalized edges are
asserted by `ivory_key_actual_advantage2_carrier_lifetime_matrix`.

## Opt-in AD01 Kanata-to-generated-XKB differential

One separately invoked differential joins two already narrow boundaries. The
hash-gated Kanata oracle emits exactly eight tagged, asserted edge records for
the base, code-85, code-84, and code-85-plus-84 contexts. Each context has an
owner-first plain row and a foreign-first shifted row, and every row has the
same trailing 10 ms settling interval. The Common Lisp driver accepts only
that closed label set and the `F`, `LShift`, `Q`, code-84, and code-85 edge
vocabulary before passing a temporary record file to the libxkbcommon probe.

Run the opt-in composition in the declared environment with the exact archive:

```sh
KANATA_CARGO_TOOLCHAIN=nightly direnv exec . \
  sbcl --script tests/external/manna-xkb-group2-state.lisp \
  --kanata-ad01-differential PATH-TO-kanata-1.12.0.tar.gz \
  PATH-TO-FROZEN-MANNA-ROOT
```

At the single `Q` down, the C probe checks the generated AD01 symbol, effective
and depressed group, and exact effective and consumed modifier masks, including
the Group1 alphabetic type's Shift/Lock/LevelThree consumption and Group2's
Shift-only consumption. It then
requires one complete Q interval and zero remaining parsed-key, modifier, or
group state. This proves only those eight Kanata-output-to-generated-XKB
records. It does not select an interaction policy or profile, authorize Kanata
emission, cover arbitrary input routes, or prove client/live-device behavior.

The oracle also establishes an important incompatibility with the currently
proposed [ADR 0003](decisions/0003-manna-release-trigger-v1.md): Kanata 1.12.0
does not leave a foreign key temporally untouched while a tap-hold is pending.
In the early-owner-release case, the foreign `B` press is emitted only after
the owner resolves as a tap. In the foreign-release hold case, the buffered
`B` press/release pair is emitted after the hold commits. The exact expected
event strings in `kanata-1.12-manna-oracle.patch` make that ordering a checked
fact rather than prose inference.

## Decision boundary

This evidence narrows, but does not eliminate, the owner decision:

1. A modern `manna-release-trigger-v1` profile may retain ADR 0003's explicit
   no-delay/no-replay rule. It is then intentionally different from Kanata
   1.12.0 and cannot use the generic Kanata tap-hold action as an exact
   lowering.
2. A Kanata-1.12 compatibility profile must model the pending foreign-event
   buffer and its ordered release. Ivory Key now has a bounded single-owner
   reference transaction, derived normalized contracts, and an inert typed
   compiler handoff. The frozen native-route partition is now structurally
   closed, but per-class queue/redispatch evidence, the process-unmapped input
   boundary, cancellation, multi-owner arbitration, and backend differential
   proof remain mandatory before selection or emission.

Until one route is selected and implemented, the active Manna realization
continues to refuse all sixteen source-selected tap-holds before artifact
publication.
