#!/usr/bin/env bash
# Replace ONLY the installer script inside an already-built Riva-Arch-Boot.zip.
# The big rootfs-*.tar.xz is not touched or recompressed, so no rebuild is needed.
# Usage: tools/patch-existing-arch-zip.sh /path/to/Riva-Arch-Boot.zip
set -Eeuo pipefail
ZIP="${1:?usage: $0 Riva-Arch-Boot.zip}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/META-INF/com/google/android"
cp "$HERE/installer/arch/META-INF/com/google/android/update-binary" \
   "$HERE/installer/arch/META-INF/com/google/android/updater-script" \
   "$TMP/META-INF/com/google/android/"
chmod 0755 "$TMP/META-INF/com/google/android/update-binary"
( cd "$TMP" && zip -X -9 "$(realpath "$ZIP")" \
    META-INF/com/google/android/update-binary \
    META-INF/com/google/android/updater-script )
unzip -t "$ZIP" >/dev/null && echo "Patched OK: $ZIP"
sha256sum "$ZIP" > "$ZIP.sha256"
