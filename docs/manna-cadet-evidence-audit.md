# Manna Cadet evidence audit

This audit classifies the Manna Cadet material available at frozen commit
`c92a9fd98adfb334c31ec5be15d444230e879a32`.  It is a migration review aid,
not a generated-keymap, installation, or live-input-equivalence claim.  The
five hash-addressed primary inputs, two separately classified chorded inputs,
and the static-table digest are recorded in
[manna-cadet-baseline.md](manna-cadet-baseline.md).

The labels below are deliberately narrow:

- **transcribed** means an exact source result has a target-neutral layout
  representation;
- **reserved** means the source resource is recorded but cannot be allocated
  again;
- **unresolved** means source text supplies values but the model has no proven
  operational equivalence yet;
- **regression-only** means the material is useful historical evidence but is
  not part of the selected primary layered migration; and
- **excluded** means a comment or inactive source fragment is not behavior.

## Phase 7 and Phase 9 boundary

The completed evidence tranche records 52 static XKB tables, fourteen direct
normal-layer bindings (four tap identities, six shared navigation keys, and
four Advantage 360 local F-key routes), the five semantic-modifier names, both primary layered
physical placements, four direct immediate selector lifecycles, sixteen
structurally transcribed tap-hold interactions with a selected buffered
compatibility/allocation profile, and the 29
output positions of the common primary function table.
The latter is represented as the abstract `function` patch axis in
`layouts/manna-cadet.ivory`; it contains command identities or Unicode scalar
outputs, never XKB keysyms, Kanata aliases, or carrier numbers.  The function
axis is activated by the two selected source tap-hold instances, and the
selected backend realization lowers them through the closed typed native-domain
contract.

Together with the closed 68/72 native ledgers, reference barrier tests, pinned
Kanata 1.12 observations, libxkbcommon modifier/selector probes, and reviewed
generated-to-baseline comparison, that evidence meets Phase 7's generation
exit criterion. The selected profile has a complete typed-output vocabulary
and 29 source-backed carrier allocations; normal compilation emits exact
XKB/Kanata artifacts. This remains distinct from Phase 8 installation and live
device proof.

Phase 9 does not relax any of those requirements.  A QMK or other backend may
state capabilities and generate its own artifacts, but it cannot turn an
unresolved Manna timing rule, command meaning, or overlay policy into a Manna
equivalence claim.

## Phase 7 audit ledger

The following ledger separates work that can be made more mechanically
reviewable from a semantic choice that only an owner can make.  A refusal is a
current, deliberate V1 disposition; it is not missing evidence that this
document is permitted to fill in by inference.

### Closed source-inventory gap

The frozen `diff` report now parses every active primary `defalias` declaration
and every selected `deflayer` structurally, without evaluating Kanata text.  It
requires a one-to-one disposition for every declared alias and requires each
selected layer to cover the complete physical `defsrc` table:

| Primary file | `defsrc` positions | Complete layers | Declared/classified aliases |
|---|---:|---|---:|
| Advantage 2 | 68 | `normal`, `fun` | 49 / 49 |
| Advantage 360 | 72 | `normal`, `game`, `fun` | 57 / 57 |

The resulting closed classes are 16 timing refusals, two direct selectors,
29 function outputs, two inactive historical aliases, and eight
Advantage-360-only game aliases.  A new alias, duplicate classification,
omitted alias, malformed alias line, `defsrc`-arity change, or incomplete
selected layer fails the report before it can print `Unchecked differences: 0`.
This closes the primary-alias/layer inventory gap; it does not assign semantics
to a refused class.

### Canonical frozen native-route ledger

The truth-table tool now has a separate `routes` render for the complete,
ordered primary native-input surface:

```sh
sbcl --script tools/manna-truth-table.lisp routes \
  /home/tay/src/dotfiles/keyboard/manna-cadet
```

It hash-gates the two layered sources, preserves every `defsrc` index, and
requires exact `normal`/`fun` coverage. Its canonical digest is
`9b2e5a6878ee4e50c6efa05b20310811b99c3cc99233c9a79c9127e86bbff0e5`.
The closed partition is:

| Code | Stable source-route class | A2 | A360 | Evidence disposition |
|---|---|---:|---:|---|
| C1 | context-key/direct identity | 39 | 39 | source-classified; runtime unproved |
| C2 | direct physical modifier | 3 | 3 | source-classified; runtime unproved |
| C3 | residual direct named key | 7 | 7 | source-classified; runtime unproved; includes A2 `menu` / A360 `caps` |
| C4 | renamed direct local key | 0 | 4 | exact 360 `K18/K20/K19/K21` → `F18/F20/F19/F21`; runtime unproved |
| C5 | `tap-hold-release` owner | 16 | 16 | source-selected; policy/runtime refused |
| C6 | direct carrier selector | 2 | 2 | exact `lctl → @gr/85` and `rctl → @top/84`; runtime unproved |
| C7 | stateful/control-plane | 1 | 1 | A2 `lalt → lrld` and A360 `lalt → @GoGame`; unresolved/refused |
| F1 | function carrier output | 29 | 29 | source-classified; runtime unproved |
| F2 | transparent to normal | 39 | 43 | source-classified; runtime unproved |

C5 deliberately includes the source-selected `@gdel` and `@rtop` rows as well
as the fourteen other primary owners. Hash-pinned direct traces now close
their early-tap and foreign-release runtime edge order; no profile is thereby
selected. The active 72-row Advantage 360 `game` layer is arity-checked but
remains a single explicit unresolved/refused surface outside the C/F semantic
partition.

Both hash-frozen files also say `process-unmapped-keys yes`. Consequently the
140 ordered `defsrc` rows are a closed source ledger, not a closed set of all
physical inputs Kanata may process: an external input absent from `defsrc`
remains an unresolved/refused foreign-input route. The ledger grants no replay,
simulator, compiler, backend, XKB, client, or live-device claim.

The selected generated profile deliberately changes that boundary to
`process-unmapped-keys no`. Its typed allocation explicitly names the five
binding-free pass-through rows and the two direct selector carriers, and the
backend refuses an unclassified `defsrc` row. This is a reviewed fail-closed
correction, not a claim that the frozen source had a closed hardware domain.

### Remaining evidence and tooling work

| PLAN requirement or evidence gap | What is already proven | Bounded next work / blocker | Disposition |
|---|---|---|---|
| §13.1 frozen inventory of the selected layered and chorded sources | five primary hashes, two regression-only chorded hashes, static-table digest, all primary aliases/layers, the 140-row canonical native-route ledger, exact carriers/function positions, and the complete chorded structure below | no Phase 7 work remains | complete |
| §13.2/§13.7 reviewable truth and behavior comparison | static 52 × 8 table, fourteen direct bindings, 29 function rows per device, four immediate holders, 16 source-transcribed tap-holds, all differences classified, generated-artifact traces, and the pinned Kanata-1.12 oracle | live comparison is Phase 8 | complete for generation |
| §13.3 complete physical placement | complete 73-position union, A2 68 physical/five unreachable, A360 72 physical/one unreachable, an ordered disposition for every primary `defsrc` row, and the two frozen source-recorded `/dev/input/by-id/` endpoints carried into generated artifacts with distinct targetable virtual-output names | connection and live hardware/output identity confirmation are Phase 8 | complete for generation |
| §13.5 complete simulation | selected barrier covers deadlines, repeated/reverse intervals, equal/unequal owners, modifier/function lifetime, selectors, context tables, and function patch routing | live client behavior is Phase 8 | complete for selected profile |
| §13.6 full compile and target validation | public project compilation emits deterministic A2/A360 XKB and Kanata artifacts with exact grades and 29 provenance-bearing allocations; installed tools accept them | installation is Phase 8 | complete |
| historical-runtime equivalence | source text plus a source-archive-checked Kanata-1.12 state-machine oracle establish bounded current-runtime behavior | recover the frozen baseline runtime/pin and raw event-level traces, or explicitly create a new non-historical compatibility profile | original historical evidence absent; no claim permitted |

### Explicit semantic/profile choices retained as reviewed boundaries

The V1 defaults in [ADR 0002](decisions/0002-v1-policy-defaults.md) answer the
general §16 questions by refusing unsupported behavior. The selected profile
activates only the reviewed rows below; excluded alternatives remain explicit.

| Source area | Selected disposition | Retained boundary |
|---|---|---|
| fourteen primary tap-holds and the Delete/Enter selector tap-holds | exact typed Kanata-1.12 buffered actions and allocations | proposed ADR 0003 remains an unselected alternative |
| five semantic modifiers | exact typed holds plus distinct XKB Control/Mod1/Mod2/Mod3/Mod4 maps | live client delivery remains Phase 8 |
| function overlay | all 29 results plus End/PgDn first/final-owner lifetime lower exactly | game-layer behavior remains excluded |
| direct Greek and Top selectors | exact held carrier lifecycles and probed generated-XKB state | no historical source-era runtime claim |
| Advantage-360 game layer | source aliases and layer are classified, while the selected common profile excludes it | select a separate 360 profile with its own overlay, timing, and interaction policy, or preserve its exclusion |
| older chorded files | P-04 makes them regression-only | select a distinct profile and establish arbitration/timing before any chord becomes active |
| `shift-latch` comment and inactive `osft`/`csft` aliases | comment-only latch is excluded; inactive aliases have no normal-layer use | provide executable source evidence and a complete interaction policy before adding either behavior |

The literal static `NoSymbol` result is not an owner choice: it is already the
explicit abstract `none` result.  Likewise, command and symbol identity names
are recorded through the realization vocabulary; their historical transport
does not itself prove application-level command equivalence.

### Supplemental live-test context, not an oracle

The later dotfiles planning document at commit `31aba7b`,
`dotfiles/sway-plan.md`, names Kanata 1.12.0 and proposes `wev` checks for
modifier gestures and Delete/Enter selectors.  It records intended checks and
expectations, not captured event-level output, a frozen executable pin, or a
historical test result.  It is therefore version/context evidence only.  The
separate [Kanata-1.12 oracle](kanata-1.12-oracle.md) adds narrowly scoped
source-state-machine evidence, but neither document proves the historical
runtime or selects the delayed-foreign-event compatibility route.

## Source variants

| Material | Evidence | Classification | Consequence |
|---|---|---|---|
| Advantage 2 layered Kanata | frozen primary hash `d36a93e…f5226b` | primary | source for common function patch and A2 placement |
| Advantage 360 layered Kanata | frozen primary hash `632a757…496df5a` | primary | source for common function patch, 360 placement, and separate game evidence |
| Group 1 plus Top XKB symbols | frozen primary hash `b559d883…739f3a0` | primary | 52 positions and eight projected static contexts |
| layered mnemonic note | frozen primary hash `8c4c975e…27bc7b` | supporting | confirms selected function mnemonics, not a timing specification |
| Advantage 2 chorded Kanata | frozen regression hash `e4ce45dc6d5f265fbdef1de80e5792e2c7080d2a1c61705efe1b82a05401d4cd` | regression-only | one 68-position normal layer, 47 aliases, and 29 exact chord rows |
| Advantage 360 chorded Kanata | frozen regression hash `45ca3b2769b6d1686724f81e50401123a80216c888bcd8be7bb8ec19cb984cd7` | regression-only | one 72-position normal layer, same 47 aliases/29 textual chord rows; two `menu` participants are outside `defsrc` |

The five-file primary static manifest remains the input to the canonical
static-table digest.  The truth-table verifier additionally checks the two
chorded hashes and produces a closed textual inventory: 16 `tap-hold-release`
aliases (15 `200/200`, one `250/250`), 31 exact carrier aliases, 16 normal
alias references, and all 29 `45 first-release ()` chord rows for each source.
The sources are still not selected compatibility profiles.  In particular, the
360 `menu`/`caps` structural mismatch is neither silently corrected nor used to
infer failure or reachability.  A future owner must explicitly choose a chorded
profile and establish timing, commitment, arbitration, output, and test
evidence before it becomes an executable Ivory Key variant.

## Remaining physical surface

The 52 static bindings account for symbol-producing positions, not every
physical source token.  The following residual inputs are classified so that a
future migration does not mistake an absent layout binding for permission to
drop or reinterpret it.

| Physical source surface | Frozen normal-layer result | Classification |
|---|---|---|
| `lshift`, `rshift`, arrows, `home`, and `pgup` | passed through by both primary layered files; XKB supplies the corresponding direct named keys | unresolved common controls: their physical source is known, but no target-neutral layout behavior/lifetime has been selected |
| `esc`, apostrophe, Backspace, Space, Enter, Delete, End, and PgDn | each is part of a selected buffered tap-hold or function selector except for its tap result | all 16 interaction shapes and realization allocations are selected; `escape`, `delete`, and `pgdn` have direct named-key ordinary bindings, while frozen `<END>` is the semantic `end` command; RETURN remains the sole Enter position; backend emission remains refused pending native-domain and whole-pipeline proof |
| Advantage 2 `lalt` | source spells the normal result `lrld` | unresolved: no alias defines that spelling in the frozen file, so no semantic identity is inferred |
| Advantage 360 `K18`, `K20`, `K19`, `K21` | source-only local keys emit `F18`, `F20`, `F19`, `F21` respectively | device-specific direct outputs; absent from the shared layout because the A2 primary source has no corresponding positions |
| A2 `menu` / 360 `caps` | direct inactive result differs by device; function result is common `alt-mode` | transcribed only as the shared active `mode-key` patch binding; inactive common behavior remains intentionally unspecified |
| `<LSGT>` static XKB table | no direct token in either primary Kanata `defsrc` | static symbol evidence retained; both devices declare it `unreachable`, so no physical placement is invented |

The 360 local-key comments give source keycodes 127, 115, 130, and 142 for
those four `K18`–`K21` identifiers.  They do not demonstrate a common Kinesis
topology position or authorize reuse as function carriers.

## Static symbols and `NoSymbol`

The checked-in truth-table tool proves 52 XKB positions × eight projected
case/script/plane contexts.  It finds **158 literal `NoSymbol` cells**.  Every
one is transcribed as the explicit Ivory Key behavior `none`; none is treated
as inheritance, transparency, or a missing table entry.

Group 1 has four levels: base, Shift, Greek, and Shift+Greek. Top is a
separate `TWO_LEVEL` group. The frozen truth-table projection repeats each
observed Top symbol in the Greek+Top columns because that is the literal
two-level XKB source table.

The separately tagged, read-only
`tests/external/manna-xkb-group2-state.lisp` probe preserves two distinct
claims. Its hash-pinned frozen mode compiles the checked-in keymap with its
source include directory. Under Guix xkeyboard-config 2.44 and
libxkbcommon/xkbcli 1.11.0, `evdev+aliases(qwerty)` has no `ZEHA`, so this
mode proves only the frozen
`AD01` Group 1/Group 2 shape, LVL3/LVL5 depressed Group2 serialization, and
consumed Shift in Group2. It cannot prove a frozen Greek or Greek+Top event.
This host's xkeyboard-config 2.48-1 with libxkbcommon 1.13.2 supplies
ZEHA=93; that xkeyboard-config include-data difference is recorded, not
substituted for the pinned Guix observation.

The probe's separate generated-map mode emits Ivory Key's closed typed carrier
allocation: Linux 84 is `<LVL3>=92` and Linux 85 is `<ZEHA>=93`. It has no
generated LVL5 override or selected device mapping, while compiled `pc+us`
still contributes inherited LVL5/ISO_Level5_Shift/Mod3 behavior outside that
input domain. For both accepted Group 1 type forms it proves via libxkbcommon
that ZEHA alone selects and consumes Group1 Level3; Group2 is depressed and
serialized; held ZEHA remains effective/unconsumed for a Group2 key; and
Group2 Shift is consumed. It covers ZEHA down/up and ZEHA+LVL3 in both press
orders. This is an exact selected **generated XKB state
sub-contract**, not an assertion that frozen Kanata delivers code 85 this way,
that a client/compositor observes the same semantics, or that Manna migration
is equivalent.

Thus the only settled `NoSymbol` decision is output absence at those literal
source cells.  The following remain unresolved operational questions, not
alternate meanings for a `none` cell:

- how a complete realization maps the frozen Kanata code 85/`ZEHA` source
  spelling to the selected generated XKB event path;
- how clients receive or interpret group serialization and consumed selector
  state beyond the selected libxkbcommon key-state APIs; and
- how a later backend represents the same absent output without XKB fallback.

## Modifiers and selectors

| Abstract identity / selector | Frozen source evidence | Classification |
|---|---|---|
| `control` | XKB `Control` maps `<LCTL>`; home-row `d` and `k` aliases hold `lctl` | identity transcribed; tap-hold commitment unresolved |
| `meta` | XKB `Mod1` maps `<LALT>`; home-row `s` and `l` aliases hold `lalt` | identity transcribed; tap-hold commitment unresolved |
| `super` | XKB `Mod4` maps `<LWIN>`; home-row `a` and `;` aliases hold `lmet` | identity transcribed; 250 ms left-side exception unresolved |
| `hyper` | XKB `Mod2` maps `<RWIN>`; `esc` and apostrophe aliases hold `rmet` | identity transcribed; tap-hold commitment unresolved |
| `alt` | XKB `Mod3` maps `<RALT>`; Backspace and Space thumb aliases hold `ralt` | identity transcribed; tap-hold commitment unresolved |
| `case` | `<LFSH>` and `<RTSH>` map to `Shift_L` / `Shift_R`; both primary normal layers leave `lshift` / `rshift` unchanged | two exact immediate owner-scoped holders set `case=shifted`; the home-row `f` / `j` tap-holds remain unresolved |
| `script` / Greek | symbols source spells `<ZEHA>` as Mod5 `ISO_Level3_Shift`; primary layer sends carrier 85 from `lctl`, and `del` can tap-hold it | direct `lctl` is an exact abstract immediate held `script → greek` interaction; selected generated XKB proves its own ZEHA state contract, while frozen carrier bridging, `del` tap-hold, and client/live equivalence remain unresolved |
| `plane` / Top | `Mode_switch` on `<LVL3>/<LVL5>` uses a group action; primary layer sends carrier 84 via `rctl`/Enter tap-hold | direct `rctl` is an exact abstract immediate held `plane → top`; selected generated XKB proves its LVL3 Group2 contract, while frozen LVL5 remains outside it and Enter tap-hold/carrier/client/lifetime equivalence remain unresolved |
| Caps Lock / Menu slot | A2 source has `menu`; 360 source has `caps` at the same logical location | inactive result is device-specific and not placed in the common layout; active function result is transcribed as `mode-key → alt-mode` |

The XKB comment's modifier-slot description is evidence of the historical
Linux realization, not a reason to leak modifier-slot numbers into the
abstract layout.  Carrier 84's source comment calls it “iso level 3,” while
the XKB symbols file says `Mode_switch` performs `SetGroup +1`; the latter is
why `plane` remains a selector/lowering issue rather than a sixth semantic
modifier.

### Frozen primary tap-hold table

Both frozen primary `deflayer normal` forms select the same 14
`tap-hold-release` aliases below.  `position` is both the literal tap action
and the corresponding `defsrc` token; the table records the literal Kanata
hold action rather than normalizing right-hand aliases to a different spelling.

| Semantic family | Alias / position | Tap-repress / hold timeout (ms) | Literal tap action | Literal hold action |
|---|---|---:|---|---|
| case | `@Sf` / `f` | 200 / 200 | `f` | `lshift` |
| case | `@Sj` / `j` | 200 / 200 | `j` | `lshift` |
| control | `@Cd` / `d` | 200 / 200 | `d` | `lctl` |
| control | `@Ck` / `k` | 200 / 200 | `k` | `lctl` |
| meta | `@Ms` / `s` | 200 / 200 | `s` | `lalt` |
| meta | `@Ml` / `l` | 200 / 200 | `l` | `lalt` |
| super | `@sa` / `a` | 250 / 250 | `a` | `lmet` |
| super | `@s;` / `;` | 200 / 200 | `;` | `lmet` |
| hyper | `@eoam` / `esc` | 200 / 200 | `esc` | `rmet` |
| hyper | `@qoam` / `'` | 200 / 200 | `'` | `rmet` |
| alt | `@Hro` / `bspc` | 200 / 200 | `bspc` | `ralt` |
| alt | `@Hsp` / `spc` | 200 / 200 | `spc` | `ralt` |
| function | `@HscL` / `end` | 200 / 200 | `end` | `(layer-while-held fun)` |
| function | `@HscR` / `pgdn` | 200 / 200 | `pgdn` | `(layer-while-held fun)` |

The dedicated `lshift` and `rshift` `defsrc` tokens also occur unchanged in
each primary normal layer.  They are immediate physical case holders, not
tap-holds.  The fixture transcribes them as the owner-scoped
`hold-case-left-shift` and `hold-case-right-shift` interactions: the
whole-layout simulator proves that either first release leaves the other owner
holding `case=shifted`, and the final release exposes `case=plain`.  This is
the selected Ivory Key immediate-held lifecycle, not a claim of complete
historical Kanata/XKB runtime equivalence.  The unused `osft` and `csft`
aliases do not alter this table; they are declared but not selected by either
primary normal layer.

The current official [Kanata configuration documentation](https://github.com/jtroo/kanata/blob/main/docs/config.adoc)
defines the four `tap-hold` fields in this order: tap-repress timeout, hold
timeout, tap action, and hold action.  It says the `tap-hold-release` variant
activates the hold action early when a different key is pressed and released;
otherwise the hold timeout is the deadline for the hold action.  The frozen
files set `process-unmapped-keys yes` and `concurrent-tap-hold yes` in both
variants.  The former makes Kanata process unmapped keys for tap-hold actions
and is now an explicit boundary of the canonical native-route ledger: inputs
outside the ordered `defsrc` table are not silently classified;
the official [sample configuration](https://github.com/jtroo/kanata/blob/main/cfg_samples/kanata.kbd)
says the latter changes how near-simultaneous tap-hold timeouts expire.

This is a source-plus-documentation interpretation, not yet a frozen runtime
oracle: a narrow search of frozen commit
`c92a9fd98adfb334c31ec5be15d444230e879a32` finds no Kanata binary/version,
package pin, or lock file (its README only links upstream).  Neither primary
file supplies a total order for equal-time events, multi-owner release, or the
precise concurrent-tap-hold scheduler. No Ivory Key interaction is added to
the checked-in Manna layout from these rows until an owner selects that complete
policy. [ADR 0003](decisions/0003-manna-release-trigger-v1.md) records one
proposed modern `manna-release-trigger-v1` route and now supplies a
source-decoded, reference-simulated complete 14+2 fixture for its bounded
abstract semantics. It remains unselected, does not alter this evidence
classification, does not establish historical Kanata equivalence, and does not
unblock Manna lowering.

[ADR 0004](decisions/0004-kanata-1-12-buffered-compatibility.md) records the
separate proposed, non-default `kanata-1-12-buffered` route from the
hash-pinned Kanata-1.12 oracle.  It records the oracle's delayed foreign-input
ordering and first/final-owner lifetime facts alongside the closed sixteen-row
source inventory. A positive buffered-interaction evidence ledger admits all
sixteen source-selected normal-layer tap-holds to the structural contract,
including the now directly traced Delete/Enter selector pair. A strict derived
normalized contract and bounded direct-named-key dispatch transaction now
represent the proven prefix subset without adding source replay syntax. It is still not
a `.ivory` realization, selects no profile, has no exact Kanata lowering, and
cannot make a source-era equivalence claim.

The direct physical Shift pair is now materialized separately.  If an
owner-scoped `tap-hold-release` lifecycle is selected without changing the
evidenced positions/actions, these are the remaining exact source-derived
interaction instances to materialize (all common to Advantage 2 and Advantage
360):

| Family | Future instance identities |
|---|---|
| case tap-holds | `tap-hold-case-f`, `tap-hold-case-j` |
| control | `tap-hold-control-d`, `tap-hold-control-k` |
| meta | `tap-hold-meta-s`, `tap-hold-meta-l` |
| super | `tap-hold-super-a`, `tap-hold-super-semicolon` |
| hyper | `tap-hold-hyper-escape`, `tap-hold-hyper-apostrophe` |
| alt | `tap-hold-alt-backspace`, `tap-hold-alt-space` |
| function | `tap-hold-function-end`, `tap-hold-function-pgdn` |

Those are planned source identities only. They still require the complete
operator policy above and backend lowering that preserves the selected
semantics.

## Primary layered function overlay

Both primary layered files have one `fun` layer, entered by holding either the
End or PgDn thumb source position.  The common table has all 29 `@sc-*` output
aliases.  The exact source-position result is now transcribed as follows:

| Positions | Transcribed result |
|---|---|
| `1 2 3 4` | Unicode `Ⅰ Ⅱ Ⅲ Ⅳ` |
| `7 8 9 0` | Unicode `☚ 👍 👎 ☛` |
| `q w e t` | `quote`, `terminal`, `macro`, `over-strike` |
| `u i o` | `status`, `call`, `stop-output` |
| `s g h j k l ;` | `system`, `abort`, `help`, `line`, `clear-input`, `clear-screen`, `end` |
| `z x c m .` | `hold-output`, `network`, `break`, `resume`, `repeat` |
| `grave` | `mode-lock` |
| device-specific `mode-key` | `alt-mode` while the function patch is active |

The `mode-key` inactive result remains intentionally unspecified in the common
layout because the A2 base layer passes `Menu` while the 360 base layer passes
`Caps_Lock`.  Both device fixtures record their actual physical spellings, and
the shared function-table output is the same `alt-mode` command.  An inactive
press therefore has no invented shared abstract result.

The mnemonic document directly corroborates the mnemonic placements it names.
Its “remaining … chord-derived neighborhood” sentence is supporting evidence
only; the primary layered table itself is the authority for every row above.

## Interactions, timing, and overlays

| Source feature | Exact observed parameters | Classification |
|---|---|---|
| Direct Greek selector | `lctl → @gr → (arbitrary-code 85)` in both primary normal layers | transcribed as immediate one-participant `hold-greek-selector`; it holds `script=greek` and explicitly restores `roman` on release |
| Direct Top selector | `rctl → @top → (arbitrary-code 84)` in both primary normal layers | transcribed as immediate one-participant `hold-top-selector`; it holds `plane=top` and explicitly restores `base` on release |
| Direct physical case holders | `lshift` and `rshift` are unchanged at their `defsrc` indexes in both primary normal layers; XKB maps `<LFSH>` / `<RTSH>` to `Shift_L` / `Shift_R` | transcribed as `hold-case-left-shift` / `hold-case-right-shift`; owner-scoped hold state keeps `case=shifted` until the last release |
| Case and five semantic modifier tap-holds | exact 12 alias rows in the frozen-primary table above: 200/200 ms except `a → lmet` at 250/250 ms | raw aliases, typed hold allocations, version-pinned buffered scheduling evidence, owner-scoped release, and distinct generated XKB modifier maps are recorded; full native-domain and whole-pipeline equivalence remain unresolved |
| Function activation | End and PgDn `tap-hold-release 200 200` to `layer-while-held fun` | both exact aliases are recorded; overlay table transcribed, but activation remains explicitly unresolved/refused |
| Escape / apostrophe Hyper | `tap-hold-release 200 200` | unresolved |
| Number-row Shift aliases | `osft` and `csft`, `tap-hold-release 0 0`, are declared but unused by either primary normal layer | excluded as inactive aliases until an owner selects a behavior |
| Top / Greek tap-holds | Enter → Top and Delete → Greek, both `tap-hold-release 200 200` | unresolved |
| 360 game layer | enters at `lalt`; exits at that same location; `K18` is ordered `up` then `del`, `K19` the reverse, `K20` repeats `kp7` at 50, and `del`/`pgdn`/Enter have 200/200 Alt/Super/Control tap-holds | unresolved, Advantage-360-only overlay; not a common Manna layout fact |
| Older chords | each chorded file has 29 exact pairs, each `45 first-release ()`; 47 aliases comprise 16 literal tap-holds and 31 carriers | regression-only; the old `i`+`o → stop-output` pair is not active.  The 360 source has two literal `menu` chord participants outside `defsrc`; that is retained as a non-semantic structural mismatch |

The primary `defcfg` settings are evidence about the observed Kanata policy,
not a version-pinned complete model candidate/arbitration rule.
The fixture has exactly four active immediate held interactions: two direct
selectors and the two direct physical case holders. It has no transcribed Manna
tap-hold, chord, or function-activation interaction.
The previously checked-in `latch-latch` `on-tap` binding is removed: the frozen
primary source only says “press both to latch?” in a comment and supplies
neither positions nor an executable alias.  It is excluded, not converted to
a behavioral axis.

## Commands and carriers

The source has one exact Linux carrier mapping for each function-table result.
Those carrier values are recorded in device `reserve-carriers` declarations so
the allocator cannot silently reuse them. They are not abstract bindings. The
realization-owned `manna-cadet-linux-output` vocabulary records the frozen XKB
spelling for every typed static output and the paired XKB/Kanata spelling for
these 29 function outputs; the layout itself remains free of backend data.

| Identity | Kanata carrier | XKB result |
|---|---:|---|
| `macro`, `terminal`, `quote`, `over-strike`, `clear-input`, `clear-screen`, `hold-output`, `stop-output` | 183–190 | `UE000`–`UE007` |
| `abort`, `break`, `resume`, `call`, `system`, `network`, `status`, `line`, `help` | 191–199 (source order includes the documented gaps) | `UE008`, `UE009`, `UE011`, `UE00C`, `UE00A`, `UE00B`, `UE012`, `UE013`, `UE014` |
| `alt-mode`, `mode-lock` | 211, 212 | `UE00F`, `UE010` |
| `roman-one` through `roman-four` | 218–221 | `U2160`–`U2163` |
| `finger-left`, `thumb-up`, `thumb-down`, `finger-right`, `repeat` | 222–226 | `U261A`, `U1F44D`, `U1F44E`, `U261B`, `UE00E` |
| `end` | 240 | `UE00D` |
| Top selector | 84 | source spelling `Mode_switch` / group action via `<LVL3>`; selected generated map fixes `<LVL3>=92`; frozen LVL5 evidence is not selected |
| Greek selector | 85 | source spelling `ISO_Level3_Shift` via `<ZEHA>`; selected generated map fixes `<ZEHA>=93`, while frozen Guix `evdev` still lacks that key name |

The identity names in the layout come from the source aliases and mnemonic
evidence.  They do **not** establish that the older XKB comment's suggested
`XF86*`, `Insert`, `Pause`, or `Help` alternatives are the same
application-visible commands: the actual frozen generated mapping is the
listed private-use or Unicode result. The selected vocabulary maps every typed
command/named output required by this profile and passes every resulting
spelling through the backend safety validator before a proposal can be
emitted. The only accepted Kanata action shape is the exact frozen
`(arbitrary-code N)` carrier form; no token or command spelling has been
guessed.

## Checked-in consequences and review gates

- `layouts/manna-cadet.ivory` has 52 static eight-context bindings, fourteen direct
  ordinary bindings, one function patch with 29 entries, four immediate held
  interactions, and 16 structurally transcribed tap-hold interactions. The
  realization selects their buffered compatibility policy and typed allocation
  ledger, which the selected compiler lowers exactly.
- The shared topology is the complete 73-position device union. Advantage 2
  has 68 physical placements plus typed-unreachable `<LSGT>` and four local
  hotkeys; Advantage 360 has 72 physical placements plus typed-unreachable
  `<LSGT>`. The `mode-key` maps to `MENU`/`menu` on A2 and `CAPS`/`caps` on
  360. RETURN remains the sole physical Enter identity.
- `manna-cadet-advantage360-linux` is a second project composition. It selects
  the frozen 360 placement and shared buffered profile; it does not select or
  implement the game layer.
- The migration regression test verifies the five primary hashes, two
  regression-only chorded hashes, and deterministic static truth table. Its
  generated `diff` report additionally enumerates all 52 static tables/416
  cells, both 29-row function placements, all four direct selectors, and every
  old chorded alias/carrier/combo/layer row. It refuses an unexpected table,
  placement, carrier, selector, chord row, or count before printing `Unchecked
  differences: 0`; that terminal count means every frozen-versus-fixture
  difference is classified, not that a refusal is solved. It separately
  data-checks all 16 selected `tap-hold-release` aliases, their normal-layer
  selection, direct Shift holders, relevant `defcfg`, and the checked-in typed
  compatibility/allocation selection.

Run `sbcl --script tools/manna-truth-table.lisp diff ROOT` against the
hash-verified frozen checkout for the complete review artifact.  The report's
only non-selected classes are deliberate: typed-unreachable `<LSGT>`, the
device-specific inactive mode-key result, two inactive historical Shift
aliases, and the Advantage360 game aliases. The selected sixteen tap-holds and
four direct interactions have exact typed Kanata/XKB lifecycles.

The selected Manna profile contains all 52 hash-pinned source-derived static
type declarations. The compiler emits its deterministic XKB lowering: 51
generated Manna selector overrides, all 29 function carriers,
their 29 XKB `I(N+8)` carrier key entries, and carrier keys `84 → <LVL3>=92`
and `85 → <ZEHA>=93`. The remaining declared row, `<LSGT>`, is explicitly
typed unreachable on both devices and receives no Manna override. The partial
map includes `pc+us`, so compiled `<LSGT>` retains inherited default
less/greater behavior; it is outside selected device-input coverage and is not
the frozen eight-state Manna table. The tagged libxkbcommon probe executes this
51-override generated XKB artifact, in addition to its one-key type-form
checks. The combined compiler pairs it with the exact selected Kanata artifact.
The five semantic modifier identities have closed
Kanata allocations and distinct generated XKB Control/Mod1/Mod2/Mod3/Mod4
maps, with effective/unconsumed state checked on AD01.

Phase 7's generated migration claim is complete. Before deployment, follow the
separate authorized integration path in the plan; this audit changes no
dotfiles checkout or live device.
