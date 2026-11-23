# 上架 Mac App Store

Hush 有两个版本,来自同一份代码:

| | GitHub 版 | Mac App Store 版 |
|---|---|---|
| 价格 | 免费,GPL-3.0 开源 | 由你在 App Store Connect 设定 |
| 构建 | `make release` / 推送版本标签 | `make appstore`(方案 “Hush App Store”,配置 `AppStore`) |
| 直接粘贴(⌘↩) | 有(需要“辅助功能”权限) | **没有**:沙盒应用拿不到辅助功能权限,⌘↩ 等同于复制 |
| 检查更新 | 打开 GitHub 发布页 | **没有**:Mac 应用只能通过 App Store 更新 |
| 签名 | 暂未签名 | Apple Distribution 证书 |

两者的差异由编译条件 `APP_STORE` 控制,相关代码在 App Store 版中不会被编译进去;`scripts/appstore.sh` 会检查归档里不含辅助功能相关的调用。

你是 Hush 全部代码的唯一版权人,所以可以在以 GPL 开源的同时,按 App Store 的条款销售。外部贡献依据 [CONTRIBUTING.md](../CONTRIBUTING.md) 中的授权条款,也可以进入 App Store 版。

## 一次性准备

1. **加入 Apple Developer Program**(个人,99 美元/年),在 Xcode › Settings › Accounts 登录该账号。
2. **确定 Bundle ID**。上架后无法修改,建议用你的域名倒序:`fyi.hushpass.Hush`。在 [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) 注册这个 App ID。
3. **在 App Store Connect 新建 App**:平台 macOS,Bundle ID 选上一步的,SKU 随意(如 `hush-mac`)。
   - **名称**:App Store 上的名称必须唯一,“Hush” 很可能已被占用。可以用 “Hush – Password Generator” 或 “HushPass”,App 本身仍显示为 Hush。
4. **协议、税务和银行**:在 App Store Connect › 业务 中签署“付费 App 协议”,填写税务和收款信息。收费 App 必须完成这一步。

## 每个版本

```sh
TEAM_ID=你的TeamID BUNDLE_ID=fyi.hushpass.Hush make appstore           # 生成 dist/appstore/Hush.pkg
TEAM_ID=你的TeamID BUNDLE_ID=fyi.hushpass.Hush UPLOAD=1 make appstore  # 直接上传
```

版本号沿用 `App/project.yml` 的 `MARKETING_VERSION`,构建号自动取当前时间。也可以用 Apple 的 Transporter App 上传导出的 `.pkg`。上传后先在 TestFlight 里自己装一遍,确认没问题再提交审核。

## App Store Connect 里要填的内容

| 项目 | 填写 |
|---|---|
| 销售范围 | 取消勾选 **中国大陆**(其他地区不需要 ICP 备案) |
| 类别 | 主类别:工具(Utilities) |
| 隐私政策网址 | `https://hushpass.fyi/privacy/`(英文:`https://hushpass.fyi/en/privacy/`) |
| App 隐私(数据收集) | 选择 **“不收集数据”** |
| 年龄分级 | 所有问题选“无”,结果为 4+ |
| 加密出口合规 | 已在 Info.plist 声明 `ITSAppUsesNonExemptEncryption = NO`,上传后不会再问 |
| 版权 | `© 2026 XuYi` |
| 技术支持网址 | `https://github.com/08820048/hush/issues` |
| 营销网址 | `https://hushpass.fyi` |
| 截图 | 至少 1 张,尺寸 1280×800、1440×900、2560×1600 或 2880×1800 之一。可以用宣传设计稿或 `make snapshots` 的界面截图制作 |

### 给审核人员的备注(App Review Information › Notes)

Hush 是菜单栏 App,没有 Dock 图标,审核人员可能找不到入口。建议填写:

> Hush is a menu bar app (no Dock icon). After launch, click the three-dot icon in the menu bar to generate and copy a password, or right-click it for the quick panel. Press Option-Command-P to open the main panel. No account or network connection is needed; the app has no network entitlement. The source code is public at https://github.com/08820048/hush.

## 常见被拒原因与对策

- **4.2 功能过少**:强调五种模式、网站规则、预设、快捷指令、大字显示与二维码,截图展示这些功能。
- **2.4.5 更新机制 / 引导到其他渠道**:App Store 版已去掉“检查更新”,也不要在 App 描述里放 GitHub 下载链接。
- **5.1.1 隐私**:隐私政策网址必须能访问,内容与“不收集数据”一致(已满足)。
