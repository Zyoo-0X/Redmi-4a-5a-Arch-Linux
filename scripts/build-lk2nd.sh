#!/usr/bin/env bash
# Build LK2ND for Redmi 5A using a 64 MiB extlinux boot-memory window.
# BASE_ADDR=0x80000000; Redmi 5A DTS reserves qseecom from 0x84a00000.
# 64 MiB ends at 0x84000000, below that reserved-memory region.
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${WORK_DIR:-${ROOT_DIR}/work}"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/out}"
LK2ND_REPO="${LK2ND_REPO:-https://github.com/msm8916-mainline/lk2nd.git}"
LK2ND_REF="${LK2ND_REF:-cf45aefd22d744b2bf9b39455afae697ce430063}"
LK2ND_BOOT_MEM_SIZE="${LK2ND_BOOT_MEM_SIZE:-0x04000000}"
LK2ND_SRC="${WORK_DIR}/lk2nd"

[[ "${LK2ND_BOOT_MEM_SIZE}" == "0x04000000" ]] || {
  echo "Refusing unexpected LK2ND memory size: ${LK2ND_BOOT_MEM_SIZE}" >&2
  exit 2
}
for tool in git make arm-none-eabi-gcc dtc; do
  command -v "${tool}" >/dev/null 2>&1 || { echo "Missing build tool: ${tool}" >&2; exit 2; }
done

rm -rf "${LK2ND_SRC}"
mkdir -p "${WORK_DIR}" "${OUT_DIR}/boot"
git clone --filter=blob:none "${LK2ND_REPO}" "${LK2ND_SRC}"
git -C "${LK2ND_SRC}" checkout --detach "${LK2ND_REF}"

make -C "${LK2ND_SRC}" \
  TOOLCHAIN_PREFIX=arm-none-eabi- \
  LK2ND_BOOT_MEM_SIZE="${LK2ND_BOOT_MEM_SIZE}" \
  lk2nd-msm8952

LK2ND_IMAGE="${LK2ND_SRC}/build-lk2nd-msm8952/lk2nd.img"
if [[ ! -s "${LK2ND_IMAGE}" ]]; then
  echo "LK2ND image not found at documented output path: ${LK2ND_IMAGE}" >&2
  find "${LK2ND_SRC}" -name lk2nd.img -type f -print >&2
  exit 3
fi
install -m 0644 "${LK2ND_IMAGE}" "${OUT_DIR}/boot/lk2nd-riva.img"
sha256sum "${OUT_DIR}/boot/lk2nd-riva.img" > "${OUT_DIR}/boot/lk2nd-riva.img.sha256"
echo "Built LK2ND for Redmi 5A (MSM8917 via msm8952 target)."
echo "Boot-memory window: ${LK2ND_BOOT_MEM_SIZE} (64 MiB)."
echo "LK2ND source commit: $(git -C "${LK2ND_SRC}" rev-parse HEAD)"
ls -lh "${OUT_DIR}/boot/lk2nd-riva.img"
