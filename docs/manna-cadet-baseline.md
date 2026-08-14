# Manna Cadet frozen baseline

This is a read-only, hash-addressed transcription aid for Manna Cadet commit
`e5f7e81cdb6e30a7735cdcab622ede29007e379b`. It is not a generated
replacement, installation, or live-input-equivalence claim.

| Path | SHA-256 |
|---|---|
| `xkb/symbols/spacecadet` | `b559d8832462556f990bee273b53a91ab2c6c81fc7e2fa9c9bb0cdfce739f3a0` |
| `xkb/keymap/spacecadet.xkb` | `68dcb0f3c77fa2b88cfc2db04347b07089efad25a2bcf8b86324a5f283539fba` |
| `kanata/kinesis.advantage2.layered.kanata.kbd` | `d36a93eab6e2355707f7a6bfbcfac2a4e3b0ea361cc399d388543f51e1f5226b` |
| `kanata/kinesis.advantage360.layered.kanata.kbd` | `632a7574938b535a8d4b1d2e3ce1c5f711d0486298d2ce4d98adda702496df5a` |
| `space-cadet-layered-mnemonics.md` | `8c4c975e0acee03f96f51ae144f2c12c1efc249672b4ef50e39a781e8f27bc7b` |

The canonical parsed-table SHA-256 is
`3ef72eabdd26d2154481c1b8fd0becba50dfbb9a0ba50d0d37556930f92dc807`.

Run this before any migration review:

```sh
sbcl --script tools/manna-truth-table.lisp verify \
  /home/tay/src/dotfiles/keyboard/manna-cadet
```

`verify` checks the commit, all five file hashes, the 52-key static set,
and the canonical truth-table digest. `render` prints the table and
`fixture` emits the mechanically derived Ivory Key static binding rows.

For the complete checked-in fixture comparison, run:

```sh
sbcl --script tools/manna-truth-table.lisp diff \
  /home/tay/src/dotfiles/keyboard/manna-cadet
```

`diff` first performs the same commit/hash verification.  It then generates a
closed report for all 52 static tables (416 cells, including 158 literal
`NoSymbol` cells), all 29 primary function outputs on each device, and the
four direct held selectors/case holders.  It refuses to print a successful
report if a table, physical placement, carrier, function output, selector, or
fixture count is not accounted for.  The report has one explicit row for every
remaining difference: the unplaced `<LSGT>` table, the Menu/Caps inactive
device variance, 14 primary and two alternate-selector tap-holds, inactive
historical Shift aliases, the eight Advantage-360-only game aliases, and the
unproved Group-2/lowering boundary.  Its final `Unchecked differences: 0` is
only a complete classification of frozen source versus fixture; it is not a
claim that any refused row is equivalent or deployable.

## Static XKB symbol truth table

The baseline has four Group 1 levels and a two-level Top group. The eight
columns below are the case/script/plane projection in Ivory Key ordering.
Because Top is `TWO_LEVEL`, the Greek+Top cells repeat its observed Top
symbol; that does not establish whether Mod5 is consumed or visible to
applications. `NoSymbol` is the explicit XKB no-symbol entry, not a guess.

| XKB key | plain/roman/base | shifted/roman/base | plain/greek/base | shifted/greek/base | plain/roman/top | shifted/roman/top | plain/greek/top | shifted/greek/top |
|---|---|---|---|---|---|---|---|---|
| `<AE01>` | `1` | `exclam` | `dagger` | `NoSymbol` | `NoSymbol` | `NoSymbol` | `NoSymbol` | `NoSymbol` |
| `<AE02>` | `2` | `at` | `doubledagger` | `NoSymbol` | `NoSymbol` | `NoSymbol` | `NoSymbol` | `NoSymbol` |
| `<AE03>` | `3` | `numbersign` | `opentribulletdown` | `NoSymbol` | `NoSymbol` | `NoSymbol` | `NoSymbol` | `NoSymbol` |
| `<AE04>` | `4` | `dollar` | `cent` | `NoSymbol` | `NoSymbol` | `NoSymbol` | `NoSymbol` | `NoSymbol` |
| `<AE05>` | `5` | `percent` | `circle` | `NoSymbol` | `NoSymbol` | `NoSymbol` | `NoSymbol` | `NoSymbol` |
| `<AE06>` | `6` | `asciicircum` | `U25AF` | `NoSymbol` | `NoSymbol` | `NoSymbol` | `NoSymbol` | `NoSymbol` |
| `<AE07>` | `7` | `ampersand` | `division` | `NoSymbol` | `NoSymbol` | `NoSymbol` | `NoSymbol` | `NoSymbol` |
| `<AE08>` | `8` | `asterisk` | `multiply` | `NoSymbol` | `NoSymbol` | `NoSymbol` | `NoSymbol` | `NoSymbol` |
| `<AE09>` | `9` | `parenleft` | `paragraph` | `NoSymbol` | `NoSymbol` | `NoSymbol` | `NoSymbol` | `NoSymbol` |
| `<AE10>` | `0` | `parenright` | `emopencircle` | `NoSymbol` | `NoSymbol` | `NoSymbol` | `NoSymbol` | `NoSymbol` |
| `<AE11>` | `minus` | `underscore` | `U2248` | `NoSymbol` | `NoSymbol` | `NoSymbol` | `NoSymbol` | `NoSymbol` |
| `<AE12>` | `equal` | `plus` | `U2205` | `NoSymbol` | `NoSymbol` | `NoSymbol` | `NoSymbol` | `NoSymbol` |
| `<BKSP>` | `BackSpace` | `BackSpace` | `BackSpace` | `BackSpace` | `BackSpace` | `BackSpace` | `BackSpace` | `BackSpace` |
| `<TAB>` | `Tab` | `ISO_Left_Tab` | `Tab` | `ISO_Left_Tab` | `Tab` | `ISO_Left_Tab` | `Tab` | `ISO_Left_Tab` |
| `<AD01>` | `q` | `Q` | `Greek_theta` | `Greek_THETA` | `upcaret` | `NoSymbol` | `upcaret` | `NoSymbol` |
| `<AD02>` | `w` | `W` | `Greek_omega` | `Greek_OMEGA` | `downcaret` | `NoSymbol` | `downcaret` | `NoSymbol` |
| `<AD03>` | `e` | `E` | `Greek_epsilon` | `Greek_EPSILON` | `downshoe` | `NoSymbol` | `downshoe` | `NoSymbol` |
| `<AD04>` | `r` | `R` | `Greek_rho` | `Greek_RHO` | `upshoe` | `NoSymbol` | `upshoe` | `NoSymbol` |
| `<AD05>` | `t` | `T` | `Greek_tau` | `Greek_TAU` | `leftshoe` | `NoSymbol` | `leftshoe` | `NoSymbol` |
| `<AD06>` | `y` | `Y` | `Greek_psi` | `Greek_PSI` | `rightshoe` | `NoSymbol` | `rightshoe` | `NoSymbol` |
| `<AD07>` | `u` | `U` | `Greek_upsilon` | `Greek_UPSILON` | `U2200` | `NoSymbol` | `U2200` | `NoSymbol` |
| `<AD08>` | `i` | `I` | `Greek_iota` | `Greek_IOTA` | `infinity` | `NoSymbol` | `infinity` | `NoSymbol` |
| `<AD09>` | `o` | `O` | `Greek_omicron` | `Greek_OMICRON` | `U2203` | `NoSymbol` | `U2203` | `NoSymbol` |
| `<AD10>` | `p` | `P` | `Greek_pi` | `Greek_PI` | `partialderivative` | `NoSymbol` | `partialderivative` | `NoSymbol` |
| `<AD11>` | `bracketleft` | `braceleft` | `U27E6` | `U2983` | `NoSymbol` | `NoSymbol` | `NoSymbol` | `NoSymbol` |
| `<AD12>` | `bracketright` | `braceright` | `U27E7` | `U2984` | `NoSymbol` | `NoSymbol` | `NoSymbol` | `NoSymbol` |
| `<RTRN>` | `Return` | `NoSymbol` | `Linefeed` | `NoSymbol` | `Return` | `NoSymbol` | `Return` | `NoSymbol` |
| `<AC01>` | `a` | `A` | `Greek_alpha` | `Greek_ALPHA` | `uptack` | `NoSymbol` | `uptack` | `NoSymbol` |
| `<AC02>` | `s` | `S` | `Greek_sigma` | `Greek_SIGMA` | `downtack` | `NoSymbol` | `downtack` | `NoSymbol` |
| `<AC03>` | `d` | `D` | `Greek_delta` | `Greek_DELTA` | `righttack` | `NoSymbol` | `righttack` | `NoSymbol` |
| `<AC04>` | `f` | `F` | `Greek_phi` | `Greek_PHI` | `lefttack` | `NoSymbol` | `lefttack` | `NoSymbol` |
| `<AC05>` | `g` | `G` | `Greek_gamma` | `Greek_GAMMA` | `uparrow` | `NoSymbol` | `uparrow` | `NoSymbol` |
| `<AC06>` | `h` | `H` | `Greek_eta` | `Greek_ETA` | `downarrow` | `NoSymbol` | `downarrow` | `NoSymbol` |
| `<AC07>` | `j` | `J` | `U03D1` | `U03F4` | `leftarrow` | `NoSymbol` | `leftarrow` | `NoSymbol` |
| `<AC08>` | `k` | `K` | `Greek_kappa` | `Greek_KAPPA` | `rightarrow` | `NoSymbol` | `rightarrow` | `NoSymbol` |
| `<AC09>` | `l` | `L` | `Greek_lambda` | `Greek_LAMBDA` | `U2194` | `NoSymbol` | `U2194` | `NoSymbol` |
| `<AC10>` | `semicolon` | `colon` | `diaeresis` | `NoSymbol` | `NoSymbol` | `NoSymbol` | `NoSymbol` | `NoSymbol` |
| `<AC11>` | `apostrophe` | `quotedbl` | `periodcentered` | `U0387` | `NoSymbol` | `NoSymbol` | `NoSymbol` | `NoSymbol` |
| `<TLDE>` | `grave` | `asciitilde` | `grave` | `asciitilde` | `NoSymbol` | `NoSymbol` | `NoSymbol` | `NoSymbol` |
| `<BKSL>` | `backslash` | `bar` | `U2016` | `brokenbar` | `NoSymbol` | `NoSymbol` | `NoSymbol` | `NoSymbol` |
| `<AB01>` | `z` | `Z` | `Greek_zeta` | `Greek_ZETA` | `downcaret` | `NoSymbol` | `downcaret` | `NoSymbol` |
| `<AB02>` | `x` | `X` | `Greek_xi` | `Greek_XI` | `downstile` | `NoSymbol` | `downstile` | `NoSymbol` |
| `<AB03>` | `c` | `C` | `Greek_chi` | `Greek_CHI` | `upstile` | `NoSymbol` | `upstile` | `NoSymbol` |
| `<AB04>` | `v` | `V` | `Greek_finalsmallsigma` | `Greek_SIGMA` | `similarequal` | `NoSymbol` | `similarequal` | `NoSymbol` |
| `<AB05>` | `b` | `B` | `Greek_beta` | `Greek_BETA` | `identical` | `NoSymbol` | `identical` | `NoSymbol` |
| `<AB06>` | `n` | `N` | `Greek_nu` | `Greek_NU` | `lessthanequal` | `NoSymbol` | `lessthanequal` | `NoSymbol` |
| `<AB07>` | `m` | `M` | `Greek_mu` | `Greek_MU` | `greaterthanequal` | `NoSymbol` | `greaterthanequal` | `NoSymbol` |
| `<AB08>` | `comma` | `less` | `guillemetleft` | `U300A` | `NoSymbol` | `NoSymbol` | `NoSymbol` | `NoSymbol` |
| `<AB09>` | `period` | `greater` | `guillemetright` | `U300B` | `NoSymbol` | `NoSymbol` | `NoSymbol` | `NoSymbol` |
| `<AB10>` | `slash` | `question` | `integral` | `NoSymbol` | `NoSymbol` | `NoSymbol` | `NoSymbol` | `NoSymbol` |
| `<SPCE>` | `space` | `NoSymbol` | `space` | `NoSymbol` | `space` | `NoSymbol` | `space` | `NoSymbol` |
| `<LSGT>` | `less` | `greater` | `less` | `greater` | `bar` | `brokenbar` | `bar` | `brokenbar` |

## Transcribed fixture scope

`layouts/manna-cadet.ivory` contains all 52 static tables. Its
`named-symbol` values are neutral semantic registry names, not XKB or
private-use carrier escapes. `realizations/manna-cadet-output-vocabulary.ivory`
owns their frozen XKB spellings; the compiler therefore prepares the 51 static
tables that have an evidenced device placement, while preserving physical
Kanata events for XKB to translate. This remains a refused partial proposal,
not a generatable replacement.

The Kinesis topology has the 52 static positions, two direct physical case
holders, directly evidenced `greek` and `top` selectors, and a shared
`mode-key` whose inactive result differs by device. Both device files place 51
static positions (every table except `<LSGT>`), the two direct case holders,
the two direct selectors, and the common mode-key location:

| Device | Physical source | XKB output |
|---|---|---|
| Advantage 2 | `lshift` | `LFSH` / `Shift_L` |
| Advantage 2 | `rshift` | `RTSH` / `Shift_R` |
| Advantage 360 | `lshift` | `LFSH` / `Shift_L` |
| Advantage 360 | `rshift` | `RTSH` / `Shift_R` |

| Device | Physical source | XKB selector output |
|---|---|---|
| Advantage 2 | `lctl` | `ZEHA` |
| Advantage 360 | `lctl` | `ZEHA` |

| Device | Physical source | XKB selector output |
|---|---|---|
| Advantage 2 | `rctl` | `LVL3` / `Mode_switch` |
| Advantage 360 | `rctl` | `LVL3` / `Mode_switch` |

| Device | Mode-key source | XKB spelling outside function patch |
|---|---|---|
| Advantage 2 | `menu` | `MENU` |
| Advantage 360 | `caps` | `CAPS` |

`<LSGT>` has no direct `defsrc` token in either layered file and remains
unplaced.  The earlier `latch-latch` fixture construct has been removed: the
frozen primary source contains only a question in a comment, not a position or
executable behavior.

## Commands, variants, and undecided behavior

Kanata documents command carriers 183–199, 211–212, 218–226, and 240;
the device fixtures reserve exactly those values plus selectors 84 and 85.
The following neutral command/symbol identities preserve the evidence without
turning private-use keysyms or carrier codes into abstract-layout values. The
29 primary function-table outputs are now present as abstract patch entries;
the realization-owned vocabulary records each XKB/Kanata pair and compiler
allocation. Source activation/timing semantics remain unfinished, so no final
lowering or deployment is claimed.

| Identity | Carrier | Baseline XKB result |
|---|---:|---|
| `macro`, `terminal`, `quote`, `over-strike`, `clear-input`, `clear-screen`, `hold-output`, `stop-output` | 183–190 | `UE000`–`UE007` |
| `abort`, `break`, `resume`, `call`, `system`, `network`, `status`, `line`, `help` | 191–199 | `UE008`, `UE009`, `UE011`, `UE00C`, `UE00A`, `UE00B`, `UE012`, `UE013`, `UE014` |
| `alt-mode`, `mode-lock` | 211, 212 | `UE00F`, `UE010` |
| `roman-one`, `roman-two`, `roman-three`, `roman-four` | 218–221 | `U2160`–`U2163` |
| `finger-left`, `thumb-up`, `thumb-down`, `finger-right`, `repeat` | 222–226 | `U261A`, `U1F44D`, `U1F44E`, `U261B`, `UE00E` |
| `end` | 240 | `UE00D` |

- The common function output table is transcribed as one patch with precedence
  100. Its two activators, and the Advantage 360-only game layer, still need
  explicit patch-axis entry/exit behavior and precedence policy.
- The two primary files have the same 14 selected `tap-hold-release` aliases:
  the two case aliases, all five semantic modifier families, and the two
  function activators. Their exact positions, literal hold actions, and 200/200
  timings (250/250 only for `a → lmet`) are data-checked against the frozen
  sources in [manna-cadet-evidence-audit.md](manna-cadet-evidence-audit.md).
  The source does not pin a Kanata runtime or complete simultaneous-event
  policy, so no lifecycle equivalence is claimed.
- The older chorded files are excluded from the primary layered migration
  and remain regression evidence only.
- Direct `lshift` / `rshift`, `lctl`, and `rctl` now have separately modeled
  immediate held lifecycles. The two Shift holders use owner-scoped release so
  the first release does not clear the other holder; this is model/simulation
  evidence, not a complete historical-runtime equivalence claim. Delete/Enter
  are distinct 200 ms tap-holds and remain unresolved. Top with Greek still has
  unresolved consumed-modifier/application-state semantics for backend lowering.
- The selected Linux profile now maps every named symbol and command through
  its realization-owned vocabulary; the function activators and selector/
  modifier semantics remain unresolved.

See [manna-cadet-evidence-audit.md](manna-cadet-evidence-audit.md) for the
complete classification, including the old 45 ms chord variants and the
comment-only latch hypothesis.

No baseline file was edited and no device was deployed.
