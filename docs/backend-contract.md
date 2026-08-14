# Backend contract and fidelity

The backend protocol is intentionally separate from the semantic model. A
backend supplies structured capabilities, lowers a request to a backend plan,
emits deterministically to a stream, and may validate a written artifact.
External validation uses argument vectors through UIOP; it does not construct a
shell command string.

The capability record has separate fields for input identities, native level
and group limits, real and virtual modifier resources, context-axis and patch
operations, resolution styles, timed-pattern/clock/lifecycle/arbitration
semantics, output mechanisms, carrier channels, validation programs, and
platform assumptions. An empty field means no implementation is claimed; a
platform feature is not automatically an Ivory Key capability.

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

That binding-table grade is deliberately narrow. Every context selector,
semantic modifier, multi-bank selector, timed interaction, and resource
requirement receives its own realization result. Each is currently
`unsupported` until a backend-specific lowering proves it independently, even
when the associated static table fits in one native bank.
`require-planned-realizations` rejects a plan containing any such unresolved
obligation; an exact binding table never promotes the rest of the plan to
exactness.

For a static table larger than one native level bank, the planner also records
a deterministic contiguous multi-bank partition, context-to-bank/level
assignments, and bank-selector/carrier resource obligations. Twenty states at
eight levels become `8+8+4`; forty states require five banks and exceed the
advertised four-group capacity. Both remain unsupported because capacity is
not a proof of runtime bank selection.

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

## Typed native-selector policy boundary

A realization may declare a closed `selector-policy`; this is model data, not
an XKB or Kanata snippet. Its current source clauses are:

```lisp
(selector-policy
  (static-type POSITION four-level|four-level-alphabetic two-level)
  (selector AXIS STATE shift|level-three|group-two
            consumed|group-action
            core-shift|consumed-level-three|
            libxkbcommon-depressed-group-two-with-visible-level-three|
            unproved-group-two)
  (carrier POSITION AXIS STATE 84|85 lvl3|zeha))
```

The decoder accepts identifiers and integers only. Constructors validate the
closed enums, require the historical Group 1 and Group 2 table shapes, reject
duplicate owners/resources, and admit only the source-recorded `85`/`ZEHA`
and `84`/`LVL3` carrier pairs. Those pairs preserve frozen source vocabulary;
they are not themselves proof that a compiled XKB keymap has a carrier for
either selector. Programmatic policy objects are revalidated at the compiler
boundary.

`unproved-group-two` remains inspection-only and is graded unsupported. The
long evidence-named value is narrower: it may grade **only the generated XKB
sub-contract** exact after all of the following are present: exactly the three
binary Shift/Level3/Group2 contexts, a static-type declaration covering every
emitted eight-cell selector table, and the two collision-free carriers `84 →
<LVL3>=92` and `85 → <ZEHA>=93`. A declared static type with no emitted entry
is refused unless the request contains exactly one typed `input_coverage`
record naming that same logical position as `unreachable`; this records an
already reviewed physical absence and never invents a placement. It emits
Group 1 as `FOUR_LEVEL` or `FOUR_LEVEL_ALPHABETIC`, Group 2 as `TWO_LEVEL`,
removes pc's inherited Mod5 map from `<LVL3>`, and maps only `<ZEHA>` to Mod5.
It has no generated `<LVL5>` override or selected device mapping; any inherited
`pc+us` LVL5/ISO_Level5_Shift/Mod3 behavior is outside this selected input
domain. Frozen-map LVL5 observations are likewise outside this selected
contract.

The separately tagged external probe runs both permitted Group 1 types against
libxkbcommon. It proves for the **generated artifact** that Group2 is
depressed/serialized, Group1 Level3 is effective then consumed, Group2 Level3
is effective and remains client-visible/unconsumed, and Group2 Shift is
effective then consumed. It covers ZEHA down/up and ZEHA+LVL3 in both press
orders. This is not historical Manna equivalence, Kanata event proof, client
protocol proof, compositor proof, or live-device proof. The compiler retains
an explicit `unsupported-kanata-selector-action-plan` refusal, and the Kanata
backend independently refuses selector metadata; semantic tap-holds and
generic interactions remain independent refusals.

The same tagged probe also emits the selected Manna Cadet XKB partial request
from project analysis and runs it through the state checks. That request has
52 hash-pinned source type declarations, 51 generated Manna selector
overrides, and the two carrier keys; its sole omitted type is `less-greater`,
whose two device records explicitly declare it unreachable because neither
reviewed primary `defsrc` contains a direct source token. Because the partial
map includes `pc+us`, compiled `<LSGT>` still has the inherited default keycode
and less/greater behavior. It is outside the selected device-input domain and
is not the frozen Manna eight-state table. This validates the generated XKB
sub-contract only. The combined compiler still refuses its Kanata selector
action/lifetime and the other unresolved Manna features before any artifact
write.

## Typed interaction-compatibility selection

A realization can opt into exactly one bounded Manna/Kanata policy value for
an explicit nonempty set of concrete interaction instances:

```lisp
(interaction-compatibility modern-no-delay
  (instances tap-hold-super-a tap-hold-function-end))
```

The closed modes are `modern-no-delay` and `kanata-1-12-buffered`. Omission is
an explicit unselected state, not a backend default. Instance identities are
canonicalized as an unordered set, so declaration order cannot imply candidate
priority. Every named instance must exist after layout normalization; unknown
names refuse. Unlisted interactions retain only the target-generic timed
interaction refusal and never acquire a Manna-specific requirement merely by
existing.

The former profile-wide two-atom spelling, `(interaction-compatibility MODE)`,
is an intentional migration checkpoint failure. It never means “all
interactions”; update a future profile with an explicit `(instances ...)` set
only after naming the reviewed concrete instances.

The selection is carried as typed model metadata so `planned`, `backend`, and
`explain` output can identify the intended contract. The modern route is
unsupported because Kanata 1.12 buffers and redispatches pending foreign input,
contrary to its no-delay rule. The versioned buffered route has a closed,
derived normalized contract and a bounded reference dispatch transaction.
That reference route can resolve an explicitly selected owner's ordinary tap
binding and an unpatched foreign output table at the eventual dispatch
frontier. Every possible table value must be text, a named key, a named symbol,
or `none`; commands, state changes, overlays, and timed re-entry still refuse.

A buffered realization may additionally describe the backend atoms needed by
the existing non-emitting Kanata action IR:

```lisp
(kanata-buffered-allocations
  (route b b)
  (action tap-hold-case-f
    (tap f)
    (hold axis-modifier case shifted lshift)
    (routes b)))
```

`route` associates one admitted logical position with one opaque Kanata token.
An `action` names one selected interaction, its tap token, one typed hold, and
a nonempty set of declared route positions. The closed hold forms are
`(hold modifier MODIFIER TOKEN)`,
`(hold axis-modifier AXIS STATE TOKEN)`, and
`(hold axis-layer AXIS STATE LAYER TOKEN)`. The allocation action set must
equal the compatibility instance set exactly. Tokens are validated as single
atoms; this surface cannot contain an alias body, S-expression action, or
configuration fragment.

The current compiler handoff constructs a backend route only when that
position is one context-free named-key binding. The broader output-table route
above is reference semantics awaiting the Kanata-to-XKB pipeline differential;
it cannot yet populate an action allocation or clear a backend refusal.

These allocations authorize inspection only. The compiler may construct the
typed action values, but it retains
`unproved-kanata-buffered-pending-lifecycle`; Kanata grades the actions
unsupported and emission refuses. Named instances receive the mode-specific
refusal, all other interactions retain the generic refusal, and no raw
`tap-hold-release` text is inferred. Positive realization remains prohibited
until native queue/cancellation coverage and a generated Kanata-to-XKB
differential prove the complete selected input domain.

## Current Kanata contract

The Kanata backend emits one `defsrc` and one `deflayer`; direct entries receive
an `exact` grade. Although native Kanata has tap/hold/layer/chord mechanisms,
this backend advertises no abstract interaction, clock, or lifecycle capability
until an explicit closed template lowering proves the semantics. Generic
abstract interactions are therefore classified as unsupported.

Layer names, source tokens, and output tokens must be non-empty ASCII strings
using only alphanumeric characters plus `_` and `-`. The same
check on the layer name is essential because it is written into the `deflayer`
header; unsafe input is rejected rather than becoming emitted Kanata syntax.

## QMK firmware backend contract

The QMK backend is a separate implementation of the same CLOS backend
protocol; it does not add a QMK form to the abstract layout language. Its
current exact slice emits deterministic QMK Configurator JSON for one static
base layer. A realization must explicitly provide the QMK keyboard,
layout macro, and complete physical-position order. Every position must have
exactly one opaque QMK keycode identifier. Although QMK itself supports more
layers, the backend refuses them until an abstract selector has a proven QMK
activation policy. Successful target compilation is still required. The backend refuses
implicit matrix ordering, arbitrary C expressions, semantic modifiers, and
timed interactions instead of guessing firmware policy.

`validate-artifact` invokes `qmk compile /ABSOLUTE/FILE.json` as an argument
vector; the absolute positional path cannot be parsed as an option. Per
QMK's CLI contract, this is a real firmware compilation and therefore requires
an installed QMK CLI with a configured firmware checkout. The hermetic suite
proves deterministic emission, injection refusal, explicit ordering, fidelity
refusal, and base-layer ordering agreement with the XKB backend; an
environmental firmware build remains separate evidence.

The first environmental build of an Ivory Key generated one-key artifact is
recorded in [QMK backend validation evidence](qmk-validation.md). It completed
successfully through the official QMK compile service; no firmware was flashed.

This backend establishes the Phase 9 extension boundary, but it is not yet a
compiler-selected realization profile and does not claim that Manna Cadet is
realizable in QMK.

## Pipeline and validation evidence

`compile-xkb-kanata-request` lowers one request into `keymap.xkb` and
`layout.kbd` string artifacts after fidelity refusal. Artifact writes reject
absolute paths and parent traversal. The CLI compiler emits through a fresh
sibling directory derived from an exclusive random reservation, verifies the
physical parent and temporary contents, refuses an existing target, and
includes a deterministic generated-output contract. `manifest.json` records
the language/compiler versions, selected declarations, relocatable source
identities and SHA-256 hashes, backend artifact hashes, fidelity grades, and
the closed per-topology-position `input_coverage` disposition (`physical` or
`unreachable`). A missing coverage record is an exact-lowering refusal, never
an implied unreachable position. This shape is generated-contract schema
version 5. Schema version 2 introduced `input_coverage`, a deterministic
topology disposition inventory independent of backend carrier allocations;
version 4 adds the closed, privacy-preserving validation-evidence records
described below; version 5 adds typed provenance. Virtual backend carriers
remain separate allocations, not input coverage.
`source-map.json` gives every emitted direct mapping an `origin`: either
`null` for deliberately programmatic IR, or a relocatable source identity with
definition line/column and an ordered definition-nearest-to-outermost
`template_uses` list. `allocations.json` similarly records the complete
`origins` list for each concrete allocation, since one finite resource can
serve several equal normalized uses. The compiler resolves parser source names
only through its declared `(identity . pathname)` inputs; physical names are
not serialized, and non-NIL unmapped or ambiguous origins refuse publication.
Header-only imported project modules are included in that input inventory.

Portable Common Lisp has no atomic
non-replacing directory rename or directory-descriptor API, so the output
parent must already exist and must not be concurrently writable by an
untrusted principal. Regular compilation is tool-free. Explicit
`compile --validate-before-publish` validates each emitted artifact in that
trusted staging directory before the final non-replacing rename. It invokes
`xkbcli compile-keymap --keymap PATH` and `kanata --check -c PATH` as UIOP
argument vectors (never a shell command), probes each validator with its
direct `--version` argument vector, and re-hashes every artifact after
validation. A changed artifact, unavailable validator, failed validation, or
incomplete validator coverage refuses publication; the requested output path
is never created. The retained private staging directory contains the failed
contract/report for inspection.

On an all-passing opt-in run, the immutable public contract contains one
canonical validation record per artifact: its artifact-relative identity, tool,
normalized single-line version, status, and SHA-256 digests of the raw version
and validator-result byte streams. It deliberately does not publish randomized
staging paths or raw tool chatter. Ordinary compilation omits the `validation`
member entirely. `validate-build DIRECTORY` remains the distinct, read-only
post-build observation mode: it may report artifact acceptance, but never
retroactively changes an already-published contract.

The separately tagged `tests/external/xkb-kanata.lisp` probe additionally
compiles a focused supported XKB plan and inspects the compiled result through
libxkbcommon's keymap and state APIs. It verifies one group, the exact level
and symbol tables, absence of explicit per-key actions, Shift selection of a
two-level key, Shift consumption for that key, and preservation of
application-visible unconsumed Shift for a one-level key. The helper is built
inside the declared Guix environment from `tests/external/xkb-state.c`; it is
environmental evidence and remains outside the hermetic ASDF suite.

`tests/external/manna-xkb-group2-state.lisp` is a separately tagged, read-only
pair of probes. Run it in the declared environment with:

```sh
direnv exec . sbcl --script tests/external/manna-xkb-group2-state.lisp \
  /home/tay/src/dotfiles/keyboard/manna-cadet
```

The first mode verifies the hash-addressed frozen XKB/primary-Kanata inputs,
compiles the frozen keymap with its source include directory, and uses only
keymap/state APIs. In the declared Guix environment, where xkeyboard-config
2.44 with libxkbcommon/xkbcli 1.11.0 has no `ZEHA` in
`evdev+aliases(qwerty)`, it proves the frozen `AD01`
four-level Group 1/two-level Group 2 table, LVL3/LVL5 Group2 serialization,
and consumed Group2 Shift. Therefore that frozen mode cannot observe Greek or
Greek+Top event state. This host's xkeyboard-config 2.48-1 paired with
libxkbcommon 1.13.2 supplies `ZEHA=93` through the newer standard `evdev`
include; that divergent xkeyboard-config data is deliberately not treated as
evidence for the pinned Guix claim.

The second mode emits the closed Ivory Key map then checks its generated state
contract described above. Explicit `<ZEHA>=93` makes that test independent of
the host's pre-existing keycode name. Neither ordinary mode establishes how
frozen Kanata code 85 reaches XKB. The opt-in differential below covers only
its closed AD01 records; arbitrary routes, client protocol, compositor,
live-device, and historical migration equivalence remain explicit refusal
boundaries.

An additional opt-in `--kanata-ad01-differential` mode invokes the separately
hash-gated Kanata 1.12 oracle, extracts only its closed eight tagged AD01 edge
records, and applies those edges to the generated 51-override Manna XKB map.
Its C boundary admits only `F`, `LShift`, `Q`, and carrier codes 84/85; it
checks exact symbol, group, effective/consumed modifiers at Q-down (including
Group1 alphabetic Shift/Lock/LevelThree versus Group2 Shift consumption) and complete
terminal settling. This is a composed environmental sub-contract, not a
compiler capability, selected profile, emission permission, or whole-layout
differential.

CLI inspection, explanation, and compilation may instead select a confined
project composition with `--project PROJECT --composition NAME`; this is an
input-selection mode, not deployment. Project mode does not mix independent
layout/device/profile paths with a composition.

Both `explain` input modes also print a target-neutral planner section with
canonical static-table counts, XKB table-capacity grades, and selector,
modifier, and resource obligations. That section is observational: the
unchanged direct emitter still independently refuses every unproved selector,
named output, modifier, or timed interaction.

For tables larger than one native bank, that report includes deterministic
bank sizes, complete context-to-bank/level assignments, advertised-capacity
status, and explicit bank-selector/carrier needs. These are planning facts,
not an XKB group-selection implementation.

In project mode, a realization-owned output vocabulary can make a static typed
named key or named symbol exact by supplying both XKB and Kanata spellings.
Analysis and compilation use the same vocabulary-aware path. Missing mappings,
commands without an approved semantic lowering, profile/backend mismatches,
and tokens rejected by an existing backend validator stop before build output.

Tool validation is optional environmental evidence. A passing `xkbcli` or
`kanata` invocation alone proves only artifact acceptance. The focused
libxkbcommon probe proves only the direct XKB level/modifier slice it inspects;
neither result proves Manna semantic equivalence, live device behavior, or
deployment. The Manna inspection path can construct a deterministic partial
static/function-carrier proposal, but public compilation refuses before writing
it because selector, modifier, interaction, placement, and activation proof is
incomplete. An empty allocation contract in the supported direct-static path
does not imply that those Manna obligations disappeared. Validation run after
publication is reported by the post-build validator but does not retroactively
rewrite an immutable build manifest.
