#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

config="$ROOT/etc/mkinitcpio.conf.d/thunderbolt_module.conf"

bash -n "$config" || fail "the thunderbolt drop-in has valid syntax"

with_module=$(
  modinfo() { echo /usr/lib/modules/test/kernel/drivers/thunderbolt/thunderbolt.ko.zst; }
  MODULES=()
  source "$config"
  echo "${MODULES[*]}"
)
[[ $with_module == "thunderbolt" ]] ||
  fail "thunderbolt is early-loaded where the kernel has the module"

without_module=$(
  modinfo() { return 1; }
  MODULES=()
  source "$config"
  echo "${MODULES[*]}"
)
[[ -z $without_module ]] ||
  fail "a kernel without the thunderbolt module is not asked for it"

pass "thunderbolt is requested only where the kernel has the module"
