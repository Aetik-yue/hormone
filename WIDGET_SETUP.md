# Android 桌面小组件整合指南

Flutter 侧的 `lib/features/widget/` 已经能够把今日课程写入
`home_widget` 的数据通道，并触发 Android App Widget 刷新。

原生小组件代码保存在 `native_templates/android/`。由于生成的 `android/`
目录不提交到仓库，首次克隆后需要按下面步骤恢复并接入模板。

## 1. 生成 Android 工程

在仓库根目录执行：

```bash
flutter create . --platforms=android --org com.aetikyue
flutter pub get
```

## 2. 复制 Android 原生模板

| 模板文件 | 目标位置 |
|---|---|
| `native_templates/android/app/build.gradle.kts` | `android/app/build.gradle.kts` |
| `native_templates/android/app/src/main/AndroidManifest.xml` | `android/app/src/main/AndroidManifest.xml` |
| `native_templates/android/app/src/main/java/com/aetikyue/hormone/CourseWidgetProvider.kt` | `android/app/src/main/java/com/aetikyue/hormone/CourseWidgetProvider.kt` |
| `native_templates/android/app/src/main/res/xml/course_widget_info.xml` | `android/app/src/main/res/xml/course_widget_info.xml` |
| `native_templates/android/app/src/main/res/layout/course_widget.xml` | `android/app/src/main/res/layout/course_widget.xml` |
| `native_templates/android/app/src/main/res/xml/filepaths.xml` | `android/app/src/main/res/xml/filepaths.xml` |

模板中的 Kotlin 包名与真实包名 `com.aetikyue.hormone` 一致，复制后无需修改。

也可以在 PowerShell 中一次性覆盖复制整个原生模板：

```powershell
Copy-Item native_templates/android/app/build.gradle.kts android/app/build.gradle.kts -Force
Copy-Item native_templates/android/app/src/main/* android/app/src/main/ -Recurse -Force
```

Gradle 模板包含 API 24 最低版本、更新插件需要的 desugaring 版本和固定签名配置。
若旧的本地工程仍有 `android/app/build.gradle`，请先备份并合并其中的自定义配置，
最终只保留一种 app 模块构建脚本，避免 Groovy 文件优先于 Kotlin 模板。

完整的 `AndroidManifest.xml` 已注册桌面小组件 Receiver 与应用内更新所需的
FileProvider/安装权限；`AndroidManifest.receiver.xml` 仅作为 Receiver 片段参考。

Android 上 `home_widget` 将数据写入 `HomeWidgetSharedPreferences`；
`CourseWidgetProvider` 读取其中的 `widget_title` 和 `courses`，无需额外的数据服务。

## 3. 验证

```bash
dart run build_runner build --delete-conflicting-outputs
flutter analyze --fatal-infos --fatal-warnings
flutter test
flutter run
```

打开课表主页后返回系统桌面，添加“今日课程”小组件。小组件应显示当天课程；
点击后应能拉起 App。

## 4. 已知限制

- 小组件刷新集中由应用根部的 `_AppEffects` 驱动：监听学期/课程/节次变化（防抖）
  与回到前台、跨过午夜时补刷；App 未在后台运行时不刷新。
- 尚未接入 Android 后台定时任务（如需整点自定义，可加 `WorkManager` 或
  `home_widget` 的 background callback）。
- 小组件最多展示原生模板允许的前若干门课程；如需滚动列表，可改为
  `RemoteViewsService`。
- ICS 时间按学校本地时间处理，忽略 `TZID`/UTC 偏移。
