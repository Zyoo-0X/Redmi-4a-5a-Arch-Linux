#!/usr/bin/env bash
# Package one selected Arch Linux rootfs into a TWRP-flashable ZIP (<2 GB).
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/out}"
DESKTOP="${DESKTOP:-kde}"
case "$DESKTOP" in terminal|kde|gnome) ;; *) echo "DESKTOP must be terminal, kde or gnome" >&2; exit 2 ;; esac

ROOTFS="${OUT_DIR}/rootfs-${DESKTOP}.tar.xz"
LK2ND_IMAGE="${OUT_DIR}/boot/lk2nd-riva.img"
for f in "${OUT_DIR}/boot/Image" "${OUT_DIR}/boot/msm8917-xiaomi-riva.dtb" "$LK2ND_IMAGE" "${OUT_DIR}/kernel/config" "$ROOTFS"; do
  [[ -s "$f" ]] || { echo "Missing required file: $f" >&2; exit 2; }
done

# Custom LK2ND uses 64 MiB starting at 0x80000000. Redmi 5A DTS reserves
# qseecom memory starting at 0x84a00000, so this window ends 10 MiB earlier.
LK2ND_BOOT_MEM_SIZE_BYTES=$((64 * 1024 * 1024))
LK2ND_SHA256_ACTUAL="$(sha256sum "$LK2ND_IMAGE" | cut -d' ' -f1)"
python3 - "${OUT_DIR}/boot/Image" "${OUT_DIR}/boot/msm8917-xiaomi-riva.dtb" "$LK2ND_BOOT_MEM_SIZE_BYTES" <<'CHECK_KERNEL'
import os, struct, sys
image, dtb, mem_text = sys.argv[1:]
mem = int(mem_text)
with open(image, "rb") as f:
    hdr = f.read(64)
if len(hdr) < 32:
    raise SystemExit("Kernel Image header is too small")
text_offset = struct.unpack_from("<Q", hdr, 8)[0]
image_size = struct.unpack_from("<Q", hdr, 16)[0]
if image_size == 0:
    raise SystemExit("Kernel Image header has image_size=0; refusing unverified boot image")
if text_offset > 2 * 1024 * 1024:
    text_offset = 0
else:
    text_offset = text_offset or 0x80000
max_kernel = mem - (2 * 1024 * 1024) - text_offset
file_size = os.path.getsize(image)
dtb_size = os.path.getsize(dtb)
if file_size > max_kernel or image_size > max_kernel:
    raise SystemExit(f"Kernel too large for LK2ND: file={file_size}, image_size={image_size}, max={max_kernel}")
if dtb_size >= 2 * 1024 * 1024:
    raise SystemExit(f"DTB too large for LK2ND's 2 MiB tags area: {dtb_size}")
print(f"LK2ND memory check OK: image_size={image_size}, max_kernel={max_kernel}, DTB={dtb_size}, boot_mem={mem}")
CHECK_KERNEL

ROOTFS_UNCOMPRESSED="$(xz -l --robot "$ROOTFS" | awk -F'\t' '$1=="totals" {print $5}')"
[[ "$ROOTFS_UNCOMPRESSED" =~ ^[0-9]+$ ]] || { echo "Cannot read rootfs uncompressed size." >&2; exit 4; }

STAGE="${ROOT_DIR}/work/internal-boot-stage"
ZIP="${OUT_DIR}/Riva-Arch-Boot.zip"
rm -rf "$STAGE" "$ZIP"
mkdir -p "$STAGE/META-INF/com/google/android" "$STAGE/boot"
cp "$ROOT_DIR/installer/arch/META-INF/com/google/android/update-binary" "$STAGE/META-INF/com/google/android/"
cp "$ROOT_DIR/installer/arch/META-INF/com/google/android/updater-script" "$STAGE/META-INF/com/google/android/"
chmod 0755 "$STAGE/META-INF/com/google/android/update-binary"
cp "$OUT_DIR/boot/Image" "$STAGE/boot/"
cp "$OUT_DIR/boot/msm8917-xiaomi-riva.dtb" "$STAGE/boot/"
cp "$LK2ND_IMAGE" "$STAGE/boot/lk2nd-riva.img"

cat > "$STAGE/BUILD-INFO.txt" <<INFO
device=riva
desktop=${DESKTOP}
rootfs_file=rootfs-${DESKTOP}.tar.xz
rootfs_compressed_bytes=$(stat -c %s "$ROOTFS")
rootfs_uncompressed_bytes=${ROOTFS_UNCOMPRESSED}
rootfs_uncompressed_sectors=$((ROOTFS_UNCOMPRESSED / 512))
kernel_source=https://github.com/msm89x7-mainline/linux.git
lk2nd_source=https://github.com/msm8916-mainline/lk2nd
lk2nd_commit=cf45aefd22d744b2bf9b39455afae697ce430063
lk2nd_target=msm8952 (MSM8917)
lk2nd_boot_mem_size_bytes=${LK2ND_BOOT_MEM_SIZE_BYTES}
lk2nd_base_addr=0x80000000
lk2nd_reserved_memory_start=0x84a00000
lk2nd_sha256=${LK2ND_SHA256_ACTUAL}
build_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
partition_strategy=system-ext2-for-lk2nd;userdata-ext4-for-rootfs;no-gpt-changes
INFO

# Keep the rootfs already compressed by xz; do not recompress it.
( cd "$STAGE" && zip -r -X -9 "$ZIP" META-INF boot BUILD-INFO.txt )
( cd "$OUT_DIR" && zip -0 -X "$ZIP" "rootfs-${DESKTOP}.tar.xz" )
SIZE=$(stat -c %s "$ZIP")
if (( SIZE >= 1900000000 )); then
  echo "Riva-Arch-Boot.zip is too large for the GitHub Release safety limit: ${SIZE} bytes." >&2
  rm -f "$ZIP"; exit 5
fi
unzip -t "$ZIP" >/dev/null
sha256sum "$ZIP" > "$ZIP.sha256"
ls -lh "$ZIP" "$ZIP.sha256"
