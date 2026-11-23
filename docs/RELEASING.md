# 发布流程

## 一次性准备(需要 Apple Developer Program 会员)

1. **Developer ID 证书**:在 Xcode › Settings › Accounts › Manage Certificates 中新建 "Developer ID Application" 证书。在"钥匙串访问"中把它导出为 `.p12`,并设置一个密码。
2. **公证用的 API Key**:在 App Store Connect › 用户和访问 › 集成 › App Store Connect API 中新建一个 Key(角色选 Developer),下载 `.p8`。记下 Key ID 和 Issuer ID。
3. **Bundle ID**:把 `App/project.yml` 中的占位值 `dev.hushapp.Hush` 换成你自己的,例如 `com.<你的域名>.hush`。
4. **GitHub Secrets**:在仓库 Settings › Secrets and variables › Actions 中添加:

| Secret | 内容 |
|---|---|
| `DEVELOPER_ID_P12` | `base64 -i cert.p12 \| pbcopy` 的结果 |
| `DEVELOPER_ID_P12_PASSWORD` | 导出 `.p12` 时设置的密码 |
| `DEVELOPER_ID` | 例如 `Developer ID Application: Your Name (TEAMID)` |
| `TEAM_ID` | 10 位 Team ID |
| `NOTARY_KEY_P8` | `base64 -i AuthKey_XXXX.p8 \| pbcopy` 的结果 |
| `NOTARY_KEY_ID` | API Key 的 Key ID |
| `NOTARY_ISSUER` | Issuer ID |

## 每次发布

1. 修改 `App/project.yml` 中的 `MARKETING_VERSION`(以及 CLI 的 `version`,在 `Sources/hush/Hush.swift`),提交。
2. 打标签并推送:

   ```sh
   git tag v0.2.0
   git push origin v0.2.0
   ```

3. GitHub Actions 的 Release 流程会自动测试、构建通用二进制(Apple 芯片 + Intel)、签名、公证,并创建 GitHub Release。没有配置证书时,只发布标注"仅供测试"的预发布版。
4. 更新 Homebrew:运行 `scripts/homebrew.sh 0.2.0`,把 `packaging/homebrew/out/` 中的文件复制到 tap 仓库。详见 `packaging/homebrew/README.md`。

## 在本机发布

```sh
make release                       # 不签名,只用于本机测试
DEVELOPER_ID="Developer ID Application: …" TEAM_ID=… NOTARY_PROFILE=hush-notary make release
```

`NOTARY_PROFILE` 需要先用 `xcrun notarytool store-credentials hush-notary` 保存一次。产物在 `dist/`。
