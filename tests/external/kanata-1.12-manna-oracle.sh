#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later

set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: $0 PATH-TO-kanata-1.12.0.tar.gz FROZEN-MANNA-ROOT" >&2
    exit 2
fi

archive=$1
baseline_root=$2
expected_sha256=7081073d1d22fe4e404cf8e7d1dfa3f72562fb2d96538367c07f64877dcbf87a
actual_sha256=$(sha256sum "$archive" | awk '{print $1}')
config=$baseline_root/kanata/kinesis.advantage2.layered.kanata.kbd
expected_config_sha256=d36a93eab6e2355707f7a6bfbcfac2a4e3b0ea361cc399d388543f51e1f5226b

if [ "$actual_sha256" != "$expected_sha256" ]; then
    echo "kanata oracle: source archive hash mismatch" >&2
    echo "expected: $expected_sha256" >&2
    echo "actual:   $actual_sha256" >&2
    exit 1
fi

actual_config_sha256=$(sha256sum "$config" | awk '{print $1}')
if [ "$actual_config_sha256" != "$expected_config_sha256" ]; then
    echo "kanata oracle: frozen Advantage 2 config hash mismatch" >&2
    echo "expected: $expected_config_sha256" >&2
    echo "actual:   $actual_config_sha256" >&2
    exit 1
fi

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
temporary=$(mktemp -d)
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM

tar -xf "$archive" -C "$temporary"
source_directory=$temporary/kanata-1.12.0
cp "$config" "$source_directory/cfg_samples/ivory-key-manna.kbd"
patch -d "$source_directory" -p1 \
    < "$script_directory/kanata-1.12-manna-oracle.patch"

cargo_program=${CARGO:-cargo}
if [ -n "${KANATA_CARGO_TOOLCHAIN:-}" ]; then
    "$cargo_program" "+$KANATA_CARGO_TOOLCHAIN" test ivory_key_ \
        --manifest-path "$source_directory/Cargo.toml" \
        --no-default-features --features simulated_output -- \
        --test-threads=1 --nocapture
else
    "$cargo_program" test ivory_key_ \
        --manifest-path "$source_directory/Cargo.toml" \
        --no-default-features --features simulated_output -- \
        --test-threads=1 --nocapture
fi

echo "KANATA-1.12-MANNA-ORACLE: PASSED"
