#!/usr/bin/env bash
# Lengkapkan DTB yang tiada (cth. rolex) TANPA bina semula kernel, menggunakan out/kernel/config
# dan commit kernel yang sama (direkod dalam out/kernel/INFO). Berguna bila guna semula artifact kernel lama.
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${WORK_DIR:-${ROOT_DIR}/work}"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/out}"
DTB_NAMES="${DTB_NAMES:-msm8917-xiaomi-riva.dtb msm8917-xiaomi-rolex.dtb}"

MISSING=()
for n in ${DTB_NAMES}; do [[ -s "${OUT_DIR}/boot/${n}" ]] || MISSING+=("${n}"); done
(( ${#MISSING[@]} )) || { echo "Semua DTB sudah ada."; exit 0; }
echo "DTB tiada: ${MISSING[*]} - bina sahaja DTB (tanpa bina kernel)"

[[ -s "${OUT_DIR}/kernel/INFO" && -s "${OUT_DIR}/kernel/config" ]] || { echo "RALAT: INFO/config kernel tiada." >&2; exit 2; }
REPO="$(sed -n 's/^repo=//p' "${OUT_DIR}/kernel/INFO")"
COMMIT="$(sed -n 's/^commit=//p' "${OUT_DIR}/kernel/INFO")"
[[ -n "${REPO}" && -n "${COMMIT}" ]] || { echo "RALAT: repo/commit tiada dalam INFO." >&2; exit 2; }

SRC="${WORK_DIR}/linux-dtb"; BUILD="${WORK_DIR}/dtb-out"
rm -rf "${SRC}" "${BUILD}"; mkdir -p "${SRC}" "${BUILD}"
git -C "${SRC}" init -q
git -C "${SRC}" remote add origin "${REPO}"
git -C "${SRC}" fetch -q --depth=1 origin "${COMMIT}"
git -C "${SRC}" checkout -q FETCH_HEAD

export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
cp "${OUT_DIR}/kernel/config" "${BUILD}/.config"
make -C "${SRC}" O="${BUILD}" olddefconfig >/dev/null

GOT=0
for n in "${MISSING[@]}"; do
  target="qcom/${n}"
  if make -C "${SRC}" O="${BUILD}" -j"$(nproc)" "${target}"; then
    install -m 0644 "${BUILD}/arch/arm64/boot/dts/qcom/${n}" "${OUT_DIR}/boot/${n}"; GOT=$((GOT+1))
    echo "OK: ${n}"
  else
    echo "AMARAN: ${n} tidak boleh dibina daripada commit ${COMMIT:0:12} (kernel ini tiada sokongan peranti itu)." >&2
  fi
done
ls -l "${OUT_DIR}/boot"
