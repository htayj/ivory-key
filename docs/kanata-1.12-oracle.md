# Kanata 1.12 Manna release oracle

This is separately tagged environmental evidence for the current Manna
`tap-hold-release` question. It does not select a policy, change the abstract
layout, authorize lowering, or prove live-device behavior.

## Frozen oracle input

The surrounding dotfiles audit identifies Kanata 1.12.0 as the installed
runtime. The locally retained AUR source package identifies upstream tag
`v1.12.0` and records this source-archive SHA-256:

```text
7081073d1d22fe4e404cf8e7d1dfa3f72562fb2d96538367c07f64877dcbf87a
```

The actual frozen Advantage 2 configuration used by the oracle has SHA-256:

```text
d36a93eab6e2355707f7a6bfbcfac2a4e3b0ea361cc399d388543f51e1f5226b
```

The external harness refuses any other archive or configuration. It copies the
hash-verified configuration into a temporary unpacked Kanata source tree,
applies only the checked-in test patch, and invokes Kanata's own
simulated-output state machine with default features disabled. No keyboard,
uinput device, service, or installed configuration is opened or changed.

Run it with an explicitly selected Cargo toolchain:

```sh
KANATA_CARGO_TOOLCHAIN=nightly \
  tests/external/kanata-1.12-manna-oracle.sh \
  PATH-TO-kanata-1.12.0.tar.gz \
  PATH-TO-FROZEN-MANNA-ROOT
```

Cargo dependencies must already be available or may be fetched according to
the caller's Cargo configuration, so this remains outside the hermetic ASDF
suite and the Guix-only core proof.

## Observed state-machine contract

The four checked tests use both small synthetic configurations and the actual
hash-frozen Advantage 2 configuration. They exercise its two equal timer
shapes, 200/200 ms and 250/250 ms, with `concurrent-tap-hold yes`, and assert:

- release immediately before the deadline produces only the tap;
- the deadline produces the hold and releasing the owner releases it;
- a foreign press followed by its release commits the hold;
- releasing the tap-hold owner before the foreign release produces the tap;
- two owners of the same modifier retain the modifier until the final owner
  releases, in either release order, including all five frozen semantic
  modifier pairs; and
- two owners of `layer-while-held` retain the function layer until the final
  owner releases, in either release order.

The oracle also establishes an important incompatibility with the currently
proposed [ADR 0003](decisions/0003-manna-release-trigger-v1.md): Kanata 1.12.0
does not leave a foreign key temporally untouched while a tap-hold is pending.
In the early-owner-release case, the foreign `B` press is emitted only after
the owner resolves as a tap. In the foreign-release hold case, the buffered
`B` press/release pair is emitted after the hold commits. The exact expected
event strings in `kanata-1.12-manna-oracle.patch` make that ordering a checked
fact rather than prose inference.

## Decision boundary

This evidence narrows, but does not eliminate, the owner decision:

1. A modern `manna-release-trigger-v1` profile may retain ADR 0003's explicit
   no-delay/no-replay rule. It is then intentionally different from Kanata
   1.12.0 and cannot use the generic Kanata tap-hold action as an exact
   lowering.
2. A Kanata-1.12 compatibility profile must model the pending foreign-event
   buffer and its ordered release. That requires an explicit ownership,
   buffering, cancellation, and replay contract before it can enter the
   abstract interaction model or compiler.

Until one route is selected and implemented, the active Manna realization
continues to refuse all fourteen primary tap-holds and the two alternate
selector tap-holds before artifact publication.
