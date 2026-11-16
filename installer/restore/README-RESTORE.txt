RIVA ANDROID RESTORE PREPARATION

This is a filesystem-preparation ZIP, not a TWRP backup. It formats only the existing
Android system and userdata partitions as ext4. It does not change GPT or partition sizes.

After flashing in TWRP:
- To return to your previous Android installation, use TWRP Restore and restore a
  matching backup set: Boot, System/System Image, Vendor/Vendor Image, Data, and
  Recovery only when needed.
- To install crDroid or another ROM, follow its exact Redmi 5A clean-install guide.
  Do not restore the old System/Boot/Data over a newly flashed ROM.

The ZIP deliberately leaves Boot, Recovery, Vendor, Persist and modem-related partitions
untouched. Store the TWRP backup on a PC or USB OTG before installing Arch, because
userdata is erased by the Arch installer.
