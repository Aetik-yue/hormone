# Hormone 课表

[![CI](https://github.com/Aetik-yue/hormone/actions/workflows/ci.yml/badge.svg)](https://github.com/Aetik-yue/hormone/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Aetik-yue/hormone)](https://github.com/Aetik-yue/hormone/releases)
[![Android](https://img.shields.io/badge/Android-7.0%2B-3DDC84?logo=android&logoColor=white)](https://github.com/Aetik-yue/hormone/releases/latest)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](#开源许可)

一款简洁、轻量的 Android 大学课程表应用。把教务系统里的课表带到手机上，查看每周安排、设置课前提醒，也能手动添加课程、管理多个学期。

基于 Flutter 构建，使用 Material 3 界面，支持浅色与深色主题。课程与学期保存在本地，导入后可以离线查看。目前仅支持 **Android 7.0（API 24）及以上**。

**[下载最新版](https://github.com/Aetik-yue/hormone/releases/latest)** · **[查看更新日志](version)** · **[反馈问题](https://github.com/Aetik-yue/hormone/issues)**

## 界面预览

| 每周课表 | 课程编辑 | 学期管理 | 设置 | 教务导入 |
| :---: | :---: | :---: | :---: | :---: |
| ![每周课表](docs/screenshots/week.jpg) | ![课程编辑](docs/screenshots/edit.jpg) | ![学期管理](docs/screenshots/semester.jpg) | ![设置](docs/screenshots/settings.jpg) | ![教务导入](docs/screenshots/import.jpg) |

## 能做什么

- **查看课程安排**：七天周视图、今日课程时间线、周次切换与快速跳转；可按课程名、教师或教室搜索。
- **编辑自己的课表**：添加、编辑、复制和删除课程，设置星期、节次、周次、教师、教室、颜色及备注；支持单周、双周等周次选择。
- **管理多个学期**：设置开学日期和学期周数，自动计算当前周，也可手动调整以应对调课或假期。
- **导入教务课表**：在内置浏览器中登录学校教务系统，抓取课程后预览、勾选并导入；也支持 ICS 和 JSON 文件。
- **按习惯设置提醒与外观**：课前 5 / 10 / 15 / 30 分钟提醒，自定义节次时间，切换浅色、深色或跟随系统主题。
- **备份与恢复数据**：将全部学期和课程导出为 JSON，通过系统分享面板保存；支持从备份完整恢复。
- **在桌面查看今日课程**：提供 Android 桌面小组件，课表变化后同步刷新。
- **在应用内检查更新**：自动或手动检查 GitHub 正式版本，查看更新说明，下载并校验 APK 后进入系统安装页面。

## 下载与开始使用

到 [GitHub Releases](https://github.com/Aetik-yue/hormone/releases/latest) 下载以 `.apk` 结尾的安装包。`.aab` 用于应用分发，不能直接在手机上安装；`.apk.sha256` 是安装包校验文件。

1. 安装并打开应用，在学期管理中确认开学日期和总周数。
2. 手动添加课程，或进入导入页面，从教务系统、ICS 文件或 JSON 文件导入。
3. 核对课程的星期、节次和上课周次，并在设置中调整节次时间。
4. 按需开启课前提醒，或在 Android 桌面添加“今日课程”小组件。

日后可在“设置 → 检查更新”中升级。应用也会每天自动检查正式版本；下载完成后，需要在系统安装页面确认安装。

## 课程导入

### 从教务系统抓取

内置目录目前包含 **43 所学校**，支持按校名、拼音、教务系统名称或网址搜索。适配分为三个级别：

| 级别 | 说明 |
| --- | --- |
| 专用适配 | 重庆大学、江西财经大学、沈阳化工大学、南昌大学、井冈山大学具有专门的课程提取规则。 |
| 系统兼容 | 根据学校使用的教务产品复用解析规则，仍需对应学校账号验证实际页面。 |
| 通用抓取 | 使用通用页面解析规则；学校未列出时，可以填写自定义教务系统 URL。 |

学校出现在目录中，不代表所有版本的教务页面都已验证。具体入口和适配级别以应用内显示及 [学校适配器目录](lib/features/import/data/school_adapter.dart) 为准。

抓取流程：**选择学校 → 完成登录 → 打开个人课表 → 点击“抓取课表” → 核对并导入**。

- 验证码、短信验证和统一身份认证需要在学校页面手动完成；学校要求校园网或 VPN 时，需先连接相应网络。
- 登录、浏览和课程预览保持竖屏，执行抓取时会短暂切换横屏，以便页面显示更完整的课表。
- 抓取前等待课表加载完成，并展开折叠的课程。应用内的“课程抓取使用说明”提供了操作步骤与常见问题排查。
- 导入前可以取消勾选不需要的课程，并查看时间冲突提示。

### 从文件导入

支持 `.ics` 日历文件和 `.json` 课程文件。两种导入模式都作用于**当前学期**，执行前会再次确认：

| 模式 | 对现有课程的影响 |
| --- | --- |
| 替换 | 用选中的课程替换当前学期原有课表。 |
| 合并 | 保留现有课程，追加选中的课程，并提示与现有课表的时间冲突。 |

<details>
<summary>展开查看 JSON 课程模板</summary>

保存以下内容为 UTF-8 编码的 `.json` 文件，即可从文件导入：

```json
{
  "courses": [
    {
      "name": "高等数学",
      "teacher": "张老师",
      "location": "教学楼 A301",
      "dayOfWeek": 1,
      "startSection": 1,
      "endSection": 2,
      "weeks": [1, 2, 3, 4, 5, 6, 7, 8],
      "color": "#5B8DEF",
      "notes": "记得带教材"
    }
  ]
}
```

- `dayOfWeek`：1 表示周一，7 表示周日。
- `startSection` / `endSection`：起止节次，范围为 1–16，结束节次不能早于开始节次。
- `weeks`：实际上课周次，从 1 开始，应在当前学期总周数内。
- `teacher`、`location`、`color`、`notes` 可省略；未指定颜色时使用默认蓝色。
- 顶层也可以直接使用课程数组。字段无效的课程会被跳过，并在导入时提示。

该模板用于向当前学期导入课程。应用导出的完整备份包含多个学期，应通过“设置 → 从备份恢复”读取；恢复会替换当前全部学期与课程。

</details>

## 使用说明与限制

- **课程只在实际上课周显示**：例如第 6、8 周的实验课，需要切换到相应周次查看。导入后找不到课程时，先检查当前学期、周次和节次。
- **ICS 按学校本地时间解析**：目前忽略 `TZID` 和 UTC 偏移，跨时区日历需核对课程时间。
- **小组件刷新依赖应用运行**：课表变更、回到前台和应用运行时跨午夜会触发刷新；应用未在后台运行时，不会通过独立后台任务自动刷新。
- **课前提醒需要通知权限**：提醒时间使用设置中的节次时间，导入后请先确认学校作息。

## 本地开发

### 环境准备

- Flutter SDK stable；Dart 版本需满足 `pubspec.yaml` 中的 `>=3.7.0 <4.0.0`。
- Android SDK，以及与所用 Flutter / Gradle 兼容的 JDK。
- Node.js：部分学校适配器测试会调用 Node 执行 JavaScript 提取脚本。
- Android 真机或模拟器。

CI 使用 Flutter stable，依赖约束以 [pubspec.yaml](pubspec.yaml) 为准。项目不维护 iOS 构建目标。

### 首次运行

```bash
git clone https://github.com/Aetik-yue/hormone.git
cd hormone
git switch develop

flutter create . --platforms=android --org com.aetikyue
flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

**运行前还需要恢复 Android 原生模板。** `android/` 不纳入版本控制，生成的默认工程需要接入项目的 Gradle、Manifest、小组件和应用更新配置。按 [Android 原生整合指南](WIDGET_SETUP.md) 复制模板后，再执行：

```bash
flutter run
```

调试运行不需要正式签名。Release 构建必须先配置固定签名，步骤见 [Android 发布指南](docs/RELEASE.md)。

### 常用命令

```bash
# 修改数据库表或 @DriftDatabase 配置后重新生成代码
dart run build_runner build --delete-conflicting-outputs

# 严格静态分析，与 CI 门槛一致
flutter analyze --fatal-infos --fatal-warnings

# 完整测试
flutter test

# 单独运行一个测试文件
flutter test test/week_calculator_test.dart

# 修改图标或启动页资源后重新生成
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

不要手动编辑 drift 生成的 `lib/data/app_database.g.dart`。当前路由直接声明在 `lib/app/router.dart` 中，修改路由不需要代码生成。

### 技术与目录

| 层面 | 实现 |
| --- | --- |
| 界面 | Flutter、Material 3 |
| 状态管理 | Riverpod |
| 本地数据 | drift / SQLite，数据库在后台 isolate 打开 |
| 路由 | go_router |
| 教务导入 | webview_flutter、学校适配器与 JavaScript 提取脚本 |
| 系统集成 | flutter_local_notifications、home_widget、share_plus |
| 应用更新 | GitHub Releases、ota_update |

```text
lib/
├── app/                 # 路由
├── core/                # 领域模型、常量、主题与纯函数工具
├── data/                # drift 数据库、表、Repository、Provider
│   └── mappers.dart     # 数据库实体与领域模型之间的转换
└── features/
    ├── course/          # 课程编辑
    ├── import/          # 教务抓取、文件解析与导入预览
    ├── notification/    # 提醒设置与调度
    ├── schedule/        # 周课表、今日课程与搜索
    ├── semester/        # 学期管理
    ├── settings/        # 外观、节次时间、备份与恢复
    ├── update/          # 版本检查与应用内更新
    └── widget/          # 桌面小组件数据桥接
native_templates/        # Android 原生配置与小组件模板
test/                    # 领域逻辑、数据层与界面测试
scripts/                 # 本地签名构建脚本
docs/                    # 设计文档、截图与发布指南
version/                 # 各版本更新日志
```

功能模块按 `application/`、`presentation/` 分层，按需包含 `data/` 和 `domain/`。Repository 对外提供领域模型，drift 实体通过 `mappers.dart` 转换。更多设计说明见 [系统设计文档](docs/system_design.md)。

### 适配新学校

1. 在 `lib/features/import/data/` 中实现 `SchoolAdapter`，提供学校名称、登录地址、课表地址、页面识别逻辑和 `extractJs`。
2. 在 `school_adapter.dart` 中注册适配器，并补充拼音搜索键和适配级别；可复用教务产品规则的学校可使用 `ConfiguredSchoolAdapter`。
3. 提取结果返回符合 `ExtractedCourse.fromJson` 的 JSON 字符串：包含 `name`、`dayOfWeek`、`startSection`、`endSection`、`weeks`，以及可选的 `teacher`、`location`。
4. 为解析规则补充回归测试，覆盖周次、连续节次、重复课程和空页面；可参考 `test/cqu_adapter_test.dart`、`test/jgsu_adapter_test.dart`。

星期使用 1–7，周次从 1 开始。提取脚本应规范化节次，保证开始节次不大于结束节次。学校目录、通用规则和专用适配器都位于同一数据目录，便于对照实现。

## 构建与发布

完成原生模板接入和 [正式签名配置](docs/RELEASE.md) 后，可以构建：

```bash
flutter build apk --release
flutter build appbundle --release
```

| 产物 | 默认输出位置 |
| --- | --- |
| APK | `build/app/outputs/flutter-apk/app-release.apk` |
| AAB | `build/app/outputs/bundle/release/app-release.aab` |

项目使用 `develop` 进行日常开发，`main` 保留稳定发布代码。提交前运行代码生成、严格分析和完整测试；提交信息采用 `type(scope): description`，例如 `fix(import): handle missing course numbers`。

[CI](.github/workflows/ci.yml) 会在推送或提交 PR 到 `main`、`develop`、`master` 时执行依赖安装、代码生成、分析和测试。推送 `v*` 标签会触发 [Release Build](.github/workflows/release.yml)，重建 Android 工程、注入原生模板与签名，生成 APK、AAB 和 SHA-256 校验文件，再发布 GitHub Release。

签名配置、Windows 本地构建脚本、版本同步和发布失败重试步骤统一维护在 [Android 发布指南](docs/RELEASE.md)。

## 反馈与参与

欢迎通过 [Issues](https://github.com/Aetik-yue/hormone/issues) 反馈问题、提出功能建议或提供学校适配信息。

报告问题时，请尽量附上应用版本、Android 版本、复现步骤和截图。教务导入问题还可以提供学校名称、教务系统类型，以及脱敏后的课表页面结构；请勿提交账号密码、验证码、Cookie 或包含个人信息的页面。

## 开源许可

本项目采用 MIT License。

课表配色参考 [WakeUp 课表](https://wakeup.cool/)，感谢提供反馈、参与测试和贡献代码的朋友。
