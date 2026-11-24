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
2. **注册 Bundle ID** `fyi.hushpass.Hush`(项目已使用这个 ID,上架后不能修改)。在 [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) 注册这个 App ID。
3. **在 App Store Connect 新建 App**:平台 macOS,Bundle ID 选上一步的,SKU 随意(如 `hush-mac`)。
   - **名称**:**HushPass**(与域名 hushpass.fyi 一致;App Store 名称必须唯一,“Hush” 很可能已被占用)。副标题建议:中文“安静、离线的密码生成器”,英文 “Quiet, offline password generator”。安装后 App 本身仍显示为 Hush。
4. **接受最新协议**:先在 developer.apple.com › Account 接受最新的 Apple Developer Program License Agreement,再到 App Store Connect › 业务 接受“付费 App 协议”(Paid Applications Schedule)。
5. **协议、税务和银行**:在 App Store Connect › 业务 中签署“付费 App 协议”,填写税务和收款信息。收费 App 必须完成这一步。

## 每个版本

```sh
TEAM_ID=你的TeamID make appstore           # 生成 dist/appstore/Hush.pkg
TEAM_ID=你的TeamID UPLOAD=1 make appstore  # 直接上传
```

版本号沿用 `App/project.yml` 的 `MARKETING_VERSION`,构建号自动取当前时间。也可以用 Apple 的 Transporter App 上传导出的 `.pkg`。上传后先在 TestFlight 里自己装一遍,确认没问题再提交审核。

## 用 Xcode Cloud 构建并上传(推荐)

Xcode Cloud 在 Apple 的服务器上用**正式版 Xcode** 构建、云端签名,并直接上传到 App Store Connect / TestFlight,本机装的是测试版 Xcode 也没关系。仓库已经准备好:工程文件与依赖锁定文件(`Package.resolved`)已提交,工程里设置了 Team ID。

**第一次设置**(在本机 Xcode 中完成,测试版 Xcode 也可以):

1. 打开 `App/Hush.xcodeproj`,菜单 **Integrate › Create Workflow…**(旧版本在 Product › Xcode Cloud),选择 App **HushPass**。
2. 按提示授权 Xcode Cloud 访问 GitHub 仓库 `08820048/hush`。
3. 编辑工作流:
   - **General**:名称如 “App Store Release”。
   - **Environment**:Xcode 选 **Latest Release**,macOS 选 **Latest Release**。
   - **Start Conditions**:删掉默认的“分支变更”,改为 **Tag Changes**,标签匹配 `v*`(每次推送版本标签时构建);也可以只保留手动开始。
   - **Actions**:删掉默认动作,添加 **Archive – macOS**,Scheme 选 **Hush App Store**,Deployment Preparation 选 **App Store Connect**。
   - **Post-Actions**:添加 **TestFlight Internal Testing**,选你自己所在的测试组。
4. 保存后点 **Start Build**。构建号由 Xcode Cloud 自动递增,无需手动修改。

**之后每个版本**:运行 `scripts/bump-version.sh` 并推送版本标签,GitHub Actions 发布 GitHub 版,Xcode Cloud 同时构建 App Store 版并送到 TestFlight;在 TestFlight 里确认后,到 App Store Connect 提交审核。

本机命令 `make appstore` 仍然可用(需要正式版 Xcode),作为 Xcode Cloud 之外的备用方式。

## App Store Connect 里要填的内容

| 项目 | 填写 |
|---|---|
| 销售范围 | 取消勾选 **中国大陆**(避免 App 备案、AIGC 声明与安全评估)和 **欧盟 27 国**(奥地利、比利时、保加利亚、克罗地亚、塞浦路斯、捷克、丹麦、爱沙尼亚、芬兰、法国、德国、希腊、匈牙利、爱尔兰、意大利、拉脱维亚、立陶宛、卢森堡、马耳他、荷兰、波兰、葡萄牙、罗马尼亚、斯洛伐克、斯洛文尼亚、西班牙、瑞典)。英国、瑞士、挪威等非欧盟国家照常销售 |
| 欧盟商家身份(DSA) | 暂不填写。在欧盟上架前需要声明为“商家”,并公开经过验证的地址、电话和邮箱;准备好后填写并把欧盟加回销售范围即可 |
| 类别 | 主类别:工具(Utilities) |
| 隐私政策网址 | `https://hushpass.fyi/privacy/`(英文:`https://hushpass.fyi/en/privacy/`) |
| App 隐私(数据收集) | 选择 **“不收集数据”** |
| 年龄分级 | 所有问题选“无”,结果为 4+ |
| 加密出口合规 | 已在 Info.plist 声明 `ITSAppUsesNonExemptEncryption = NO`,上传后不会再问 |
| 版权 | `© 2026 XuYi` |
| 技术支持网址 | `https://github.com/08820048/hush/issues` |
| 营销网址 | `https://hushpass.fyi` |
| 截图 | 已做好:`marketing/appstore/screenshots/en/` 与 `zh-Hans/`,各 5 张 2880×1800,按文件名顺序上传。改了官网文案或界面后运行 `make appstore-screenshots` 重新生成。截图不含 App Store 版没有的功能(直接粘贴、检查更新) |

### 给审核人员的备注(App Review Information › Notes)

Hush 是菜单栏 App,没有 Dock 图标,审核人员可能找不到入口。建议填写:

> Hush is a menu bar app (no Dock icon). After launch, click the three-dot icon in the menu bar to generate and copy a password, or right-click it for the quick panel. Press Option-Command-P to open the main panel. No account or network connection is needed; the app has no network entitlement. The source code is public at https://github.com/08820048/hush.

## 常见被拒原因与对策

- **4.2 功能过少**:强调五种模式、网站规则、预设、快捷指令、大字显示与二维码,截图展示这些功能。
- **2.4.5 更新机制 / 引导到其他渠道**:App Store 版已去掉“检查更新”,也不要在 App 描述里放 GitHub 下载链接。
- **5.1.1 隐私**:隐私政策网址必须能访问,内容与“不收集数据”一致(已满足)。
