# Hush

**Mac 上最快的密码生成器。** 按一下快捷键,一个强密码就安静地躺在你的剪贴板里——复制 30 秒后自动清空,剪贴板工具不会记录。

完全离线、不存储任何密码、MIT 开源。

> English: Hush is a menu-bar password generator for macOS. Press ⌥⌘P anywhere, hit ↩, and a strong password is on your clipboard — hidden from clipboard managers and wiped after 30 seconds. Offline, nothing stored, MIT licensed.

## 功能

- **五种模式**:随机字符 · 短语(EFF 7,776 词库)· PIN(避开 123456、日期等弱模式)· 可读音节 · 密钥(Hex / Base64 / Base64URL / UUID)
- **键盘优先**:`⌥⌘P` 唤起,`↩` 复制,`⌘↩` 直接粘贴到原来的 App,`␣` 换一个,`↑↓` 调长度,`1–5` 切模式,`⌘1–9` 切预设,`⌘D` 按网站规则,`⌘S` 存为预设,`⌘L` 大字显示,`⌘K` 二维码,`⌘Y` 临时历史
- **网站密码规则**:输入网址,自动生成符合该网站要求的密码(长度上限、允许的符号、连续重复限制等)。内置 Apple 开源的 471 个网站规则,离线可用
- **自定义预设**:保存常用设置,绑定全局快捷键;可导出为 JSON 文件与团队共享,再导入
- **菜单栏**:左键单击直接生成并复制;右键打开快捷面板,先看到密码,可切换模式、调长度、换一个、切换预设,满意再复制。预设可绑定独立全局快捷键,不弹面板
- **剪贴板保护**:标记为 Concealed / Transient,Maccy、Paste、Raycast 等不记录;到时只在剪贴板仍是该密码时才清空
- **如实的强度**:4 格强度条 + 熵值(bits),"每类至少一个"、PIN 弱模式排除都精确计入,不虚标
- **命令行工具 `hush`**:与 App 共享同一个生成核心

## 安全设计

- 随机数只来自 `SecRandomCopyBytes`,取值使用拒绝采样,没有取模偏差
- "每类至少一个"通过整串重新生成实现,保持均匀分布
- App 启用 App Sandbox,**没有申请网络权限**(见 `App/Hush/Hush.entitlements`),无统计、无埋点
- 密码从不写入磁盘;临时历史只在内存中,5 分钟后、锁屏、睡眠或退出时销毁

详见 [SECURITY.md](SECURITY.md)。

## 构建

需要 macOS 14+、Xcode 16+(Swift 6)和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```sh
make test     # 运行核心测试
make cli      # 构建命令行工具 → .build/release/hush
make run      # 生成 Xcode 工程、构建并启动 App
make release  # 打包发布版到 dist/(发布流程见 docs/RELEASING.md)
```

如果当前选中的不是完整 Xcode,可在命令前加 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。

## 命令行

```sh
hush                          # 20 位强密码
hush -l 32 --no-symbols       # 32 位,不含符号
hush -a                       # 排除易混淆字符
hush phrase -w 6 -s .         # 6 个词,用 . 分隔
hush pin 6                    # 6 位 PIN
hush say                      # 可读音节
hush key -b 32 -f base64url   # 32 字节密钥
hush -p wifi                  # 使用内置预设
hush --site example.com       # 按网站的已知密码规则生成
hush --rules 'minlength: 8; maxlength: 16; required: digit;'   # 按 Apple 密码规则文本生成
hush --preset-file team.json -p "Team VPN"                      # 使用从 App 导出的预设文件
hush -n 5 --json              # 批量 + JSON(含熵值与强度)
hush presets                  # 列出内置预设
```

## 自动化

**URL Scheme**:任何能打开链接的工具(Alfred、Raycast、终端里的 `open`、脚本)都能调用 Hush。默认生成后直接复制(同样受剪贴板保护),加 `copy=0` 改为在面板中显示。

```sh
open "hush://open"                                        # 打开面板
open "hush://generate"                                    # 默认强密码,直接复制
open "hush://generate?preset=wifi"                        # 使用预设(内置或自定义)
open "hush://generate?site=example.com"                   # 按网站的已知密码规则
open "hush://generate?mode=random&length=32&symbols=0"    # 随机:length upper lower digits symbols symbolset exclude-ambiguous exclude require-each
open "hush://generate?mode=passphrase&words=6&separator=space"   # 短语:words separator capitalize digit
open "hush://generate?mode=pin&length=8"                  # PIN:length avoid-weak
open "hush://generate?mode=key&bytes=64&format=hex&copy=0"       # 密钥:bytes format;可读:groups digits
```

参数写错时会弹出提示,说明是哪个参数,不会静默忽略。

**快捷指令**:提供"生成密码"和"用预设生成"两个动作,返回生成的密码,可选同时复制到剪贴板。

**自定义预设**:在面板里调好设置,按 `⌘S` 存为预设;在设置的"预设"页可以重命名、排序、删除,并给它绑定全局快捷键。

## 更新

Hush 从不联网,所以**不会自动检查更新**。想更新时:

- 菜单栏菜单或"设置 › 通用"中点击"检查更新…",会在浏览器中打开 [GitHub 上的最新版本](https://github.com/08820048/hush/releases/latest),下载后替换"应用程序"中的 Hush.app 即可。设置和预设都会保留。
- 用 Homebrew 安装的:`brew upgrade --cask hush`(命令行工具:`brew upgrade hush-cli`)。
- 想收到新版本通知,可以在 GitHub 仓库页面点 Watch › Custom › Releases。

## 语言

App 支持简体中文和英文,跟随系统语言;其他语言的系统显示英文。界面文案都在 `App/Hush/Localizable.xcstrings`(String Catalog)里,用 Xcode 打开即可编辑或新增语言,欢迎提交翻译。

## 目录结构

```
Core/               生成核心 HushCore + 测试(独立 Swift 包,App 与 CLI 共用)
Sources/hush/       命令行工具(根目录 Package.swift)
App/                macOS App(XcodeGen 工程)
docs/               需求文档
scripts/            App 图标渲染脚本
```

## 许可

MIT。短语词库来自 EFF(CC BY 3.0),第三方署名见 [NOTICE](NOTICE)。
