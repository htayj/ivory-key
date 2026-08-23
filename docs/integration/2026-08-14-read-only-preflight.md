# Advantage360 controlled-integration preflight — 2026-08-14

This record is a read-only Phase 8 checkpoint for host `basedserv`. It is not
an installation, activation, live-input proof, or authorization to perform
one. No file, service, compositor input, or input event was changed while
collecting it.

## Current service and restoration baseline

- `kanata@advantage360.service` is enabled, active, and running as PID 1316.
- The unit is
  `/home/tay/.config/systemd/user/kanata@.service`, a link to
  `/home/tay/src/dotfiles/config/.config/systemd/user/kanata@.service`.
- `ExecStart` is `/home/tay/kanata-launch.sh advantage360`.
- The running executable resolves to `/usr/bin/kanata` and reports Kanata
  1.12.0.
- `/home/tay/kinesis.advantage360.layered.kanata.kbd` resolves to the frozen
  dotfiles configuration
  `/home/tay/src/dotfiles/keyboard/manna-cadet/kanata/kinesis.advantage360.layered.kanata.kbd`.
- Sway's active keymap file is
  `/home/tay/.config/sway/spacecadet.resolved.xkb`, resolving to
  `/home/tay/src/dotfiles/sway/.config/sway/spacecadet.resolved.xkb`.

The exact restoration hashes observed at this checkpoint are:

| Object | SHA-256 |
| --- | --- |
| frozen Advantage360 Kanata configuration | `632a7574938b535a8d4b1d2e3ce1c5f711d0486298d2ce4d98adda702496df5a` |
| `kanata-launch.sh` | `a32a428ac0a33ac1842d7c8268487e82d85837b64656d4a056eebd227d943d27` |
| `kanata@.service` | `4129ea451ff2d500651456bbc749e334c8aaff0f94381c012b664ccd197a5356` |
| resolved Sway XKB keymap | `64b76f3c7a5314fe1712c481211c7ef89b9a370f5ba636a0859046d7e3e1dbb5` |

Rollback must restore those exact link targets and hashes, restart only
`kanata@advantage360.service`, and reapply the recorded resolved Sway keymap to
the candidate virtual device. The independently running
`kanata@footswitches.service` is outside the transaction and must not be
restarted or altered.

## Current device state

The physical Advantage360 endpoint
`/dev/input/by-id/usb-Kinesis_Kinesis_Adv360_360555127546-if01-event-kbd`
is absent. The service journal records its removal at
`2026-08-12T22:43:26-04:00` and subsequent unsuccessful discovery checks.
Only a Blue Yeti input identity is currently present under
`/dev/input/by-id`.

The Kanata process remains active and Sway reports two keyboard inputs with
identifier `1:1:kanata`, name `kanata`, and layout `Space Cadet`. They cannot
be distinguished by the old shared virtual-device name. The generated
Advantage360 artifact instead declares the closed pair:

```text
linux-dev /dev/input/by-id/usb-Kinesis_Kinesis_Adv360_360555127546-if01-event-kbd
linux-output-device-name "ivory-key-manna-advantage360"
```

The output-name change must be proved after restart by observing the new
target-specific virtual device; this checkpoint does not infer that result.

## Generated candidate evidence

Two fresh generations for each composition were byte-identical. Read-only
preflight reported schema 5, 29 allocations, and no recorded validation claim;
the separate `validate-build` invocation then passed XKB and Kanata for each
candidate.

| Composition | mappings | `keymap.xkb` SHA-256 | `layout.kbd` SHA-256 |
| --- | ---: | --- | --- |
| `manna-cadet-linux` | 865 | `938188b67fc4d09273fd345d856526ecefe633cb09469eab94267efd748033d0` | `7bf48c77223bff2dcd74aa6fb6779cd21cec31565981ac55b51d20fb3bad692e` |
| `manna-cadet-advantage360-linux` | 873 | `09a5e399d5fa9b81e825ec182a2c3f1dcc5452dd819a998c87929adf13b1924d` | `9e744b8e5da6606cdf082e8fc1da1b50c4470017c4589df91c1487a27af4b6d5` |

These temporary build directories are validation evidence, not installation
sources. The authorized session must regenerate into a newly named trusted
staging parent and verify the hashes again immediately before switching.

## Remaining entry gates

The integration transaction remains blocked until all of the following are
true:

1. the staged Ivory Key commit is signed, pushed, and green in CI;
2. the physical Advantage360 endpoint is connected and its exact by-id name is
   re-observed;
3. the user explicitly authorizes the installation, restart, transient Sway
   keymap change, input capture, and rollback scope; and
4. fresh staging hashes match this generated candidate or any difference is
   reviewed before proceeding.

After authorization, follow the transaction and complete live matrix in the
[controlled integration runbook](../controlled-integration-runbook.md). The
first failed check enters rollback; it never authorizes editing generated
artifacts in place.
