echo "Set up the Surface Pro X on installs made before its board setup"

# See install/hardware/microsoft/surface-pro-x.sh. It loads the Type Cover's
# and the USB drivers early, so the disk password prompt takes keys, then the
# boot image is rebuilt to pick them up. Rerunning the setup rewrites the same
# file.
rebuild_marker=/var/lib/omarchy/migrations/1795130986

if ! omarchy-hw-aarch64-qualcomm ||
  ! omarchy-hw-match-device-tree microsoft,cambria microsoft,carina microsoft,caspar; then
  exit 0
fi

sudo env PATH="$PATH" OMARCHY_PATH="$OMARCHY_PATH" bash -euo pipefail -c '
  source "$OMARCHY_PATH/install/hardware/microsoft/surface-pro-x.sh"
'

# A marker records the machine-wide rebuild: another user's run must not repeat
# it, while a missing marker still retries an interrupted rebuild.
if [[ ! -e $rebuild_marker ]]; then
  rebuild_log=$(mktemp)
  trap 'rm -f "$rebuild_log"' EXIT
  sudo limine-mkinitcpio 2>&1 | tee "$rebuild_log"

  # limine-mkinitcpio reports a kernel it could not rebuild and still exits 0.
  # That image lacks the early drivers, so the migration stays pending.
  if grep -q 'mkinitcpio failed for kernel' "$rebuild_log"; then
    echo "A boot image was not rebuilt. Fix the error above, then run omarchy-migrate again before rebooting." >&2
    exit 1
  fi

  sudo install -Dm644 /dev/null "$rebuild_marker"
  omarchy-state set reboot-required
fi
