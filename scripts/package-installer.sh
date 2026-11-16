#!/usr/bin/env bash
# Himpun zip flashable (OrangeFox/TWRP) dengan pilihan Volume Up = KDE, Volume Down = GNOME.
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/out}"
STAGE="${ROOT_DIR}/work/zip-stage"
ZIP="${OUT_DIR}/Riva-ArchLinux-Installer.zip"
LK2ND_URL="${LK2ND_URL:-}"
LK2ND_SHA256="${LK2ND_SHA256:-}"       # pilihan: kalau diisi, wajib sepadan

for f in boot/Image rootfs-kde.tar.xz rootfs-gnome.tar.xz; do
  [[ -s "${OUT_DIR}/${f}" ]] || { echo "RALAT: ${OUT_DIR}/${f} tiada" >&2; exit 2; }
done
DTBS=()
for n in msm8917-xiaomi-riva.dtb msm8917-xiaomi-rolex.dtb; do
  [[ -s "${OUT_DIR}/boot/${n}" ]] && DTBS+=("${n}")
done
(( ${#DTBS[@]} )) || { echo "RALAT: tiada DTB riva/rolex dalam ${OUT_DIR}/boot" >&2; exit 2; }
echo "DTB dalam zip: ${DTBS[*]}"

rm -rf "${STAGE}" "${ZIP}"; mkdir -p "${STAGE}/boot"
cp -a "${ROOT_DIR}/installer/META-INF" "${STAGE}/"
chmod 0755 "${STAGE}/META-INF/com/google/android/update-binary"
cp "${OUT_DIR}/boot/Image" "${STAGE}/boot/"
for n in "${DTBS[@]}"; do cp "${OUT_DIR}/boot/${n}" "${STAGE}/boot/"; done

echo "==> lk2nd"
if [[ -z "${LK2ND_URL}" ]]; then
  LK2ND_URL="$(curl -fsL https://api.github.com/repos/msm8916-mainline/lk2nd/releases/latest \
    | jq -r '.assets[]|select(.name=="lk2nd-msm8952.img")|.browser_download_url' | head -n1 || true)"
  [[ -n "${LK2ND_URL}" ]] || LK2ND_URL="https://github.com/msm8916-mainline/lk2nd/releases/download/23.1/lk2nd-msm8952.img"
fi
curl -fL --retry 3 "${LK2ND_URL}" -o "${STAGE}/boot/lk2nd-msm8952.img"
LK_SHA="$(sha256sum "${STAGE}/boot/lk2nd-msm8952.img" | cut -d' ' -f1)"
if [[ -n "${LK2ND_SHA256}" && "${LK_SHA}" != "${LK2ND_SHA256}" ]]; then
  echo "RALAT: sha256 lk2nd tidak sepadan (${LK_SHA})" >&2; exit 4
fi

cat > "${STAGE}/BUILD-INFO.txt" <<INFO
Riva Arch Linux installer - Redmi 5A (riva) / Redmi 4A (rolex)
DTB       : ${DTBS[*]}
Build UTC : $(date -u +%Y-%m-%dT%H:%M:%SZ)
lk2nd     : ${LK2ND_URL}
lk2nd sha : ${LK_SHA}
$(cat "${OUT_DIR}/kernel/INFO" 2>/dev/null || true)
EXPERIMENTAL - belum diuji pada telefon sebenar.
INFO

( cd "${STAGE}" && zip -r -X -9 "${ZIP}" META-INF boot BUILD-INFO.txt )
# Rootfs sudah termampat (xz): simpan tanpa pemampatan semula.
( cd "${OUT_DIR}" && zip -0 -X "${ZIP}" rootfs-kde.tar.xz rootfs-gnome.tar.xz )

SIZE=$(stat -c %s "${ZIP}")
ls -lh "${ZIP}"
if (( SIZE > 2000000000 )); then
  echo "AMARAN: zip > 2 GB - melebihi had aset GitHub Release (2 GB). Kurangkan pakej atau pecahkan." >&2
fi
