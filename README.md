# Riva Native Arch Linux ↔ Android (TWRP)

A GitHub Actions workspace for Xiaomi Redmi 5A (`riva`). It builds two separate recovery-flashable packages:

- **`Riva-Arch-Boot.zip`** — installs one selected Arch Linux ARM profile and switches the phone to LK2ND/Linux boot.
- **`Riva-Android-Restore.zip`** — prepares the original Android `system` and `userdata` filesystems so that a TWRP backup can be restored, or a compatible Android ROM can be clean-flashed.

> **Experimental port. Not tested on a physical Redmi 5A.** This uses the previously built `msm89x7-mainline` kernel, Redmi 5A DTB, kernel modules, and existing KDE/GNOME rootfs artifacts where available. Display, touch, GPU acceleration, Wi-Fi, audio, charging and suspend are not guaranteed.

## Important storage design

This project deliberately does **not** change the eMMC GPT or resize partitions. It reuses the existing Android partition map:

| Existing Android partition | Arch Linux use | Android return |
|---|---|---|
| `boot` | LK2ND secondary bootloader | Restore the saved TWRP Boot backup, or flash an Android ROM that writes its own boot image |
| `system` | Formatted as ext2; stores `Image`, Redmi 5A DTB and `/extlinux/extlinux.conf` | `Riva-Android-Restore.zip` formats it as ext4; then restore Android System/System Image or clean-flash a ROM |
| `userdata` | Formatted as ext4; stores the Arch Linux root filesystem | `Riva-Android-Restore.zip` formats it as ext4; then restore TWRP Data or format it for a clean ROM install |
| `recovery` | Left unchanged (TWRP/OrangeFox remains available) | Left unchanged |
| `vendor`, `persist`, modem-related partitions | Left unchanged | Left unchanged |

**This is not a GPT repartition ZIP.** Neither ZIP changes the partition table or partition sizes. The Android Restore ZIP only reformats `system` and `userdata` as ext4; the TWRP backup or Android ROM installer restores the actual Android contents. This is intentional: it avoids inventing device-specific sector offsets. The Arch installer erases Android `system` and `userdata`, and replaces the Android `boot` image with LK2ND. You must back up first.

## Desktop selection and file-size limit

Run the workflow once for one profile:

| Workflow choice | Result |
|---|---|
| `terminal` | Small command-line Arch Linux profile; lightest option |
| `kde` | KDE Plasma profile from the earlier project build |
| `gnome` | GNOME profile from the earlier project build |

Only one root filesystem is placed in `Riva-Arch-Boot.zip` per build. The rootfs is already `.xz`-compressed and is stored in the ZIP without recompressing it. The packaging script refuses to publish an Arch ZIP at or above **1.9 GB**, leaving margin below GitHub's 2 GB release-asset limit.

Hyprland is not offered in this build because the earlier project only had KDE and GNOME rootfs definitions. It should not be displayed as a working option until its ARM64 packages, session startup and graphics path are built and tested.

## 1. Before flashing: make and copy a TWRP backup

1. Unlock the bootloader and confirm TWRP/OrangeFox can boot on this exact phone.
2. Boot recovery and create a backup to **USB OTG or a PC**. Do not leave the only copy on internal storage: the Arch installer formats `userdata`.
3. Select the following partitions when they are shown by your recovery:
   - **Boot** — essential; Arch replaces the boot image with LK2ND.
   - **System or System Image** — essential; Arch uses the system partition for its boot files.
   - **Vendor or Vendor Image** — recommended; kept intact by the Arch installer, but useful for full Android recovery.
   - **Data** — apps, settings and app data. TWRP normally excludes shared internal storage (`/data/media`), so copy photos, downloads and documents separately.
   - **Recovery** — optional but recommended if available.
   - **Persist**, **EFS**, **modemst1**, **modemst2**, **fsg**, **modem**, **bluetooth** and **dsp** (only when your recovery exposes them) — make read-only backup copies for safekeeping. Never format these partitions and never restore identity/calibration data from another phone.
4. Copy the complete TWRP backup folder to a PC or USB OTG and verify the archive files are present. Keep a second copy of photos, downloads and documents because TWRP normally excludes shared storage (`/data/media`).
5. Keep a copy of the exact TWRP/OrangeFox recovery image, the Android boot image/ROM and the matching firmware package you currently use.

Do not wipe `persist`, EFS, modemst, fsg, bootloader or other radio/firmware partitions as part of this Linux process.

## 2. Build both ZIPs with GitHub Actions

1. Create a GitHub repository.
2. Upload the **contents of this project folder** to the repository root (so `.github/`, `scripts/`, `installer/`, `config/` and `overlay/` are at the top level).
3. Open **Actions → Build Riva Native Arch and Android Restore ZIPs → Run workflow**.
4. Choose one desktop: `terminal`, `kde` or `gnome`.
5. Keep `kernel_mode = reuse` to use the earlier kernel artifact. The default run ID is prefilled. If that artifact expires or is unavailable, the workflow builds a new kernel.
6. Keep the default rootfs run ID to reuse the earlier KDE/GNOME artifacts. If a selected rootfs artifact is missing, the workflow builds that profile again. `terminal` is built from the minimal package list.
7. Keep `publish_release = true`.
8. When the workflow finishes successfully, open **Releases** and download:
   - `Riva-Arch-Boot.zip`
   - `Riva-Android-Restore.zip`
   - their `.sha256` files

The workflow also uploads both ZIPs as a GitHub Actions artifact. Check that the build job is green before flashing.

## 3. Install Arch Linux from TWRP

**This erases Android System and Userdata, and replaces Boot with LK2ND.** Only continue after the full backup has been copied off the phone.

1. Keep `Riva-Arch-Boot.zip` on the PC or USB OTG. **Do not place it only in internal storage**: the installer formats `userdata`, which is where `/sdcard` lives.
2. Boot TWRP/OrangeFox and connect the phone to the PC.
3. Use **ADB Sideload** (Advanced → ADB Sideload) or select the ZIP from USB OTG. The installer intentionally refuses ZIPs launched from `/sdcard` or `/data`.
4. Do not manually wipe System or Data first; the installer formats the two target partitions itself.
5. Reboot System. LK2ND should find `/extlinux/extlinux.conf` on the ext2 `system` partition and boot the selected Arch root filesystem from `userdata`.

The installer refuses to proceed unless it identifies the phone as `riva`, finds the `system`, `userdata` and `boot` by-name blocks on `/dev/block/mmcblk0`, and sees sufficient partition sizes. It leaves `recovery`, `vendor`, `persist` and modem-related partitions untouched. It does not edit the GPT.

Default account in the existing desktop rootfs: `riva` / `riva`. Change the password immediately with `passwd` after boot. This default password is only for initial experimental setup.

## 4. Return to the previous Android ROM

1. Boot recovery (TWRP/OrangeFox remains in the `recovery` partition).
2. Keep `Riva-Android-Restore.zip` on the PC/USB OTG and flash it with **ADB Sideload** or from USB OTG. Do not run it from `/sdcard`: it formats `userdata`.
3. Flash **`Riva-Android-Restore.zip`**. This formats `system` and `userdata` as ext4. It does not write the GPT, boot, recovery, vendor, persist or modem partitions.
4. If the backup is on a PC rather than USB OTG, mount Data in TWRP and copy it back to the freshly formatted internal storage. Example from a PC (adjust the local backup folder as needed):
   ```sh
   adb push ./TWRP /data/media/0/TWRP
   ```
5. In TWRP choose **Restore** and restore your saved **Boot, System/System Image, Vendor/Vendor Image and Data** backups. Restore Recovery only if required by your setup.
6. Reboot System.

If you used a backup of a particular Android ROM, restore a consistent set from the same backup. Do not mix System from one ROM with Vendor/Data/Boot from another.

## 5. Switch from Arch Linux to crDroid or another Android ROM

There are two different operations:

- **Restore your previous Android:** flash `Riva-Android-Restore.zip`, then restore the matching TWRP backup.
- **Install crDroid cleanly:** flash `Riva-Android-Restore.zip` to put `system` and `userdata` back into Android-friendly ext4 filesystems, then follow the exact official crDroid instructions for Redmi 4A/5A. Do **not** restore old System/Boot/Data over the new ROM. Flash the ROM, required device firmware and optional GApps/Magisk exactly as that ROM's guide specifies.

For crDroid 12, the published Redmi 4A/5A guide requires an unlocked bootloader, a compatible recovery, wiping Dalvik/ART Cache, System, Vendor and Cache, formatting Data, flashing the ROM, then flashing the specified Android 7-based firmware; GApps and Magisk are optional. Always use the live device-specific guide and stop if any step fails.

## 6. Troubleshooting and recovery

- If the Arch installer reports `system`/`userdata` by-name missing, stop. Do not substitute a guessed `/dev/block/mmcblk0pNN` number. The installer is designed to fail closed.
- If LK2ND does not load Linux, return to recovery and restore the saved Boot/System/Data backup using `Riva-Android-Restore.zip` first.
- If TWRP cannot decrypt Data after the Android filesystem restore, use the recovery's **Format Data** option and then restore the Data backup again. This deletes the contents of Data, so keep the backup external.
- Keep the `.sha256` files and verify the downloaded ZIPs on the PC before flashing.
- Do not flash a ZIP built for Redmi 4A (`rolex`) or any other device. This workspace targets Redmi 5A (`riva`) only.

## 7. What is and is not proven

The earlier project produced a kernel artifact with both the `riva` and `rolex` DTBs, and separate KDE/GNOME rootfs artifacts. This workspace reuses those artifacts when available and packages only the selected desktop. It also builds a custom LK2ND image from the pinned `msm8916-mainline/lk2nd` commit for a 64 MiB extlinux boot-memory window. The earlier kernel's arm64 `Image` header reports an image size around 51.8 MiB, so the upstream 50 MiB default is too small. The custom window starts at `0x80000000` and ends at `0x84000000`; the Redmi 5A device tree places the qseecom reserved-memory region at `0x84a00000`, leaving a 10 MiB gap. The packaging script checks the kernel `image_size` and DTB size against this budget before it creates the ZIP. Packaging scripts include LK2ND memory-budget, size and ZIP integrity checks.

This workspace has not been tested on a physical Redmi 5A. In particular, no claim is made that this kernel/LK2ND combination will boot from the internal `system` partition on every firmware/recovery variant, or that GPU, touch, Wi-Fi, audio, charging and suspend work. Back up first and be prepared to restore Android using the saved recovery and TWRP backup.

## Project files

- `.github/workflows/build.yml` — GitHub Actions workflow.
- `scripts/build-kernel.sh`, `scripts/build-rootfs.sh`, `scripts/chroot-setup.sh` — build system.
- `scripts/build-lk2nd.sh` — builds a Redmi 5A LK2ND image with a checked 64 MiB boot-memory window.
- `scripts/package-internal-boot.sh` — validates the LK2ND/kernel memory budget and creates the selected Arch boot ZIP.
- `scripts/package-android-restore.sh` — creates the Android filesystem restore ZIP.
- `installer/arch/` — TWRP installer for native Arch Linux.
- `installer/restore/` — TWRP Android restore-preparation installer.
- `config/` and `overlay/` — kernel and desktop configuration from the earlier project.

## Changelog

### v2 – mkfs fix
`Could not format system as ext2` was caused by the installer hiding all mke2fs errors and not
releasing the partition first. Both installers now: set the block device read-write, unmount every
mount point backed by the target partition (lazy/force if needed), wipe stale signatures, try several
mke2fs variants (all ext2-compatible for LK2ND), and print the real mke2fs error on screen if every
attempt fails. If you already have a built `Riva-Arch-Boot.zip`, run
`tools/patch-existing-arch-zip.sh Riva-Arch-Boot.zip` to swap in the fixed installer without a rebuild.
