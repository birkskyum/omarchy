#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

env_file="$ROOT/default/uwsm/default"
stubs=$(mktemp -d)
trap 'rm -rf "$stubs"' EXIT

cat > "$stubs/findmnt" <<'STUB'
#!/bin/bash
echo "/dev/mapper/root[/@]"
STUB
cat > "$stubs/lsblk" <<'STUB'
#!/bin/bash
[[ ${@: -1} == /dev/mapper/root ]] || exit 1
echo btrfs
[[ $STUB_ROOT == luks ]] && echo crypto_LUKS
true
STUB
chmod +x "$stubs/findmnt" "$stubs/lsblk"

backend() {
  env -u SECURE_KEY_CONTAINER_BACKEND PATH="$stubs:$PATH" STUB_ROOT="$1" "${@:2}" \
    bash -c 'source "$1"; printf "%s" "${SECURE_KEY_CONTAINER_BACKEND-unset}"' bash "$env_file"
}

value=$(backend luks)
[[ $value == mlock ]] || fail "Bitwarden uses locked memory on an encrypted disk" "actual: $value"
pass "Bitwarden uses locked memory on an encrypted disk"

value=$(backend plain)
[[ $value == unset ]] || fail "Bitwarden keeps memfd_secret on an unencrypted disk" "actual: $value"
pass "Bitwarden keeps memfd_secret on an unencrypted disk"

value=$(backend luks SECURE_KEY_CONTAINER_BACKEND=keyctl)
[[ $value == keyctl ]] || fail "a backend the user chose is kept" "actual: $value"
pass "a backend the user chose is kept"
