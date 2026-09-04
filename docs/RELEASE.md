# Hormone Android 发布指南

> 本项目只面向 Android。仓库不维护或构建任何 iOS 目标。

构建环境要求 Flutter 3.29+ / Dart 3.7+；最低支持 Android 7.0（API 24）。

## 1. 本地开发验证

首次克隆后生成 Android 原生工程：

```bash
flutter create . --platforms=android --org com.aetikyue
flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart run flutter_launcher_icons
dart run flutter_native_splash:create
flutter analyze --fatal-infos --fatal-warnings
flutter test
```

`android/` 是生成目录，不提交到仓库。自定义 Gradle 配置和 Android 小组件
及应用内更新模板保存在 `native_templates/android/`；接入方式见 `WIDGET_SETUP.md`。

## 2. Application ID

当前应用包名为 `com.aetikyue.hormone`（由 `flutter create --org com.aetikyue`
生成；`pubspec.yaml` 项目名为 `hormone`）。如需修改，在生成后的
`android/app/build.gradle.kts` 中同步修改：

```kotlin
android {
    namespace = "com.yourcompany.hormone"
    defaultConfig {
        applicationId = "com.yourcompany.hormone"
    }
}
```

同时修改 `CourseWidgetProvider.kt` 顶部的 Kotlin 包名和对应目录结构，
以及 `.github/workflows/release.yml` 中 `flutter create` 的 `--org` 参数
（否则 CI 产物包名仍是 `com.aetikyue.hormone`）。

> ⚠️ 包名是应用身份标识，Google Play 上架后不可更改；请提前确认未被占用。

## 3. 正式签名

release CI 必须使用长期固定的 Android 签名证书。Android 覆盖升级要求新旧 APK
包名与签名都一致；一旦更换或丢失密钥，现有用户就无法通过应用内更新升级。

生成密钥：

```bash
keytool -genkeypair -v \
  -keystore hormone-release-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias hormone
```

本地正式构建时，创建不提交到 Git 的 `android/key.properties`：

```properties
storePassword=<密码>
keyPassword=<密码>
keyAlias=hormone
storeFile=<密钥绝对路径或相对路径>
```

`native_templates/android/app/build.gradle.kts` 会使用该文件或 `HORMONE_KEYSTORE_PATH`、
`HORMONE_KEYSTORE_PASSWORD`、`HORMONE_KEY_ALIAS`、`HORMONE_KEY_PASSWORD` 环境变量。
Release 构建缺少完整签名配置时会直接失败，不再回退到 debug 签名。

已配置 Windows 加密凭据的维护者可使用以下脚本构建 APK/AAB，无需保存明文
`key.properties`（替换 Flutter SDK 路径）：

```powershell
./scripts/build_signed_android.ps1 -FlutterSdk E:/flutter
```

脚本默认读取当前用户 `.android/hormone-release/hormone-release-key.jks` 与
`credentials.clixml`，也可通过 `-SigningDirectory` 指定目录。`credentials.clixml`
使用 Windows 当前用户/机器加密，不能仅靠复制此文件在另一台电脑恢复密码；
请在更换电脑前将签名文件和密码分别备份到安全离线存储与密码管理器。

将 keystore 转为单行 Base64（不要提交输出文件）：

```bash
base64 -w 0 hormone-release-key.jks
```

在 GitHub 仓库 Settings → Secrets and variables → Actions 中配置：

- `ANDROID_KEYSTORE_BASE64`：上一步的完整 Base64。
- `ANDROID_KEYSTORE_PASSWORD`：keystore 密码。
- `ANDROID_KEY_ALIAS`：例如 `hormone`。
- `ANDROID_KEY_PASSWORD`：alias 密码。

密钥本体、alias 和两个密码必须安全离线备份。正式发布前先完成这一步。

当前固定签名沿用了实际发布的 v1.2.2 签名。已校验本地 v1.2.2 APK 的 SHA-256
与 GitHub Release 一致，且证书与旧 `.android/debug.keystore` 一致；密钥现已复制
到独立 keystore 并更换存储密码，但证书身份不变（证书名称仍为历史的 Android Debug）。

固定证书 SHA-256：

```text
7206848b62105dcc9ea3e62a7a2f11158f14b6705849e10441dcf68fae52a6f6
```

v1.2.2 用户无需因本次签名整理卸载 App。更早的历史 CI 包可能使用不同的临时
debug 证书；只有系统确实提示签名不兼容时，才需要先导出课表备份，再卸载重装。
这套签名面向 GitHub APK 分发；若将来上架 Google Play，需要另行规划生产签名与迁移。

## 4. 构建产物

```bash
flutter build apk --release
flutter build appbundle --release
```

产物位置：

- APK：`build/app/outputs/flutter-apk/app-release.apk`
- AAB：`build/app/outputs/bundle/release/app-release.aab`

发布前核对 APK 包内版本和签名：

```bash
aapt dump badging build/app/outputs/flutter-apk/app-release.apk
apksigner verify --verbose --print-certs build/app/outputs/flutter-apk/app-release.apk
```

## 5. Android 桌面小组件

按照 `WIDGET_SETUP.md` 将 `native_templates/android/` 中的模板复制到生成的
Android 工程，并在 `AndroidManifest.xml` 注册 `CourseWidgetProvider`。

发布前至少验证：

- 无课程、本周无课和有多门课程三种状态。
- App 启动、导入、编辑和删除课程后的小组件刷新。
- 点击小组件可以正常拉起 App。
- 深色桌面和不同 Android 版本上的可读性。

## 6. Google Play 发布

1. 登录 [Google Play Console](https://play.google.com/console) 并创建应用。
2. 填写商店列表，文案与截图计划见 `docs/STORE_LISTING.md`。
3. 上传使用正式密钥签名的 AAB。
4. 先经过 Internal testing 和 Closed testing，再逐步发布到 Production。
5. 检查 Play Console 当前要求的 targetSdk、隐私政策和数据安全表单。

## 7. GitHub Release

项目版本号位于 `pubspec.yaml`：

```yaml
version: major.minor.patch+buildNumber
```

发布步骤：

1. 更新版本号和 `version/<版本>/更新日志.md`。
2. 完成代码生成、严格分析、完整测试和 release APK 构建。
3. 提交并直接同步到 `develop` 和 `main`。
4. 在 `main` 发布提交上创建 `vX.Y.Z` 标签并推送。
5. `.github/workflows/release.yml` 会用固定密钥构建 APK/AAB，生成 APK 的
   `.sha256` 文件，并自动创建 GitHub Release；如存在
   `version/<版本>/更新日志.md`，会直接作为 Release 说明。
6. 确认 GitHub Release 中同时存在 APK、AAB、APK.sha256 三个资产。

App 通过 GitHub 的 `releases/latest` 接口检查最新正式版本。请勿只上传 Actions
Artifact，也不要把常规版本标记为 draft/prerelease，否则客户端不会发现它。

应用内安装面向 GitHub APK 分发。普通 Android 应用无法静默更新：下载并校验后，
用户仍需在系统安装页确认；Android 8+ 首次使用时还可能要求授予“安装未知应用”
权限。如果将来通过 Google Play 分发，应改用 Play In-App Updates，并重新评估
`REQUEST_INSTALL_PACKAGES` 是否符合 Play 政策。

## 8. 发布 Checklist

- [ ] `pubspec.yaml` 版本号和 build number 已递增。
- [ ] 更新日志已完成。
- [ ] `flutter analyze --fatal-infos --fatal-warnings` 通过。
- [ ] `flutter test` 全部通过。
- [ ] release APK 和 AAB 构建成功。
- [ ] APK 包名、版本、最低/目标 API 正确。
- [ ] APK 签名证书与上一版本一致。
- [ ] 四个 GitHub Actions 签名 Secrets 均已配置且未发生轮换。
- [ ] 桌面小组件已在 Android 真机验证。
- [ ] GitHub Release 资产的大小和 SHA-256 与本地产物一致。
- [ ] 在上一正式版本真机上完成“检查 → 下载 → 系统确认 → 覆盖安装”验证。
- [ ] `main`、`develop` 和版本标签指向预期提交。
