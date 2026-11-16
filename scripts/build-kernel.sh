#!/usr/bin/env bash
# Bina kernel Linux untuk Redmi 5A (riva / MSM8917).
# Default: fork msm89x7-mainline (dikekalkan oleh pasukan postmarketOS) kerana ia membawa
# pemacu panel skrin yang TIADA dalam Linux mainline - tanpanya skrin kekal hitam.
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${WORK_DIR:-${ROOT_DIR}/work}"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/out}"
SRC="${WORK_DIR}/linux"
BUILD="${WORK_DIR}/kernel-out"
MODROOT="${WORK_DIR}/modroot"

KERNEL_REPO="${KERNEL_REPO:-https://github.com/msm89x7-mainline/linux.git}"
KERNEL_REF="${KERNEL_REF:-}"                    # cabang/tag; kosong = cabang default repo
KERNEL_CONFIG_URL="${KERNEL_CONFIG_URL:-}"      # pilihan: config penuh (cth. config postmarketOS)
# Redmi 5A = riva, Redmi 4A = rolex (perkakasan hampir sama; beza: pengecas, fuel gauge, panel, codec speaker)
DTB_NAMES="${DTB_NAMES:-msm8917-xiaomi-riva.dtb msm8917-xiaomi-rolex.dtb}"
SKIP_CONFIG_CHECK="${SKIP_CONFIG_CHECK:-0}"

export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
mkdir -p "${WORK_DIR}" "${OUT_DIR}/boot" "${OUT_DIR}/kernel"
rm -rf "${SRC}" "${BUILD}" "${MODROOT}"

echo "==> Clone ${KERNEL_REPO} ${KERNEL_REF}"
git clone --depth=1 ${KERNEL_REF:+--branch "${KERNEL_REF}"} "${KERNEL_REPO}" "${SRC}"
KERNEL_COMMIT="$(git -C "${SRC}" rev-parse HEAD)"

echo "==> Configure native eMMC kernel"
if [[ -n "${KERNEL_CONFIG_URL}" ]]; then
  mkdir -p "${BUILD}"
  curl -fL --retry 3 "${KERNEL_CONFIG_URL}" -o "${BUILD}/.config"
  make -C "${SRC}" O="${BUILD}" olddefconfig
else
  make -C "${SRC}" O="${BUILD}" defconfig
fi
"${SRC}/scripts/kconfig/merge_config.sh" -m -O "${BUILD}" "${BUILD}/.config" "${ROOT_DIR}/config/kernel.fragment"

# Semua pemacu panel DRM sebagai modul (udev akan muat yang sepadan dengan skrin telefon).
mapfile -t PANELS < <(grep -rhoE '^config DRM_PANEL_[A-Z0-9_]+' "${SRC}"/drivers/gpu/drm/panel/Kconfig* | awk '{print $2}' | sort -u)
for sym in "${PANELS[@]}"; do
  "${SRC}/scripts/config" --file "${BUILD}/.config" --module "${sym}" || true
done
make -C "${SRC}" O="${BUILD}" olddefconfig

echo "==> Checking built-in options required for native internal-eMMC rootfs boot"
REQUIRED=(ARCH_QCOM PINCTRL_MSM8917 MSM_GCC_8917 MMC_SDHCI_MSM MMC_BLOCK EFI_PARTITION EXT4_FS DEVTMPFS)
MISSING=()
for sym in "${REQUIRED[@]}"; do
  grep -q "^CONFIG_${sym}=y" "${BUILD}/.config" || MISSING+=("${sym}")
done
if (( ${#MISSING[@]} )); then
  echo "ERROR: these required native-boot options are not built in: ${MISSING[*]}" >&2
  echo "This kernel may not mount the internal GPT userdata root. Check the kernel source/configuration." >&2
  [[ "${SKIP_CONFIG_CHECK}" == "1" ]] || exit 3
fi
# Pemacu paparan: =y atau =m sama-sama diterima (modul dimuat oleh udev selepas boot).
# Kconfig menurunkan DRM_MSM ke =m jika kebergantungannya (cth. QCOM_LLCC) ialah modul.
if grep -q '^CONFIG_DRM_MSM=y' "${BUILD}/.config"; then
  echo "DRM_MSM=y (paparan awal)"
elif grep -q '^CONFIG_DRM_MSM=m' "${BUILD}/.config"; then
  echo "AMARAN: DRM_MSM=m - paparan hanya muncul selepas udev memuat modul (normal, bukan ralat)."
else
  echo "RALAT: DRM_MSM tiada langsung - skrin tidak akan berfungsi." >&2
  [[ "${SKIP_CONFIG_CHECK}" == "1" ]] || exit 3
fi

echo "==> Compile kernel"
make -C "${SRC}" O="${BUILD}" -j"$(nproc)" Image dtbs modules

[[ -s "${BUILD}/arch/arm64/boot/Image" ]] || { echo "RALAT: Image tiada." >&2; exit 2; }
install -m 0644 "${BUILD}/arch/arm64/boot/Image" "${OUT_DIR}/boot/Image"
cp "${BUILD}/.config" "${OUT_DIR}/kernel/config"

BUILT=()
for name in ${DTB_NAMES}; do
  DTB="${BUILD}/arch/arm64/boot/dts/qcom/${name}"
  [[ -s "${DTB}" ]] || DTB="$(find "${BUILD}/arch/arm64/boot/dts" -name "${name}" | head -n1 || true)"
  if [[ -s "${DTB:-}" ]]; then
    install -m 0644 "${DTB}" "${OUT_DIR}/boot/${name}"; BUILT+=("${name}")
  else
    echo "AMARAN: ${name} tidak dihasilkan oleh sumber kernel ini (peranti itu belum disokong dalam kernel ini)." >&2
  fi
done
(( ${#BUILT[@]} )) || { echo "RALAT: tiada satu pun DTB (${DTB_NAMES}) dihasilkan." >&2; exit 2; }
echo "DTB dibina: ${BUILT[*]}"

echo "==> Install kernel modules into the Arch rootfs"
make -C "${SRC}" O="${BUILD}" modules_install INSTALL_MOD_PATH="${MODROOT}/usr" INSTALL_MOD_STRIP=1
find "${MODROOT}" -maxdepth 4 \( -name build -o -name source \) -type l -delete
tar -C "${MODROOT}" -cf - usr | xz -T0 -6 > "${OUT_DIR}/kernel/modules.tar.xz"

KREL="$(make -s -C "${SRC}" O="${BUILD}" kernelrelease)"
printf 'repo=%s\nref=%s\ncommit=%s\nrelease=%s\ndtb=%s\n' \
  "${KERNEL_REPO}" "${KERNEL_REF:-default}" "${KERNEL_COMMIT}" "${KREL}" "${BUILT[*]}" > "${OUT_DIR}/kernel/INFO"
ls -lh "${OUT_DIR}/boot" "${OUT_DIR}/kernel"
