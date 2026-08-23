# basedbox Advantage360 Phase 8 integration — 2026-08-23

## Disposition

Accepted live deployment on `basedbox`.  This record captures the observed
integration evidence and the persistent managed configuration.  It does not
claim the project-wide completion rule yet: a rollback drill, publication of
the compatibility source changes, secret scan, signed commits, push, green CI,
and clean worktrees remain separate closeout gates.

## Target and generated inputs

| Item | Value |
| --- | --- |
| physical input | `/dev/input/by-id/usb-Kinesis_Kinesis_Adv360_360555127546-if01-event-kbd` → `/dev/input/event2` |
| managed service | Shepherd `kanata-advantage360` |
| pinned runtime | Kanata 1.12.0, launched from `/gnu/store/110r7g65mg4a8kc6hml8fvvi8nmkap7h-kanata-1.12.0/bin/kanata` |
| source commit at staging | `3245e1537d5636c4d65fe720e9df4b462418aa71` |
| deployed compatibility source commit | `6aa8f2c` (`fix: preserve distinct Manna modifier routes`) |
| selected composition | `manna-cadet-advantage360-linux` |
| Kanata artifact SHA-256 | `9e744b8e5da6606cdf082e8fc1da1b50c4470017c4589df91c1487a27af4b6d5` |
| XKB artifact SHA-256 | `06829f3fe54c661e530188bc6738311ce7ab0b2e1c117cfb920d07c658213935` |

The build passed `preflight-build`, `validate-build`, XKB validation, and
Kanata validation before activation.  The source/compiler regression suite
passed 291 tests after the basedbox modifier compatibility correction.

## Transaction

1. Staged and validated the A360 output under
   `~/.local/state/ivory-key/phase8-3245e15/`.
2. Started a disposable Kanata 1.12 candidate with the stable A360 input
   endpoint and applied its XKB map to `:0`.
3. Detected that inherited `pc+us` modifier memberships caused StumpWM to
   classify the thumb Alt route as Meta.  The persistent XKB reload helper now
   installs the explicit X modifier allocation and asks StumpWM to refresh its
   modifier map:
   Alt/Meta/Super/Hyper = Mod1/Mod3/Mod4/Mod2.
4. Installed the finalized generated Kanata and XKB artifacts through Guix
   Home, with the service using the local hash-pinned Kanata 1.12 package.
5. Stopped the disposable candidate and restarted only
   `kanata-advantage360`; it now owns the physical input.  The
   `kanata-footswitches` service was not restarted.

## Live acceptance evidence

Observed interactively by the authorized operator on the active desktop:

| Surface | Result |
| --- | --- |
| ordinary letters | accepted |
| Greek and Top | accepted |
| Control, Meta, thumb Alt, Super, Hyper | accepted |
| modifier release/no-stuck behavior | accepted |
| `Home`, `PgUp`, `PgDn` taps | accepted as named keys |
| `End` tap | accepted as the selected semantic `end` command, private-use `U+E00D` |
| hold `End` or `PgDn` plus `1` | accepted; emits `Ⅰ` |

The virtual-device trace independently observed `KEY_RIGHTALT` while the thumb
Alt route was held.  X input observed its chord with effective Mod1, and the
running StumpWM session reported `(:MOD-1)`, `(:MOD-3)`, `(:MOD-4)`, and
`(:MOD-2)` for Alt, Meta, Super, and Hyper respectively.

## Rollback status

The pre-activation store-backed Home configuration and the disposable staged
candidate were retained during the transaction.  No rollback was required and
no rollback drill was performed after acceptance.  A future final-closeout
record must either exercise and restore the rollback path or explicitly obtain
approval to retain this accepted deployment without that drill.

## Publication status

The live configuration is durable through the active Guix Home generation.
The compatibility source is committed; this evidence record still requires its
own signed publication, CI result, and a clean-worktree audit.  The
documentation must not describe Phase 8 as project-complete until those and
the rollback gate are closed.
