#!/usr/bin/env bash
# Build one Arch Linux ARM profile: terminal, kde or gnome.
# Requires sudo, qemu-user-static and the previously built kernel modules.
set -Eeuo pipefail

DE="${1:?Usage: build-rootfs.sh terminal|kde|gnome}"
[[ "${DE}" == terminal || "${DE}" == kde || "${DE}" == gnome ]] || { echo "DE must be terminal, kde or gnome" >&2; exit 1; }

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${WORK_DIR:-${ROOT_DIR}/work}"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/out}"
ROOTFS="${WORK_DIR}/rootfs-${DE}"
TARBALL="${WORK_DIR}/ArchLinuxARM-aarch64-latest.tar.gz"

# Rootfs sudah ada (cth. dimuat turun daripada run lama)? Langkau - jimat masa.
if [[ -s "${OUT_DIR}/rootfs-${DE}.tar.xz" && "${FORCE_REBUILD:-0}" != 1 ]]; then
  echo "==> rootfs-${DE}.tar.xz sudah ada - dilangkau (FORCE_REBUILD=1 untuk bina semula)"
  [[ -n "${GITHUB_OUTPUT:-}" ]] && echo "built=0" >> "${GITHUB_OUTPUT}"
  exit 0
fi

[[ -s "${OUT_DIR}/kernel/modules.tar.xz" ]] || { echo "RALAT: bina kernel dahulu." >&2; exit 2; }
QEMU="$(command -v qemu-aarch64-static || true)"
[[ -n "${QEMU}" ]] || { echo "RALAT: pasang qemu-user-static + binfmt-support." >&2; exit 2; }

mkdir -p "${WORK_DIR}"
# os.archlinuxarm.org kadang-kadang mempunyai sijil HTTPS yang tidak sepadan; cuba beberapa sumber.
# Integriti: md5 (daripada sumber yang sama) + semua pakej kemudiannya disahkan tandatangan oleh pacman.
if [[ ! -s "${TARBALL}" ]]; then
  CANDIDATES=()
  [[ -n "${ROOTFS_URL:-}" ]] && CANDIDATES+=("${ROOTFS_URL}")
  CANDIDATES+=(
    "https://os.archlinuxarm.org/os"
    "https://mirror.archlinuxarm.org/os"
    "http://mirror.archlinuxarm.org/os"
    "http://os.archlinuxarm.org/os"
  )
  GOT=""
  for base in "${CANDIDATES[@]}"; do
    echo "==> Cuba ${base}"
    if curl -fL --retry 2 --retry-delay 2 --connect-timeout 20 "${base}/ArchLinuxARM-aarch64-latest.tar.gz" -o "${TARBALL}.part"; then
      mv "${TARBALL}.part" "${TARBALL}"
      curl -fsL --retry 2 --connect-timeout 20 "${base}/ArchLinuxARM-aarch64-latest.tar.gz.md5" -o "${TARBALL}.md5" || rm -f "${TARBALL}.md5"
      GOT="${base}"; break
    fi
    rm -f "${TARBALL}.part"
  done
  [[ -n "${GOT}" ]] || { echo "RALAT: semua sumber rootfs gagal. Letak ROOTFS_URL=<url> secara manual." >&2; exit 4; }
  if [[ -s "${TARBALL}.md5" ]]; then
    (cd "${WORK_DIR}" && md5sum -c "$(basename "${TARBALL}").md5") || { echo "RALAT: md5 rootfs tidak sepadan" >&2; rm -f "${TARBALL}"; exit 4; }
  else
    echo "AMARAN: fail .md5 tidak dapat dimuat turun; integriti tidak disahkan" >&2
  fi
fi


# ---------------------------------------------------------------------------
# Pengurusan mount chroot yang SELAMAT.
# Pelajaran: pacman-key meninggalkan gpg-agent yang mengunci mount; umount gagal senyap lalu
# `rm -rf` masuk ke /dev runner. Maka: bunuh proses sisa, unmount (lazy sebagai sandaran),
# SAHKAN tiada mount tinggal, dan rm hanya dengan --one-file-system.
# ---------------------------------------------------------------------------
mounts_under() { findmnt -rn -o TARGET | grep -E "^${ROOTFS}(/|$)" | sort -r || true; }

release_chroot() {
  local p r m
  for p in /proc/[0-9]*; do
    r="$(sudo readlink "${p}/root" 2>/dev/null || true)"
    [[ "${r}" == "${ROOTFS}" ]] && sudo kill -9 "${p#/proc/}" 2>/dev/null || true
  done
  sleep 1
  for _ in 1 2 3; do
    mapfile -t M < <(mounts_under)
    (( ${#M[@]} )) || return 0
    for m in "${M[@]}"; do sudo umount "${m}" 2>/dev/null || sudo umount -l "${m}" 2>/dev/null || true; done
    sleep 1
  done
  mapfile -t M < <(mounts_under)
  (( ${#M[@]} == 0 ))
}

safe_rm_rootfs() {
  if [[ -n "$(mounts_under)" ]]; then
    echo "RALAT: masih ada mount di bawah ${ROOTFS}; TIDAK memadam demi keselamatan." >&2
    return 1
  fi
  sudo rm -rf --one-file-system "${ROOTFS}"
}

release_chroot || true
safe_rm_rootfs || exit 5
mkdir -p "${ROOTFS}"
sudo tar -xpf "${TARBALL}" --numeric-owner --xattrs --xattrs-include='*' --acls --warning=no-unknown-keyword -C "${ROOTFS}"

cleanup() { release_chroot || echo "AMARAN: unmount chroot tidak lengkap" >&2; }
trap cleanup EXIT

# Kernel modules (keep-directory-symlink kerana /lib -> usr/lib)
sudo xz -dc "${OUT_DIR}/kernel/modules.tar.xz" | sudo tar -x --keep-directory-symlink --no-same-owner -C "${ROOTFS}"

# Bahan persediaan untuk chroot
sudo mkdir -p "${ROOTFS}/root/riva-setup"
sudo cp -a "${ROOT_DIR}/config/packages" "${ROOTFS}/root/riva-setup/packages"
sudo cp -a "${ROOT_DIR}/overlay/common" "${ROOTFS}/root/riva-setup/overlay-common"
if [[ -d "${ROOT_DIR}/overlay/${DE}" ]]; then
  sudo cp -a "${ROOT_DIR}/overlay/${DE}" "${ROOTFS}/root/riva-setup/overlay-${DE}"
else
  sudo mkdir -p "${ROOTFS}/root/riva-setup/overlay-${DE}"
fi
sudo install -m 0755 "${ROOT_DIR}/scripts/chroot-setup.sh" "${ROOTFS}/root/riva-setup/chroot-setup.sh"

sudo install -m 0755 "${QEMU}" "${ROOTFS}/usr/bin/qemu-aarch64-static"
sudo rm -f "${ROOTFS}/etc/resolv.conf"
printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' | sudo tee "${ROOTFS}/etc/resolv.conf" >/dev/null

sudo mount -t proc proc "${ROOTFS}/proc"
sudo mount -t sysfs sys "${ROOTFS}/sys"
sudo mount --rbind /dev "${ROOTFS}/dev"
sudo mount --make-rslave "${ROOTFS}/dev"

sudo chroot "${ROOTFS}" /usr/bin/qemu-aarch64-static /bin/bash /root/riva-setup/chroot-setup.sh "${DE}"

release_chroot || { echo "RALAT: gagal unmount chroot; berhenti sebelum pek/padam." >&2; exit 5; }
sudo rm -f "${ROOTFS}/usr/bin/qemu-aarch64-static"

echo "==> Pek rootfs-${DE} (xz; boleh ambil masa)"
mkdir -p "${OUT_DIR}"
sudo tar -C "${ROOTFS}" --one-file-system --numeric-owner --xattrs --xattrs-include='*' --acls -cpf - . \
  | xz -T0 -6 > "${OUT_DIR}/rootfs-${DE}.tar.xz"
safe_rm_rootfs || echo "AMARAN: rootfs sementara tidak dipadam" >&2
[[ -n "${GITHUB_OUTPUT:-}" ]] && echo "built=1" >> "${GITHUB_OUTPUT}"
ls -lh "${OUT_DIR}/rootfs-${DE}.tar.xz"
