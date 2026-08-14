# Manna Cadet migration status

## Status: not migrated; no deployment performed

Ivory Key does not yet replace, generate a complete equivalent of, install, or
activate the existing Manna Cadet configuration. No current `.ivory` fixture
is a migration-complete claim. The repository contains a small semantic
fixture, topology/device/profile sketches, a twenty-level conformance fixture,
and a read-only baseline-inventory facility.

This distinction is deliberate: parsing a fixture, constructing a partial
model, emitting a small backend plan, validating syntax with an external tool,
and proving live keyboard behavior are different evidence levels.

## What is checked in now

- `layouts/manna-cadet.ivory` records a limited central design: product axes
  for case/script/plane, a behavioral `shift-latch` axis, five semantic
  modifiers, selected `q`/`t` tables, and a `stop-output` interaction.
- `layouts/twenty-level.ivory` demonstrates that the source model is not
  conceptually limited to eight product states. The current XKB bootstrap
  lowering cannot realize a twenty-output entry exactly.
- `topologies/kinesis-advantage.ivory` and `topologies/one-key.ivory` record
  logical positions and descriptive geometry.
- `devices/kinesis-advantage2.ivory` and
  `devices/kinesis-advantage360.ivory` sketch separate physical mappings and
  reserved carrier numbers.
- `realizations/linux-xkb-kanata.ivory` and
  `realizations/manna-cadet-linux.ivory` express intended pipeline policy.

The Manna fragment and twenty-level fixture now decode, validate, and
normalize. The fragment yields three normalized bindings and two interactions;
the conformance fixture yields twenty entries. Topology, device, and profile
files can be supplied explicitly to compiler commands. Imports, `realize`
composition, a complete historical transcription, and the lowerings needed for
Manna's context selection/modifiers/interactions remain unfinished, so this is
still not a complete cross-file realization.

## Existing baseline evidence

`ivory-key inventory ROOT` calls `inventory-manna-cadet` for a supplied Manna
Cadet checkout. It verifies that the expected XKB, Kanata, and mnemonic files
exist; records the checkout's current `HEAD`, SHA-256 values, byte counts,
SBCL/Kanata/xkbcli version probes, and selected XKB/Kanata evidence lines. It
is read-only with respect to the checkout.

The intended historical baseline is documented in [PLAN.md](../PLAN.md):
Manna Cadet at commit `e5f7e81cdb6e30a7735cdcab622ede29007e379b` in the
dotfiles checkout. That identifier is planning evidence, not a fresh inventory
performed by this repository checkout. Re-run `inventory` against the actual
target before any migration review, and retain the resulting hashes and tool
versions with the review.

## Work still required before a migration claim

1. Implement named imports/`realize` composition and surface overlays, then
   resolve the complete layout/device/profile graph as one compilation unit.
2. Freeze a fresh, hash-addressed source baseline and construct a reviewable
   position/context/behavior truth table for the layered variants; explicitly
   classify older chorded variants.
3. Complete the semantic transcription, including every symbol, command,
   modifier, interaction, timing policy, overlay, carrier, and intentional
   `NoSymbol`/inheritance decision.
4. Simulate the complete abstract layout and compare the results with the
   reviewed truth table.
5. Plan resources and lower the complete selected profile. Refuse unsupported
   or unapproved lossy behavior; validate generated artifacts with the target
   installed tools.
6. Review every difference from the frozen baseline. Only then consider a
   separately authorized dotfiles integration and disposable-device/live-input
   validation with a rollback path.

Until all of those steps are complete, Manna Cadet remains the active external
configuration and Ivory Key remains a non-deploying implementation effort.
