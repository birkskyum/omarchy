#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

helper="$ROOT/bin/omarchy-install-video-decode"
migration=$(grep -l -- 'omarchy-install-video-decode' "$ROOT"/migrations/*.sh | head -n1)
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
hwdec='hwdec=auto-safe,v4l2m2m-copy'

touch "$OMARCHY_TEST_QUALCOMM"
home=$(new_home shipped)
cp "$shipped" "$home/.config/chromium-flags.conf"
run_helper "$home"
run_helper "$home"
conf="$home/.config/chromium-flags.conf"
(( $(grep -c -- '^--use-angle=gles-egl$' "$conf") == 1 )) || fail "Snapdragon Chromium gets ANGLE on GLES once" "$(cat "$conf")"
grep -Fxq -- "$features,AcceleratedVideoDecoder" "$conf" || fail "Snapdragon Chromium keeps its features and adds AcceleratedVideoDecoder once" "$(cat "$conf")"
(( $(grep -c -- '^--enable-features=' "$conf") == 1 )) || fail "Snapdragon Chromium keeps one feature list" "$(cat "$conf")"
(( $(grep -cFx -- "$hwdec" "$home/.config/mpv/mpv.conf") == 1 )) || fail "Snapdragon mpv gets the V4L2 fallback once" "$(cat "$home/.config/mpv/mpv.conf")"
pass "a Snapdragon laptop gets the mpv and Chromium settings once, even when the helper runs twice"

rm "$OMARCHY_TEST_QUALCOMM"
home=$(new_home other)
cp "$shipped" "$home/.config/chromium-flags.conf"
run_helper "$home"
cmp -s "$shipped" "$home/.config/chromium-flags.conf" || fail "other machines keep Chromium's flags" "$(cat "$home/.config/chromium-flags.conf")"
[[ ! -e $home/.config/mpv ]] || fail "other machines get no mpv config"
pass "other machines keep Chromium's flags and get no mpv config"

touch "$OMARCHY_TEST_QUALCOMM"
home=$(new_home user-choices)
printf '%s\n' '--use-angle=vulkan' '--enable-features=AcceleratedVideoDecoder' >"$home/.config/chromium-flags.conf"
mkdir -p "$home/.config/mpv"
printf '%s\n' 'volume=80' 'hwdec = no' >"$home/.config/mpv/mpv.conf"
run_helper "$home"
[[ $(cat "$home/.config/chromium-flags.conf") == $'--use-angle=vulkan\n--enable-features=AcceleratedVideoDecoder' ]] ||
  fail "a Chromium backend and feature the user set stay as they are" "$(cat "$home/.config/chromium-flags.conf")"
[[ $(cat "$home/.config/mpv/mpv.conf") == $'volume=80\nhwdec = no' ]] ||
  fail "an mpv hwdec the user set stays as it is" "$(cat "$home/.config/mpv/mpv.conf")"
pass "settings the user chose stay as they are"

home=$(new_home profile)
mkdir -p "$home/.config/mpv"
printf '%s\n' 'volume=80' '' '[big]' 'fs=yes' >"$home/.config/mpv/mpv.conf"
run_helper "$home"
mapfile -t lines <"$home/.config/mpv/mpv.conf"
[[ ${lines[1]} == "$hwdec" && ${lines[2]} == 'volume=80' && ${lines[*]: -2:1} == '[big]' ]] ||
  fail "the mpv fallback goes on top, outside any profile" "$(cat "$home/.config/mpv/mpv.conf")"
pass "the mpv fallback goes on top, outside any profile"

home=$(new_home profile-hwdec)
mkdir -p "$home/.config/mpv"
printf '%s\n' '[software]' 'hwdec=no' >"$home/.config/mpv/mpv.conf"
run_helper "$home"
mapfile -t lines <"$home/.config/mpv/mpv.conf"
[[ ${lines[1]} == "$hwdec" && ${lines[2]} == '[software]' && ${lines[3]} == 'hwdec=no' ]] ||
  fail "an hwdec inside a profile still gets the global fallback on top" "$(cat "$home/.config/mpv/mpv.conf")"
pass "an hwdec inside a profile still gets the global fallback on top"

home=$(new_home default-hwdec)
mkdir -p "$home/.config/mpv"
printf '%s\n' '[software]' 'hwdec=no' '[default]' 'hwdec=auto' >"$home/.config/mpv/mpv.conf"
run_helper "$home"
[[ $(cat "$home/.config/mpv/mpv.conf") == $'[software]\nhwdec=no\n[default]\nhwdec=auto' ]] ||
  fail "an hwdec after [default] counts as the user's global choice" "$(cat "$home/.config/mpv/mpv.conf")"
pass "an hwdec after [default] counts as the user's global choice"

home=$(new_home bare)
printf '%s' '--ozone-platform=wayland' >"$home/.config/chromium-flags.conf"
run_helper "$home"
[[ $(cat "$home/.config/chromium-flags.conf") == $'--ozone-platform=wayland\n--use-angle=gles-egl\n--enable-features=AcceleratedVideoDecoder' ]] ||
  fail "a Chromium file without a trailing newline or feature list gets both flags on lines of their own" "$(cat "$home/.config/chromium-flags.conf")"
pass "a Chromium file without a trailing newline or feature list gets both flags on lines of their own"

home=$(new_home missing)
run_helper "$home"
[[ ! -e $home/.config/chromium-flags.conf ]] || fail "a missing Chromium flags file stays missing"
pass "a missing Chromium flags file stays missing"

home=$(new_home symlink)
cp "$shipped" "$test_tmp/flags-target.conf"
ln -s "$test_tmp/flags-target.conf" "$home/.config/chromium-flags.conf"
mkdir -p "$home/.config/mpv"
printf '%s\n' 'volume=80' >"$test_tmp/mpv-target.conf"
ln -s "$test_tmp/mpv-target.conf" "$home/.config/mpv/mpv.conf"
run_helper "$home"
[[ -L $home/.config/chromium-flags.conf && -L $home/.config/mpv/mpv.conf ]] || fail "symlinked config files stay symlinks"
grep -Fxq -- "$features,AcceleratedVideoDecoder" "$test_tmp/flags-target.conf" || fail "the target of a symlinked Chromium file gets the feature"
grep -Fxq -- "$hwdec" "$test_tmp/mpv-target.conf" || fail "the target of a symlinked mpv config gets the fallback"
pass "symlinked config files stay symlinks and their targets get the settings"

[[ -n $migration ]] || fail "a migration applies the settings on existing installs"
home=$(new_home migration)
cp "$shipped" "$home/.config/chromium-flags.conf"
HOME="$home" bash -euo pipefail "$migration" >/dev/null
if ! grep -Fxq -- '--use-angle=gles-egl' "$home/.config/chromium-flags.conf" ||
  ! grep -Fxq -- "$features,AcceleratedVideoDecoder" "$home/.config/chromium-flags.conf" ||
  ! grep -Fxq -- "$hwdec" "$home/.config/mpv/mpv.conf"; then
  fail "the migration applies the settings on an existing Snapdragon install" "$(cat "$home/.config/chromium-flags.conf")"
fi
pass "the migration applies the settings on an existing Snapdragon install"
