#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Prepare the pinned ugglite ztMetro source in a new directory.
set -eu

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 UPSTREAM_ZTOS_CHECKOUT NEW_OUTPUT_DIRECTORY" >&2
    exit 2
fi

upstream=$1
output=$2
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
pin=94b35c2a1f4ceb568bc0ab60f5a1acebe7cfefaf
expected=a41147d923a2309d28ee4eead5fe692dbf81f871a62f0f3d605eded0ee581852

git -C "$upstream" cat-file -e "$pin^{commit}"
mkdir -- "$output"
output=$(CDPATH= cd -- "$output" && pwd)

git -C "$upstream" archive --output="$output/upstream.tar" "$pin" ztmetro
tar -xf "$output/upstream.tar" -C "$output"
rm -- "$output/upstream.tar"

series="$repo/patches/userspace/ztmetro"
for patch in "$series"/000[1-6]-*.patch; do
    git -C "$output" apply --check "$patch"
    git -C "$output" apply "$patch"
done

if command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum "$output/ztmetro/ztmetro.c")
else
    actual=$(shasum -a 256 "$output/ztmetro/ztmetro.c")
fi
[ "${actual%% *}" = "$expected" ] || {
    echo "Unexpected ztMetro source hash: ${actual%% *}" >&2
    exit 1
}
printf 'Prepared %s/ztmetro (SHA256 %s)\n' "$output" "$expected"
