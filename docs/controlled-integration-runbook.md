# Controlled integration runbook

This runbook prepares PLAN Phase 8 without authorizing it.  Nothing in this
document is permission to edit the dotfiles checkout, replace a generated
artifact, restart Kanata, flash firmware, or inject events into a live input
session.  Those operations begin only after an explicit target, device, and
rollback path are approved in a separate integration session.

## Entry gates

Do not begin integration unless all of these are true:

1. `docs/plan-status.md` marks Phases 0 through 7 complete for the selected
   Manna realization.
2. Project compilation succeeds without bypassing a fidelity refusal or
   permitting an unreviewed lossy grade.
3. The frozen migration comparison and both Lisp test systems pass from the
   exact commit being integrated.
4. `ivory-key preflight-build BUILD-DIRECTORY` passes: it verifies the
   generated contract, fixed artifact inventory, digests, and relocatable
   provenance without invoking a validator or touching a service or device.
5. `ivory-key validate-build BUILD-DIRECTORY` accepts the generated XKB and
   Kanata artifacts with the installed target tools.
6. A reviewer has compared `manifest.json`, `allocations.json`,
   `source-map.json`, `REPORT.md`, and both backend artifacts with the frozen
   baseline and accepted every stated difference.
7. The current live configuration, service state, and input-device identity
   have been recorded read-only, and their restoration commands have been
   tested on the selected host.

## Reproducible generation

Use the checked-in environment and a new output directory; never overwrite a
previous build in place:

```sh
direnv exec . ./bin/ivory-key compile \
  --project manna-cadet-project.ivory \
  --composition manna-cadet-linux \
  --output BUILD-DIRECTORY
direnv exec . ./bin/ivory-key preflight-build BUILD-DIRECTORY
direnv exec . ./bin/ivory-key validate-build BUILD-DIRECTORY
```

Record the Ivory Key commit, project composition, Guix manifest commit, build
directory hash inventory, validator versions, and validator output in the
integration record.  A fresh regeneration must be byte-identical before any
installation step.

Before review or staging, inspect `layout.kbd` and require exactly one
`linux-dev` entry. It must equal the approved physical keyboard's stable
`/dev/input/by-id/` name and the selected device declaration; absence, a host
default, a second endpoint, or a path for another keyboard blocks integration.
Require exactly one `linux-output-device-name` as well, distinct from every
unrelated active remapper. Use that identity for target-specific compositor
configuration and virtual-device proof. These are generation gates, not
evidence that the named physical device is currently connected.

`preflight-build` is deliberately narrower than either backend validation or
live proof.  It verifies only the published build directory currently named by
the caller; it neither proves Manna semantics nor grants installation,
activation, restart, dotfile, or input-injection authority.

Treat `BUILD-DIRECTORY` and every file beneath it as untrusted read-only input.
Before invoking preflight, the authorized operator must identify a trusted,
non-hostile parent for that build directory.  Preflight resolves the build root
once, rejects visible child symlinks that resolve outside it, applies bounded
non-evaluating JSON parsing, and brackets reads with content digests.  Portable
Common Lisp does not provide an atomic, descriptor-relative traversal API, so
this is not a guarantee against a hostile writer replacing names during or
after the check.  Regenerate or re-run the gate after any such possibility; do
not use a successful preflight as authorization to install or activate files.

## Installation transaction

The current Advantage360 host baseline and restoration hashes are recorded in
[the 2026-08-14 read-only preflight](integration/2026-08-14-read-only-preflight.md).
That record documents readiness and blockers only; it grants no live-change
authority.

The authorized session must fill in the exact host paths and service names
from the dotfiles repository rather than copying placeholders from this
runbook.  The transaction is:

1. snapshot the current installed XKB/Kanata files and their hashes;
2. stage generated files beside, not over, the installed files;
3. validate the staged paths again;
4. switch the smallest independently reversible reference to the staged
   files;
5. restart or reload only the explicitly authorized service;
6. prove the expected virtual input device exists and the old service did not
   remain concurrently active; and
7. run the live event matrix before making the switch persistent.

Any failed check immediately enters rollback.  Do not repair a failed live
test by hand-editing generated output; change Ivory Key source, regenerate a
new build, and repeat review.

## Live proof matrix

The integration record must contain observed events and resulting client-
visible outputs for:

- every one of the eight case/script/plane contexts on representative keys;
- all five semantic modifiers, including press, chord, release, and no-stuck-
  modifier checks;
- both function-layer activators at tap, hold boundary, interrupted hold, and
  release-order cases;
- Greek and Top selection, their combination, and latch-consumption behavior;
- an ordinary key adjacent to each timed participant to detect ownership or
  replay errors; and
- every accepted difference from the frozen baseline.

Static `xkbcli`/Kanata acceptance is not live proof.  Record the physical input
device, virtual output device, timestamps, raw event sequence, observed output,
expected output, and responsible Ivory Key trace/build-contract entry.

## Rollback

Rollback restores the previously recorded references and files, reloads only
the authorized service, and proves the pre-integration virtual device and a
small known-good key sample.  Preserve the failed generated build and logs for
diagnosis.  Do not delete the prior configuration or its snapshot until a
later session has accepted the live proof and explicitly authorized cleanup.

## Exit record

Phase 8 becomes complete only when the repository links to an integration
record containing the approved target, exact commit and build hashes,
installation transaction, validator output, full live event evidence,
rollback evidence, and final disposition.  A commit, push, green CI run, or
successful service restart alone is not sufficient.
