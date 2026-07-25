# hormone Phase 8 完成概览

## 本次完成内容

Phase 8（发布阶段）已完成，主要包含应用图标、启动屏、商店元数据与 CI/CD 配置：

1. **应用图标与启动屏**
   - 生成 `assets/icon/icon.png`（1024×1024，蓝底 + 白色课程表卡片）。
   - 生成 `assets/splash/logo.png`（透明底，用于启动屏）。
   - 使用自写 Python 脚本（`tools/generate_assets.py`，仅标准库）生成，无需外部图像工具。

2. **pubspec.yaml 更新**
   - 版本号 `1.0.0+1`。
   - 新增 `flutter_launcher_icons` 与 `flutter_native_splash` 开发依赖及生成配置。
   - 声明 `assets/icon/` 与 `assets/splash/` 资源目录。

3. **CI/CD 工作流**
   - `.github/workflows/ci.yml`：每次 push/PR 自动 `flutter pub get` → `build_runner` → `flutter analyze` → `flutter test`。
   - `.github/workflows/release.yml`：推送 `v*` 标签时自动构建 Android APK/AAB，并在 macOS runner 上构建 iOS（无签名）。

4. **发布文档**
   - `docs/RELEASE.md`：本地验证命令、Bundle ID 替换、签名、构建命令、上架流程、发布 Checklist。
   - `docs/STORE_LISTING.md`：中英文应用名称、副标题、描述、关键词、截图策略、隐私政策模板。

5. **仓库基础**
   - 新增 `.gitignore`（Flutter 标准 + 忽略 `android/`/`ios/` 等由 `flutter create .` 生成的目录）。

## 验证状态

- **沙箱内无法找到 Flutter 可执行文件**：已用 `which flutter`、PATH 检查、常见目录探测、以及最大深度 6 的文件系统扫描进行全面排查，均未发现 `flutter`/`flutter.bat`/`flutter.exe`。
- 原因：当前 WorkBuddy 沙箱环境与用户本机的 PATH/文件系统隔离；你本机配置的 Flutter PATH 未传递到该沙箱。
- **后续验证需在本机终端执行**（完整命令见 `docs/RELEASE.md` 第 1 节）。

## 建议的本地验证命令

```bash
flutter create .
flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart run flutter_launcher_icons
dart run flutter_native_splash:create
flutter analyze --fatal-infos --fatal-warnings
flutter test
```

若想让沙箱内直接运行，请在本机 PowerShell/CMD 执行 `where flutter`，把输出的绝对路径（例如 `C:\Users\yanha\flutter\bin\flutter.bat`）贴回；只要该路径在沙箱可见，我可以继续代跑验证。
