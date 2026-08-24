# Hormone Android 发布指南

> 本项目只面向 Android。仓库不维护或构建任何 iOS 目标。

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
模板保存在 `native_templates/android/`；小组件接入方式见 `WIDGET_SETUP.md`。

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
（否则 CI 产物包名仍是 `com.example.hormone`）。

> ⚠️ 包名是应用身份标识，Google Play 上架后不可更改；请提前确认未被占用。

## 3. 正式签名

当前仓库的 release 构建暂时使用 Android Debug 证书，只适合直接安装和测试。
发布 Google Play 前必须配置长期保存的正式密钥。

生成密钥：

```bash
keytool -genkeypair -v \
  -keystore hormone-release-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias hormone
```

创建不提交到 Git 的 `android/key.properties`：

```properties
storePassword=<密码>
keyPassword=<密码>
keyAlias=hormone
storeFile=<密钥绝对路径或相对路径>
```

然后在 `android/app/build.gradle.kts` 中创建 `signingConfigs.release` 并让
`buildTypes.release` 使用该配置。密钥和密码必须离线备份；丢失密钥将无法为
现有安装用户发布可覆盖升级的版本。

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
3. 将经过校验的 APK 复制为 `version/<版本>/Hormone.apk`。
4. 提交并直接同步到 `develop` 和 `main`。
5. 在 `main` 发布提交上创建 `vX.Y.Z` 标签。
6. 创建 GitHub Release，并上传 `Hormone.apk`。
7. 确认 `.github/workflows/release.yml` 的 Android APK、AAB 与产物上传步骤通过。

## 8. 发布 Checklist

- [ ] `pubspec.yaml` 版本号和 build number 已递增。
- [ ] 更新日志已完成。
- [ ] `flutter analyze --fatal-infos --fatal-warnings` 通过。
- [ ] `flutter test` 全部通过。
- [ ] release APK 和 AAB 构建成功。
- [ ] APK 包名、版本、最低/目标 API 正确。
- [ ] APK 签名证书与上一版本一致。
- [ ] 桌面小组件已在 Android 真机验证。
- [ ] GitHub Release 资产的大小和 SHA-256 与本地产物一致。
- [ ] `main`、`develop` 和版本标签指向预期提交。
