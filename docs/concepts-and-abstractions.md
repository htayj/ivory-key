# Ivory Key concepts and abstractions

The simplest way to think about Ivory Key is:

> It is a compiler for the meaning of a keyboard.

You describe the ideal keyboard without mentioning XKB, Kanata, evdev codes,
modifier slots, or firmware constraints. Ivory Key then figures out how closely
a chosen collection of real systems can implement it.

## 1. The major separation

Ivory Key separates five things that conventional keymaps usually mix
together:

| Concept | Question it answers |
| --- | --- |
| Abstract layout | What does each position mean? |
| Topology | What logical positions exist? |
| Device placement | Which physical switch produces each position? |
| Realization profile | Which real systems implement the design, and what compromises are allowed? |
| Generated artifacts | What XKB, Kanata, QMK, etc. files should be installed? |

The flow is roughly:

```text
abstract layout
      +
logical topology
      +
physical-device placement
      +
realization profile
      |
      v
normalized keyboard model
      |
      v
capability planner
      |
      +----> Kanata configuration
      +----> XKB configuration
      +----> future QMK configuration
      +----> allocation and fidelity reports
```

That separation is the heart of Ivory Key.

For example, the abstract layout says:

```lisp
(hold-modifier meta)
```

The Linux realization might decide that Kanata should emit a particular
carrier keycode and XKB should place it in `Mod1`. None of that machinery
contaminates the abstract layout.

## 2. Logical positions versus physical keys

A binding is attached to a logical position, not directly to Linux keycode 30
or XKB key `<AC01>`.

A topology defines positions such as:

```text
left-pinky-home
left-index-home
left-thumb-main
right-thumb-main
```

It may also provide coordinates, hand, finger, and drawing information.

A device placement then says how those positions correspond to a particular
keyboard:

```text
Kinesis Advantage 360 switch -> left-thumb-main
Kinesis Advantage 2 switch   -> left-thumb-main
```

Both keyboards can therefore use the same Manna Cadet layout even if their
firmware or input codes differ.

Geometry remains descriptive. A key does not acquire meaning merely because it
is under the left index finger.

## 3. Context axes are the common state abstraction

An axis is a typed context variable whose value can participate in behavior
selection. Instead of declaring a fixed list of eight XKB-like levels, Ivory
Key models independent conceptual dimensions:

```lisp
(axis case   (:states plain shifted) (:resolution product))
(axis script (:states roman greek)   (:resolution product))
(axis plane  (:states base top)      (:resolution product))
(level-order case script plane)
```

These three binary axes produce:

| Case | Script | Plane | Familiar name |
| --- | --- | --- | --- |
| plain | roman | base | Normal |
| shifted | roman | base | Shift |
| plain | greek | base | Greek |
| shifted | greek | base | Greek+Shift |
| plain | roman | top | Top |
| shifted | roman | top | Top+Shift |
| plain | greek | top | Top+Greek |
| shifted | greek | top | Top+Greek+Shift |

The first declared axis varies fastest, matching the conventional eight-level
ordering.

These are **product axes**: they contribute coordinates to a systematic
behavior table, and their combination does not depend on activation order.

But axes need not be binary. This is perfectly legitimate conceptually:

```lisp
(axis case
  (:states plain shifted alternate titlecase)
  (:resolution product))
(axis plane
  (:states base greek math navigation symbols)
  (:resolution product))
```

That produces twenty states. Nothing in the abstract representation cares
whether XKB can conveniently implement them.

Axes need not select symbols. Ivory Key recognizes three useful declaration
styles built on the same context-axis model:

- **Product axes** provide orthogonal coordinates such as case, script, and
  plane.
- **Behavioral axes** select complete behaviors, such as whether a shift key
  should act momentarily or latch its selected state.
- **Patch or overlay axes** apply sparse, precedence-ordered changes to the
  binding map.

An axis state can be:

- held momentarily;
- latched until the next committed behavior selection that consults it;
- locked;
- unlocked;
- toggled or cycled.

The realization planner decides whether that becomes an XKB modifier, XKB
group, Kanata layer, QMK state, or some combination.

Axes are dependency-scoped. A binding is expanded only across axes it actually
consults. A letter may depend on `case`, `script`, and `plane`, while a Greek
shift key may depend only on `shift-latch`. Adding `shift-latch` therefore does
not double every letter from eight states to sixteen.

## 4. Semantic modifiers are not context axes

Manna Cadet has five semantic modifiers:

```lisp
(modifiers control meta super hyper alt)
```

These are signals intended to reach applications. Greek and Top, by contrast,
select what a key means.

That distinction matters:

- `Greek+q` chooses `θ`.
- `Meta+q` still emits the `q` meaning while reporting Meta to Emacs.
- `Meta+Greek+q` emits `θ` while Meta remains active.
- A backend may consume the Greek selector during symbol selection, but it
  must preserve Meta for the application.

Shift is modeled as the non-default state of the `case` axis. A real backend
may nevertheless implement it with its native Shift modifier.

Internally, modifier sets are collections of names, not 32-bit or 64-bit masks.
The model can therefore describe more than 64 modifiers even though current
operating systems cannot expose that many directly.

## 5. Product axes, overlays, and backend layers

The word "layer" is dangerously overloaded. Product axes and overlays are
both context selectors, but use different resolution rules; a backend layer is
only an implementation mechanism.

### Product-axis state

Greek changes the symbol selected for ordinary bindings:

```text
q → q
Shift+q → Q
Greek+q → θ
Greek+Shift+q → Θ
```

### Patch or overlay axis

The Manna Cadet `fun` overlay replaces whole behaviors. On that overlay, `q`
might mean the historical `quote` command rather than a different form of the
letter q.

The `game` overlay similarly changes a set of bindings as a unit. Overlays are
sparse patches: unmentioned positions fall through, and simultaneous patches
need explicit precedence. Unlike product axes, applying `game` over `fun` may
not mean the same thing as applying `fun` over `game`.

### Backend layer

Kanata might use one of its layers to implement either of the preceding
concepts. That is merely an implementation choice and never becomes the
abstract definition.

All three surface concepts normalize into context-axis state plus a resolution
policy. So:

> Greek is a product-axis state, `fun` is a patch-axis state, and a Kanata
> layer is a lowering mechanism.

## 6. Bindings produce behaviors, not merely keysyms

An Ivory Key binding maps a logical position to a behavior. Behaviors compose:
every branch of a compound behavior contains another complete behavior rather
than being restricted to one output token.

A simple symbol table might look like:

```lisp
(binding q
  (at (plain   roman base) (unicode "q"))
  (at (shifted roman base) (unicode "Q"))
  (at (plain   greek base) (unicode "θ"))
  (at (shifted greek base) (unicode "Θ")))
```

Here `q` is a logical position identifier. The final language may choose a
less ambiguous name such as `q-position`.

Bindings may produce:

- Unicode characters or text;
- named keys such as `return` or `backspace`;
- semantic commands such as `stop-output`;
- modifier operations;
- context-axis operations;
- simultaneous actions;
- ordered sequences;
- explicit no-output behavior.

They do not produce XKB keysyms or Kanata tokens directly.

Repeated patterns can be factored into named, parameterized behavior templates.
These templates are declarative, finite, and acyclic; they are not arbitrary
Common Lisp functions evaluated from the configuration.

A historical command is represented semantically:

```lisp
(command stop-output)
```

A Linux profile may realize that through private-use keysym `UE007`. Another
backend could assign a QMK custom keycode. The command's identity remains
`stop-output`.

## 7. Missing bindings are explicit

Traditional keymaps often treat a missing entry as `NoSymbol`, transparent, or
inherited depending on context. Ivory Key refuses to guess.

A level entry must explicitly be one of:

- a defined behavior;
- `none`;
- transparent;
- inherited from a named state or binding.

For example:

```lisp
(at (plain greek top)
    (inherit (plain roman top)))
```

This says exactly what happens at Top+Greek. It avoids encoding accidental gaps
from the current XKB file as deliberate keyboard semantics.

## 8. Tap-hold and other temporal behavior

A key can describe abstract tap-hold behavior:

```lisp
(binding left-thumb-main
  (tap-hold
    (:tap  (named-key backspace))
    (:hold (hold-modifier alt))
    (:timing home-row)
    (:resolve after-other-release)))
```

This expresses:

- tapping emits Backspace;
- holding asserts semantic Alt;
- timing comes from the `home-row` policy;
- interruption is resolved after another key is released.

It does not say `tap-hold-release 200 200 ...`, because that is Kanata syntax.

### Axis-sensitive tap behavior

The tap branch can itself consult the complete product of all axes relevant to
the tap:

```lisp
(binding a-position
  (tap-hold
    (:tap
      (by-level
        ((plain   roman base) (unicode "a"))
        ((shifted roman base) (unicode "A"))
        ((plain   greek base) (unicode "α"))
        ((shifted greek base) (unicode "Α"))
        ((plain   roman top)  (named-symbol up-tack))
        ((shifted roman top)  none)
        ((plain   greek top)  (inherit (plain roman top)))
        ((shifted greek top)  none)))
    (:hold
      (hold-modifier super))
    (:timing home-row)
    (:selection-time press)))
```

The tap-hold wrapper is written once. Its tap behavior retains all eight Manna
Cadet product states, while its hold behavior asserts Super.

Because tap-hold delays the output decision, the default is to capture relevant
context-axis values at the initial key press. Pressing Greek, pressing this
key, releasing Greek, and then releasing this key still produces the Greek tap
value. Any different observation time must be requested explicitly and must be
supported by the simulator and realization contract.

### The `shift-latch` behavioral axis

`LATCHLATCH` does not need a special schema primitive. It can latch an ordinary
behavioral axis whose state is consulted by shift-key definitions:

```lisp
(axis shift-latch
  (:states plain latch)
  (:resolution behavioral))

(binding latch-latch
  (on-tap
    (latch-axis-state shift-latch latch)))

(define-behavior shift-key (axis state)
  (by-axis shift-latch
    (plain
      (hold-axis-state axis state))
    (latch
      (latch-axis-state axis state))))

(binding greek
  (shift-key script greek))
```

The sequence is:

```text
LATCHLATCH
    → latch shift-latch=latch

GREEK
    → consult shift-latch
    → latch script=greek
    → consume the shift-latch latch

T
    → consult script
    → emit τ
    → consume the script latch
```

A latched axis is consumed by the first committed behavior selection that
consults it, not necessarily by the next physical key. In
`LATCHLATCH A GREEK T`, an A binding that does not consult `shift-latch` leaves
the latch intact for Greek. Speculative resolution and a tap-hold or combo
branch that is later rejected do not consume it.

Ivory Key defines its own event semantics for:

- press and release;
- timeouts;
- interruption by another press;
- interruption by another release;
- combo arbitration;
- context capture and committed selection;
- selective latch consumption;
- cancellation;
- one-shots;
- sequences and macros;
- patch/overlay changes.

This is necessary because two backends can use similar-looking terminology
while behaving differently at timing boundaries.

## 9. Combos are logical-position relationships

A combo is defined over logical positions:

```lisp
(combo stop-output
  (:positions i o)
  (:window (milliseconds 45))
  (:resolve first-release)
  (:action (command stop-output)))
```

The physical device determines which switches are `i` and `o`. The realization
determines whether the combo runs in Kanata, QMK, or somewhere else.

The abstract semantics define what happens when:

- one participant is released early;
- another combo overlaps;
- a combo participant also has tap-hold behavior;
- the timing window expires.

Those rules must be settled before trusting generated configurations.

## 10. The reference simulator is the semantic authority

Ivory Key will include an abstract keyboard simulator.

Given events such as:

```text
0 ms:   press left-thumb-main
40 ms:  press q
70 ms:  release q
90 ms:  release left-thumb-main
```

it computes semantic outputs and state transitions according to Ivory Key's
rules.

This simulator, not Kanata or XKB, defines correct behavior.

Generated configurations are then tested against the same event fixtures:

```text
Abstract simulator result
          =
Observed generated-backend result
```

That allows us to distinguish "Kanata happens to do this today" from "this is
what Manna Cadet means."

## 11. Realization profiles contain the kludges

A realization profile selects a backend pipeline and its policy:

```text
Manna Cadet
+ Kinesis Advantage 360
+ Linux XKB/Kanata realization
```

It records things such as:

- available carrier keycodes;
- forbidden or already-used codes;
- XKB modifier-slot allocation;
- whether to use levels or groups;
- command-to-keysym assignments;
- physical device path;
- permitted timing overrides;
- permitted approximations.

For the current layout, the planner might choose:

```text
physical keyboard
      |
      v
Kanata
  - physical placement
  - tap-holds
  - combos
  - fun/game overlays
  - carrier keycodes
      |
      v
XKB
  - Roman/Greek/Top symbol selection
  - application-visible modifiers
  - command keysyms
      |
      v
applications
```

For a twenty-level layout, the planner might distribute state across XKB
groups, XKB levels, and Kanata overlays. A future profile might place some of
it in QMK firmware.

## 12. Fidelity is reported explicitly

Every requested feature receives one of four grades:

- **Exact:** directly matches the abstract semantics.
- **Emulated:** observable behavior is exact, but implemented through a kludge.
- **Lossy:** there is a known behavioral difference that the profile explicitly
  permits.
- **Unsupported:** the selected pipeline cannot implement it acceptably.

Lossy compilation requires an explicit opt-in. Unsupported behavior fails
compilation.

Ivory Key must never silently:

- drop a level;
- erase a modifier;
- replace an unknown command;
- insert `NoSymbol`;
- reuse a conflicting carrier;
- flash firmware;
- claim an approximation is exact.

## 13. The compiler stages

The planned pipeline is:

1. Parse the safe S-expression syntax.
2. Decode forms into typed declarations.
3. Resolve names and imports.
4. Validate the semantics.
5. Normalize shorthand, relevant product coordinates, behavioral selections,
   patch precedence, and finite behavior templates.
6. Build the reference event machine.
7. Compare requirements with backend capabilities.
8. Allocate modifiers, groups, carriers, and commands.
9. Lower into backend-specific IRs.
10. Emit deterministic files.
11. Validate those files with tools such as `kanata --check` and `xkbcli`.

Compilation also generates:

- a manifest with input and artifact hashes;
- a complete allocation table;
- source maps from generated mechanisms back to abstract bindings;
- a human-readable fidelity report.

## 14. Why the syntax is Lispy but not executable Common Lisp

Layout files look like Lisp:

```lisp
(ivory-key 1)
(define-layout manna-cadet ...)
```

But Ivory Key does not call the host Common Lisp reader and does not evaluate
these forms.

It has a small dedicated parser supporting only the required S-expression
subset. That provides:

- no `#.` reader evaluation;
- stable syntax across implementations;
- exact source spans for diagnostics;
- controlled imports;
- parser recovery;
- protection from package pollution and arbitrary symbol interning.

The implementation is Common Lisp; the input is safe declarative data with
Lisp structure.

## 15. How Common Lisp fits internally

The planned implementation uses:

- **CLOS objects** for layouts, topologies, context axes, behaviors, behavior
  templates, profiles, and backends;
- **generic functions** for backend capability queries, planning, lowering,
  and emission;
- **structures** for small value objects such as source spans and normalized
  level tuples;
- **conditions** for structured diagnostics;
- **ASDF** for the compiler, CLI, and test systems;
- **UIOP** for portable filesystem and external-process boundaries.

That gives us an extensible backend protocol without putting one giant `case`
statement at the center of the compiler.

## The essence

If Ivory Key is reduced to three rules:

1. **Describe keyboard meaning without naming implementation mechanisms.**
2. **Make every real-world compromise explicit and inspectable.**
3. **Test generated behavior against an executable abstract model.**

That is what keeps the keyboard pristine in the ivory tower while still
letting us descend into the XKB/Kanata basement when necessary.
