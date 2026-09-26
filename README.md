# Omarchy Language Switcher

English | [简体中文](README.zh-CN.md)

![Omarchy Language Switcher preview](preview.png)

[Preview from the original post](https://x.com/manateelazycat/status/2103848803740893201)

**License: GPL 3.0**

An Omarchy Shell plugin for changing the system language. Click the language icon in the bar to search and select a locale on the focused monitor.

## Features

- Lists every UTF-8 locale supported by the system and marks the current and installed locales.
- Selects the current system locale when opened. Search by Chinese, English, native language name, or locale code.
- Generates a missing locale with `locale-gen` after graphical administrator authorization, then sets the system `LANG` with `localectl`.
- Shows progress and the result on the same monitor. Sign out and sign back in for a successful change to take effect.

The plugin changes the system locale. It does not change the keyboard layout or input method.

## Install

```bash
git clone https://github.com/manateelazycat/omarchy-language-switcher.git
cd omarchy-language-switcher
./install.sh
```

The installer links this directory to `~/.config/omarchy/plugins/andy.language-switcher`, backs up `shell.json`, enables the plugin, and adds its icon to the right side of the bar. Keep the cloned directory in place.

## Use

Click the language icon in the bar or run `omarchy-shell andy.language-switcher show`. Use `↑` and `↓` to select a language, `Enter` to switch, and `Esc` to close the dialog.

## Remove

```bash
omarchy plugin remove andy.language-switcher --yes
```

Your local clone is not deleted.

## Requirements

Omarchy Shell, Hyprland, Python 3, `locale-gen`, `localectl`, `pkexec`, and a graphical Polkit authentication agent. The installer also uses `jq`. Available translations depend on the language packs installed on your system.

## License

Omarchy Language Switcher is licensed under the GNU General Public License version 3.0 only (`GPL-3.0-only`). See [LICENSE](LICENSE) for the full terms.
