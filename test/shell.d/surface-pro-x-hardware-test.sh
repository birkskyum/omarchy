#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

setup="$ROOT/install/hardware/microsoft/surface-pro-x.sh"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

bash -n "$setup" || fail "Surface Pro X hardware script has valid syntax"

require_platform_fixtures "the Surface Pro X setup"

run_setup() (
  set -eE
  local dir=$1
  PATH="$ROOT/bin:$PATH"
  omarchy-hw-aarch64-qualcomm() { return 0; }

  OMARCHY_PROC_ROOT="$dir/proc" \
    OMARCHY_SURFACE_PRO_X_MKINITCPIO_DIR="$dir/mkinitcpio.conf.d" \
    source "$setup"
)

compatible() {
  mkdir -p "$1/proc/device-tree"
  printf '%b' "$2" >"$1/proc/device-tree/compatible"
}

for model in cambria carina caspar; do
  matching="$scratch/$model"
  compatible "$matching" "microsoft,$model\0qcom,sc8180x\0"
  # An install from before the Intel Surface fixes were limited to x86
  mkdir -p "$matching/mkinitcpio.conf.d"
  echo 'MODULES=(pinctrl_tigerlake intel_lpss_pci 8250_dw)' >"$matching/mkinitcpio.conf.d/surface_device_modules.conf"
  run_setup "$matching" >/dev/null

  [[ ! -e $matching/mkinitcpio.conf.d/surface_device_modules.conf ]] ||
    fail "the Intel Surface module file, which would reset MODULES, is removed on the $model"

  (
    MODULES=()
    source "$matching/mkinitcpio.conf.d/surface-pro-x-initramfs.conf"

    for module in "${MODULES[@]}"; do
      [[ $module == *\? ]] || fail "$module is optional, so a kernel without it still builds its image"
    done

    for module in surface_aggregator surface_aggregator_registry surface_hid surface_kbd; do
      [[ " ${MODULES[*]} " == *" $module? "* ]] ||
        fail "$module loads early on the $model, for the Type Cover at disk unlock"
    done

    for module in dwc3-qcom-legacy phy-qcom-snps-femto-v2 usbhid; do
      [[ " ${MODULES[*]} " == *" $module? "* ]] ||
        fail "$module loads early on the $model, for a USB keyboard at disk unlock"
    done
  )
done

for other in 'microsoft,denali\0qcom,x1e80100\0' 'lenovo,flex-5g\0qcom,sc8180x\0'; do
  dir="$scratch/other-${other%%\\0*}"
  compatible "$dir" "$other"
  run_setup "$dir" >/dev/null
  [[ ! -e $dir/mkinitcpio.conf.d ]] || fail "${other%%\\0*} is left alone"
done

pass "Surface Pro X setup loads the Type Cover and USB drivers early on its three models only"
