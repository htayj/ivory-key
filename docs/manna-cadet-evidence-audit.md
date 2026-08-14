# Manna Cadet evidence audit

This audit classifies the Manna Cadet material available at frozen commit
`e5f7e81cdb6e30a7735cdcab622ede29007e379b`.  It is a migration review aid,
not a generated-keymap, installation, or live-input-equivalence claim.  The
five hash-addressed primary inputs and the static-table digest are recorded in
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

The completed evidence tranche is deliberately limited to the 52 static XKB
tables, the five semantic-modifier names, both primary layered physical
placements, and the 29 output positions of the common primary function table.
The latter is represented as the abstract `function` patch axis in
`layouts/manna-cadet.ivory`; it contains command identities or Unicode scalar
outputs, never XKB keysyms, Kanata aliases, or carrier numbers.  The function
axis has no source activation behavior yet.  This accurately records what the
active table does *after* the source layer is active, without claiming that
Ivory Key has reproduced the two tap-hold activators.

That evidence does **not** meet Phase 7's migration exit criterion.  The
selected profile now has a complete typed-output vocabulary and deterministic
allocation of the 29 frozen function carriers; its non-emitting proposal passes
XKB/Kanata artifact validation. It still lacks selector/modifier and function-
activation semantics, complete simulation, and a reviewed generated-to-
baseline behavior comparison. Public compilation therefore still refuses.

Phase 9 does not relax any of those requirements.  A QMK or other backend may
state capabilities and generate its own artifacts, but it cannot turn an
unresolved Manna timing rule, command meaning, or overlay policy into a Manna
equivalence claim.

## Source variants

| Material | Evidence | Classification | Consequence |
|---|---|---|---|
| Advantage 2 layered Kanata | frozen primary hash `d36a93e…f5226b` | primary | source for common function patch and A2 placement |
| Advantage 360 layered Kanata | frozen primary hash `632a757…496df5a` | primary | source for common function patch, 360 placement, and separate game evidence |
| Group 1 plus Top XKB symbols | frozen primary hash `b559d883…739f3a0` | primary | 52 positions and eight projected static contexts |
| layered mnemonic note | frozen primary hash `8c4c975e…27bc7b` | supporting | confirms selected function mnemonics, not a timing specification |
| Advantage 2 chorded Kanata | same Git commit, SHA-256 `e4ce45dc6d5f265fbdef1de80e5792e2c7080d2a1c61705efe1b82a05401d4cd7` | regression-only | 29 `defchordsv2` rows; not active layout semantics |
| Advantage 360 chorded Kanata | same Git commit, SHA-256 `45ca3b2769b6d1686724f81e50401123a80216c888bcd8be7bb8ec19cb984cd7` | regression-only | same 29 chord rows with the 360 physical source |

The two chorded files are intentionally not added to the original five-file
hash manifest.  Their hashes above identify the reviewed material at the
frozen commit, but they are not selected compatibility profiles.  A future
owner must explicitly choose a chorded profile and establish its timing and
arbitration semantics before it becomes an executable Ivory Key variant.

## Remaining physical surface

The 52 static bindings account for symbol-producing positions, not every
physical source token.  The following residual inputs are classified so that a
future migration does not mistake an absent layout binding for permission to
drop or reinterpret it.

| Physical source surface | Frozen normal-layer result | Classification |
|---|---|---|
| `lshift`, `rshift`, arrows, `home`, and `pgup` | passed through by both primary layered files; XKB supplies the corresponding direct named keys | unresolved common controls: their physical source is known, but no target-neutral layout behavior/lifetime has been selected |
| `esc`, apostrophe, Backspace, Space, Enter, Delete, End, and PgDn | each is part of a primary tap-hold or function selector except for its tap result | listed in the timing table below; no duplicate logical placement is manufactured for its tap and hold outputs |
| Advantage 2 `lalt` | source spells the normal result `lrld` | unresolved: no alias defines that spelling in the frozen file, so no semantic identity is inferred |
| Advantage 360 `K18`, `K20`, `K19`, `K21` | source-only local keys emit `F18`, `F20`, `F19`, `F21` respectively | device-specific direct outputs; absent from the shared layout because the A2 primary source has no corresponding positions |
| A2 `menu` / 360 `caps` | direct inactive result differs by device; function result is common `alt-mode` | transcribed only as the shared active `mode-key` patch binding; inactive common behavior remains intentionally unspecified |
| `<LSGT>` static XKB table | no direct token in either primary Kanata `defsrc` | static symbol evidence retained; device placement remains unassigned |

The 360 local-key comments give source keycodes 127, 115, 130, and 142 for
those four `K18`–`K21` identifiers.  They do not demonstrate a common Kinesis
topology position or authorize reuse as function carriers.

## Static symbols and `NoSymbol`

The checked-in truth-table tool proves 52 XKB positions × eight projected
case/script/plane contexts.  It finds **158 literal `NoSymbol` cells**.  Every
one is transcribed as the explicit Ivory Key behavior `none`; none is treated
as inheritance, transparency, or a missing table entry.

Group 1 has four levels: base, Shift, Greek, and Shift+Greek.  Top is a
separate `TWO_LEVEL` group.  The frozen truth-table projection repeats each
observed Top symbol in the Greek+Top columns because that is the literal
two-level XKB source table.  This is a symbol-selection fact, not evidence
that Mod5 is consumed, hidden, or application-visible under Top.

Thus the only settled `NoSymbol` decision is output absence at those literal
source cells.  The following remain unresolved operational questions, not
alternate meanings for a `none` cell:

- how the Top group action combines with the Greek Mod5 state in a complete
  generated realization;
- whether clients should observe either consumed selector modifier; and
- how a later backend represents the same absent output without XKB fallback.

## Modifiers and selectors

| Abstract identity / selector | Frozen source evidence | Classification |
|---|---|---|
| `control` | XKB `Control` maps `<LCTL>`; home-row `d` and `k` aliases hold `lctl` | identity transcribed; tap-hold commitment unresolved |
| `meta` | XKB `Mod1` maps `<LALT>`; home-row `s` and `l` aliases hold `lalt` | identity transcribed; tap-hold commitment unresolved |
| `super` | XKB `Mod4` maps `<LWIN>`; home-row `a` and `;` aliases hold `lmet` | identity transcribed; 250 ms left-side exception unresolved |
| `hyper` | XKB `Mod2` maps `<RWIN>`; `esc` and apostrophe aliases hold `rmet` | identity transcribed; tap-hold commitment unresolved |
| `alt` | XKB `Mod3` maps `<RALT>`; Backspace and Space thumb aliases hold `ralt` | identity transcribed; tap-hold commitment unresolved |
| `case` | `<LFSH>` and `<RTSH>` map to Shift | static product-state evidence; physical holding behavior not separately transcribed |
| `script` / Greek | `<ZEHA>` maps to Mod5 `ISO_Level3_Shift`; primary layer sends carrier 85 from `lctl`, and `del` can tap-hold it | direct `lctl` selector is transcribed in device evidence; `del` tap-hold is unresolved |
| `plane` / Top | `Mode_switch` on `<LVL3>/<LVL5>` uses a group action; primary layer sends carrier 84 via `rctl`/Enter tap-hold | static table transcribed; trigger timing and modifier/group visibility unresolved |
| Caps Lock / Menu slot | A2 source has `menu`; 360 source has `caps` at the same logical location | inactive result is device-specific and not placed in the common layout; active function result is transcribed as `mode-key → alt-mode` |

The XKB comment's modifier-slot description is evidence of the historical
Linux realization, not a reason to leak modifier-slot numbers into the
abstract layout.  Carrier 84's source comment calls it “iso level 3,” while
the XKB symbols file says `Mode_switch` performs `SetGroup +1`; the latter is
why `plane` remains a selector/lowering issue rather than a sixth semantic
modifier.

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

## Interactions, timing, and overlays not yet modeled

| Source feature | Exact observed parameters | Classification |
|---|---|---|
| Home-row modifiers | eight `tap-hold-release`: `f/d/s/a`, `j/k/l/;`; 200/200 ms except `a` at 250/250 ms | unresolved: source action exists, but tap/hold commitment, interruption, cancellation, and output ordering have not been equivalently specified |
| Thumb Alt | Backspace and Space `tap-hold-release 200 200` | unresolved for the same reason |
| Function activation | End and PgDn `tap-hold-release 200 200` to `layer-while-held fun` | overlay table transcribed; activation explicitly unresolved/refused |
| Escape / apostrophe Hyper | `tap-hold-release 200 200` | unresolved |
| Number-row Shift aliases | `osft` and `csft`, `tap-hold-release 0 0`, are declared but unused by either primary normal layer | excluded as inactive aliases until an owner selects a behavior |
| Top / Greek tap-holds | Enter → Top and Delete → Greek, both `tap-hold-release 200 200` | unresolved |
| 360 game layer | enters at `lalt`; exits at that same location; `K18` is ordered `up` then `del`, `K19` the reverse, `K20` repeats `kp7` at 50, and `del`/`pgdn`/Enter have 200/200 Alt/Super/Control tap-holds | unresolved, Advantage-360-only overlay; not a common Manna layout fact |
| Older chords | 29 pairs, each `45 first-release ()` | regression-only; the old `i`+`o → stop-output` pair is not an active primary interaction |

The primary `defcfg` also sets `concurrent-tap-hold yes` and
`process-unmapped-keys yes`.  They are Kanata runtime policy, not enough by
themselves to derive the model's candidate commitment/arbitration rules.
Accordingly, there are no active generic interactions in the Manna fixture.
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
| Top selector | 84 | `Mode_switch` / group action via `<LVL3>` |
| Greek selector | 85 | `ISO_Level3_Shift` via `<ZEHA>` |

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

- `layouts/manna-cadet.ivory` has 52 static bindings, one function patch with
  29 entries, and zero active timed interactions.
- The shared topology has the 52 static positions, the immediate Greek
  selector, and the common `mode-key`.  Each device has 53 explicit placements;
  the `mode-key` maps to `MENU`/`menu` on A2 and `CAPS`/`caps` on 360.
- `manna-cadet-advantage360-linux` is a second project composition.  It selects
  the frozen 360 placement only; it does not select or implement the game
  layer.
- The migration regression test verifies the frozen five-file hash set and
  deterministic static truth table.  It also checks the evidence-based fixture
  counts and rejects a reintroduction of the old chord or comment-only latch as
  active Manna semantics.

The compiler can inspect a deterministic partial lowering: 51 placed static
tables, all 29 function carriers, their 29 XKB `I(N+8)` carrier key entries,
and a physical Kanata pass-through/function-layer proposal. It refuses final
compilation before any artifact write. The deterministic first refusal is
`:unsupported-semantic-modifiers`; the remaining independent blockers are the
case/script/plane selector allocations, unplaced `<LSGT>`, and missing function
activation/timing/arbitration semantics.

Before a Phase 7 migration claim, reviewers still need an explicit decision
for each unresolved row above, a complete simulation proof,
generated-artifact validation after those decisions, and a reviewed behavior
diff. Before deployment, follow the separate authorized integration path in
the plan; this audit changes no dotfiles checkout or live device.
