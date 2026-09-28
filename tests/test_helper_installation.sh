#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$project_dir/helper-installation.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
helper_dir="$fixture"
helper_path="$fixture/omarchy-language-switcher-helper"
receipt_path="$helper_path.receipt"

# The fixture is user-owned. Pretend only its UID is root while retaining
# the real file type and permission checks.
stat() {
  local result
  result="$(command stat "$@")"
  if [[ "$1" == -c && "$2" == '%u %a' ]]; then
    printf '0 %s\n' "${result#* }"
  else
    printf '%s\n' "$result"
  fi
}

expect_rejected() {
  local expected="$1" result
  if result="$(check_managed_helper 2>&1)"; then
    echo "Expected helper check to fail: $expected" >&2
    exit 1
  fi
  if [[ "$result" != *"$expected"* ]]; then
    echo "Unexpected error: $result" >&2
    exit 1
  fi
}

if check_managed_helper; then
  echo "Expected an absent helper to be reported as absent" >&2
  exit 1
fi

printf 'foreign file\n' > "$helper_path"
expect_rejected '安装记录不完整'

printf 'plugin helper\n' > "$helper_path"
digest="$(sha256sum -- "$helper_path")"
printf 'andy.language-switcher v1 %s\n' "${digest%% *}" > "$receipt_path"
check_managed_helper

printf 'modified helper\n' > "$helper_path"
expect_rejected '内容已变化'

printf 'plugin helper\n' > "$helper_path"
rm -- "$receipt_path"
ln -s -- "$helper_path" "$receipt_path"
expect_rejected '不是普通系统文件'

rm -- "$receipt_path"
printf 'andy.language-switcher v1 %s\n' "${digest%% *}" > "$receipt_path"
chmod 0666 -- "$receipt_path"
expect_rejected '所有者或权限不安全'

echo 'Helper ownership checks passed.'
