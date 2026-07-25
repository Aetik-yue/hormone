# hormone 发布指南（Phase 8）

> 本文档汇总从开发到 App Store / Google Play 上架的关键步骤、签名配置与发布节奏。

---

## 1. 本地开发验证命令

在已安装 Flutter 的机器上，进入项目根目录执行：

```bash
# 1. 生成原生工程（本仓库不保留 android/ios，首次运行时创建）
flutter create .

# 2. 拉取依赖
flutter pub get

# 3. 生成 drift 代码（app_database.g.dart）
dart run build_runner build --delete-conflicting-outputs

# 4. 生成应用图标与启动屏
#    源文件位于 assets/icon/icon.png 与 assets/splash/logo.png
dart run flutter_launcher_icons
dart run flutter_native_splash:create

# 5. 静态分析与测试
flutter analyze --fatal-infos --fatal-warnings
flutter test

# 6. 运行
flutter run
```

> 注：项目采用 **“无原生目录”** 维护方式。`flutter create .` 会生成 `android/`、`ios/` 等目录；`native_templates/` 中保存了桌面小组件的原生模板，需按 `WIDGET_SETUP.md` 手动复制/集成。

---

## 2. Bundle ID / Application ID

首次发布前必须替换占位包名。当前为 `com.example.hormone`，请改为自有域名：

- **Android**：`android/app/build.gradle`
  ```gradle
  namespace = "com.yourcompany.hormone"
  applicationId = "com.yourcompany.hormone"
  ```
- **iOS**：`ios/Runner.xcodeproj/project.pbxproj` 中的 `PRODUCT_BUNDLE_IDENTIFIER`。
- 同步修改 `CFBundleIdentifier`（`ios/Runner/Info.plist`）。

> 如使用 `change_app_package_name` 包可一键替换：
> ```bash
> dart run change_app_package_name:main com.yourcompany.hormone
> ```

---

## 3. 应用签名

### Android

1. 生成发布密钥（仅一次）：
   ```bash
   keytool -genkey -v -keystore ~/hormone-release-key.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias hormone
   ```
2. 创建 `android/key.properties`（已加入 `.gitignore`，勿提交）：
   ```properties
   storePassword=<密码>
   keyPassword=<密码>
   keyAlias=hormone
   storeFile=../../hormone-release-key.jks
   ```
3. 在 `android/app/build.gradle` 中引用 `key.properties` 并启用 `signingConfigs.release`。

### iOS

1. 在 **Xcode → Signing & Capabilities** 中选择 Team。
2. 设置 Bundle Identifier，勾选 `Automatically manage signing`。
3. 如需桌面小组件，确保 **App Groups** 能力已启用，group ID 为 `group.hormone`（与 `widget_service.dart` 中一致）。

---

## 4. 崩溃监控（可选但推荐）

`pubspec.yaml` 已引入 `sentry_flutter: ^8.0.0`，但当前未初始化。发布前：

1. 在 Sentry 创建项目并获取 **DSN**。
2. 在 `lib/main.dart` 中包裹 `runApp`：
   ```dart
   await SentryFlutter.init(
     (options) {
       options.dsn = 'YOUR_DSN_HERE';
       options.tracesSampleRate = 0.1;
     },
     appRunner: () => runApp(const ProviderScope(child: HormoneApp())),
   );
   ```
3. 通过 `dart define` 或环境变量注入 DSN，避免硬编码。

---

## 5. 构建产物

### Android

```bash
flutter build apk --release          # APK
flutter build appbundle --release    # Google Play 上架用 AAB
```

产物位置：
- APK：`build/app/outputs/flutter-apk/app-release.apk`
- AAB：`build/app/outputs/bundle/release/app-release.aab`

### iOS

```bash
flutter build ipa --release
```

产物位置：`build/ios/ipa/hormone.ipa`。需要在 macOS + Xcode 环境下完成归档与分发。

---

## 6. 桌面小组件发布注意事项

小组件原生代码位于 `native_templates/`，不会随 `flutter create .` 自动生效。上架前：

1. 按 `WIDGET_SETUP.md` 复制模板到 `ios/Runner/Widgets/` 与 `android/app/src/main/...`。
2. iOS 在 Xcode 中：File → New → Target → Widget Extension；开启 App Group `group.hormone`。
3. Android 在 `AndroidManifest.xml` 注册 `CourseWidgetProvider`；`home_widget` 已负责 SharedPreferences 桥接。
4. 审核截图中应包含至少一张小组件效果图。

---

## 7. 商店发布与分阶段 rollout

### Google Play

1. 登录 [Play Console](https://play.google.com/console)，创建应用。
2. 填写商店列表（见 `docs/STORE_LISTING.md`），上传隐私政策 URL。
3. 在 **Release → Production → Create new release** 上传 AAB。
4. 建议：先进行 **Internal testing** → **Closed testing** → **Open testing** → **Production**，按 5% → 20% → 50% → 100% 阶梯放量。
5. 目标 API：当前 `targetSdk 34`（随 Flutter 版本自动维护）。

### App Store

1. 登录 [App Store Connect](https://appstoreconnect.apple.com)，新建 iOS App。
2. 填写名称、副标题、描述、关键词、隐私政策等（文案见 `docs/STORE_LISTING.md`）。
3. 使用 Xcode → Product → Archive → Distribute App 上传。
4. 在 App Store Connect 中选择构建版本，配置截图（见 `STORE_LISTING.md`）。
5. 启用 **Phased Release for Automatic Updates**，默认 7 天分阶段推送。

---

## 8. 发布前 Checklist

- [ ] `flutter analyze` 无错误、`flutter test` 全部通过。
- [ ] 包名已替换为自有 Bundle ID。
- [ ] Android 发布签名已配置，密钥未提交到仓库。
- [ ] iOS Team、Capability（App Group）已配置。
- [ ] 图标/启动屏已生成并肉眼检查（各尺寸无白边、无拉伸）。
- [ ] 深浅主题在真机/模拟器上验证。
- [ ] 桌面小组件按 `WIDGET_SETUP.md` 集成并验证刷新。
- [ ] ICS / JSON 导入用真实学校课表测试。
- [ ] Sentry DSN 已配置（如启用）。
- [ ] 隐私政策页面可访问。
- [ ] 截图、宣传文本、关键词已按 `STORE_LISTING.md` 准备。

---

## 9. 版本号管理

Flutter 版本号格式：`version: major.minor.patch+buildNumber`

```yaml
# pubspec.yaml
version: 1.0.0+1
```

- **Android**：`versionCode = buildNumber`，`versionName = major.minor.patch`。
- **iOS**：`CFBundleShortVersionString = major.minor.patch`，`CFBundleVersion = buildNumber`。
- 每次上架至少 +1 buildNumber；功能/修复按语义化版本调整 major/minor/patch。
