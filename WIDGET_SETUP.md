# Android 桌面小组件整合指南

Flutter 侧的 `lib/features/widget/` 已经能够把今日课程写入
`home_widget` 的数据通道，并触发 Android App Widget 刷新。

原生小组件代码保存在 `native_templates/android/`。由于生成的 `android/`
目录不提交到仓库，首次克隆后需要按下面步骤恢复并接入模板。

## 1. 生成 Android 工程

在仓库根目录执行：

```bash
flutter create . --platforms=android
flutter pub get
```

## 2. 复制小组件模板

| 模板文件 | 目标位置 |
|---|---|
| `native_templates/android/app/src/main/java/com/example/hormone/CourseWidgetProvider.kt` | `android/app/src/main/java/<你的包名>/CourseWidgetProvider.kt` |
| `native_templates/android/app/src/main/res/xml/course_widget_info.xml` | `android/app/src/main/res/xml/course_widget_info.xml` |
| `native_templates/android/app/src/main/res/layout/course_widget.xml` | `android/app/src/main/res/layout/course_widget.xml` |

复制 `CourseWidgetProvider.kt` 后，把文件顶部的
`package com.example.hormone` 改为应用真实包名。真实包名以
`android/app/build.gradle.kts` 中的 `namespace` 和 `applicationId` 为准。

## 3. 注册 Receiver

把 `native_templates/android/app/src/main/AndroidManifest.receiver.xml` 中的
`<receiver>...</receiver>` 合并到
`android/app/src/main/AndroidManifest.xml` 的 `<application>` 标签内。

Android 上 `home_widget` 将数据写入 `HomeWidgetSharedPreferences`；
`CourseWidgetProvider` 读取其中的 `widget_title` 和 `courses`，无需额外的数据服务。

## 4. 验证

```bash
dart run build_runner build --delete-conflicting-outputs
flutter analyze --fatal-infos --fatal-warnings
flutter test
flutter run
```

打开课表主页后返回系统桌面，添加“今日课程”小组件。小组件应显示当天课程；
点击后应能拉起 App。

## 5. 已知限制

- 小组件主要在 App 启动、课程导入或编辑后刷新，尚未接入后台定时任务。
- 小组件最多展示原生模板允许的前若干门课程；如需滚动列表，可改为
  `RemoteViewsService`。
- ICS 时间按学校本地时间处理，忽略 `TZID`/UTC 偏移。
