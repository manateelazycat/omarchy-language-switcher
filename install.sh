#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/andy.language-switcher"
source "$project_dir/helper-installation.sh"

if (( EUID == 0 )); then
  echo "请以普通用户运行安装脚本；脚本会在需要时调用 sudo。" >&2
  exit 1
fi

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
if check_managed_helper; then
  updating_helper=true
else
  updating_helper=false
fi

# Feed source bytes as the desktop user. Root only writes within the trusted
# directory and never opens a path from the user-writable checkout.
helper_tmp="$(sudo mktemp "$helper_path.new.XXXXXXXX")"
receipt_tmp=""
new_helper_linked=false
new_receipt_linked=false
install_done=false
cleanup() {
  if [[ "$install_done" != true && "$new_receipt_linked" == true &&
        -e "$receipt_path" && -e "$receipt_tmp" && "$receipt_path" -ef "$receipt_tmp" ]]; then
    sudo rm -- "$receipt_path"
  fi
  if [[ "$install_done" != true && "$new_helper_linked" == true &&
        -e "$helper_path" && -e "$helper_tmp" && "$helper_path" -ef "$helper_tmp" ]]; then
    sudo rm -- "$helper_path"
  fi
  if [[ -n "$helper_tmp" ]]; then sudo rm -f -- "$helper_tmp"; fi
  if [[ -n "$receipt_tmp" ]]; then sudo rm -f -- "$receipt_tmp"; fi
}
trap cleanup EXIT
cat -- "$project_dir/locale_helper.py" | sudo install -o root -g root -m 0755 /dev/stdin "$helper_tmp"
new_hash_output="$(sha256sum -- "$helper_tmp")"
new_digest="${new_hash_output%% *}"
receipt_tmp="$(sudo mktemp "$receipt_path.new.XXXXXXXX")"
printf 'andy.language-switcher v1 %s\n' "$new_digest" |
  sudo install -o root -g root -m 0644 /dev/stdin "$receipt_tmp"
if [[ "$updating_helper" == true ]]; then
  sudo mv -T -- "$helper_tmp" "$helper_path"
  sudo mv -T -- "$receipt_tmp" "$receipt_path"
else
  sudo ln -- "$helper_tmp" "$helper_path"
  new_helper_linked=true
  sudo ln -- "$receipt_tmp" "$receipt_path"
  new_receipt_linked=true
fi
check_managed_helper
install_done=true

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
