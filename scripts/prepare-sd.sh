#!/usr/bin/env bash
# Sediakan microSD pada PC Linux: p1 = RIVA_BOOT (ext2, 512 MiB), p2 = RIVA_ROOT (ext4, baki).
# GUNA: sudo ./prepare-sd.sh /dev/sdX      (MEMADAM SEMUA DATA pada kad)
set -Eeuo pipefail
DEV="${1:?guna: sudo $0 /dev/sdX}"
[[ $EUID -eq 0 ]] || { echo "Jalankan dengan sudo." >&2; exit 1; }
[[ -b "${DEV}" ]] || { echo "${DEV} bukan peranti blok." >&2; exit 1; }
[[ "$(lsblk -dno TYPE "${DEV}")" == disk ]] || { echo "${DEV} mesti disk penuh (bukan partition)." >&2; exit 1; }
[[ "$(lsblk -dno RM "${DEV}")" == 1 ]] || { echo "${DEV} bukan peranti boleh-tanggal. Dihentikan demi keselamatan." >&2; exit 1; }
SIZE_GB=$(( $(lsblk -bdno SIZE "${DEV}") / 1024 / 1024 / 1024 ))
(( SIZE_GB <= 256 )) || { echo "${DEV} ${SIZE_GB} GB - terlalu besar untuk microSD? Dihentikan." >&2; exit 1; }

lsblk "${DEV}"
echo "SEMUA data pada ${DEV} (${SIZE_GB} GB) akan DIPADAM."
read -r -p "Taip nama peranti penuh untuk teruskan: " ANS
[[ "${ANS}" == "${DEV}" ]] || { echo "Dibatalkan."; exit 1; }

umount "${DEV}"?* 2>/dev/null || true
wipefs -a "${DEV}"
parted -s "${DEV}" mklabel msdos
parted -s "${DEV}" mkpart primary ext2 1MiB 513MiB
parted -s "${DEV}" mkpart primary ext4 513MiB 100%
partprobe "${DEV}"; sleep 2
P1="${DEV}1"; P2="${DEV}2"
[[ -b "${P1}" ]] || { P1="${DEV}p1"; P2="${DEV}p2"; }
mkfs.ext2 -F -L RIVA_BOOT "${P1}"
mkfs.ext4 -F -L RIVA_ROOT "${P2}"
lsblk -f "${DEV}"
echo "Siap. Letak Riva-ArchLinux-Installer.zip pada storan INTERNAL telefon (bukan pada kad ini), kemudian flash di recovery."
