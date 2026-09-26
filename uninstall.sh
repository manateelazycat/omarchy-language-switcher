#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/andy.language-switcher"
helper_path="/usr/local/libexec/omarchy-language-switcher-helper"

if (( EUID == 0 )); then
  echo "请以普通用户运行卸载脚本；脚本会在需要时调用 sudo。" >&2
  exit 1
fi

if [[ -e "$plugin_dir" || -L "$plugin_dir" ]]; then
  if [[ ! -L "$plugin_dir" || "$(readlink -f -- "$plugin_dir")" != "$project_dir" ]]; then
    echo "插件目录不是本项目的链接，拒绝删除：$plugin_dir" >&2
    exit 1
  fi
fi

if [[ -e "$helper_path" || -L "$helper_path" ]]; then
  for dir in /usr /usr/local /usr/local/libexec; do
    if [[ ! -d "$dir" || -L "$dir" || "$(stat -c '%u' -- "$dir")" != 0 ]]; then
      echo "不是可信的系统目录：$dir" >&2
      exit 1
    fi
    mode="$(stat -c '%a' -- "$dir")"
    if (( (8#$mode & 0022) != 0 )); then
      echo "系统目录可由非 root 用户修改：$dir" >&2
      exit 1
    fi
  done
fi

if [[ -L "$plugin_dir" ]]; then
  export OMARCHY_SHELL_IPC_TIMEOUT=20s
  omarchy plugin remove andy.language-switcher --yes
fi
if [[ -e "$helper_path" || -L "$helper_path" ]]; then
  sudo rm -- "$helper_path"
fi

echo "Language Switcher 已卸载。项目克隆目录未删除。"
