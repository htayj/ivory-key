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
- latched until the next committed interaction interpretation that consults
  it;
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

Repeated patterns can be factored into named, parameterized behavior and
interaction templates. These templates are declarative, finite, and acyclic;
they are not arbitrary Common Lisp functions evaluated from the configuration.

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

## 8. Timed interactions unify tap, hold, and combo

Every press of a logical position forms an interval:

```text
A-down ---------------- A-up
```

Ivory Key treats tap, hold, combo, tap dance, roll, sequence, and one-shot as
recognizable patterns over these intervals. They are not separate kinds of
keyboard machinery. An **interaction** says which positions participate, what
events and context it observes, what temporal pattern must occur, when that
interpretation commits, what effects it has, and how it competes with other
possible interpretations.

The core event vocabulary contains logical-position down and up events,
deadlines, and context observations. The pattern algebra includes forms such
as:

```lisp
(sequence pattern ...)
(all pattern ...)
(either pattern ...)
(duration position :at-least time :less-than time)
(deadline time :after event :while-down position)
(within time event ...)
(overlap position ...)
(without event :between start end)
(repeat pattern :at-most count)
```

`sequence` constrains total event order; `all` requires its members without
inventing an order; `and` combines temporal and contextual constraints over the
same candidate. These distinctions let a layout say exactly how much ordering
matters instead of treating every multi-key interaction as simultaneous.

Named captures allow a reusable pattern to refer to participants without
hard-coding their positions. Repetition, participant sets, and clocks remain
finite so the compiler can analyze the pattern and construct a timed state
machine.

### A complete axis-sensitive interaction

One candidate can select all eight product states while another provides a
held effect:

```lisp
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
```

The output-producing candidate captures the relevant axes at A-down by
default. Pressing Greek, pressing A, releasing Greek, and then releasing A
therefore still selects A's Greek value. Its full level table is not lost just
because the same position participates in a timed interaction.

This spelling is conceptual, not an accepted V1 source fixture.  In particular,
its `:context-at` and named duration forms are reserved, and its held candidate
does not yet provide the required `:do` and `:exit` clauses.  The exact V1
grammar, event rules, and refusal boundary are in
[language-reference-v1.md](language-reference-v1.md).  The semantic
requirements—complete candidate behaviors, explicit context capture,
commitment, and effect lifetime—remain the important part.
The accepted V1 defaults for unresolved migration-content questions are in
[Decision 0002](decisions/0002-v1-policy-defaults.md); they deliberately do
not turn this conceptual example into a historical Manna behavior claim.

### One-second and two-second holds

Duration regions can classify the completed interval:

```lisp
(interaction staged-hold
  (:participants a)

  (case short
    (:match (duration a :less-than (seconds 1)))
    (:commit (up a))
    (:do short-action))

  (case medium
    (:match
      (duration a
        :at-least (seconds 1)
        :less-than (seconds 2)))
    (:commit (up a))
    (:do one-second-action))

  (case long
    (:match
      (deadline (seconds 2) :after (down a) :while-down a))
    (:commit (deadline (seconds 2) :after (down a)))
    (:do two-second-action)))
```

This example waits to classify shorter cases. For a modifier or axis state that
must be active while the key remains down, an interaction instead uses paired
lifecycle effects:

```lisp
(interaction staged-modifier
  (:participants a)

  (phase medium
    (:enter (deadline (seconds 1) :after (down a)))
    (:exit
      (either
        (up a)
        (deadline (seconds 2) :after (down a))))
    (:while (hold-modifier meta)))

  (phase long
    (:enter (deadline (seconds 2) :after (down a)))
    (:exit (up a))
    (:while (hold-modifier hyper))))
```

This distinction is essential. Once a character or command has been delivered
to an application, Ivory Key generally cannot take it back. If a one-second
interpretation may later become a two-second interpretation, the source must
choose one of three honest semantics:

- delay irreversible output until the interpretation commits;
- declare that the one- and two-second results are cumulative;
- use reversible enter/exit effects and transition between them.

There is no implicit rollback of emitted output.

### Absence, overlap, and exact release order

“A release with no other key pressed while A was down” is an absence pattern:

```lisp
(and
  (sequence (down a) (up a))
  (without (down (other-than a))
    :between (down a) (up a)))
```

Absence can only be proven when its closing boundary occurs, so this pattern
cannot commit before A-up.

Multi-position interactions can distinguish exact traces:

```lisp
(interaction ab-release-order
  (:participants a b)

  (case a-first
    (:match
      (sequence (down a) (down b) (up a) (up b)))
    (:commit (up b))
    (:do action-a-first))

  (case b-first
    (:match
      (sequence (down a) (down b) (up b) (up a)))
    (:commit (up a))
    (:do action-b-first)))
```

An ordinary unordered combo is simply a less restrictive interaction requiring
that all participant intervals overlap and that their down events fall within
a window. Rolls, nested holds, overlap-duration actions, and tap dances are
other patterns over the same event vocabulary.

### Candidate commitment and arbitration

After A-down, several candidates may still be viable: an A release, an A hold,
an A+B interaction, or the start of A+B+C. Matching is therefore speculative.
An interaction explicitly declares when a candidate commits:

```lisp
(:commit (up a))
(:commit (deadline (seconds 2) :after (down a)))
(:commit when-unambiguous)
```

Only a committed candidate:

- claims its participant events;
- consumes context-axis latches that it consulted;
- emits irreversible output;
- defeats incompatible candidates.

Rejected or cancelled candidates do none of those things. Overlapping
candidates require explicit priority, a longest-match policy with a deadline,
or another deterministic rule. If incompatible candidates can commit on the
same trace and no arbitration resolves them, the layout is invalid. Longest
match and absence predicates can introduce latency, which the compiler reports
rather than hiding.

### The `shift-latch` behavioral axis

`LATCHLATCH` still needs no special schema primitive. Its tap shorthand expands
to an interaction that latches an ordinary behavioral axis:

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
    → commit interaction
    → latch shift-latch=latch

GREEK
    → committed interpretation consults shift-latch
    → latch script=greek
    → consume the shift-latch latch

T
    → committed interpretation consults script
    → emit τ
    → consume the script latch
```

In `LATCHLATCH A GREEK T`, an A interaction that does not consult
`shift-latch` leaves the latch intact for Greek. Speculative and rejected
candidates do not consume it.

## 9. Friendly forms are interaction templates

Ivory Key can retain readable forms such as:

```lisp
(tap ...)
(hold ...)
(tap-hold ...)
(combo ...)
(tap-dance ...)
```

These are finite, declarative standard-library templates that expand into the
same interaction IR. They add no private resolution rules. A user can employ
the concise form for a conventional behavior and the full interaction syntax
when timing, ordering, absence, or effect lifecycles matter.

Each top-level template materialization has an explicit source-level instance
name:

```lisp
(instantiate-interaction instance-name template-name (:parameter value) ...)
```

That name is an identity for diagnostics, traces, arbitration, and source
maps; it does not change the interaction's temporal semantics. Ivory Key does
not synthesize it from the template or its arguments. The choice is recorded
as accepted but revisitable in [Decision 0001](decisions/0001-explicit-interaction-instance-names.md).

A template may delegate to another template without creating a second named
interaction; that nested call inherits the outer materialization's identity.

The physical device still determines which switches produce the logical
participant positions. A realization still decides whether Kanata, QMK, XKB,
or a combination implements the normalized timed interaction. Backend forms
such as Kanata's `tap-hold-release` never define Ivory Key semantics.

## 10. The reference simulator is the semantic authority

Ivory Key will include an abstract keyboard simulator.

Given events such as:

```text
0 ms:   press left-thumb-main
40 ms:  press q
70 ms:  release q
90 ms:  release left-thumb-main
```

it reports viable candidates, deadlines, commitments, cancellations, effect
lifecycles, consumed context, semantic outputs, and final state according to
Ivory Key's rules.

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
  - timed interactions it can realize
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
   patch precedence, and finite behavior/interaction templates.
6. Compile interaction patterns into the reference timed event transducer.
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

- **CLOS objects** for layouts, topologies, context axes, behaviors,
  interactions, patterns, templates, profiles, and backends;
- **structures** for source spans, normalized level tuples, timestamped events,
  clocks, and simulator candidate state;
- **generic functions** for backend capability queries, planning, lowering,
  and emission;
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
