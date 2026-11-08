#!/usr/bin/env bash
# Build the signed release APK and keep a copy per version in debug/apk
# (git-ignored): debug/apk/pureshell-<version>.apk, e.g. pureshell-1.0.0+1.apk.
# An earlier build with the same version is never overwritten: the new copy
# gets _2, _3, ... Use `tool/build-release.sh --copy-only` to copy the APK
# that is already built. `--debug` builds and keeps a debug APK instead:
# debug/apk/pureshell-<version>-debug.apk (debug-signed, logs the input path).
set -euo pipefail
cd "$(dirname "$0")/.."

flavor=release
suffix=
case "${1:-}" in
  --debug) flavor=debug; suffix=-debug ;;
esac
[ "${1:-}" = "--copy-only" ] || flutter build apk --$flavor

src=build/app/outputs/flutter-apk/app-$flavor.apk
[ -f "$src" ] || { echo "no $src: build first" >&2; exit 1; }

version=$(sed -n 's/^version: *//p' pubspec.yaml | head -1)
mkdir -p debug/apk
dest=debug/apk/pureshell-$version$suffix.apk
n=2
while [ -e "$dest" ]; do
  if cmp -s "$src" "$dest"; then echo "already saved: $dest"; exit 0; fi
  dest=debug/apk/pureshell-${version}${suffix}_$n.apk
  n=$((n + 1))
done
cp "$src" "$dest"
echo "saved: $dest"
echo "signer: $(apksigner verify --print-certs "$dest" 2>/dev/null | sed -n 's/.*SHA-256 digest: //p' | head -1)"
