#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/andy.language-switcher"
helper_dir="/usr/local/libexec"
helper_path="$helper_dir/omarchy-language-switcher-helper"

if (( EUID == 0 )); then
  echo "请以普通用户运行安装脚本；脚本会在需要时调用 sudo。" >&2
  exit 1
fi

check_trusted_dir() {
  local dir="$1" owner mode
  if [[ ! -d "$dir" || -L "$dir" ]]; then
    echo "不是可信的系统目录：$dir" >&2
    exit 1
  fi
  read -r owner mode < <(stat -c '%u %a' -- "$dir")
  if [[ "$owner" != 0 ]] || (( (8#$mode & 0022) != 0 )); then
    echo "系统目录可由非 root 用户修改：$dir" >&2
    exit 1
  fi
}

if [[ -e "$plugin_dir" && ! -L "$plugin_dir" ]]; then
  echo "插件目录已存在，无法建立项目链接：$plugin_dir" >&2
  exit 1
fi
if [[ -L "$plugin_dir" && "$(readlink -f -- "$plugin_dir")" != "$project_dir" ]]; then
  echo "插件目录已经指向其他位置：$plugin_dir" >&2
  exit 1
fi

omarchy plugin validate "$project_dir"
check_trusted_dir /usr
check_trusted_dir /usr/local
if [[ ! -e "$helper_dir" && ! -L "$helper_dir" ]]; then
  sudo install -d -o root -g root -m 0755 -- "$helper_dir"
fi
check_trusted_dir "$helper_dir"

# Feed source bytes as the desktop user. Root only writes within the trusted
# directory and never opens a path from the user-writable checkout.
helper_tmp="$helper_path.new.$$"
cat -- "$project_dir/locale_helper.py" | sudo install -o root -g root -m 0755 /dev/stdin "$helper_tmp"
sudo mv -f -- "$helper_tmp" "$helper_path"
if [[ ! -f "$helper_path" || -L "$helper_path" ]]; then
  echo "特权 helper 安装失败：$helper_path" >&2
  exit 1
fi
read -r helper_owner helper_mode < <(stat -c '%u %a' -- "$helper_path")
if [[ "$helper_owner" != 0 ]] || (( (8#$helper_mode & 0022) != 0 )); then
  echo "特权 helper 的所有者或权限不安全：$helper_path" >&2
  exit 1
fi

mkdir -p -- "$(dirname -- "$plugin_dir")"
ln -sfn -- "$project_dir" "$plugin_dir"
export OMARCHY_SHELL_IPC_TIMEOUT=20s
omarchy-shell shell rescanPlugins

discovered=false
for ((attempt = 0; attempt < 20; attempt++)); do
  if omarchy plugin list --json 2>/dev/null | jq -e 'any(.[]; .id == "andy.language-switcher")' >/dev/null; then
    discovered=true
    break
  fi
  sleep 1
done
if [[ "$discovered" != true ]]; then
  echo "Omarchy Shell 未能发现插件，请检查 shell 运行状态" >&2
  exit 1
fi

shell_config="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell.json"
if [[ -f "$shell_config" ]]; then
  cp -p -- "$shell_config" "$shell_config.bak.language-switcher.$(date +%Y%m%d%H%M%S)"
fi
omarchy plugin enable andy.language-switcher
omarchy bar move andy.language-switcher --section right
echo "Language Switcher 已安装到任务栏右侧。"
