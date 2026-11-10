#!/usr/bin/env bash
# Build the signed release app bundle (.aab, for Google Play) and keep a copy
# per version in debug/aab (git-ignored): debug/aab/pureshell-<version>.aab,
# e.g. pureshell-1.1.0+9.aab. An earlier build with the same version is never
# overwritten: the new copy gets _2, _3, ... `--copy-only` copies the bundle
# that is already built.
#
# Ends by printing the SHA-256 of the certificate the bundle is signed with
# ("signer SHA-256: ..."), and FAILS if it cannot be read: compare it with the
# upload key registered in Play Console (it must match the APKs from
# tool/build-release.sh).
set -euo pipefail
cd "$(dirname "$0")/.."

[ "${1:-}" = "--copy-only" ] || flutter build appbundle --release

src=build/app/outputs/bundle/release/app-release.aab
[ -f "$src" ] || { echo "no $src: build first" >&2; exit 1; }

report_signer() {
  local digest
  digest=$(keytool -printcert -jarfile "$1" 2>/dev/null \
    | sed -n 's/^[[:space:]]*SHA256: *//p' | head -1 | tr -d ':' \
    | tr 'A-F' 'a-f' || true)
  if [ -z "$digest" ]; then
    echo "FAILED: no signing certificate found in $1 (unsigned bundle?)" >&2
    exit 1
  fi
  echo "signer SHA-256: $digest"
}

version=$(sed -n 's/^version: *//p' pubspec.yaml | head -1)
mkdir -p debug/aab
dest=debug/aab/pureshell-$version.aab
n=2
while [ -e "$dest" ]; do
  if cmp -s "$src" "$dest"; then
    echo "already saved: $dest"
    report_signer "$dest"
    exit 0
  fi
  dest=debug/aab/pureshell-${version}_$n.aab
  n=$((n + 1))
done
cp "$src" "$dest"
echo "saved: $dest"
report_signer "$dest"
