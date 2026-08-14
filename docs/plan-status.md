# PLAN.md completion audit

This is a living requirement-to-evidence audit for [PLAN.md](../PLAN.md). A
green unit-test suite proves only the implemented slice; it does not turn a
partial phase into a completed phase. Status changes require the named exit
criterion's direct evidence.

## Phase status

| Phase | Current disposition | Direct evidence and remaining gate |
| --- | --- | --- |
| 0 — language RFC and frozen fixtures | Complete | [V1 normative reference](language-reference-v1.md) gives a closed disposition for every representative §5.2 form, including reserved/refused forms. The frozen inventory and static digest are reviewable, and [ADR 0002](decisions/0002-v1-policy-defaults.md) records every §16 content choice as an explicit, revisitable policy rather than leaving it implicit. |
| 1 — project bootstrap | Complete | `ivory-key`, `ivory-key/cli`, and `ivory-key/tests` load through ASDF; the runtime core depends only on UIOP. `manifest.scm` and `.envrc` provide a reproducible Guix/direnv environment, and [development conventions](development.md) define Common Lisp style, formatting, hermetic checks, and separately tagged environmental validation. |
| 2 — syntax frontend | Complete | Safe lexer/parser diagnostics, resource limits, spans, deterministic fuzz smoke, formatter round-trip/idempotence, project imports, and CLI syntax commands are covered by the hermetic suite without host reader evaluation. |
| 3 — semantic model and normalization | Complete for the named exit fixtures | Eight-state, twenty-state, dependency-scoped latch, seventy-modifier, incomplete-table, inheritance-cycle, overlay, and finite-template fixtures have direct tests and stable refusals. Definition and ordered nested-use spans survive template expansion and normalization without a global provenance table. |
| 4 — reference event simulator | Complete for the selected V1 arbitration policy | The registered temporal matrix covers clocks, commitment, priority, effects, ownership, anchor-time `context-is`, overlays, latch consumption, tap/hold boundaries, rolling release order, and normative refusals. Every output and held-state transition carries closed provenance for its source pattern, candidate transition, commit point, and responsible effect; terminal effects cannot re-enter after exit/cancellation. Both model and raw simulator IR refuse `longest-match`, whose comparison/latency scheduler remains deliberately unselected. |
| 5 — backend protocol and capability planner | Complete | CLOS protocols, structured capability categories, resource pools, pipeline IR, grades, deterministic static and multibank planning, allocation reports, collision/exhaustion, `explain`, and deterministic non-emitting `planned`/`backend` IR dumps are implemented. Unsupported capability fields remain explicitly empty rather than inheriting native-platform features. A fake constrained backend exercises real exact/emulated/lossy/unsupported lowering paths, and focused tests cover every named exit path. |
| 6 — XKB and Kanata emitters | Complete for the declared capability boundary | Direct static emitters, safe artifact writing, allocation/source maps, generated contracts, staged validation-before-publication, and installed-tool acceptance are covered. A hermetic differential matches reference output and exact event order for the supported direct Unicode path, and exercises levels, modifiers, single/multi-participant interactions, staged durations, overlays, behavioral latches, and latch consumption by requiring explicit backend/compiler refusal wherever no exact lowering exists. The separately tagged public-compiler probe passes staged `xkbcli` and Kanata validation under SBCL and ECL; its compiled-state helper also verifies the focused XKB group's levels, symbols, lack of explicit actions, Shift selection, and consumed versus unconsumed modifier state through libxkbcommon APIs. |
| 7 — full Manna Cadet migration | In progress, not migration-complete | The frozen 52-key/eight-context table, 158 explicit `NoSymbol` cells, both device placements, 29-output function patch, realization vocabulary, deterministic carrier proposal, and four direct case/Greek/Top holders are transcribed and model-simulated with owner-scoped release. The generated frozen diff classifies all 52 tables/416 cells, both function placements, four selectors, all active primary aliases and layer memberships, and every known refusal/variant with `Unchecked differences: 0`. A hash-pinned [Kanata 1.12 source-state-machine oracle](kanata-1.12-oracle.md) proves the actual five modifier pairs and final-owner function lifetime, while also proving that pending foreign events are delayed—contradicting [ADR 0003](decisions/0003-manna-release-trigger-v1.md)'s proposed no-delay route. That profile choice remains explicit and unselected. A closed selector-policy schema exposes Group1/Group2 types, native mechanisms, client semantics, and carriers, but only an explicit unproved Group2 disposition is admitted, so public compilation correctly refuses. See [Manna evidence audit](manna-cadet-evidence-audit.md). The 14 historical tap-holds and five semantic modifiers still lack a selected abstract/backend compatibility policy; `<LSGT>` placement, function activation/arbitration, selected 360 compatibility policy, exact native selector lowering, and generated-backend event-level proof also remain. |
| 8 — controlled integration | Prepared, not authorized or started | The [controlled integration runbook](controlled-integration-runbook.md) defines entry gates, deterministic regeneration, a reversible transaction, live proof, and rollback evidence. No generated configuration has been installed or activated and no disposable/live device proof exists; execution still requires separate authorization. |
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
