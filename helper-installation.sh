#!/usr/bin/env bash

helper_dir="/usr/local/libexec"
helper_path="$helper_dir/omarchy-language-switcher-helper"
receipt_path="$helper_path.receipt"

fail_helper() {
  echo "$*" >&2
  exit 1
}

check_trusted_dir() {
  local dir="$1" owner mode
  if [[ ! -d "$dir" || -L "$dir" ]]; then
    fail_helper "不是可信的系统目录：$dir"
  fi
  read -r owner mode < <(stat -c '%u %a' -- "$dir")
  if [[ "$owner" != 0 ]] || (( (8#$mode & 0022) != 0 )); then
    fail_helper "系统目录可由非 root 用户修改：$dir"
  fi
}

check_managed_file() {
  local path="$1" owner mode
  if [[ ! -f "$path" || -L "$path" ]]; then
    fail_helper "不是普通系统文件：$path"
  fi
  read -r owner mode < <(stat -c '%u %a' -- "$path")
  if [[ "$owner" != 0 ]] || (( (8#$mode & 0022) != 0 )); then
    fail_helper "系统文件的所有者或权限不安全：$path"
  fi
}

# Returns 1 only when neither file exists. Any partial, foreign, or modified
# installation is an error and must be resolved explicitly by its owner.
check_managed_helper() {
  if [[ ! -e "$helper_path" && ! -L "$helper_path" &&
        ! -e "$receipt_path" && ! -L "$receipt_path" ]]; then
    return 1
  fi

  check_trusted_dir /usr
  check_trusted_dir /usr/local
  check_trusted_dir "$helper_dir"
  if [[ ! -e "$helper_path" && ! -L "$helper_path" ]] ||
     [[ ! -e "$receipt_path" && ! -L "$receipt_path" ]]; then
    fail_helper "helper 与安装记录不完整；拒绝修改 $helper_path"
  fi
  check_managed_file "$helper_path"
  check_managed_file "$receipt_path"

  local digest expected hash_output receipt
  hash_output="$(sha256sum -- "$helper_path")" || fail_helper "无法校验 helper：$helper_path"
  digest="${hash_output%% *}"
  [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || fail_helper "helper 摘要无效：$helper_path"
  expected="andy.language-switcher v1 $digest"
  receipt="$(cat -- "$receipt_path")" || fail_helper "无法读取安装记录：$receipt_path"
  if [[ "$receipt" != "$expected" ]]; then
    fail_helper "helper 没有匹配的安装记录，或内容已变化；拒绝修改 $helper_path"
  fi
}
