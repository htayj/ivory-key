# PLAN.md completion audit

This is a living requirement-to-evidence audit for [PLAN.md](../PLAN.md). A
green unit-test suite proves only the implemented slice; it does not turn a
partial phase into a completed phase. Status changes require the named exit
criterion's direct evidence.

## Phase status

| Phase | Current disposition | Direct evidence and remaining gate |
| --- | --- | --- |
| 0 — language RFC and frozen fixtures | Complete | [V1 normative reference](language-reference-v1.md) gives a closed disposition for every representative §5.2 form, including reserved/refused forms. The frozen inventory and static digest are reviewable, and [ADR 0002](decisions/0002-v1-policy-defaults.md) records every §16 content choice as an explicit, revisitable policy rather than leaving it implicit. |
| 1 — project bootstrap | Complete | `ivory-key`, `ivory-key/cli`, and `ivory-key/tests` load through ASDF; the runtime core depends only on UIOP. `manifest.scm` and `.envrc` provide a reproducible Guix/direnv environment. |
| 2 — syntax frontend | Complete | Safe lexer/parser diagnostics, resource limits, spans, deterministic fuzz smoke, formatter round-trip/idempotence, project imports, and CLI syntax commands are covered by the hermetic suite without host reader evaluation. |
| 3 — semantic model and normalization | Complete for the named exit fixtures | Eight-state, twenty-state, dependency-scoped latch, seventy-modifier, incomplete-table, inheritance-cycle, overlay, and finite-template fixtures have direct tests and stable refusals. |
| 4 — reference event simulator | In progress | The registered temporal matrix now covers clocks, commitment, priority, effects, ownership, context snapshots, overlays, latch consumption, tap/hold boundaries, rolling release order, and normative refusals. Traces retain interaction/case/candidate identity, but still need direct source-pattern and effect provenance for every output or held state to meet the exit criterion. |
| 5 — backend protocol and capability planner | Complete | CLOS protocols, resource pools, pipeline IR, grades, deterministic static and multibank planning, allocation reports, collision/exhaustion, and `explain` are implemented. A fake constrained backend exercises real exact/emulated/lossy/unsupported lowering paths, and focused tests cover every named exit path. |
| 6 — XKB and Kanata emitters | In progress | Direct static emitters, safe artifact writing, generated contracts, and installed-tool acceptance exist. The separate external probe compiles through the public compiler and passes `xkbcli` and Kanata. The required simulator-to-backend differential categories and complete selector/modifier/carrier lowering are not yet proven. |
| 7 — full Manna Cadet migration | In progress, not migration-complete | The frozen 52-key/eight-context table, 158 explicit `NoSymbol` cells, both device placements, 29-output function patch, realization vocabulary, and deterministic Linux carrier proposal are transcribed and audited. The proposal passes XKB/Kanata validation but public compilation correctly refuses it. See [Manna evidence audit](manna-cadet-evidence-audit.md). Timed selectors and five semantic modifiers, `<LSGT>` placement, function activation/arbitration, game/chord variants, complete simulation, and generated diff review remain. |
| 8 — controlled integration | Not started | No generated configuration has been installed or activated and no disposable/live device proof exists. This phase requires separate authorization, rollback, regeneration documentation, and live event evidence. |
| 9 — future backend | Complete for the planned QMK extension slice | A separate QMK backend implements capabilities, exact one-layer lowering, deterministic Configurator JSON emission, real compile validation, security refusals, and a base-layer XKB/QMK ordering differential without adding backend syntax to the abstract language. Multi-layer plans fail closed until a selector policy exists. The official QMK compile service successfully built the generated one-key artifact; see [QMK validation evidence](qmk-validation.md). |

## Completion rule

The entire plan is complete only when every row is complete and the final
audit can point to all of the following without inference:

1. full hermetic SBCL and ECL suites in the checked-in Guix environment;
2. separately tagged installed-tool and firmware validation;
3. a generated, reviewed Manna build whose manifest accounts for every source,
   allocation, grade, and behavior difference;
4. reference-versus-backend differential proof for every Phase 6 category;
5. separately authorized installation with rollback and live input proof; and
6. a clean exact commit, secret scan, pushed remote, and green CI.

Until those gates are met, documentation must continue to say which subset was
proved and which requirement refused; no narrower checkpoint is called the
entire plan.
