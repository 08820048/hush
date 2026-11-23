# 发布流程

Hush 通过**版本标签**自动发布:推送 `v*.*.*` 标签后,GitHub Actions 会自动测试、构建并创建 GitHub Release。目前的版本**不签名、不公证**(开源项目暂不使用 Apple 开发者证书),Release 说明里会告诉用户如何打开。

## 每次发布

```sh
scripts/bump-version.sh 0.2.0          # 同时修改 App 和 CLI 的版本号
git commit -am "chore: release v0.2.0"
git tag v0.2.0
git push origin main v0.2.0
```

推送标签后,Release 工作流(`.github/workflows/release.yml`)会依次执行:

1. **检查版本**:标签必须和代码中的版本号一致(`App/project.yml` 的 `MARKETING_VERSION`、`Sources/hush/Hush.swift` 的 `version`)。不一致时直接失败,并提示运行 `scripts/bump-version.sh`。
2. **测试和构建**:运行核心测试;构建通用二进制(Apple 芯片 + Intel)的 `Hush.app` 和 `hush` 命令行工具;检查 App 没有网络权限。构建号(`CFBundleVersion`)使用工作流的运行编号。
3. **发布**:根据上一个标签到这个标签之间的提交生成更新日志,附上下载说明和未签名 App 的打开方法(中英文),创建 GitHub Release。产物为 `Hush-<版本>.zip`、`hush-cli-<版本>.zip`、`SHA256SUMS.txt`。
4. **Homebrew**(可选):见下文。

- 带后缀的标签(如 `v0.2.0-beta.1`)会发布为**预发布版**,不更新 Homebrew。
- 对同一个标签重新运行工作流,会覆盖该 Release 的文件和说明。
- 在 Actions 页面选择 Release › Run workflow 并输入版本号,可以**只构建不发布**,用来演练;构建产物可在该次运行的 Artifacts 中下载,保留 14 天。

### 版本号规则

`主版本.次版本.修订号`,可选预发布后缀:`1.2.3`、`1.2.3-beta.1`。提交信息建议使用 `feat:`、`fix:` 等前缀,更新日志会原样列出。以 `chore: release v` 开头的提交不会出现在更新日志里。

## Homebrew(可选)

1. 在 GitHub 新建公开仓库 `08820048/homebrew-tap`。
2. 新建一个只对该仓库有 Contents 读写权限的 Fine-grained token,在 hush 仓库的 Settings › Secrets and variables › Actions 中添加为 `HOMEBREW_TAP_TOKEN`。
3. 之后每个正式版(非预发布)会自动更新 tap 中的 `Casks/hush.rb` 和 `Formula/hush-cli.rb`。用户安装:

```sh
brew install --cask 08820048/tap/hush     # App
brew install 08820048/tap/hush-cli        # 命令行工具
```

没有设置 token 时,这一步自动跳过。也可以手动生成:`scripts/homebrew.sh 0.2.0`,输出在 `packaging/homebrew/out/`。

## 在本机构建发布版

```sh
make release          # 产物在 dist/,与 CI 相同
```

## 以后启用签名和公证

`scripts/release.sh` 已经支持 Developer ID 签名、公证和 staple:设置 `DEVELOPER_ID`、`TEAM_ID`,以及 `NOTARY_PROFILE`(本机,用 `xcrun notarytool store-credentials` 创建)或 `NOTARY_KEY_PATH`/`NOTARY_KEY_ID`/`NOTARY_ISSUER`(App Store Connect API Key)。启用时还需要:

- 把 `App/project.yml` 中的占位 Bundle ID `dev.hushapp.Hush` 换成自己的。
- 在 Release 工作流中加入导入证书的步骤,并把上面的变量传给 `scripts/release.sh`。
- 删除 Release 说明和 Homebrew cask 中"尚未签名"的提示。
