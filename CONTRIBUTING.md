# 参与贡献 · Contributing

感谢你愿意帮助 Hush!Bug 报告、功能建议、翻译和代码都非常欢迎。
Thanks for helping with Hush! Bug reports, ideas, translations and code are all welcome. English follows the Chinese.

## 开始之前

- 先搜索 [Issues](https://github.com/08820048/hush/issues),看看是否已有人提过。
- 较大的改动(新功能、改变交互、新增依赖)请先开一个 Issue 讨论,避免白费功夫。
- **安全问题不要公开提 Issue**,请按 [SECURITY.md](SECURITY.md) 私下报告。
- 参与即表示你同意遵守 [行为准则](CODE_OF_CONDUCT.md)。

## 开发环境

- macOS 14 或更新版本
- Xcode 16 或更新版本(Swift 6)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen):`brew install xcodegen`

```sh
make test       # 核心测试(Core/)
make cli        # 构建命令行工具 → .build/release/hush
make run        # 生成 Xcode 工程、构建并启动 App
make snapshots  # 离屏渲染所有界面截图(调试版),检查布局用
```

用 Xcode 开发时打开 `App/Hush.xcodeproj`(由 `App/project.yml` 生成,不要手动修改工程文件;新增文件后运行 `make project`)。

## 代码结构

| 目录 | 内容 |
|---|---|
| `Core/` | 生成核心 HushCore:随机数、各模式生成器、强度计算、网站规则、URL 解析。**不依赖任何 UI**,有完整测试 |
| `Sources/hush/` | 命令行工具 |
| `App/` | macOS App(SwiftUI + AppKit) |
| `website/` | 产品官网(静态页面,部署在 Cloudflare Pages) |
| `docs/` | 需求文档、发布流程 |

## 提交改动

1. Fork 仓库并从 `main` 新建分支。
2. 生成或安全相关的逻辑放在 `Core/`,并补充测试。涉及随机性的改动需要说明为什么分布仍然均匀、熵值仍然准确。
3. 界面改动请附上浅色和深色的截图(`make snapshots` 可以生成)。
4. 运行 `make test`,确认 App 可以编译(`make app`)。
5. 提交信息使用 [Conventional Commits](https://www.conventionalcommits.org/zh-hans/) 格式,例如 `feat: …`、`fix: …`、`docs: …`。更新日志由提交信息自动生成。
6. 发起 Pull Request,按模板填写。

### 不接受的改动

- 让 App 联网的功能(统计、崩溃上报、在线同步等)。“不联网”是 Hush 的核心承诺。
- 把密码写入磁盘的功能。
- 用 `random()`、`arc4random` 等代替 `SecRandomCopyBytes` 的随机数实现。

## 翻译

界面文案在 `App/Hush/Localizable.xcstrings`(String Catalog),用 Xcode 打开即可编辑。新增语言:在 Xcode 中打开该文件,点击“+”添加语言并逐条翻译。快捷指令的语音短语在 `App/Hush/AppShortcuts.xcstrings`。

## 贡献的授权

Hush 以 [GNU GPL-3.0](LICENSE)(GPL-3.0-or-later)发布。提交贡献即表示:

1. 你有权提交这些内容(是你本人的作品,或其许可证允许这样做);
2. 你的贡献以 GPL-3.0-or-later 授权;
3. 你同时授予项目维护者 XuYi 一项永久、全球、免费、非独占的许可,允许其通过 Mac App Store 等应用商店、按这些商店要求的条款(包括收费)分发包含你贡献的 Hush。

需要第 3 条,是因为 App Store 的使用条款与 GPL 不兼容:没有这项许可,任何外部贡献都无法出现在 App Store 版本中。你的贡献在 GitHub 上始终以 GPL 开源。如果你不同意,请在 Pull Request 中说明。

---

## English

### Before you start

- Search the [issues](https://github.com/08820048/hush/issues) first.
- For larger changes (new features, interaction changes, new dependencies), open an issue to discuss before writing code.
- **Do not report security problems in public issues.** Follow [SECURITY.md](SECURITY.md).
- By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).

### Setup

macOS 14+, Xcode 16+ (Swift 6) and [XcodeGen](https://github.com/yonaskolb/XcodeGen). Then `make test`, `make cli`, `make run`, `make snapshots`. Open `App/Hush.xcodeproj` in Xcode; it is generated from `App/project.yml`, so run `make project` after adding files instead of editing the project.

### Making a change

1. Fork and branch from `main`.
2. Generation and security logic belongs in `Core/`, with tests. Changes touching randomness must explain why the output stays uniform and the entropy stays exact.
3. Include light and dark screenshots for UI changes (`make snapshots`).
4. Run `make test` and make sure the app builds (`make app`).
5. Use [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:` …); release notes are generated from them.
6. Open a pull request and fill in the template.

Out of scope: anything that makes the app go online (analytics, crash reporting, sync), writes secrets to disk, or replaces `SecRandomCopyBytes`.

### Translations

UI strings live in `App/Hush/Localizable.xcstrings`; Siri phrases in `App/Hush/AppShortcuts.xcstrings`. Open them in Xcode to edit or add a language.

### Licensing of contributions

Hush is licensed under the [GNU GPL-3.0](LICENSE) (GPL-3.0-or-later). By contributing, you confirm that you have the right to submit the work, you license it under GPL-3.0-or-later, and you also grant the maintainer, XuYi, a perpetual, worldwide, royalty-free, non-exclusive license to distribute Hush including your contribution through app stores such as the Mac App Store, under the terms those stores require (including for a fee).

The App Store's terms are not compatible with the GPL, so without this grant no outside contribution could ship in the App Store version. Your contribution always stays open source under the GPL on GitHub. If you do not agree, say so in your pull request.
