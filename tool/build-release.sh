#!/usr/bin/env bash
# Build the signed release APK and keep a copy per version in debug/apk
# (git-ignored): debug/apk/pureshell-<version>.apk, e.g. pureshell-1.0.0+1.apk.
# An earlier build with the same version is never overwritten: the new copy
# gets _2, _3, ... Use `tool/build-release.sh --copy-only` to copy the APK
# that is already built. `--debug` builds and keeps a debug APK instead:
# debug/apk/pureshell-<version>-debug.apk (debug-signed, logs the input path).
#
# Every run ends by printing the SHA-256 of the certificate the APK is signed
# with ("signer SHA-256: ..."). For a release build the script FAILS if the
# signature does not verify or no certificate can be read, so an unsigned or
# wrongly signed APK is never mistaken for a good one.
set -euo pipefail
cd "$(dirname "$0")/.."

flavor=release
suffix=
case "${1:-}" in
  --debug) flavor=debug; suffix=-debug ;;
esac

# apksigner: on PATH, or in the newest build-tools of the Android SDK.
find_apksigner() {
  if command -v apksigner >/dev/null 2>&1; then command -v apksigner; return; fi
  local sdk found
  for sdk in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Android/Sdk" \
      "$(dirname "$(dirname "$(command -v adb 2>/dev/null || echo /nonexistent/x)")")"; do
    [ -n "$sdk" ] || continue
    found=$(ls "$sdk"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1 || true)
    if [ -n "$found" ]; then echo "$found"; return; fi
  done
  return 1
}

# Prints the signing certificate's SHA-256 of an APK, or fails.
print_signer() {
  local apk=$1 signer out digest
  if ! signer=$(find_apksigner); then
    echo "signer: apksigner not found (set ANDROID_HOME or put apksigner on PATH)" >&2
    return 1
  fi
  if ! out=$("$signer" verify --print-certs "$apk" 2>&1); then
    echo "signer: the signature of $apk does not verify:" >&2
    echo "$out" >&2
    return 1
  fi
  digest=$(printf '%s\n' "$out" | sed -n 's/.*certificate SHA-256 digest: //p' | head -1)
  if [ -z "$digest" ]; then
    echo "signer: no certificate found in $apk" >&2
    return 1
  fi
  echo "signer SHA-256: $digest"
}

# Prints the signer; only a release build must have a verifiable one.
report_signer() {
  if ! print_signer "$1"; then
    [ "$flavor" = release ] && { echo "FAILED: release APK is not properly signed" >&2; exit 1; }
    echo "(debug build: carrying on)" >&2
  fi
}

[ "${1:-}" = "--copy-only" ] || flutter build apk --$flavor

src=build/app/outputs/flutter-apk/app-$flavor.apk
[ -f "$src" ] || { echo "no $src: build first" >&2; exit 1; }

version=$(sed -n 's/^version: *//p' pubspec.yaml | head -1)
mkdir -p debug/apk
dest=debug/apk/pureshell-$version$suffix.apk
n=2
while [ -e "$dest" ]; do
  if cmp -s "$src" "$dest"; then
    echo "already saved: $dest"
    report_signer "$dest"
    exit 0
  fi
  dest=debug/apk/pureshell-${version}${suffix}_$n.apk
  n=$((n + 1))
done
cp "$src" "$dest"
echo "saved: $dest"
report_signer "$dest"
