# 发布签名配置

`.github/workflows/release.yml` 只接受可分发的正式产物。正式签名、公证或商店提交所需的
secret 缺失时，对应 job 会失败，不会再上传未签名或临时证书签名的安装包。

工作流代码存在只表示发布链路已经配置，不表示任何既有产物已经签名、公证或提交。
只有使用正式 Secrets 的对应 job 成功完成全部验证后，才能对该次产物作出上述声明。

二进制内容使用 Base64 保存为 GitHub Actions secret。macOS 可用：

```bash
base64 -i path/to/file | pbcopy
```

## Android

- `ANDROID_KEYSTORE_BASE64`：release keystore
- `ANDROID_KEY_PROPERTIES_BASE64`：包含 `storeFile`、`storePassword`、`keyAlias`、
  `keyPassword` 的 `key.properties`；工作流会把 `storeFile` 重写为 CI 内的安全路径

## iOS

- `APPLE_DISTRIBUTION_CERTIFICATE_BASE64`：包含私钥的 Apple Distribution `.p12`
- `APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD`：`.p12` 密码
- `APPLE_KEYCHAIN_PASSWORD`：CI 临时 keychain 密码
- `IOS_APP_PROVISIONING_PROFILE_BASE64`：`com.kkape.mynas` 的 App Store profile
- `IOS_WIDGETS_PROVISIONING_PROFILE_BASE64`：`com.kkape.mynas.MyNasWidgets` 的 App Store profile
- `IOS_LIVE_ACTIVITY_PROVISIONING_PROFILE_BASE64`：
  `com.kkape.mynas.MusicActivityWidget` 的 App Store profile
- `APPLE_API_KEY_ID`、`APPLE_API_ISSUER_ID`、`APPLE_API_PRIVATE_KEY_BASE64`：
  App Store Connect API key，用于上传 IPA，也供 macOS 公证使用

iOS job 会生成并验证签名 IPA，随后提交 App Store Connect。App Store 签名 IPA 不能从
GitHub Release 直接安装，因此不会作为 GitHub 附件发布。TestFlight 或正式上架仍需在
App Store Connect 中确认处理、合规与审核状态。

## macOS

- `MACOS_DEVELOPER_ID_CERTIFICATE_BASE64`：包含私钥的 Developer ID Application `.p12`
- `MACOS_DEVELOPER_ID_CERTIFICATE_PASSWORD`：`.p12` 密码
- `MACOS_APP_PROVISIONING_PROFILE_BASE64`：`com.kkape.mynas` 的 Developer ID profile
- `MACOS_WIDGET_PROVISIONING_PROFILE_BASE64`：
  `com.kkape.mynas.MyNasWidgets` 的 Developer ID profile
- 与 iOS 共用 `APPLE_KEYCHAIN_PASSWORD` 和三个 App Store Connect API key secret

macOS job 会验证 app 签名，签名 DMG，等待 `notarytool` 公证完成，执行 stapling，并用
Gatekeeper 再次校验。任一步失败都不会上传 DMG。

## Windows

- `WINDOWS_CODE_SIGNING_CERTIFICATE_BASE64`：包含私钥的 Authenticode `.pfx`
- `WINDOWS_CODE_SIGNING_CERTIFICATE_PASSWORD`：`.pfx` 密码

工作流会对 Release 目录中的 EXE/DLL、MSIX 和 Inno Setup 安装程序签名并添加 RFC 3161
时间戳，然后使用 `signtool verify` 校验。MSIX manifest 的 Publisher 自动取自证书 Subject，
必须与计划使用的 Microsoft Store 产品身份一致。

MSIX 版本不再在 `msix_config` 中硬编码，而是由 `pubspec.yaml` 顶层 `version` 自动转换：
例如 `1.2.0+10` 生成包版本 `1.2.0.0`。
