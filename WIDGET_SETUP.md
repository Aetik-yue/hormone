# 桌面小组件（iOS WidgetKit / Android App Widget）整合指南

本目录的 Flutter 侧代码（`lib/features/widget/`）已经可以：
- 在 App 启动、课程导入后，把「今日课程」写入原生小组件的数据通道；
- 通过 `home_widget` 触发原生小组件刷新。

但**原生侧的小组件目标尚未创建**——因为当前工作区还没有 `ios/` 与 `android/` 原生工程目录（需先 `flutter create .` 生成）。下面的步骤把 `native_templates/` 里的原生模板接入你的工程。

---

## 0. 前置：生成原生工程

在仓库根目录执行（仅需一次）：

```bash
flutter create .
```

这会在 `ios/` 与 `android/` 下生成原生工程。之后再把下方文件复制进去。

---

## 1. 依赖确认

`pubspec.yaml` 已包含：

```yaml
dependencies:
  home_widget: ^0.6.0
```

如尚未安装，执行 `flutter pub get`。

---

## 2. iOS（WidgetKit）

### 2.1 添加 Widget Extension 目标
1. 用 **Xcode** 打开 `ios/Runner.xcworkspace`。
2. `File ▸ New ▸ Target ▸ Widget Extension`，名称填 **CourseWidget**，勾选 **Include Configuration Intent** 可不选（我们用 StaticConfiguration）。
3. Xcode 会生成 `CourseWidget/CourseWidget.swift` 等文件——**用本仓库的
   `native_templates/ios/Runner/Widgets/CourseWidget.swift` 覆盖它**（或把内容粘贴进去）。

### 2.2 配置 App Group
1. 在 Xcode 中选中主 App 目标 `Runner` → `Signing & Capabilities` → 添加 **App Groups**，名称 `group.hormone`（需与 `widget_service.dart` 中 `_appGroupId` 一致）。
2. 同样为 **CourseWidget** 扩展目标添加同一个 App Group `group.hormone`。
3. 两个目标的 Bundle Identifier 需属于同一开发者团队（App Group 要求）。

> 小组件读取 `UserDefaults(suiteName: "group.hormone")` 中的 `widget_title` 与 `courses`，键名与 Dart 侧 `saveKeyValuePair` 完全一致。

### 2.3  bridging（点击拉起 App）
`home_widget` 已处理小组件点击回传；默认仅拉起 App。若需深链（如跳到指定周），可在 `widget_service.dart` 的 `_onWidgetClicked` 中扩展。

---

## 3. Android（App Widget）

### 3.1 复制原生文件

| 模板文件 | 目标位置 |
|---|---|
| `native_templates/android/app/src/main/java/com/example/hormone/CourseWidgetProvider.kt` | `android/app/src/main/java/<你的包名>/CourseWidgetProvider.kt` |
| `native_templates/android/app/src/main/res/xml/course_widget_info.xml` | `android/app/src/main/res/xml/course_widget_info.xml` |
| `native_templates/android/app/src/main/res/layout/course_widget.xml` | `android/app/src/main/res/layout/course_widget.xml` |

> 复制 `CourseWidgetProvider.kt` 后，把文件顶部的
> `package com.example.hormone` 改为你的真实 `applicationId`
> （见 `android/app/build.gradle` 的 `defaultConfig.applicationId`）。

### 3.2 注册 Receiver
把 `native_templates/android/app/src/main/AndroidManifest.receiver.xml` 里的
`<receiver>...</receiver>` 整段合并进
`android/app/src/main/AndroidManifest.xml` 的 `<application>` 标签内。

> Android 上 `home_widget` 把数据写入名为 `HomeWidgetSharedPreferences` 的
> SharedPreferences；`CourseWidgetProvider` 直接读取其中的 `widget_title`
> 与 `courses`，无需额外依赖。

---

## 4. 验证

1. `flutter pub get`
2. `dart run build_runner build --delete-conflicting-outputs`（drift 代码生成）
3. `flutter analyze`
4. 运行 App → 进入「课程表」主页（会自动刷新今日课程到小组件）→ 回到桌面添加
   「今日课程」小组件，应看到今天的课程。

---

## 5. 已知限制（MVP）

- 小组件刷新时机：App 启动、课程导入完成后。编辑/删除课程后需重新打开 App
  一次才会刷新（后续可接入 `WorkManager`/`Timeline` 定时刷新）。
- ICS 时间按学校本地时间处理，忽略 `TZID`/UTC 偏移（对本地课表足够）。
- Android 小组件最多展示前若干门课程（原生模板未用 RemoteViews 集合视图，
  如需滚动列表可后续升级为 `RemoteViewsService`）。
