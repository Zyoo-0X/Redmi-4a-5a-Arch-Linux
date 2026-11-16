#!/usr/bin/env bash
# Run inside an aarch64 chroot under qemu. Profiles: terminal | kde | gnome
set -Eeuo pipefail
DE="${1:?terminal|kde|gnome}"
[[ "$DE" == terminal || "$DE" == kde || "$DE" == gnome ]] || { echo "Unsupported profile: $DE" >&2; exit 1; }
SETUP=/root/riva-setup

# --- pacman: chroot di bawah qemu tidak menyokong sandbox/CheckSpace
sed -i 's/^CheckSpace/#CheckSpace/' /etc/pacman.conf
grep -q '^DisableSandbox' /etc/pacman.conf || sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf
sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf

pacman-key --init
pacman-key --populate archlinuxarm

# Buang kernel/uboot generik (kita guna kernel sendiri), kemudian naik taraf PENUH.
# (Naik taraf separa - pacman -Syy sahaja - boleh merosakkan rootfs.)
for pkg in linux-aarch64 linux-aarch64-headers; do
  pacman -Rns --noconfirm "$pkg" 2>/dev/null || true
done
# Pemecahan linux-firmware (2025) menyebabkan konflik semasa naik taraf; buang dulu, pasang semula selepas ini.
pacman -Rdd --noconfirm linux-firmware 2>/dev/null || true
pacman -Syu --noconfirm

read_list() { grep -vE '^\s*(#|$)' "$1" 2>/dev/null || true; }
FAILED=()
install_list() {
  local pk=()
  mapfile -t pk < <(read_list "$1")
  (( ${#pk[@]} )) || return 0
  if pacman -S --noconfirm --needed "${pk[@]}"; then return 0; fi
  echo "AMARAN: pemasangan kelompok gagal ($1) - cuba satu-satu"
  for p in "${pk[@]}"; do
    pacman -S --noconfirm --needed "$p" || FAILED+=("$p")
  done
}
if [[ "$DE" == terminal ]]; then
  install_list "${SETUP}/packages/terminal.txt"
else
  install_list "${SETUP}/packages/common.txt"
  install_list "${SETUP}/packages/${DE}.txt"
fi

# Pakej teras mesti ada; selainnya (kitty, foot, dll.) hanya diberi amaran supaya binaan 1+ jam tidak sia-sia.
case "${DE}" in
  terminal) CORE="networkmanager sudo" ;;
  kde) CORE="networkmanager sudo plasma-desktop" ;;
  gnome) CORE="networkmanager sudo gnome-shell gnome-session" ;;
esac
for c in ${CORE}; do
  pacman -Q "$c" >/dev/null 2>&1 || { echo "RALAT: pakej teras '$c' tidak terpasang" >&2; exit 1; }
done
if (( ${#FAILED[@]} )); then
  echo "AMARAN: pakej tidak dapat dipasang: ${FAILED[*]}"
  printf '%s\n' "${FAILED[@]}" > /etc/riva-missing-packages
fi

# Pakej pilihan: satu-satu supaya pakej yang tiada dalam repo ARM tidak menggagalkan binaan.
for p in $(read_list "${SETUP}/packages/${DE}.optional.txt"); do
  pacman -S --noconfirm --needed "$p" || echo "AMARAN: pakej pilihan '$p' tiada/gagal - dilangkau"
done
# Firmware: cuba pakej split Qualcomm dahulu (jauh lebih kecil), baru meta-pakej penuh.
pacman -S --noconfirm --needed linux-firmware-qcom || pacman -S --noconfirm --needed linux-firmware

# --- akaun: buang akaun lalai ALARM (alarm/alarm, root/root) yang tidak selamat
userdel -r alarm 2>/dev/null || true
GROUPS_OK=""
for g in wheel video input storage network audio; do getent group "$g" >/dev/null && GROUPS_OK="${GROUPS_OK},${g}"; done
id riva >/dev/null 2>&1 || useradd -m ${GROUPS_OK:+-G "${GROUPS_OK#,}"} -s /bin/bash riva
echo 'riva:riva' | chpasswd
passwd -l root || true
echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/10-riva
chmod 0440 /etc/sudoers.d/10-riva

# --- sistem
echo riva-arch > /etc/hostname
ln -sf /usr/share/zoneinfo/Asia/Kuala_Lumpur /etc/localtime
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
printf 'LABEL=RIVA_ROOT / ext4 defaults,noatime,commit=60 0 1\n' > /etc/fstab

# --- salin overlay (sudah ada di /root/riva-setup/overlay-*), tetapkan pemilik
cp -a "${SETUP}/overlay-common/." /
cp -a "${SETUP}/overlay-${DE}/." /
chown -R riva:riva /home/riva
# Bit executable hilang jika projek dimuat naik melalui web/zip - pasang semula.
chmod 0755 /usr/local/bin/kitty /usr/local/bin/riva-gfx 2>/dev/null || true
chmod 0755 /usr/local/bin/riva-kde-scale 2>/dev/null || true

# --- rangkaian: NetworkManager + systemd-resolved (resolv.conf mesti symlink, bukan salinan host build)
systemctl disable systemd-networkd.service systemd-networkd.socket 2>/dev/null || true
systemctl enable NetworkManager.service systemd-resolved.service systemd-timesyncd.service
rm -f /etc/resolv.conf
ln -s ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
systemctl disable sshd.service 2>/dev/null || true
# Elak jam menunggu rangkaian & tugas berat di latar belakang
systemctl mask systemd-networkd-wait-online.service NetworkManager-wait-online.service 2>/dev/null || true
systemctl disable archlinux-keyring-wkd-sync.timer man-db.timer 2>/dev/null || true
systemctl set-default multi-user.target   # sesi desktop dimulakan oleh autologin tty1

if [[ "${DE}" == gnome ]]; then
  dconf update
fi

echo "${DE}" > /etc/riva-release

# Hentikan gpg-agent/dirmngr yang dimulakan pacman-key (jika tidak, ia mengunci mount chroot)
gpgconf --homedir /etc/pacman.d/gnupg --kill all 2>/dev/null || true

# --- bersih-bersih untuk kecilkan imej
pacman -Scc --noconfirm || true
rm -rf /var/cache/pacman/pkg/* /var/lib/pacman/sync/* /root/riva-setup /root/.bash_history
: > /etc/machine-id
find /var/log -type f -delete 2>/dev/null || true
