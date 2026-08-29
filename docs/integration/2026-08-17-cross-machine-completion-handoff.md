# Cross-machine completion handoff — 2026-08-17

This document is the implementation and operations handoff for finishing the
original [Ivory Key plan](../../PLAN.md) from another machine. It records what
is complete, what is only staged in the present checkout, what must be
revalidated elsewhere, and what still requires an explicitly authorized live
session on host `basedserv`.

The original plan is **not complete**. Phases 0 through 7 and the bounded
Phase 9 slice are implemented and evidenced. Phase 8 remains prepared but has
not been authorized or started. Publication of the final staged source is also
blocked because the configured signing key is not cached. Do not change either
statement merely because the source compiles, a generated artifact validates,
or a service restarts.

## Non-negotiable scope and authority

The next agent may perform read-only inspection, reproduce the development
environment, run tests and validators, regenerate into fresh temporary
directories, review the staged source, prepare a signed commit, push after the
usual final checks, and observe CI.

The next agent must **not**, without a new explicit user authorization naming
the target and rollback scope:

- copy generated files into the dotfiles checkout or a live configuration;
- replace either live symlink;
- restart or reload Kanata or Sway;
- change a compositor keymap;
- inject, capture, or interpret live keyboard events as an authorized test;
- touch `kanata@footswitches.service`; or
- delete the old configuration, a rollback snapshot, a failed candidate, or
  validation logs.

The live transaction is intentionally separate from source completion. If any
live gate fails, enter rollback immediately. Do not repair generated XKB or
Kanata text by hand; repair Ivory Key source, regenerate, and repeat review.

## Exact repository state at handoff

At the start of this handoff:

- repository: `git@github.com:htayj/ivory-key.git`;
- branch: `master`;
- `HEAD`, `origin/master`, and `origin/HEAD`:
  `70cd99c8bfa5fea4c20a969e9f23ec16ea57a5cf`;
- commit subject: `feat: complete generated Manna migration`;
- upstream divergence: zero ahead, zero behind;
- unstaged diff: empty;
- staged implementation snapshot: 26 paths, 791 insertions and 53 deletions;
- implementation-only index tree, before adding this handoff document:
  `00eb10e5124b02422a7d357ed64b43d2d2badb31`;
- SHA-256 of `git diff --cached --binary` for that implementation-only
  snapshot: `6a01d77801281a1c7e9d473228b19e90c156d8cd138fc22d55c204e53d7064cd`;
- `git diff --cached --check`: clean; and
- configured signed-commit policy: `commit.gpgsign=true`, key
  `3EA36B492D7E76450D2C59267B55A97A62F6D6C0`.

All implementation changes are in the index, not in the remote commit. The
remote repository alone is therefore insufficient to continue this work.
This is the first and most important cross-machine recovery constraint.

The staged implementation paths are:

```text
.envrc
README.md
channels.scm
devices/kinesis-advantage2.ivory
devices/kinesis-advantage360.ivory
docs/backend-contract.md
docs/controlled-integration-runbook.md
docs/development.md
docs/integration/2026-08-14-read-only-preflight.md
docs/kanata-1.12-oracle.md
docs/language.md
docs/manna-cadet-evidence-audit.md
docs/migration-manna-cadet.md
docs/plan-status.md
guix/ivory-key/packages.scm
manifest.scm
src/backend/kanata-actions.lisp
src/backend/kanata.lisp
src/compiler.lisp
src/model/topology.lisp
src/packages.lisp
src/project.lisp
tests/backend/backend.lisp
tests/compiler.lisp
tests/external/manna-kanata-generated.lisp
tests/project.lisp
```

The staged slice adds the final pre-integration device boundary:

- a channel-pinned Guix environment and local Kanata 1.12 package;
- typed, validated physical input endpoints and virtual output names;
- an exact single `linux-dev` and `linux-output-device-name` in each generated
  artifact;
- `process-unmapped-keys no` for the selected closed device domain;
- Advantage2 endpoint
  `/dev/input/by-id/usb-Kinesis_Advantage2_Keyboard_314159265359-if01-event-kbd`
  and output `ivory-key-manna-advantage2`;
- Advantage360 endpoint
  `/dev/input/by-id/usb-Kinesis_Kinesis_Adv360_360555127546-if01-event-kbd`
  and output `ivory-key-manna-advantage360`; and
- parser, model, compiler, backend, generated-artifact, and project tests for
  missing, malformed, duplicated, unsafe, or conflicting endpoints and names.

## Recovering the staged work on another machine

Prefer one of these methods, in order:

1. Unlock the configured signing key on this machine, create the reviewed
   signed commit, push it, and clone/fetch that commit on the other machine.
2. Copy this complete repository, including `.git` and its index, through a
   trusted channel. After copying, verify `HEAD`, `git status --short`, the
   staged path list, and the implementation snapshot above before doing work.
3. Export the exact staged implementation as a binary patch on this machine,
   transfer the patch and this document through a trusted channel, and apply it
   to an exact checkout of `70cd99c`:

   ```sh
   git diff --cached --binary > ivory-key-endpoint-hardening.patch
   sha256sum ivory-key-endpoint-hardening.patch

   git clone git@github.com:htayj/ivory-key.git
   cd ivory-key
   git checkout 70cd99c8bfa5fea4c20a969e9f23ec16ea57a5cf
   git apply --index --3way ../ivory-key-endpoint-hardening.patch
   git diff --cached --check
   git status --short
   ```

Do not assume that a fresh clone contains the staged work. Do not reconstruct
the 791-line implementation slice from prose. Record the patch's SHA-256 at
the moment of export and compare that sidecar value after transfer. If that
transfer digest or its path list differs, stop and review the difference
rather than silently accepting it. The historical tree and patch digest above
intentionally describe the 26-path implementation snapshot before this
handoff document and its `docs/plan-status.md` link were added; a full patch
exported afterward will correctly have a different digest and 27 staged
paths.

## Machine prerequisites

The portable build machine needs:

- Git and access to the GitHub remote;
- GNU Guix with `guix time-machine`, or direnv capable of evaluating the
  checked-in `.envrc`;
- enough space and time to build the pinned Kanata/Rust dependency closure;
- GnuPG and the authorized signing identity for publication;
- `gitleaks` for the exact staged/commit secret scan;
- a Manna Cadet checkout at `c92a9fd98adfb334c31ec5be15d444230e879a32`, matching the hashes enforced by the migration
  and oracle tools; and
- the hash-pinned Kanata 1.12.0 source archive for the external runtime oracle.

Do not substitute host Common Lisp or host Kanata results for the checked-in
Guix evidence. Host tools may be useful diagnostics, but final claims use the
channel-pinned environment.

The Guix files intentionally select:

- Guix commit `637a34743d87b25d39f4a6c685b52b49b703e59a`;
- Kanata 1.12.0;
- the local package source hash
  `01jsdwp1yxg5kc40wdnx2awizs98b9ncky546v88v8hc0676cdss`; and
- Rust and Cargo 1.88 for the pinned runtime oracle.

The Kanata package runs 34 applicable upstream tests. Three upstream tests
that open real `/dev/uinput` are deliberately excluded from the package build,
and rustdoc-only doctests are outside the selected package tool output. Record
those limits; do not describe the package build as live-device proof.

## Portable completion sequence

### 1. Establish a clean, exact candidate

From the recovered checkout:

```sh
git status --short
git log -1 --oneline --decorate
git remote -v
git branch -vv
git diff --cached --check
git diff --quiet
```

Expected before adding any new work: base `70cd99c`, the staged implementation
paths listed above, no unstaged changes, and a clean whitespace check. Review
every staged hunk. In particular, verify that no source-language file embeds
raw XKB or Kanata text, that endpoint values remain typed realization data,
and that no ambient/default input device is admitted.

### 2. Enter and identify the pinned environment

Approve direnv only after reviewing `.envrc`, `channels.scm`,
`manifest.scm`, and `guix/ivory-key/packages.scm`:

```sh
direnv allow
direnv exec . kanata --version
direnv exec . sbcl --version
direnv exec . ecl --version
direnv exec . rustc --version
direnv exec . cargo --version
```

The equivalent non-direnv entry is:

```sh
guix time-machine -C channels.scm -- shell -L guix -m manifest.scm
```

Also build and lint the local Kanata package rather than trusting a stale
store item:

```sh
guix time-machine -C channels.scm -- build -L guix \
  -e '(@ (ivory-key packages) kanata-1.12)'
guix time-machine -C channels.scm -- lint -L guix --no-network \
  -e '(@ (ivory-key packages) kanata-1.12)'
```

### 3. Run the hermetic and source-format gates

Run the entire suite under both implementations, serially if the Guix output
cache is sensitive to concurrent compiles:

```sh
direnv exec . sbcl --non-interactive \
  --eval '(require :asdf)' \
  --eval '(asdf:load-asd (truename "ivory-key.asd"))' \
  --eval '(asdf:test-system "ivory-key/tests")'

direnv exec . ecl -norc \
  -eval '(require :asdf)' \
  -eval '(asdf:load-asd (truename "ivory-key.asd"))' \
  -eval '(asdf:test-system "ivory-key/tests")' \
  -eval '(ext:quit 0)'

find . -type f -name '*.ivory' -print0 | sort -z | \
  xargs -0 direnv exec . ./bin/ivory-key fmt --check
git diff --check
git diff --cached --check
```

The last recorded full result was 290 passing tests on both SBCL and ECL. That
is historical evidence only: the next agent must record fresh output from the
exact candidate it intends to publish.

### 4. Run frozen-source and installed-tool evidence

Set machine-local, read-only evidence paths:

```sh
MANNA_ROOT=/path/to/hash-frozen/manna-cadet
KANATA_ARCHIVE=/path/to/kanata-1.12.0.tar.gz
```

Then run:

```sh
direnv exec . sbcl --script tests/migration/manna-truth-table.lisp \
  "$MANNA_ROOT"

direnv exec . sbcl --script tests/external/xkb-kanata.lisp
direnv exec . ecl -norc -shell tests/external/xkb-kanata.lisp

direnv exec . sbcl --script tests/external/manna-xkb-group2-state.lisp \
  "$MANNA_ROOT"
direnv exec . ecl -norc -shell \
  tests/external/manna-xkb-group2-state.lisp "$MANNA_ROOT"

direnv exec . tests/external/kanata-1.12-manna-oracle.sh \
  "$KANATA_ARCHIVE" "$MANNA_ROOT"

direnv exec . sbcl --script tests/external/manna-kanata-generated.lisp
direnv exec . ecl -norc -shell tests/external/manna-kanata-generated.lisp

direnv exec . sbcl --script tests/external/manna-kanata-generated.lisp \
  --runtime-oracle "$KANATA_ARCHIVE" "$MANNA_ROOT"

direnv exec . sbcl --script tests/external/manna-xkb-group2-state.lisp \
  --kanata-ad01-differential "$KANATA_ARCHIVE" "$MANNA_ROOT"
```

These commands prove distinct things. Preserve their tags and raw logs rather
than collapsing them into “tests passed”:

- the migration report closes the frozen 52-key/eight-context table and the
  68/72 native-route ledgers;
- `xkb-kanata.lisp` proves installed parser/tool and focused libxkbcommon
  acceptance;
- the Group-2 probe proves the generated selector and modifier state;
- the hash-pinned oracle proves the selected Kanata 1.12 scheduling subset;
- the generated-artifact probe checks both A2 and A360 Kanata artifacts; and
- the AD01 differential checks the bounded Kanata-to-generated-XKB edge/state
  path.

The recorded QMK evidence is intentionally separate and bounded to the
one-layer slice in `docs/qmk-validation.md`. Confirm that its generated hash,
official job identity, and stated exclusions remain internally consistent.
Do not claim hardware flashing or multi-layer support.

### 5. Regenerate and review the two Manna builds

Use a newly created trusted parent, never an existing build directory and
never a directory writable by an untrusted concurrent process:

```sh
STAGING_PARENT=/trusted/path/ivory-key-integration-candidates
mkdir -p "$STAGING_PARENT"

direnv exec . ./bin/ivory-key compile --validate-before-publish \
  --project manna-cadet-project.ivory \
  --composition manna-cadet-linux \
  --output "$STAGING_PARENT/a2-first"
direnv exec . ./bin/ivory-key compile --validate-before-publish \
  --project manna-cadet-project.ivory \
  --composition manna-cadet-linux \
  --output "$STAGING_PARENT/a2-second"

direnv exec . ./bin/ivory-key compile --validate-before-publish \
  --project manna-cadet-project.ivory \
  --composition manna-cadet-advantage360-linux \
  --output "$STAGING_PARENT/a360-first"
direnv exec . ./bin/ivory-key compile --validate-before-publish \
  --project manna-cadet-project.ivory \
  --composition manna-cadet-advantage360-linux \
  --output "$STAGING_PARENT/a360-second"
```

For each build run `preflight-build` and `validate-build`, compare the two
generations byte-for-byte, and save a sorted SHA-256 inventory:

```sh
for build in "$STAGING_PARENT"/*; do
  direnv exec . ./bin/ivory-key preflight-build "$build"
  direnv exec . ./bin/ivory-key validate-build "$build"
  find "$build" -type f -print0 | sort -z | xargs -0 sha256sum
done

diff -ru "$STAGING_PARENT/a2-first" "$STAGING_PARENT/a2-second"
diff -ru "$STAGING_PARENT/a360-first" "$STAGING_PARENT/a360-second"
```

Review all six files in each exact build:

- `manifest.json`;
- `allocations.json`;
- `source-map.json`;
- `REPORT.md`;
- `keymap.xkb`; and
- `layout.kbd`.

Require schema 5, 29 concrete provenance-bearing allocations, no physical
checkout paths, exact source identities, no unreviewed fidelity grade, and one
closed input endpoint/output identity per selected device. Compare every
difference against the frozen evidence and retain the review record.

The 2026-08-14 candidate hashes were:

| Composition | `keymap.xkb` SHA-256 | `layout.kbd` SHA-256 |
| --- | --- | --- |
| `manna-cadet-linux` | `938188b67fc4d09273fd345d856526ecefe633cb09469eab94267efd748033d0` | `7bf48c77223bff2dcd74aa6fb6779cd21cec31565981ac55b51d20fb3bad692e` |
| `manna-cadet-advantage360-linux` | `09a5e399d5fa9b81e825ec182a2c3f1dcc5452dd819a998c87929adf13b1924d` | `9e744b8e5da6606cdf082e8fc1da1b50c4470017c4589df91c1487a27af4b6d5` |

Fresh matching hashes are useful reproducibility evidence. A mismatch is not
automatically a failure, but it must be explained and reviewed before any
publication or integration.

### 6. Secret scan, signed commit, push, and CI

Before committing:

```sh
git diff --cached --check
gitleaks protect --staged --redact
git status --short
git diff --cached --stat
git diff --cached
gpg-connect-agent 'keyinfo --list' /bye
```

The configured key was not cached at handoff. A previous signed-commit attempt
waited in `pinentry-curses` and was interrupted without changing the index.
Arrange an interactive, authorized GPG unlock on the machine that will sign.
Do not disable `commit.gpgsign`, remove `-S`, switch identity, or publish an
unsigned commit merely to bypass that gate.

After all exact-candidate logs are saved, create a signed commit with a
reviewed subject, verify it, and scan the commit rather than only the working
tree:

```sh
git commit -S
git log -1 --show-signature --stat
git status --short
gitleaks git --redact --log-opts='-1'
```

Fetch before pushing and make sure the remote did not move unexpectedly:

```sh
git fetch origin
git branch -vv
git log --oneline --decorate --graph --max-count=12 --all
git push origin master
git ls-remote origin refs/heads/master
```

Do not force-push. Watch the GitHub `Common Lisp CI` workflow until both the
SBCL and ECL matrix jobs are green for the exact pushed commit. Preserve the
commit ID, signature result, remote ID, workflow URL/job IDs, and failures if
any. A green push closes the publication gate, not Phase 8.

## Phase 8: target-host work still required

Phase 8 must run in a separate, explicitly authorized session on `basedserv`.
The currently selected live target is the Advantage360, not the Advantage2.

### Current read-only host baseline

Re-observed on 2026-08-17:

- host: `basedserv`;
- `kanata@advantage360.service`: enabled, active/running, PID 1316;
- `kanata@footswitches.service`: enabled, active/running, PID 1318 and outside
  the transaction;
- live Advantage360 config link target:
  `/home/tay/src/dotfiles/keyboard/manna-cadet/kanata/kinesis.advantage360.layered.kanata.kbd`;
- live Sway XKB link target:
  `/home/tay/src/dotfiles/sway/.config/sway/spacecadet.resolved.xkb`;
- physical Advantage360 by-id endpoint: absent; and
- no Kinesis device was visible through the read-only `/dev/input/by-id` and
  USB checks.

The restoration hashes still match the 2026-08-14 preflight:

| Object | SHA-256 |
| --- | --- |
| frozen Advantage360 Kanata config | `632a7574938b535a8d4b1d2e3ce1c5f711d0486298d2ce4d98adda702496df5a` |
| `/home/tay/kanata-launch.sh` | `a32a428ac0a33ac1842d7c8268487e82d85837b64656d4a056eebd227d943d27` |
| `kanata@.service` | `4129ea451ff2d500651456bbc749e334c8aaff0f94381c012b664ccd197a5356` |
| resolved Sway XKB | `64b76f3c7a5314fe1712c481211c7ef89b9a370f5ba636a0859046d7e3e1dbb5` |

Treat PIDs and live state as ephemeral. Re-run every read-only observation at
the start of the authorized session. Treat changed hashes or link targets as
a new baseline requiring review, not as permission to overwrite them.

### Entry gates before requesting live authorization

All of these must be true simultaneously:

1. The exact source commit is signed, pushed, and green in both CI jobs.
2. Portable tests and external evidence above pass on that commit.
3. Two fresh generations per selected composition are byte-identical.
4. Fresh preflight and validation pass from a trusted staging parent.
5. A human reviewer accepts every manifest, allocation, source-map, report,
   XKB, and Kanata difference.
6. The physical Advantage360 is connected and the exact selected by-id name is
   re-observed.
7. Current service, dotfile links, XKB state, device identities, and restoration
   hashes are recorded immediately before the transaction.
8. The user explicitly authorizes installation/staging, the one service
   restart, the target-specific transient Sway change, live input capture or
   injection, and rollback.

The authorization request should name:

- host `basedserv`;
- the exact signed commit and generated build hashes;
- physical endpoint
  `/dev/input/by-id/usb-Kinesis_Kinesis_Adv360_360555127546-if01-event-kbd`;
- expected virtual output `ivory-key-manna-advantage360`;
- `kanata@advantage360.service` as the only service in scope;
- the exact two references that may be switched;
- the live event/capture tools to be used;
- the rollback commands and saved copies; and
- confirmation that `kanata@footswitches.service` will not be changed.

### Authorized installation transaction

Once and only once that authorization exists, follow
`docs/controlled-integration-runbook.md` rather than improvising:

1. Re-record hashes, link targets, service properties, journal position,
   `/dev/input/by-id`, compositor input identities, and a small known-good
   current-input sample.
2. Copy the freshly validated candidate files beside the live files. Never
   overwrite the old targets and never install from a historical `/tmp` build.
3. Hash and validate the staged copies again.
4. Switch the smallest independently reversible reference to the staged
   Kanata configuration.
5. Restart only `kanata@advantage360.service`.
6. Prove exactly one intended candidate process is active, its input endpoint
   is the selected Advantage360, and its virtual output is named
   `ivory-key-manna-advantage360`.
7. Prove `kanata@footswitches.service` retained its original PID/state and
   behavior.
8. Apply the generated XKB keymap transiently to the target-specific virtual
   device. Do not use a broad “all keyboards” selector when the distinct output
   identity is available.
9. Run and record the complete live matrix below.
10. On the first failure, stop the candidate transaction and execute rollback.
11. If every check passes, leave persistence changes for only the authority
    actually granted; live success does not silently authorize dotfile cleanup
    or deletion of the previous configuration.

### Required live proof matrix

Record raw physical events, virtual events, client-visible results, timestamps,
expected results, and the responsible manifest/source-map/trace identity for:

- representative keys in all eight case/script/plane contexts;
- each of control, meta, hyper, alt, and super: press, chord, both release
  orders where relevant, and no stuck modifier;
- both function-layer owners at tap, just before deadline, exact deadline,
  interrupted hold, post-deadline hold, owner-up-first, and foreign-up-first;
- Greek and Top selection separately, together in both press orders, and their
  consumption/client-visible modifier behavior;
- latch consumption and reset behavior selected by the plan;
- an ordinary key adjacent to every timed participant, checking no dropped,
  duplicated, or reordered edge;
- equal-deadline shared owners and unequal-deadline refusal/arbitration;
- repeated foreign intervals and reverse-UP pairing;
- function-layer routing where the owner releases before the routed key;
- repeat behavior;
- cancellation and malformed/duplicate edge refusal without stuck state;
- the distinct virtual device name and target-specific XKB application; and
- every accepted A360 difference in the 72-row native-route ledger, including
  the reviewed game/control-plane disposition.

Static Kanata parsing, `xkbcli` compilation, a virtual device appearing, and a
service restart are not substitutes for this matrix.

### Rollback and evidence

Prepare rollback before switching anything. It must restore the exact previous
Kanata and XKB link targets and hashes, reload only
`kanata@advantage360.service`, reapply the previous Sway XKB map to the target,
and prove the old virtual device/input sample. Verify the footswitch service
was never touched.

Preserve:

- pre-transaction snapshots and hashes;
- candidate build and its hash inventory;
- service and journal logs;
- physical and virtual event logs;
- expected-versus-observed matrix;
- rollback commands and their output, even when rollback was not needed;
- post-transaction service/device state; and
- final disposition: accepted, rolled back, or blocked.

Phase 8 is complete only after a repository document links this exact evidence
and records the approved target, signed commit, build hashes, transaction,
complete live matrix, rollback proof, and final disposition.

## Closing the original plan after Phase 8

After successful live proof:

1. Add the dated integration record under `docs/integration/`.
2. Update `docs/plan-status.md` Phase 8 from “Prepared, not authorized or
   started” to “Complete,” linking the record.
3. Re-run the full completion-rule audit. Explicitly point to:
   - full Guix SBCL and ECL logs;
   - installed-tool and bounded firmware evidence;
   - the reviewed deterministic Manna builds and complete contracts;
   - every required reference/backend differential;
   - separately authorized installation, rollback, and live-input evidence;
   - the signed exact commits, clean secret scans, pushed remote IDs, and green
     CI jobs.
4. Re-run affected documentation/link checks, `git diff --check`, both Lisp
   suites if source changed, and the exact secret scan.
5. Create and push a second signed documentation/evidence commit if Phase 8
   records were added after the source commit. Wait for both CI jobs again.
6. Confirm the worktree and index are clean and remote `master` points to the
   signed, green completion commit.

Only then may the project claim that the entire original plan is complete.

## Subsequent McCLIM planning task — plan only

After the original plan is genuinely complete, the next task is to draft a
new, detailed plan for a McCLIM Ivory Key editing interface. Do **not** begin
implementing that interface. The user will refine the plan before authorizing
implementation.

The planning session must use standard CLIM practices and should be grounded
in McCLIM/CLIM documentation, especially application frames, panes, command
tables, presentations, presentation translators, typed input contexts,
incremental redisplay/output records, drawing, gadgets where appropriate, and
undoable command objects. The plan must cover at least:

- interactive assignment and editing of Ivory Key bindings on a visual
  keyboard layout;
- creation of a visual layout when no device drawing exists;
- semantic presentations for keys, positions, bindings, axes, states,
  interactions, devices, and validation diagnostics;
- selection, direct manipulation, keyboard-accessible commands, menus, and
  command-line equivalents following CLIM conventions;
- geometry editing, grouping/rows, labels, key sizes/shapes, device placement,
  zoom/pan, and layout constraints without mixing view geometry with semantic
  keyboard meaning;
- inspectors/editors for context tables, overlays, timed interactions,
  realization policies, and output vocabulary;
- safe parse/format/project integration, source-origin preservation,
  validation, explain/simulation previews, backend refusal display, and no
  implicit deployment;
- undo/redo, dirty state, autosave/recovery, atomic save, import/export, and
  deterministic source formatting;
- accessibility, pointer and keyboard workflows, presentation highlighting,
  redisplay performance, and backend portability;
- a test plan separating model tests, CLIM command/presentation tests,
  redisplay/geometry tests, McCLIM-specific integration tests, and manual GUI
  acceptance; and
- phased delivery with explicit exit criteria and a clear list of decisions
  for the user to refine.

Use the available McCLIM, CLIM specification, and presentation-based-interface
guidance when drafting it. The deliverable is a reviewed planning document
only. Do not add ASDF components, GUI source, dependencies, prototypes, or
screens until the user has refined and explicitly approved that plan.

## Final definition of done

Another agent may declare this handoff complete only when all boxes below are
true:

- [ ] The staged implementation was recovered exactly, not re-created from
      prose.
- [ ] The pinned Guix/Kanata environment was built and identified.
- [ ] Full SBCL and ECL suites passed on the exact source commit.
- [ ] Every `.ivory` file passed the source formatter check.
- [ ] Frozen migration, installed-tool, generated-artifact, state, scheduler,
      and AD01 differential probes passed with raw logs preserved.
- [ ] Both Manna compositions regenerated twice identically and every build
      contract/artifact was reviewed.
- [ ] The exact staged/commit snapshot passed whitespace and secret scans.
- [ ] The source commit was signed, pushed without force, and both CI jobs were
      green.
- [ ] The Advantage360 was physically connected and its by-id endpoint was
      re-observed.
- [ ] The user explicitly authorized the named live transaction and rollback.
- [ ] Only `kanata@advantage360.service` and its target-specific Sway input were
      changed.
- [ ] The complete live proof matrix passed, or the exact previous state was
      restored and the plan remained incomplete.
- [ ] A dated integration record and rollback evidence were committed, signed,
      pushed, and green in CI.
- [ ] `docs/plan-status.md` and the final audit truthfully mark every original
      plan gate complete.
- [ ] Only after all preceding boxes, the McCLIM editor plan was drafted for
      user refinement, with no GUI implementation begun.
