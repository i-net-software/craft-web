#!/usr/bin/env bash
# Downloads an upstream release asset and verifies it against the SHA256SUMS.txt
# of the same release. Fails if the asset is not listed or the checksum differs.
#
# Usage: fetch.sh <owner/repo> <version> <asset> <target-dir>
# Needs: gh (authenticated via GH_TOKEN) and sha256sum or shasum.
set -euo pipefail

upstream=$1 version=$2 asset=$3 dir=$4

sha256() {
    if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

mkdir -p "$dir"
gh release download "v${version}" --repo "$upstream" --dir "$dir" --clobber \
    --pattern "$asset" --pattern SHA256SUMS.txt

expected=$(awk -v n="$asset" '{ f = $2; sub(/^\*/, "", f); if (f == n) print tolower($1) }' "$dir/SHA256SUMS.txt")
[ -n "$expected" ] || { echo "SHA256SUMS.txt does not list ${asset}" >&2; exit 1; }
actual=$(sha256 "$dir/$asset")
[ "$expected" = "$actual" ] || { echo "SHA-256 mismatch for ${asset}: expected ${expected}, was ${actual}" >&2; exit 1; }
echo "${asset}: SHA-256 ${actual} verified"
