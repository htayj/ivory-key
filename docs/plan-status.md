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
| 7 — full Manna Cadet migration | Complete; generated, not deployed | The frozen 52-key/eight-context table, 158 explicit `NoSymbol` cells, complete 68/72 native-route ledgers, reviewed C7/game differences, and typed-unreachable `<LSGT>` disposition are closed by the deterministic truth-table report. The selected profile covers four direct holders, all sixteen tap-holds, five modifiers, the function layer, selector carriers, A360 local keys, and 29 source-backed carrier allocations. Its per-plan dispatch barrier has immutable physical evidence, ordered repeated intervals, reverse-UP pairing, equal/unequal-deadline owners, deterministic peer commitment, and shared held-effect reference counts. Hash-pinned Kanata 1.12 tests cover the selected scheduler and generated A2/A360 artifacts; installed Kanata accepts both. Generated XKB contains 51 reviewed overrides, selector carriers, and distinct Control/Mod1/Mod2/Mod3/Mod4 mappings; libxkbcommon verifies all eight contexts, selector state, and effective unconsumed modifiers, and the Kanata-to-XKB AD01 differential passes. Normal project compilation now yields two exact artifacts, a relocatable source map, and 29 concrete provenance-bearing allocations. No abstract source embeds XKB or Kanata syntax. Live installation/input proof belongs exclusively to Phase 8. |
| 8 — controlled integration | Prepared, not authorized or started | The [controlled integration runbook](controlled-integration-runbook.md) defines entry gates, deterministic regeneration, a reversible transaction, live proof, and rollback evidence. Read-only `preflight-build` now checks a closed, bounded generated-contract shape, contained files, digests, provenance, and validation records under an explicit trusted-parent/non-atomicity boundary; it invokes no validator or service. No generated configuration has been installed or activated and no disposable/live device proof exists; execution still requires separate authorization. |
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
