#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/out}"
STAGE="${ROOT_DIR}/work/android-restore-stage"
ZIP="${OUT_DIR}/Riva-Android-Restore.zip"
rm -rf "$STAGE" "$ZIP"
mkdir -p "$STAGE/META-INF/com/google/android"
cp "$ROOT_DIR/installer/restore/META-INF/com/google/android/update-binary" "$STAGE/META-INF/com/google/android/"
cp "$ROOT_DIR/installer/restore/META-INF/com/google/android/updater-script" "$STAGE/META-INF/com/google/android/"
cp "$ROOT_DIR/installer/restore/README-RESTORE.txt" "$STAGE/README-RESTORE.txt"
chmod 0755 "$STAGE/META-INF/com/google/android/update-binary"
( cd "$STAGE" && zip -r -X -9 "$ZIP" META-INF README-RESTORE.txt )
unzip -t "$ZIP" >/dev/null
sha256sum "$ZIP" > "$ZIP.sha256"
ls -lh "$ZIP" "$ZIP.sha256"
