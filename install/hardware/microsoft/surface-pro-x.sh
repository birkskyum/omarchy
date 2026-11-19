# Microsoft Surface Pro X (SQ1 and SQ2, Snapdragon 8cx) board-specific setup.

mkinitcpio_dir=${OMARCHY_SURFACE_PRO_X_MKINITCPIO_DIR:-/etc/mkinitcpio.conf.d}

if omarchy-hw-aarch64-qualcomm && omarchy-hw-match-device-tree microsoft,cambria microsoft,carina microsoft,caspar; then
  echo "Detected Microsoft Surface Pro X, applying board-specific support..."

  # Installs made before the Intel Surface fixes were limited to x86 carry
  # their keyboard module file. It sorts after this script's drop-in and
  # resets MODULES to Intel modules, leaving no keyboard to unlock with.
  rm -f "$mkinitcpio_dir/surface_device_modules.conf"

  # Bring up the Type Cover and USB before disk unlock. Without this the
  # unlock prompt takes no keys, from the cover or from a USB keyboard. As in
  # qualcomm/initramfs.sh, the ? skips a module a kernel does not have, so its
  # image still builds.
  # - The Type Cover is a HID device behind the Surface Aggregator Module,
  #   which sits on a UART and not on USB. Its registry has no device tree
  #   alias, so nothing loads it unless it is named.
  # - This chip's USB controllers are described the old way, with the DWC3
  #   core as a child node, which only dwc3-qcom-legacy binds. Its PHYs are
  #   not module dependencies of it.
  mkdir -p "$mkinitcpio_dir"
  cat >"$mkinitcpio_dir/surface-pro-x-initramfs.conf" <<'CONF'
MODULES+=(surface_aggregator? surface_aggregator_registry?
  surface_aggregator_hub? surface_hid_core? surface_hid? surface_kbd?
  dwc3-qcom-legacy? dwc3? phy-qcom-snps-femto-v2? phy-qcom-qmp-usb?
  phy-qcom-qmp-combo? usbhid? hid-microsoft? hid-generic? hid-multitouch?)
CONF
fi
