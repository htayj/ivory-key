# Backend contract and fidelity

The backend protocol is intentionally separate from the semantic model. A
backend supplies structured capabilities, lowers a request to a backend plan,
emits deterministically to a stream, and may validate a written artifact.
External validation uses argument vectors through UIOP; it does not construct a
shell command string.

## Current request boundary

The implemented XKB and Kanata emitters consume a bootstrap
`lowering-request`, containing a layout name, key entries, optional modifiers,
optional interactions, and metadata. A key entry carries a logical position,
backend-specific physical-code mapping, and backend-specific output mapping.

This request is a backend API, not the abstract Ivory Key source model. It is
where current XKB key names and Kanata tokens enter the implementation. The
conservative compiler bridge derives it from a normalized layout plus explicit
topology/device/profile inputs only when every selected feature is exactly
representable. Callers must not interpret this bootstrap API as permission to
place backend spellings in `.ivory` layout meaning.

## Capability planner before target lowering

`plan-normalized-layout` is a separate target-neutral planning stage. It takes
a normalized layout and model device placement, preserves canonical static
table order, and produces a lowering plan with explicit selector,
semantic-modifier, and resource requirements. Resource inventories are copied
before physical inputs are reserved and requirements allocated, making the
allocation report deterministic and preventing a collision or exhaustion from
mutating the caller's inventory.

For a selected backend that advertises native keysym-table capacity, static
product tables at or below that finite capacity are graded `exact`. The current
XKB capability supplies the conventional eight-level case. A table with more
than eight states is retained in full and graded `unsupported` with an explicit
requirement for another target or a separately proven emulation. It is never
truncated, replaced with `NoSymbol`, or silently assigned to Kanata or QMK.
`require-planned-realizations` refuses that unproved plan. This planner records
requirements only; it does not itself emit Kanata, XKB, firmware, or a carrier
scheme.

## Fidelity grades and refusal

Each requested feature has one of these grades:

| Grade | Meaning |
| --- | --- |
| `exact` | Directly represents the requested behavior. |
| `emulated` | Observable behavior is exact through a backend mechanism. |
| `lossy` | Has a known difference and requires explicit permission. |
| `unsupported` | Cannot be realized by the selected backend/pipeline. |

`require-permitted-realizations` always refuses `unsupported`; it also refuses
`lossy` unless the caller passes an explicit `allow-lossy` policy. The current
two emitters produce direct mappings as `exact` and generic Kanata interactions
as `unsupported`; they do not yet implement an emulated or lossy lowering.
This refusal occurs before a combined pipeline result is returned and again
before direct plan emission.

## Current XKB contract

The XKB backend advertises conventional limits of eight levels, four groups,
the normal real-modifier slot names, and keysym/Unicode/modifier/group-selector
output features. It emits a self-contained `xkb_keymap` using `complete`
types/compatibility, `pc+us`, and `ONE_LEVEL`, `TWO_LEVEL`, `FOUR_LEVEL`, or
`EIGHT_LEVEL` according to each entry's output count. More than eight outputs
for one entry are classified as unsupported by this bootstrap backend.

Layout names may contain only alphanumeric characters, `_`, and `-`; key names
are one to four uppercase letters/digits; and keysyms allow only alphanumeric
characters, `_`, `+`, and `-`. Unsafe values are rejected before formatting.
This is an emission-safety boundary, not a substitute for semantic vocabulary
mapping.

## Current Kanata contract

The Kanata backend emits one `defsrc` and one `deflayer`; direct entries receive
an `exact` grade. Its capabilities advertise common tap/hold/layer/chord
features, but generic abstract interactions are deliberately classified as
unsupported until an explicit Kanata template lowering exists.

Layer names, source tokens, and output tokens must be non-empty ASCII strings
using only alphanumeric characters plus `_` and `-`. The same
check on the layer name is essential because it is written into the `deflayer`
header; unsafe input is rejected rather than becoming emitted Kanata syntax.

## Pipeline and validation evidence

`compile-xkb-kanata-request` lowers one request into `keymap.xkb` and
`layout.kbd` string artifacts after fidelity refusal. Artifact writes reject
absolute paths and parent traversal. The CLI compiler emits through a fresh
sibling directory derived from an exclusive random reservation, verifies the
physical parent and temporary contents, refuses an existing target, and
includes a realization report. Portable Common Lisp has no atomic
non-replacing directory rename or directory-descriptor API, so the output
parent must already exist and must not be concurrently writable by an
untrusted principal. `validate-pipeline-result` invokes `xkbcli
compile-keymap --keymap PATH` and `kanata --check -c PATH` when asked.

CLI inspection, explanation, and compilation may instead select a confined
project composition with `--project PROJECT --composition NAME`; this is an
input-selection mode, not deployment. Project mode does not mix independent
layout/device/profile paths with a composition.

Both `explain` input modes also print a target-neutral planner section with
canonical static-table counts, XKB table-capacity grades, and selector,
modifier, and resource obligations. That section is observational: the
unchanged direct emitter still independently refuses every unproved selector,
named output, modifier, or timed interaction.

Tool validation is optional environmental evidence. A passing `xkbcli` or
`kanata` invocation proves only the generated artifact was accepted by that
installed tool; it does not prove semantic equivalence, live device behavior,
or deployment. The current pipeline has no integrated carrier allocation,
machine-readable manifest, or source map. The planner can inspect and allocate
an explicitly provided resource inventory, but those allocations are not yet
wired into emitted pipeline artifacts.
