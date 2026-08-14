# QMK backend validation evidence

This record distinguishes hermetic emitter tests, environmental firmware
compilation, and hardware deployment. It is evidence for the QMK backend's
current one-key static slice only.

## 2026-08-14 QMK API firmware build

Ivory Key emitted QMK Configurator JSON through `make-qmk-backend`,
`lower-request`, and `emit-plan` for the published QMK keyboard `1k`, layout
`LAYOUT_ortho_1x1`, with one `KC_A` key. The exact generated JSON had SHA-256:

```text
2d8f1fe44e83a6447c4de508b6ed166be5ad37b05ecf4f084001116c9b710a26
```

The target metadata came from QMK's published keyboard metadata endpoint,
whose response identified keyboard `1k`, the one-position layout, and an AVR
`attiny85` target. The generated document was submitted to the official QMK
compile API. Job `11740af6-9c4a-4247-a7d2-552b09047fb0` finished with
`is_failed: false`, compiler return code `0`, and firmware filename
`1k_ivory_key.hex`. The build log showed generation of `keymap.c`, compilation
with AVR GCC, successful linking, and a firmware-size check.

Authoritative service endpoints used for this evidence:

- `https://keyboards.qmk.fm/v1/keyboards/1k/info.json`
- `https://api.qmk.fm/v1/compile/11740af6-9c4a-4247-a7d2-552b09047fb0`

The service may eventually expire job artifacts, so the generated-content
hash and hermetic golden test are the durable local evidence. This validation
does not prove multi-key matrix placement, multiple firmware layers, semantic
modifiers, timed interactions, Manna Cadet equivalence, flashing, or live
keyboard behavior. No firmware was downloaded or flashed during this check.
