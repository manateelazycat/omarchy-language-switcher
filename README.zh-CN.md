# Omarchy Language Switcher

简体中文 | [English](README.md)

![Omarchy Language Switcher 预览](preview.png)

[预览图来源](https://x.com/manateelazycat/status/2103848803740893201)

**许可证：GPL 3.0**

Omarchy Shell 插件。点击任务栏右侧的语言图标，会在当前聚焦的显示器中央打开与 Omarchy 菜单同色系的搜索框，列表默认选中当前系统语言。输入中文、英文、本地语言名称或 locale 代码，使用方向键选择，按 Enter 切换系统语言；Esc 关闭。

插件从系统的 `/usr/share/i18n/SUPPORTED` 读取所有 UTF-8 locale。选择未生成的 locale 时，会通过 Omarchy 的图形管理员授权生成该 locale，再用 `localectl` 设置系统 `LANG`。搜索框在确认后立即收起，处理结果显示在同一块显示器中央；成功后提示注销并重新登录。它切换的是系统 locale，不改变键盘布局或输入法。

## 安装

```bash
git clone https://github.com/manateelazycat/omarchy-language-switcher.git
cd omarchy-language-switcher
./install.sh
```

安装脚本将项目目录链接到 `~/.config/omarchy/plugins/andy.language-switcher`，备份 `shell.json`，启用插件并把图标加入任务栏右侧。项目目录需要保留在原位置。

## 使用

点击任务栏语言图标，或运行 `omarchy-shell andy.language-switcher show` 打开搜索框。用 `↑`、`↓` 选择，按 `Enter` 切换；按 `Esc` 关闭。

## 卸载

```bash
omarchy plugin remove andy.language-switcher --yes
```

本地项目目录不会被删除。

## 运行要求

Omarchy Shell、Hyprland、Python 3、`locale-gen`、`localectl`、`pkexec`，以及可用的 Polkit 图形授权代理。安装脚本还使用 `jq`。语言资源是否完整取决于已安装的软件翻译包。

## 协议

本项目采用 GNU 通用公共许可证第 3 版（GPL 3.0，SPDX 标识符：`GPL-3.0-only`）。完整条款见 [LICENSE](LICENSE)。
