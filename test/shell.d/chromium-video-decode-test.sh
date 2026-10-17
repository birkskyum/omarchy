#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

helper="$ROOT/bin/omarchy-install-chromium-video-decode"
migration=$(grep -l -- 'omarchy-install-chromium-video-decode' "$ROOT"/migrations/*.sh | head -n1)
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

# The Snapdragon check answers from a file, so each case picks the platform.
mkdir -p "$test_tmp/bin"
cat >"$test_tmp/bin/omarchy-hw-aarch64-qualcomm" <<'STUB'
#!/bin/bash
[[ -e $OMARCHY_TEST_QUALCOMM ]]
STUB
chmod +x "$test_tmp/bin/omarchy-hw-aarch64-qualcomm"
export OMARCHY_TEST_QUALCOMM="$test_tmp/qualcomm"
export PATH="$test_tmp/bin:$ROOT/bin:$PATH"

new_home() {
  local home="$test_tmp/home-$1"
  mkdir -p "$home/.config"
  echo "$home"
}

run_helper() {
  HOME="$1" bash "$helper"
}

shipped="$ROOT/config/chromium-flags.conf"
features=$(grep -- '^--enable-features=' "$shipped")

touch "$OMARCHY_TEST_QUALCOMM"
home=$(new_home shipped)
cp "$shipped" "$home/.config/chromium-flags.conf"
run_helper "$home"
run_helper "$home"
conf="$home/.config/chromium-flags.conf"
(( $(grep -c -- '^--use-angle=gles-egl$' "$conf") == 1 )) || fail "Snapdragon Chromium gets ANGLE on GLES once" "$(cat "$conf")"
grep -Fxq -- "$features,AcceleratedVideoDecoder" "$conf" || fail "Snapdragon Chromium keeps its features and adds AcceleratedVideoDecoder once" "$(cat "$conf")"
(( $(grep -c -- '^--enable-features=' "$conf") == 1 )) || fail "Snapdragon Chromium keeps one feature list" "$(cat "$conf")"
pass "a Snapdragon laptop gets both flags once, even when the helper runs twice"

rm "$OMARCHY_TEST_QUALCOMM"
home=$(new_home other)
cp "$shipped" "$home/.config/chromium-flags.conf"
run_helper "$home"
cmp -s "$shipped" "$home/.config/chromium-flags.conf" || fail "other machines keep Chromium's flags" "$(cat "$home/.config/chromium-flags.conf")"
pass "other machines keep Chromium's flags"

touch "$OMARCHY_TEST_QUALCOMM"
home=$(new_home angle)
printf '%s\n' '--use-angle=vulkan' '--enable-features=AcceleratedVideoDecoder' >"$home/.config/chromium-flags.conf"
run_helper "$home"
[[ $(cat "$home/.config/chromium-flags.conf") == $'--use-angle=vulkan\n--enable-features=AcceleratedVideoDecoder' ]] ||
  fail "a backend and feature the user set stay as they are" "$(cat "$home/.config/chromium-flags.conf")"
pass "a backend and feature the user set stay as they are"

home=$(new_home bare)
printf '%s' '--ozone-platform=wayland' >"$home/.config/chromium-flags.conf"
run_helper "$home"
[[ $(cat "$home/.config/chromium-flags.conf") == $'--ozone-platform=wayland\n--use-angle=gles-egl\n--enable-features=AcceleratedVideoDecoder' ]] ||
  fail "a file without a trailing newline or feature list gets both flags on lines of their own" "$(cat "$home/.config/chromium-flags.conf")"
pass "a file without a trailing newline or feature list gets both flags on lines of their own"

home=$(new_home missing)
run_helper "$home"
[[ ! -e $home/.config/chromium-flags.conf ]] || fail "a missing Chromium flags file stays missing"
pass "a missing Chromium flags file stays missing"

home=$(new_home symlink)
cp "$shipped" "$test_tmp/flags-target.conf"
ln -s "$test_tmp/flags-target.conf" "$home/.config/chromium-flags.conf"
run_helper "$home"
[[ -L $home/.config/chromium-flags.conf ]] || fail "a symlinked flags file stays a symlink"
grep -Fxq -- "$features,AcceleratedVideoDecoder" "$test_tmp/flags-target.conf" || fail "the target of a symlinked flags file gets the feature"
pass "a symlinked flags file stays a symlink and its target gets the flags"

[[ -n $migration ]] || fail "a migration applies the flags on existing installs"
home=$(new_home migration)
cp "$shipped" "$home/.config/chromium-flags.conf"
HOME="$home" bash -euo pipefail "$migration" >/dev/null
if ! grep -Fxq -- '--use-angle=gles-egl' "$home/.config/chromium-flags.conf" ||
  ! grep -Fxq -- "$features,AcceleratedVideoDecoder" "$home/.config/chromium-flags.conf"; then
  fail "the migration applies the flags on an existing Snapdragon install" "$(cat "$home/.config/chromium-flags.conf")"
fi
pass "the migration applies the flags on an existing Snapdragon install"
