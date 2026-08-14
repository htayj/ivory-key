# Manna Cadet migration status

## Status: not migrated; no deployment performed

Ivory Key does not yet replace, generate a complete equivalent of, install, or
activate the existing Manna Cadet configuration. No current `.ivory` fixture
is a migration-complete claim. The repository contains a frozen 52-key static
symbol transcription, separate topology/device/profile evidence, a
twenty-level conformance fixture, and a read-only baseline-inventory facility.

This distinction is deliberate: parsing a fixture, constructing a partial
model, emitting a small backend plan, validating syntax with an external tool,
and proving live keyboard behavior are different evidence levels.

## What is checked in now

- `layouts/manna-cadet.ivory` mechanically transcribes the frozen static XKB
  evidence for 52 symbol-producing positions in documented
  case/script/plane order. The static two-level Top group is represented by
  repeating its observed Top value in the Greek+Top cells where that is the
  frozen evidence. It also transcribes the 29 output positions of the common
  primary layered function table as an abstract patch. A realization-owned
  vocabulary and deterministic partial proposal now resolve its 29 evidenced
  XKB/Kanata carriers. It also has four exact direct immediate held
  interactions: `lshift` and `rshift` each hold case, `lctl` holds Greek, and
  `rctl` holds Top. Tap-hold activation, backend-lowering policy, modifier
  policy, and all other timed interactions remain absent rather than guessed.
- `layouts/twenty-level.ivory` demonstrates that the source model is not
  conceptually limited to eight product states. The planner retains all twenty
  states and explicitly refuses the conventional eight-level XKB realization
  unless another target or separately proven emulation is supplied.
- `topologies/kinesis-advantage.ivory` and `topologies/one-key.ivory` record
  logical positions and descriptive geometry. The Kinesis topology includes
  the 52 static positions, two direct physical case holders, immediate Greek
  and Top selectors, and the shared device-variant `mode-key`; it does not
  infer missing geometry from backend names.
- `devices/kinesis-advantage2.ivory` and
  `devices/kinesis-advantage360.ivory` sketch separate physical mappings and
  reserved carrier numbers.
- `realizations/linux-xkb-kanata.ivory` and
  `realizations/manna-cadet-linux.ivory` express intended pipeline policy.

The Manna transcription and twenty-level fixture decode, validate, and
normalize. A confined project loader can resolve relative imports and a named
`realize` composition deterministically, so topology, device, and profile
definitions can now be selected as one project input to inspection,
explanation, or compilation. This is not a complete cross-file realization:
inspection can construct and externally validate the static-table/carrier
proposal, but the public compile gate still refuses unresolved semantic
modifiers, direct-held backend lifecycle policy, `<LSGT>` placement, function
activation, and remaining timed-interaction requirements.

## Existing baseline evidence

`ivory-key inventory ROOT` calls `inventory-manna-cadet` for a supplied Manna
Cadet checkout. It verifies that the expected XKB, Kanata, and mnemonic files
exist; records the checkout's current `HEAD`, SHA-256 values, byte counts,
SBCL/Kanata/xkbcli version probes, and selected XKB/Kanata evidence lines. It
is read-only with respect to the checkout.

The frozen historical baseline is documented in
[manna-cadet-baseline.md](manna-cadet-baseline.md): Manna Cadet at commit
`e5f7e81cdb6e30a7735cdcab622ede29007e379b`, with five primary and two
regression-only chorded source-file hashes and the canonical projected
truth-table digest. Run
`tools/manna-truth-table.lisp verify ROOT` (or the separately invoked
`tests/migration/manna-truth-table.lisp ROOT`) against the read-only checkout
before reviewing the transcription. This proves the static source snapshot;
it does not prove generated or live behavior. `tools/manna-truth-table.lisp
diff ROOT` is the required companion review: it deterministically compares the
two frozen primary devices with the checked-in 52-table static transcription,
29-row function table/carrier vocabulary, and four direct selectors. Its
`Unchecked differences: 0` result means all remaining differences are named
as exact transcription, device variance, or refusal; it is not a migration or
equivalence verdict.  It also fails closed unless all active primary aliases
are classified exactly once (49 for Advantage 2 and 57 for Advantage 360) and
every selected primary layer covers its `defsrc` table (68 and 72 physical
positions respectively).  The evidence audit's Phase 7 ledger separates this
closed inventory proof from the remaining owner policy choices and from
historical evidence that still needs a frozen-runtime capture.
It also inventories the two older chorded files structurally (47 aliases and
29 literal chord rows each) while preserving P-04: neither is an active Manna
profile, and the 360 file's `menu`/`caps` source-token mismatch is not silently
rewritten or treated as runtime evidence.

## Work still required before a migration claim

1. Resolve the remaining classified layered and older chorded variants,
   especially timed activation, game policy, and whether a chorded profile is
   ever selected.
2. Complete the operational transcription for every modifier, interaction,
   timing policy, function activator, and application-visible selector
   decision. The frozen primary 14-row `tap-hold-release` table is now checked
   as source evidence, but still needs an owner-selected, version-pinned
   commitment/interruption/concurrency policy; typed command spellings, frozen
   carriers, and literal static `NoSymbol` cells are already explicit.
3. Simulate the complete abstract layout and compare the results with the
   reviewed truth table.
4. Plan resources and lower the complete selected profile. Refuse unsupported
   or unapproved lossy behavior; validate generated artifacts with the target
   installed tools.
5. Run and review the generated frozen `diff` report. Resolve every explicit
   refusal through policy/evidence and re-run it with no unreviewed change;
   only then consider a separately authorized dotfiles integration and
   disposable-device/live-input validation with a rollback path.

The planned Sway migration document that names Kanata 1.12.0 is supplemental
context only: its `wev` steps are proposed checks, not captured Manna event
traces or a frozen historical runtime oracle.  A separate source-archive-
checked Kanata-1.12 state-machine oracle records bounded current behavior, but
reveals pending foreign-event buffering that differs from the proposed modern
no-replay route.  [ADR 0004](decisions/0004-kanata-1-12-buffered-compatibility.md)
records a separate proposed non-default `kanata-1-12-buffered` contract and
the complete 14+2 source inventory; the alternate selector pair still lacks a
direct oracle trace.  It is intentionally unencoded: the current model cannot
buffer or ordered-replay a foreign press interval, so no `.ivory` realization
or default policy is created.  Neither source selects a Manna compatibility
policy or closes the timing, selector, or modifier equivalence gaps above.

Until all of those steps are complete, Manna Cadet remains the active external
configuration and Ivory Key remains a non-deploying implementation effort.

The full source-to-decision inventory is
[manna-cadet-evidence-audit.md](manna-cadet-evidence-audit.md). It distinguishes
what the primary layered files prove from regression-only chord evidence and
from comment-only hypotheses.
