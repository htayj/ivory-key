# Manna Cadet migration status

## Status: generated migration complete; no deployment performed

Ivory Key now generates the reviewed A2 and Advantage360 XKB/Kanata replacement
artifacts, but it has not installed or activated them. Phase 7 is complete at
the source, allocation, emission, validation, and differential-proof boundary;
Phase 8 live integration remains a separate authorized operation.

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
  vocabulary and deterministic exact plan resolve its 29 evidenced
  XKB/Kanata carriers. It also has four exact direct immediate held
  interactions: `lshift` and `rshift` each hold case, `lctl` holds Greek, and
  `rctl` holds Top. The selected Linux realization chooses the versioned
  Kanata-1.12 buffered policy for all sixteen source tap-holds and records
  closed modifier/layer/carrier allocations. Normal compilation emits the
  selected artifacts only after the closed native-domain and typed-allocation
  gates pass.
- `layouts/twenty-level.ivory` demonstrates that the source model is not
  conceptually limited to eight product states. The planner retains all twenty
  states and explicitly refuses the conventional eight-level XKB realization
  unless another target or separately proven emulation is supplied.
- `topologies/kinesis-advantage.ivory` and `topologies/one-key.ivory` record
  logical positions and descriptive geometry. The Kinesis topology is the
  complete 73-position A2/A360 union, with explicit physical/unreachable
  coverage in each device; it does not infer missing geometry from backend
  names.
- `devices/kinesis-advantage2.ivory` and
  `devices/kinesis-advantage360.ivory` sketch separate physical mappings and
  reserved carrier numbers. Each also records the distinct stable Kanata
  `/dev/input/by-id/` endpoint found in its frozen primary configuration, so a
  generated artifact cannot fall back to ambient keyboard discovery. A
  distinct generated virtual-output name permits target-specific compositor
  proof without selecting another active Kanata service.
- `realizations/linux-xkb-kanata.ivory` and
  `realizations/manna-cadet-linux.ivory` express intended pipeline policy.

The Manna transcription and twenty-level fixture decode, validate, and
normalize. A confined project loader resolves each named composition
deterministically. The selected Manna profile closes semantic modifiers,
direct-held lifecycles, the typed-unreachable `<LSGT>` disposition, function
activation, and all sixteen timed interactions without embedding backend text
in the abstract layout. Public compilation produces two exact artifacts and a
contract containing 29 source-backed carrier allocations. Each Kanata artifact
contains exactly its selected device endpoint and virtual-output identity;
connecting and exercising that physical device remains Phase 8 evidence.

## Existing baseline evidence

`ivory-key inventory ROOT` calls `inventory-manna-cadet` for a supplied Manna
Cadet checkout. It verifies that the expected XKB, Kanata, and mnemonic files
exist; records the checkout's current `HEAD`, SHA-256 values, byte counts,
SBCL/Kanata/xkbcli version probes, and selected XKB/Kanata evidence lines. It
is read-only with respect to the checkout.

The frozen historical baseline is documented in
[manna-cadet-baseline.md](manna-cadet-baseline.md): Manna Cadet at commit
`c92a9fd98adfb334c31ec5be15d444230e879a32`, with five primary and two
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

## Work still required before live replacement

1. In a separately authorized session, regenerate and preflight a fresh build
   under the declared Guix environment.
2. Integrate it through the documented reversible transaction, preserving the
   existing configuration and rollback path.
3. Prove the live virtual/device event path and record the result. Repository
   generation and installed-tool validation are not deployment proof.

The planned Sway migration document that names Kanata 1.12.0 is supplemental
context only: its `wev` steps are proposed checks, not captured Manna event
traces or a frozen historical runtime oracle.  A separate source-archive-
checked Kanata-1.12 state-machine oracle records bounded current behavior, but
reveals pending foreign-event buffering that differs from the proposed modern
no-replay route.  [ADR 0004](decisions/0004-kanata-1-12-buffered-compatibility.md)
records a separate proposed non-default `kanata-1-12-buffered` contract and
the complete 14+2 source inventory. Its positive evidence ledger admits the
fourteen primary tap-holds and refuses the alternate selector pair, which
lacks a direct oracle trace. A strict derived normalized contract and bounded
direct-named-key reference transaction encode only the proven prefix subset,
without exposing generic replay syntax. No `.ivory` realization or default policy is created,
and no exact Kanata lowering exists. Neither source selects a Manna
compatibility policy or closes the selector, modifier, or deployment gaps
above.

Until all of those steps are complete, Manna Cadet remains the active external
configuration and Ivory Key remains a non-deploying implementation effort.

The full source-to-decision inventory is
[manna-cadet-evidence-audit.md](manna-cadet-evidence-audit.md). It distinguishes
what the primary layered files prove from regression-only chord evidence and
from comment-only hypotheses.
