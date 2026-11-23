# 更新日志 · Changelog

本文件记录每个版本的重要变化,格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/),版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。
Notable changes to Hush. Format based on Keep a Changelog; versions follow Semantic Versioning.

## [未发布 · Unreleased]

### 变更 · Changed
- 许可证由 MIT 改为 [GPL-3.0-or-later](LICENSE):分发修改版必须同样开源。v0.1.0 与 v0.2.0 仍按 MIT 提供。
  License changed from MIT to GPL-3.0-or-later. Releases 0.1.0 and 0.2.0 remain available under MIT.

### 新增 · Added
- 产品官网(`website/`,部署在 Cloudflare Pages)。Product website.
- 贡献指南、行为准则、Issue 与 PR 模板。Contributing guide, code of conduct, issue and PR templates.

## [0.2.0] - 2026-11-23

### 新增 · Added
- 菜单栏快捷面板:右键菜单栏图标,先看到密码,可切换模式、调长度、换一个、切换预设,再复制。Menu bar quick panel.
- 网站密码规则:按 ⌘D 输入网址,自动生成符合该网站要求的密码;内置 Apple password-manager-resources 的 471 个网站规则,离线可用。命令行 `--site`、`--rules`,链接 `site=`、`rules=`。Website password rules.
- 预设导入导出(JSON),命令行 `--preset-file`。Preset import and export.
- 随机模式支持“必须包含的字符组”和“最多连续重复次数”,熵值仍精确计算。Required groups and max-consecutive limits with exact entropy.
- “检查更新…”:在浏览器中打开最新版本页面,App 本身仍不联网。Check for Updates opens the releases page.
- 按版本标签自动构建与发布的 GitHub Actions 工作流。Tag-based release workflow.

## [0.1.0] - 2026-11-23

### 新增 · Added
- 首个版本:随机、短语、PIN、可读、密钥五种模式;键盘优先的面板(⌥⌘P);剪贴板保护与自动清空;临时历史;大字显示与 Wi-Fi 二维码;自定义预设与全局快捷键;`hush://` 链接与快捷指令;命令行工具 `hush`;简体中文与英文。
  First release.

[未发布 · Unreleased]: https://github.com/08820048/hush/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/08820048/hush/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/08820048/hush/releases/tag/v0.1.0
