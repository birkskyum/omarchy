#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

env_file="$ROOT/default/uwsm/default"
stubs=$(mktemp -d)
trap 'rm -rf "$stubs"' EXIT
touch "$stubs/swapfile"

cat >"$stubs/swapon" <<'STUB'
#!/bin/bash
[[ -n $STUB_SWAPS ]] && printf '%s\n' $STUB_SWAPS
true
STUB
cat >"$stubs/findmnt" <<'STUB'
#!/bin/bash
echo "/dev/mapper/root[/@swap]"
STUB
cat >"$stubs/lsblk" <<'STUB'
#!/bin/bash
case ${@: -1} in
  /dev/mapper/root) printf 'btrfs\ncrypto_LUKS\n' ;;
  /dev/nvme0n1p3) echo swap ;;
  *) exit 32 ;;
esac
STUB
chmod +x "$stubs/swapon" "$stubs/findmnt" "$stubs/lsblk"

# The value a program started from the session sees, so a lost export shows.
backend() {
  env -u SECURE_KEY_CONTAINER_BACKEND PATH="$stubs:$ROOT/bin:$PATH" STUB_SWAPS="$1" "${@:2}" \
    bash -c 'source "$1"; printenv SECURE_KEY_CONTAINER_BACKEND || echo unset' bash "$env_file"
}

value=$(backend "$stubs/swapfile /dev/zram0")
[[ $value == "mlock" ]] || fail "Bitwarden uses locked memory when the swap file is encrypted" "actual: $value"
pass "Bitwarden uses locked memory when the swap file is encrypted"

value=$(backend "$stubs/swapfile /dev/nvme0n1p3")
[[ $value == "unset" ]] || fail "Bitwarden keeps memfd_secret next to an unencrypted swap partition" "actual: $value"
pass "Bitwarden keeps memfd_secret next to an unencrypted swap partition"

value=$(backend "/dev/zram0")
[[ $value == "unset" ]] || fail "Bitwarden keeps memfd_secret with only zram swap" "actual: $value"
pass "Bitwarden keeps memfd_secret with only zram swap"

value=$(backend "")
[[ $value == "unset" ]] || fail "Bitwarden keeps memfd_secret without swap" "actual: $value"
pass "Bitwarden keeps memfd_secret without swap"

value=$(backend "$stubs/swapfile" SECURE_KEY_CONTAINER_BACKEND=keyctl)
[[ $value == "keyctl" ]] || fail "a backend the user chose is kept" "actual: $value"
pass "a backend the user chose is kept"
