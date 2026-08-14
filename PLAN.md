# Ivory Key: implementation plan

Status: plan only. This document does not authorize implementation, migration,
deployment, or replacement of the currently active keyboard configuration.

License: GNU General Public License, version 3 or later
(`GPL-3.0-or-later`). See `LICENSE`.

## 1. Goal

Build a Common Lisp system with a Lisp-shaped, declarative keyboard language
for describing the *meaning* of a keyboard layout without inheriting limits
from XKB, Kanata, QMK, a particular physical keyboard, or today's operating
systems. The first complete layout will be Manna Cadet. The first realization
pipeline will target Linux through generated Kanata and XKB configuration.

The abstract source must remain the sole authority for layout meaning. Backend
files are generated artifacts. Any workaround required by XKB modifier slots,
XKB groups or levels, evdev keycodes, Kanata carrier keys, or future firmware
must live in a realization profile or a backend compiler, never in the abstract
layout.

The system must be able to represent, validate, inspect, and simulate layouts
with any finite number of level states and semantic modifiers that available
memory permits. In particular, no IR field may encode selectors or modifiers
in a fixed-width host integer merely because a current backend uses a bitmask.

## 2. Evidence from the current Manna Cadet implementation

The migration baseline is the `manna-cadet` submodule at commit
`e5f7e81cdb6e30a7735cdcab622ede29007e379b` under the dotfiles checkout:

- `/home/tay/src/dotfiles/keyboard/manna-cadet/xkb/symbols/spacecadet`
- `/home/tay/src/dotfiles/keyboard/manna-cadet/xkb/keymap/spacecadet.xkb`
- `/home/tay/src/dotfiles/keyboard/manna-cadet/kanata/kinesis.advantage2.layered.kanata.kbd`
- `/home/tay/src/dotfiles/keyboard/manna-cadet/kanata/kinesis.advantage360.layered.kanata.kbd`
- `/home/tay/src/dotfiles/keyboard/manna-cadet/space-cadet-layered-mnemonics.md`

These files currently divide a single design among several mechanisms:

- Kanata knows physical source positions, home-row tap-holds, thumb holds,
  the `fun` and `game` layers, chords or held layers, and arbitrary evdev
  carrier codes.
- XKB knows Roman, shifted, Greek, shifted-Greek, and Top symbol meanings,
  private-use command keysyms, modifier-slot assignments, and how a carrier
  changes group or level.
- Comments and mnemonic documentation carry additional intent that is not
  machine-checkable.

The current XKB layout realizes base/Shift/Greek/Shift+Greek as four levels in
group 1 and Top/Shift+Top as two levels in group 2. It explicitly chose groups
instead of an `EIGHT_LEVEL` type to free a real modifier slot. That is a valid
backend workaround, but it must not define the new abstract model.

The installed XKB `EIGHT_LEVEL` type confirms the conventional eight-state
ordering. With Manna Cadet names it is:

| Abstract level number | Active selectors |
| --- | --- |
| 1 | normal |
| 2 | Shift |
| 3 | Greek |
| 4 | Greek + Shift |
| 5 | Top |
| 6 | Top + Shift |
| 7 | Top + Greek |
| 8 | Top + Greek + Shift |

This ordering is the Cartesian-product ordering in which the first declared
axis varies fastest. It will be a language convention and a formatter/display
convention, not an XKB limit.

Eight is not a universal XKB text-format ceiling: current libxkbcommon
documentation permits level numbers greater than eight. Eight is the size of
the conventional `EIGHT_LEVEL` types and the natural product of Shift,
LevelThree, and LevelFive. Actual capacity is constrained by key types,
available modifier state, groups, client behavior, and the rest of the selected
pipeline. The capability probe and realization profile must describe those
facts precisely instead of hard-coding “XKB supports eight” into the compiler.

Before migration begins, re-record the source commit, file hashes, installed
`sbcl`, `kanata`, and `xkbcli` versions, and compiled behavior. The versions
observed while writing this plan were SBCL 2.6.7, Kanata 1.12.0, and xkbcli
1.13.2; they are evidence for this plan, not permanent project requirements.

## 3. Architectural boundaries

The project will keep four concepts separate.

### 3.1 Abstract layout

The abstract layout defines semantic positions, context axes, modifier names,
bindings, overlays, and timed interactions. It may say that holding a
position selects Greek, that tapping another emits Backspace while holding it
asserts Alt, that a latched `shift-latch` axis changes the next shift key into
a latching shift, or that a two-position combo invokes `stop-output`. It may
not say `Mod5`, `<ZEHA>`, evdev code 85, `UE007`, `arbitrary-code`, or
`SetGroup`.

### 3.2 Topology and physical-device placement

A topology gives stable logical position identifiers and optional drawing
metadata. A device placement maps those positions to physical inputs for a
particular board and firmware profile. Kinesis Advantage 2 and Advantage 360
placements will be separate even where they share the same Manna Cadet layout.

Geometry is descriptive, not semantic: coordinates help diagrams and
same-hand policies but never determine the meaning of a binding implicitly.

### 3.3 Realization profile

A realization profile selects an ordered pipeline of actual systems and states
which compromises are permitted. The first profile will combine Kanata and
XKB. It owns such details as available carrier keycodes, XKB real-modifier slot
allocation, use of groups versus levels, private-use keysyms, device paths,
timing overrides, and whether a specific approximation is acceptable.

Adding QMK later means adding a QMK backend and selecting it in a profile. The
compiler must never assume authority to flash firmware merely because QMK
would solve a resource shortage.

### 3.4 Generated artifacts and deployment

Compilation writes a self-contained output directory. Deployment is a later,
separate operation. A successful parse, a successful compile, successful
backend validation, installation, and live input behavior are distinct proof
levels and must be reported separately.

## 4. Semantic model

### 4.1 Context axes and dependency-scoped state

A context axis is a named, ordered, typed state variable with two or more
states. Its first state is the default unless another default is declared.
Bindings may consult any relevant axes when selecting a behavior.

Manna Cadet's symbol-producing bindings use three product axes:

```lisp
(axis case   (:states plain shifted) (:resolution product))
(axis script (:states roman greek)   (:resolution product))
(axis plane  (:states base top)      (:resolution product))
(level-order case script plane)
```

Their Cartesian product yields eight states in the conventional order because
`case` varies fastest, then `script`, then `plane`. An axis is not required to
be binary. A layout could declare four states on one product axis and five on
another and thereby obtain twenty level states. A layout may also restrict a
product to an explicit list of valid tuples when not every combination makes
sense.

Axes are dependency-scoped, not members of one global Cartesian product. A
binding is expanded only across the axes that its behavior consults. A letter
may depend on `case`, `script`, and `plane`, while a shift key may depend only
on `shift-latch`. Adding that behavioral axis therefore does not turn Manna
Cadet's eight symbol levels into sixteen.

The surface language distinguishes three useful resolution styles, all
normalized into the same context-axis model:

- **Product axes** contribute orthogonal coordinates to systematic behavior
  tables. Their combination is order-independent; `Greek+Top` is the same
  context regardless of which selector was pressed first.
- **Behavioral axes** select among complete behaviors. For example,
  `shift-latch` can choose whether a Greek key acts momentarily or latches
  Greek for a later key.
- **Patch or overlay axes** apply sparse binding overrides with explicit
  transparency and precedence. Unlike product axes, simultaneously active
  patches may be order- or priority-sensitive.

Operations on any axis are semantic actions: momentarily select a state, latch
it until an applicable use, lock it, unlock it, set it, or cycle it. The axis
value and the activation mode are distinct: `latch-axis-state` can latch an
axis into a state that happens to be named `latch`. A backend may realize these
operations with modifiers, groups, layers, state machines, or firmware; those
mechanisms are not visible here.

### 4.2 Semantic modifiers

Modifiers are named members of an unbounded set and do not choose a shift
level unless a layout explicitly defines that relationship. Manna Cadet starts
with:

```lisp
(modifiers control meta super hyper alt)
```

The IR will store active modifiers as canonical ordered collections of
identifiers, not machine words. Left/right physical sources may be recorded,
but `meta` remains the semantic modifier. A device or realization can expose
side-specific variants when an application truly distinguishes them.

Context axes and semantic modifiers must not be conflated. In particular,
Greek and Top are selector states; Control, Meta, Super, Hyper, and Alt are
modifier bits; Shift is the non-default state of the `case` axis even if a
backend uses an XKB real Shift modifier to implement it.

### 4.3 Output vocabulary

Bindings produce backend-neutral outputs:

- a Unicode scalar or short text value;
- a named key such as `return`, `backspace`, or `left`;
- a semantic command such as `stop-output`, `clear-input`, or `macro`;
- a modifier press/release;
- a context-axis state operation;
- a sequence or simultaneous composition of other actions;
- no output, explicitly.

XKB keysyms, Linux input names, private-use keysyms, QMK keycodes, and Kanata
tokens are realization vocabulary. A registry in the realization profile maps
abstract named keys and commands to those representations. Missing mappings
are errors unless the profile explicitly opts into a documented lossy mapping.

### 4.4 Bindings, overlays, and inheritance

A layout binds behaviors to logical positions. Each symbol-producing binding
can provide values for all level tuples or use explicit inheritance/fallback.
A missing value is not silently converted to `NoSymbol`; the source must say
whether the state is transparent, inherits from a named state, or emits
nothing.

Named overlays are sparse binding patches exposed as patch-style context axes.
A `fun` overlay can replace whole behaviors while Greek commonly participates
in a product table. This is a difference in declaration and resolution policy,
not a claim that overlays and axes are fundamentally unrelated kinds of state.
Overlay precedence, transparency, simultaneous activation, and base
inheritance are explicit and validated for ambiguity and cycles.

### 4.5 Unified timed interactions

Tap, hold, combo, tap dance, roll, sequence, and one-shot are not independent
semantic primitives. They are common patterns over the same timed event
stream. Every press of a logical position creates an interval beginning at its
down event and ending at its up event. An **interaction** recognizes temporal
and contextual relationships among one or more such intervals and produces a
complete behavior.

An interaction declares:

- participant positions and the wider event scope it observes;
- a finite pattern over down events, up events, deadlines, and context state;
- an explicit point at which a candidate interpretation commits;
- effects on entry, at milestones or commitment, while active, on exit, and on
  cancellation;
- explicit arbitration when its event prefix overlaps another interaction.

The pattern algebra includes ordered sequence, unordered conjunction,
alternation, duration ranges, deadlines, overlap, bounded proximity, absence
of an event between two boundaries, finite repetition, and named captures.
This can distinguish `A-down B-down A-up B-up` from
`A-down B-down B-up A-up`, recognize an isolated A release with no intervening
foreign press, or divide one press into less-than-one-second,
one-to-two-second, and at-least-two-second cases.

Effects have a lifecycle because not every keyboard action is an irreversible
output. Emitting a character occurs only at commitment. Held modifiers and
axis states can instead have paired enter/exit effects and may transition at a
deadline. If a one-second candidate could later become a two-second candidate,
the source must choose to delay the first output, make the results cumulative,
or use explicitly reversible enter/exit effects. Ivory Key never invents an
implicit rollback for output already delivered to an application.

Candidate matching and commitment are distinct. The recognizer may retain
several viable interpretations of an event prefix; only a committed candidate
claims its participant events, consumes consulted latches, and emits
irreversible output. Absence predicates cannot commit until their closing
boundary, and longest-match policies can therefore add latency. Overlapping
candidates require declared priority, a declared longest-match policy with a
deadline, or another deterministic arbitration rule. Validation rejects a
trace on which incompatible candidates can commit ambiguously.

The first language version keeps this model finite and statically inspectable:
finite participants, finitely many clocks, bounded repetition, declarative
predicates, and named acyclic interaction/behavior templates. It does not
evaluate arbitrary Common Lisp or provide a Turing-complete configuration
language. The normalized interaction IR compiles to a finite timed event
transducer used by the reference simulator.

`tap`, `hold`, `tap-hold`, `combo`, `tap-dance`, and similar friendly forms may
remain in the standard library, but only as declarative templates that expand
into interactions. Backend names such as `tap-hold-release` are lowering
choices, not language primitives.

An interaction explicitly states when it observes context. The version 1
default is to capture relevant context-axis values at the anchor down event.
Thus pressing Greek, pressing a delayed letter, releasing Greek, and then
releasing the letter still produces its Greek value. Another observation
policy is permitted only when the simulator and realization contract can
express it precisely.

The event semantics must define matching, deadlines, commitment, participant
ownership, cancellation, effect entry/exit, arbitration, patch precedence,
context capture, and latch consumption. These rules will be executable in the
reference simulator before backend generation is considered trustworthy.

### 4.6 Latch consumption and the `shift-latch` axis

Manna Cadet can define a behavioral axis that changes the disposition of shift
keys without adding a special `latch-latch` construct to the schema:

```lisp
(axis shift-latch
  (:states plain latch)
  (:resolution behavioral))

(binding latch-latch
  (on-tap
    (latch-axis-state shift-latch latch)))

(define-behavior shift-key (axis state)
  (by-axis shift-latch
    (plain (hold-axis-state axis state))
    (latch (latch-axis-state axis state))))

(binding greek
  (shift-key script greek))
```

The sequence `LATCHLATCH GREEK T` first latches `shift-latch=latch`; the Greek
binding consults that axis and consequently latches `script=greek`; T then
emits Greek tau and consumes the script latch.

A latched axis value is consumed by the first committed interaction
interpretation that consults that axis, not necessarily by the next physical
key. In
`LATCHLATCH A GREEK T`, an ordinary A that does not consult `shift-latch` does
not consume it. Speculative matching and a candidate that is later rejected or
cancelled also do not consume a latch. The normative event semantics must
define exactly when an interaction commits, especially when several candidates
share an event prefix.

## 5. Source language, version 1

### 5.1 Surface syntax

Use a deliberately small S-expression language, parsed by Common Lisp but not
evaluated as Common Lisp. Files begin with an explicit language version:

```lisp
(ivory-key 1)
```

Version 1 admits lists, identifiers, keyword-like option names, strings,
non-negative integers, line comments, and block comments. It does not admit
reader evaluation, packages, arbitrary dispatch macros, pathnames, ratios,
floating-point literals, circular labels, or implementation-specific objects.
Identifiers are represented internally as strings and are never automatically
interned into a Common Lisp package.

Do not use the host `read` function on layout files. Implement a small lexer
and recursive-descent S-expression parser so that the project owns the grammar,
can attach a source span to every form, can recover after common syntax errors,
and cannot accidentally acquire executable reader features. This also makes
the language stable across Common Lisp implementations.

### 5.2 Representative Manna Cadet fragment

The exact spelling may be adjusted during the language RFC phase, but the
semantic shape is fixed by this plan:

```lisp
(ivory-key 1)

(define-layout manna-cadet
  (uses-topology kinesis-advantage)

  (axis case
    (:states plain shifted)
    (:resolution product))
  (axis script
    (:states roman greek)
    (:resolution product))
  (axis plane
    (:states base top)
    (:resolution product))
  (axis shift-latch
    (:states plain latch)
    (:resolution behavioral))
  (level-order case script plane)

  (modifiers control meta super hyper alt)

  (binding q
    (at (plain   roman base) (unicode "q"))
    (at (shifted roman base) (unicode "Q"))
    (at (plain   greek base) (unicode "θ"))
    (at (shifted greek base) (unicode "Θ"))
    (at (plain   roman top)  (named-symbol up-caret))
    (at (shifted roman top)  none)
    (at (plain   greek top)  (inherit (plain roman top)))
    (at (shifted greek top)  none))

  (interaction a-home-row
    (:participants a)
    (:observe any-position)
    (:context-at (down a))

    (case tap
      (:match
        (and
          (sequence (down a) (up a))
          (duration a :less-than home-row)
          (without (down (other-than a))
            :between (down a) (up a))))
      (:commit (up a))
      (:do
        (by-level
          ((plain   roman base) (unicode "a"))
          ((shifted roman base) (unicode "A"))
          ((plain   greek base) (unicode "α"))
          ((shifted greek base) (unicode "Α"))
          ((plain   roman top)  (named-symbol up-tack))
          ((shifted roman top)  none)
          ((plain   greek top)  (inherit (plain roman top)))
          ((shifted greek top)  none))))

    (case hold
      (:match
        (either
          (deadline home-row :after (down a) :while-down a)
          (sequence (down a) (down (other-than a)))))
      (:commit when-matched)
      (:while (hold-modifier super)))

    (:arbitration (priority hold tap)))

  (binding latch-latch
    (on-tap
      (latch-axis-state shift-latch latch)))

  (define-behavior tap-hold-shift-key (tap-action axis state timing)
    (by-axis shift-latch
      (plain
        (tap-hold
          (:tap tap-action)
          (:hold (hold-axis-state axis state))
          (:timing timing)))
      (latch
        (on-tap
          (latch-axis-state axis state)))))

  (binding greek-thumb
    (tap-hold-shift-key
      (named-key delete) script greek thumb))

  (interaction stop-output
    (:participants i o)
    (:match
      (and
        (all (down i) (down o))
        (within (milliseconds 45) (down i) (down o))))
    (:commit (first (up i) (up o)))
    (:do (command stop-output))))
```

`named-symbol` is an abstract symbol identity for historical/non-Unicode
keyboard symbols; its registry entry must document identity and intended
display. It is not an XKB keysym escape hatch.

The `a-home-row` interaction demonstrates that one timed candidate retains the
complete axis-sensitive output table while another candidate provides a
reversible held effect. `stop-output` demonstrates that a conventional combo
is merely a multi-participant interaction. The `tap-hold` and `on-tap` forms in
the shift-key example are standard-library templates expanding to the same
interaction IR, not additional semantic machinery. The `shift-latch` example
demonstrates that an axis may select another selector key's behavior without
contributing to ordinary symbol-level enumeration. The shown spelling remains
subject to the Phase 0 language RFC; the interaction, dependency, commitment,
and consumption semantics are required.

### 5.3 Modules and composition

Support explicit, relative imports for shared vocabularies, topologies, and
behavior policies. Resolve them within configured source roots; reject absolute
paths, parent traversal outside a root, duplicate definitions, and import
cycles. Imports do not execute code.

Composition must be named and deterministic. It may extend a layout, apply an
overlay, define or instantiate an acyclic parameterized behavior or interaction
template, or instantiate a layout on a compatible topology. It may not depend
on load order to redefine an existing binding silently.

### 5.4 Canonical formatter

Ship `ivory-key fmt` with the first parser release. The formatter produces a
canonical representation while preserving comments where practical. Required
round-trip property:

```text
parse(format(parse(source))) == parse(source)
```

Equality here ignores whitespace and comment placement but includes every
semantic token. The formatter is also the canonical serializer for minimized
test cases.

## 6. Common Lisp implementation architecture

Use modern ASDF systems and target portable ANSI Common Lisp for the pure
compiler core. SBCL is the first supported and CI-tested implementation. Do not
make SBCL-specific process, filesystem, or octet behavior part of the semantic
model.

Use ordinary immutable-by-convention CLOS objects for domain entities and
generic functions for backend protocols. Use small structures for hot,
value-like records such as source spans and normalized state tuples. Conditions
carry diagnostics and restartable internal errors; user-facing compilation
does not drop into a debugger by default.

Proposed systems and files:

```text
ivory-key.asd
src/
  packages.lisp
  conditions.lisp
  source.lisp
  syntax/lexer.lisp
  syntax/parser.lisp
  syntax/formatter.lisp
  model/identifiers.lisp
  model/context.lisp
  model/layout.lisp
  model/topology.lisp
  model/behavior.lisp
  model/interaction.lisp
  model/realization.lisp
  resolve.lisp
  validate.lisp
  normalize.lisp
  simulate/events.lisp
  simulate/patterns.lisp
  simulate/machine.lisp
  backend/protocol.lisp
  backend/resources.lisp
  backend/xkb.lisp
  backend/kanata.lisp
  pipeline/xkb-kanata.lisp
  report.lisp
  cli.lisp
layouts/
  manna-cadet.ivory
topologies/
  kinesis-advantage.ivory
devices/
  kinesis-advantage2.ivory
  kinesis-advantage360.ivory
realizations/
  linux-xkb-kanata.ivory
  manna-cadet-linux.ivory
tests/
  syntax/
  model/
  simulation/
  backend/
  integration/
  fixtures/
docs/
  language.md
  semantics.md
  backend-contract.md
  migration-manna-cadet.md
```

Keep runtime dependencies minimal. The lexer, parser, formatter, model,
normalizer, simulator, and text emitters should require only Common Lisp and
UIOP/ASDF. Select one test framework during bootstrap and keep it a test-system
dependency only. Any later dependency must justify portability, reproducibility,
and why the same result should not live in the small core.

The ASDF definition will expose at least `ivory-key`, `ivory-key/cli`, and
`ivory-key/tests`; `asdf:test-system` must run the complete hermetic suite.
External tool integration tests are separately tagged because the presence of
Kanata or xkbcli is an environmental capability, not a Lisp unit-test
precondition.

## 7. Compiler pipeline and IRs

Compilation proceeds through explicit stages. Each stage returns a value plus
diagnostics; it does not mutate the parsed source model in place.

1. **Lex and parse:** source text to concrete forms with byte offset, line,
   column, file, and import-stack spans.
2. **Schema decode:** concrete forms to typed declarations. Reject unknown
   required forms and malformed options with stable diagnostic codes.
3. **Name resolution:** resolve imports, identifiers, registries, topology
   positions, policies, and inheritance.
4. **Semantic validation:** enforce uniqueness, acyclic composition,
   well-formed dependency-scoped axis spaces, complete or explicit binding
   fallback, finite template expansion, bounded interaction patterns, valid
   clocks and effect lifecycles, and deterministic commitment/arbitration.
5. **Normalization:** expand relevant axis products, behavioral selections,
   patch precedence, aliases, templates, inheritance, and interaction
   shorthand into a canonical abstract IR without target assumptions.
6. **Reference simulation:** compile normalized interactions into the abstract
   timed event transducer used as the semantic oracle.
7. **Capability planning:** compare normalized requirements with the selected
   realization pipeline, allocate finite backend resources, and classify every
   feature as exact, emulated, lossy, or unsupported.
8. **Target lowering:** produce backend-specific IRs. Cross-backend carrier
   allocations are represented in a pipeline IR rather than leaked back into
   either backend's view of the abstract layout.
9. **Emission:** write deterministic artifacts, a source map, and reports to a
   fresh output directory.
10. **Backend validation:** optionally invoke tools such as `kanata --check`
    and `xkbcli compile-keymap` with argument vectors and no shell.

Every IR will have a human-readable dump command. Internal classes need not be
a public serialization format in version 1, but dumps must be stable enough for
review and minimized regression fixtures.

## 8. Backend capability and realization contract

Each backend reports structured capabilities rather than being selected by a
large conditional in the compiler. Capabilities include:

- available input and output identities;
- maximum native levels/groups, or unbounded where appropriate;
- usable real and virtual modifier resources;
- supported context-axis operations, resolution styles, and patch operations;
- timed-interaction pattern, clock, lifecycle, and arbitration semantics;
- Unicode, named-key, and command-output mechanisms;
- carrier channels exposed to the next pipeline stage;
- validation commands and platform assumptions.

The pipeline planner owns shared resources. For example, it may decide that
Kanata implements the subset of normalized timed interactions it can express
and emits reserved carrier keycodes, while XKB maps those carriers to level
changes or command symbols. Allocation must be deterministic,
collision-checked, and visible in the report.

The realization result uses four grades:

- **exact:** target behavior matches the abstract event semantics;
- **emulated:** behavior is exact at the observable boundary but uses a kludge;
- **lossy:** a documented observable difference was explicitly permitted by
  the selected profile;
- **unsupported:** no permitted lowering exists.

Lossy output requires an explicit profile opt-in naming the diagnostic code.
Unsupported output fails compilation. No backend may silently drop a level,
modifier, interaction, output, effect lifecycle, or transition.

## 9. Initial Kanata + XKB pipeline

### 9.1 Responsibility split

The first planner should prefer this split while remaining driven by declared
capabilities:

- Kanata: physical capture, device placement, timed interactions it can realize
  exactly or through an approved emulation, overlays that require temporal
  behavior, and emission of ordinary or allocated carrier keycodes.
- XKB: keycode-to-symbol translation, natively representable level selection,
  groups where chosen by the profile, semantic modifier exposure to clients,
  and private carrier-to-command mappings where necessary.

The generated XKB bundle may contain `keycodes`, `types`, `compat`, `symbols`,
and a complete `keymap`. It must not assume RMLVO installation if a complete
keymap is more reliable. The generated Kanata file must contain no shell or
`cmd` action unless a future realization explicitly allows it.

### 9.2 Resource allocation

Implement a deterministic allocator for:

- XKB real modifier slots and their semantic names;
- XKB virtual modifiers;
- level versus group representation;
- evdev/Kanata carrier codes;
- command keysyms or other application-visible command identities.

The allocator receives a reserved/forbidden inventory from the device and
realization profile. It must prove that generated carriers do not collide with
physical inputs, standard outputs still needed by the layout, or each other.
The build report includes the complete allocation table and the abstract source
span responsible for every allocation.

For the eight-state Manna Cadet symbol space, test both the conventional
eight-level lowering and the current four-level-plus-group lowering. The
profile, not the layout, chooses one. Preserve semantic modifiers through XKB
consumed-modifier behavior and test their application-visible state.

### 9.3 Beyond a profile's convenient XKB capacity

A twenty-level layout is not rejected by the abstract compiler. With the first
pipeline it may be partitioned into XKB groups and levels, implemented partly
as Kanata overlays/carriers, or reported unsupported if the selected resources
cannot realize it exactly. Later QMK support can move state into firmware.

Do not promise that every abstract layout is realizable by every pipeline. The
guarantee is that the source can express it and the planner will provide an
honest, inspectable realization or a precise failure.

## 10. Generated output contract

Each compilation writes a directory such as:

```text
build/manna-cadet/linux-xkb-kanata/
  kanata/manna-cadet.kbd
  xkb/keymap/manna-cadet.xkb
  xkb/symbols/ivory-key
  xkb/types/ivory-key
  xkb/compat/ivory-key
  manifest.json
  allocations.json
  source-map.json
  REPORT.md
```

The manifest records language version, compiler version, source hashes,
selected layout/topology/device/profile, backend tool versions when validation
ran, artifact hashes, and realization grades. JSON emission will use a small,
deterministic internal encoder restricted to the manifest data model; layout
parsing never depends on JSON.

Emission order, whitespace, identifiers, and carrier allocation are stable.
Write into a fresh temporary sibling directory, validate there, and rename it
into place only after success. Never partially overwrite a previously valid
build.

## 11. Diagnostics and CLI

Initial commands:

```text
ivory-key check FILE...
ivory-key fmt [--check] FILE...
ivory-key dump-ir --stage STAGE ...
ivory-key levels --layout LAYOUT
ivory-key simulate --layout LAYOUT --events FILE
ivory-key explain --layout LAYOUT --realization PROFILE
ivory-key compile --layout LAYOUT --device DEVICE --realization PROFILE --output DIR
ivory-key validate-build DIR
```

Diagnostics have stable codes, severity, primary source span, related spans,
and a concise repair hint. Examples include duplicate identifiers, unknown
positions, incomplete level tables, ambiguous interaction commitment,
unbounded patterns, invalid effect lifecycles, inheritance cycles, exhausted
carriers, modifier-slot conflicts, and unapproved loss.

`explain` runs capability planning without emission and prints where every
abstract feature will live. It is the primary way to inspect kludges before
accepting a realization.

## 12. Verification strategy

### 12.1 Syntax and parser tests

- Golden valid/invalid files with exact diagnostic codes and spans.
- Fuzz arbitrary bytes and nested forms; parsing must terminate under explicit
  size/depth limits and must never evaluate input.
- Formatter idempotence and parse/format/parse property tests.
- Import-root, traversal, cycle, duplicate, and malformed-string tests.
- Cross-implementation parser fixtures once a second Common Lisp is added.

Parser resource limits protect the tool, not the keyboard model. Defaults for
file size, token length, and nesting depth are CLI safety limits that can be
raised; they are not semantic limits on level or modifier counts.

### 12.2 Model and normalization tests

- Manna Cadet's three product axes enumerate in the required eight-state order.
- A four-by-five fixture produces exactly twenty states and survives parse,
  normalization, formatting, simulation, and IR dumping.
- Adding the behavioral `shift-latch` axis does not expand an ordinary letter's
  eight relevant states to sixteen; dependency discovery and normalization
  include only axes actually consulted by a binding.
- A fixture with more than sixty-four semantic modifiers proves there is no
  fixed-width modifier representation.
- Product axes compose independently of activation order; simultaneous patch
  axes follow their declared precedence and diagnose unresolved ambiguity.
- Explicit restricted products, fallbacks, transparency, and inheritance are
  deterministic and cycle-checked.
- Named behavior and interaction templates expand finitely, reject recursive
  cycles, and preserve source spans through instantiation.
- Every normalized interaction uses finite participants and clocks, bounded
  repetition, and statically analyzable event predicates.
- Pattern overlap analysis rejects incompatible candidates that can commit on
  the same trace without explicit arbitration.
- Canonical IR is independent of hash-table iteration order and source import
  order where semantics are equivalent.

### 12.3 Reference simulator tests

Use timestamped press/release event streams and assert semantic outputs and
state after every event. Cover:

- simple symbols at every level tuple;
- simultaneous semantic modifiers with every relevant product-axis state;
- an interaction whose release candidate selects all eight Manna Cadet product
  states and whose held candidate has a paired enter/exit effect;
- context captured at initial press even when a selector is released before a
  delayed interaction commits;
- duration regions below one second, from one to two seconds, and from two
  seconds onward, including exact deadline boundaries;
- isolated release with no intervening foreign down event;
- interruption on another press and on another release;
- `A-down B-down A-up B-up` and `A-down B-down B-up A-up` selecting distinct
  actions;
- unordered overlap, rolling interactions, and explicit candidate priority;
- delayed irreversible output versus cumulative output versus reversible
  enter/exit effects;
- longest-match latency, losing-candidate cancellation, and event replay or
  ownership at commitment;
- overlay activation, transparency, latch, lock, and cancellation;
- `LATCHLATCH GREEK T` emits tau through two successive latch consumptions;
- `LATCHLATCH A GREEK T` proves a key that does not consult `shift-latch` does
  not consume it;
- speculative or rejected interaction candidates do not consume axis latches;
- sequences, one-shots, repeat, and macro ordering;
- stuck-state prevention after cancellation and malformed event streams.

The simulator is the oracle. Backends are compared to it; backend behavior is
never used to retroactively define abstract semantics.

### 12.4 Backend unit and golden tests

- Capability negotiation and every realization grade.
- Deterministic modifier, group/level, keysym, and carrier allocation.
- Exhaustion and collision failures with useful source-linked diagnostics.
- Escaping and injection tests for emitted XKB and Kanata text.
- Golden output for small focused layouts, plus reviewed whole-layout output.
- Recompiling identical inputs produces byte-identical artifacts and manifests
  except fields explicitly designated observational.

### 12.5 External validation

When tools are available:

- run `kanata --check -c GENERATED_FILE`;
- run `xkbcli compile-keymap --keymap GENERATED_FILE`;
- inspect the compiled XKB key types, groups, symbols, actions, and modifier
  maps rather than accepting exit status alone;
- use xkbcommon state tests to feed key events and observe keysyms plus consumed
  and unconsumed modifiers;
- exercise Kanata's simulator, if its selected version exposes the required
  semantics, with the same abstract event fixtures.

### 12.6 End-to-end and live proof

Build a differential harness that translates an abstract event fixture into
backend input events and compares observable results with the reference
simulator. Every emulated or lossy feature gets a targeted differential test.

Live deployment remains opt-in and later. It must use a disposable or clearly
identified input device first, verify the virtual device, capture observed
events, test all eight Manna Cadet levels and all five semantic modifiers, test
representative single- and multi-participant timed interactions, and retain a
rollback path to the existing configuration.

## 13. Manna Cadet migration

Migration is a semantic transcription, not a textual conversion of the old
files.

1. Freeze a baseline inventory: source commit and hashes, logical and physical
   positions, all XKB symbols by group/level, modifier assignments, all Kanata
   aliases/layers/combos/timings, carrier codes, and mnemonic intent.
2. Turn the inventory into a reviewable truth table keyed by abstract position,
   relevant context-axis tuple, patch state, and behavior. Mark apparent
   omissions and conflicts; do not invent meanings for `NoSymbol` or stale
   comments.
3. Define the shared Kinesis topology and separate Advantage 2 and Advantage
   360 physical placements.
4. Define the Manna Cadet product and behavioral axes, five semantic modifiers,
   symbol tables, command vocabulary, home-row and thumb behaviors, function
   and game patch axes, `shift-latch` behavior, and whichever chorded variant
   remains supported.
5. Simulate the abstract layout before writing backend expectations.
6. Compile the Linux Kanata+XKB realization and validate both artifacts.
7. Compare generated behavior to the baseline truth table. Classify intentional
   corrections separately from regressions and require review for each.
8. Only after equivalence is accepted, plan a separate dotfiles/submodule
   integration change. Do not hand-edit generated copies afterward.

The migration report must distinguish the primary layered variants from the
older chorded variants and must resolve whether they are two realization
profiles, two layout variants, or one deprecated compatibility fixture.

## 14. Implementation phases and exit criteria

### Phase 0: language RFC and frozen fixtures

Deliver `docs/language.md`, `docs/semantics.md`, the baseline inventory script,
and small hand-written syntax examples including Manna Cadet and a twenty-level
layout. Resolve naming, axis dependency and latch-consumption rules, patch
precedence, inheritance, the timed-pattern algebra, commitment, effect
lifecycles, arbitration, participant ownership, and context capture before
implementation spreads across backends.

Exit when every construct in the representative fragment has normative syntax
and event semantics and the baseline inventory is reviewable.

### Phase 1: project bootstrap

Create ASDF systems, packages, conditions, test runner, CLI skeleton, license,
format/lint conventions, and reproducible developer commands. Keep the runtime
core dependency-free beyond ASDF/UIOP.

Exit when a clean SBCL can load all systems and `asdf:test-system` passes.

### Phase 2: lexer, parser, diagnostics, and formatter

Implement the restricted reader, concrete forms, source spans, imports,
resource limits, schema decoding, canonical formatter, and syntax CLI commands.

Exit when valid and invalid corpora, fuzz smoke tests, and formatter properties
pass without using Common Lisp reader evaluation.

### Phase 3: semantic model and normalizer

Implement topology, context axes and resolution styles, modifiers, outputs,
bindings, overlays, finite parameterized behavior and interaction templates,
timed patterns, effect lifecycles, name resolution, validation, and canonical
abstract IR.

Exit when the eight-state, twenty-state, dependency-scoped `shift-latch`, and
over-sixty-four-modifier fixtures pass and all incomplete, cyclic, or ambiguous
constructs fail explicitly.

### Phase 4: reference event simulator

Implement timed-pattern matching, candidate sets, clocks, commitment,
arbitration, effect entry/exit/cancellation, participant ownership, and the
normative trace format before backend lowering.

Exit when the temporal interaction matrix passes and simulator traces identify
the source pattern, candidate transition, commit point, and effect responsible
for every output or held state.

### Phase 5: backend protocol and capability planner

Implement backend CLOS protocols, capability descriptions, realization grades,
pipeline IR, deterministic resource allocation, `explain`, and reports using
fake constrained backends first.

Exit when exact, emulated, lossy, unsupported, collision, and exhaustion paths
all have focused tests.

### Phase 6: XKB and Kanata emitters

Implement separate emitters and the combined Linux pipeline. Generate complete
XKB keymaps, Kanata configs, allocation/source maps, manifests, and external
validation hooks.

Exit when focused golden tests pass, generated configs pass installed tool
checks, and differential tests cover representative levels, modifiers,
single- and multi-participant interactions, multi-stage durations, exact event
orders, overlays, and latch consumption.

### Phase 7: full Manna Cadet migration

Transcribe and review the entire current layout, both Kinesis placements, the
primary layered behavior, command vocabulary, and chosen compatibility
variants. Generate but do not deploy replacement artifacts.

Exit when the truth-table comparison is complete, every difference is reviewed,
all eight levels and five modifiers are proven, and no abstract source contains
XKB/Kanata escape hatches.

### Phase 8: controlled integration

In a separate authorized session, wire generated artifacts into dotfiles,
validate a disposable/live device, preserve rollback, and document regeneration.

Exit only after live event proof; Git integration alone is not deployment
proof.

### Phase 9: future backends

Add QMK or other backends by implementing capabilities, lowering, emission,
validation, and differential tests. Extend the abstract language only when a
new semantic concept cannot already be expressed; never add a construct solely
because one backend happens to spell something differently.

## 15. Decisions that must remain explicit

- Project and language name: use **Ivory Key** unless changed before Phase 1.
- Canonical spelling of **Manna Cadet**: follow the existing repository and
  submodule spelling unless the owner chooses a rename with migration aliases.
- Version 1 parser is a safe S-expression subset, not executable Common Lisp.
- Context-axis state and semantic modifier collections are unbounded by the
  schema.
- Product, behavioral, and patch/overlay declarations normalize to a shared
  context-axis model with different resolution policies.
- Axis products are dependency-scoped per binding; there is no mandatory
  global product of every declared axis.
- The first declared product axis varies fastest in canonical level ordering.
- Semantic modifiers are not context selectors.
- Tap, hold, combo, tap dance, roll, and sequence are templates over one
  unified timed-interaction model, not separate semantic primitives.
- A logical-position press is an interval bounded by down and up events;
  patterns relate interval endpoints, deadlines, absence, overlap, repetition,
  and context.
- Every interaction candidate produces a complete behavior and may consult the
  full relevant axis product.
- Relevant context is captured at the interaction's anchor down event by
  default.
- Matching is speculative; only explicit commitment claims participant events,
  consumes consulted latches, and permits irreversible output.
- Active held effects use explicit enter/exit/cancel lifecycles. Ivory Key does
  not implicitly retract output already delivered to an application.
- Pattern repetition, participant sets, and clocks are finite; ambiguous
  commitment without declared arbitration is invalid.
- A latched axis is consumed by the first committed interaction that consults
  it, not simply by the next physical key.
- `shift-latch` is an ordinary behavioral axis defined by the layout, not a
  schema-specific key primitive.
- Abstract commands and symbols require documented realization mappings.
- No silent fallback, dropped state, implicit `NoSymbol`, or automatic firmware
  action is allowed.
- Reference simulation defines behavior; generated backend behavior is tested
  against it.
- Generated artifacts are replaceable and accompanied by allocations, source
  maps, hashes, capability grades, and validation evidence.

## 16. Plan completion checklist

Implementation is ready to begin when the Phase 0 review has answered these
remaining semantic questions without changing the architectural boundaries:

- exact abstract names and intended outputs for every historical Space Cadet
  command and non-Unicode symbol;
- whether shifted Top and Top+Greek holes intentionally emit nothing, inherit,
  or need new meanings;
- whether the game layer belongs to the Manna Cadet layout, a user overlay, or a
  device-specific profile;
- whether the older chorded files remain supported variants or only regression
  evidence;
- the exact default arbitration policies, if any, beyond rejecting ambiguous
  interactions;
- whether losing candidates replay unclaimed events to a lower-priority
  interaction or all ownership is decided within one candidate set;
- the precise allowed absence predicates, clock bounds, and bounded-repetition
  limits for version 1;
- whether milestone output may be declared cumulative, or version 1 should
  allow only commit-time output plus reversible enter/exit effects;
- the exact commit point and conflict rules when several pending interactions
  consult the same latched axis;
- whether any constructs need a context-observation time other than the default
  initial-press snapshot;
- the exact precedence and simultaneous-activation rules for patch axes;
- the normative interaction-candidate priorities for the current Manna Cadet
  home-row, thumb, and chorded behaviors;
- which timing values are layout defaults versus device/profile overrides;
- the application-visible distinction, if any, between left/right sources of
  the five semantic modifiers.

Those are content decisions. They do not block building the parser and model
once Phase 0 supplies explicit fixture answers.

## 17. Reference material consulted for this plan

- Current local Manna Cadet XKB and Kanata files listed in section 2.
- libxkbcommon's current keymap text-format documentation, particularly key
  types, level selection, consumed modifiers, groups, and actions:
  <https://xkbcommon.org/doc/current/keymap-text-format-v1-v2.html>
- Kanata's current configuration guide for aliases, layers, tap-hold variants,
  chords, one-shots, macros, and command-safety boundaries:
  <https://github.com/jtroo/kanata/wiki/Configuration-guide>
- The current ASDF manual for modern Common Lisp system and test-system
  organization: <https://asdf.common-lisp.dev/asdf.html>

The Common Lisp Cookbook skill's systems, packages, CLOS, files/I/O, and
testing routes informed the practical decomposition. Its optional mirrored HTML
chapters were not present at the documented local path during this planning
session, so no claim in this plan depends on having inspected those chapters.
The modern translation applied here is standard ASDF rather than historical
`defsystem` examples, a test-system dependency rather than cookbook-era RT as a
fixed choice, and portable core code with implementation-specific process
calls isolated behind UIOP and integration boundaries.
