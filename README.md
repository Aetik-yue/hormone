# Hormone 课表

[![CI](https://github.com/Aetik-yue/hormone/actions/workflows/ci.yml/badge.svg)](https://github.com/Aetik-yue/hormone/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Aetik-yue/hormone)](https://github.com/Aetik-yue/hormone/releases)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.5+-02569B.svg)](https://flutter.dev)

一款简洁、轻量的大学课程表 App，支持 iOS 和 Android。

## 截图

| 周视图 | 课程编辑 | 学期管理 | 设置 | 教务导入 |
|--------|----------|----------|------|----------|
| ![week](docs/screenshots/week.jpg) | ![edit](docs/screenshots/edit.jpg) | ![semester](docs/screenshots/semester.jpg) | ![settings](docs/screenshots/settings.jpg) | ![import](docs/screenshots/import.jpg) |

## 功能

### 课表视图
- **周视图网格**：7 天 × 12 节次，彩色课程卡片按节次定位
- **周次导航**：左右滑动 / 点击箭头切换周次，支持快速跳转到任意周
- **当前周定位**：根据开学日期自动计算当前周，支持手动覆盖（调课/假期）
- **今日高亮**：今天列背景微高亮，星期表头加粗

### 课程管理
- **添加/编辑/删除**：支持课程名、教师、教室、星期、节次、周次、颜色、备注
- **周次选择**：全选/清空、单周/双周、反选，支持最多 40 周
- **课程复制**：一键复制课程，快速创建相似课程
- **未保存提醒**：编辑后退出时提示放弃修改

### 学期管理
- **多学期切换**：底部选择器快速切换，激活学期置顶
- **当前周覆盖**：支持手动调整当前周（应对调课/假期）
- **级联删除**：删除学期时自动清理关联课程

### 数据导入
- **教务系统 WebView 导入**：内置浏览器登录教务系统，自动抓取课表
  - 重庆大学（金智教务 XCampus）
  - 江西财经大学（青果教务 KINGOSOFT）
  - 沈阳化工大学（正方教务 ZFSoft）
  - 南昌大学（强智教务 QZSoft）
- **文件导入**：支持 ICS 日历文件和 JSON 模板批量导入
- **冲突检测**：导入时检测时间冲突
- **智能解析**：自动识别课程编号、周次、节次、教室等信息

### 个性化
- **节次时间自定义**：逐节修改开始时间和时长，支持预设模板（45分钟/90分钟/50分钟制）
- **主题切换**：浅色 / 深色 / 跟随系统，重启后保留
- **课程卡片颜色**：10 色预设配色

### 数据管理
- **导出备份**：一键导出全部学期和课程为 JSON 文件
- **桌面小组件**：显示今日课程（iOS WidgetKit / Android App Widget）

## 技术栈

| 类别 | 技术 |
|------|------|
| 框架 | Flutter 3.5+ / Dart |
| 状态管理 | flutter_riverpod（Provider / StateNotifier / StreamProvider） |
| 数据库 | drift（SQLite），后台 isolate 打开 |
| 路由 | go_router |
| WebView | webview_flutter（教务系统登录抓取） |
| 桌面小组件 | home_widget |
| 动画 | flutter_animate |
| CI/CD | GitHub Actions |

## 项目结构

```
lib/
├── app/              # GoRouter 路由定义
├── core/             # 常量、领域模型、主题、工具函数
│   ├── constants/    # 应用级常量（节次时间表等）
│   ├── models/       # 领域模型（Course、Semester）
│   ├── theme/        # Material 3 主题配色
│   └── utils/        # 纯函数工具（周次计算等）
├── data/             # 数据层
│   ├── repositories/ # 数据访问（CourseRepository、SemesterRepository）
│   ├── mappers/      # drift 实体 ↔ 领域模型映射
│   ├── tables/       # Drift 表定义
│   └── providers/    # Riverpod Provider
└── features/         # 功能模块（feature-first）
    ├── course/       # 课程增删改
    ├── import/       # 文件导入 + 教务系统 WebView 导入
    ├── schedule/     # 周视图主界面
    ├── semester/     # 学期管理
    ├── settings/     # 设置（主题/节次时间/导入导出）
    └── widget/       # 桌面小组件数据桥接
```

## 开发环境

### 前置要求

- Flutter SDK >= 3.3.0
- Dart SDK >= 3.3.0
- Android Studio / Xcode（用于平台开发）

### 快速开始

```bash
# 克隆项目
git clone https://github.com/Aetik-yue/hormone.git
cd hormone

# 安装依赖
flutter pub get

# 生成平台目录（android/、ios/ 等已排除出版本控制）
flutter create . --platforms=android,ios

# 运行
flutter run
```

### 代码生成

项目使用 drift 和 go_router，修改数据库表或路由后需要重新生成代码：

```bash
dart run build_runner build --delete-conflicting-outputs
```

### 启动图标

```bash
dart run flutter_launcher_icons
```

### 运行测试

```bash
flutter test
```

### 代码分析

```bash
flutter analyze --fatal-infos --fatal-warnings
```

## 构建发布

### Android APK

```bash
flutter build apk --release
```

APK 输出至 `build/app/outputs/flutter-apk/app-release.apk`。

### Android App Bundle

```bash
flutter build appbundle --release
```

### iOS

```bash
flutter build ios --release --no-codesign
```

## 适配新学校

在 `lib/features/import/data/` 下新建适配器：

```dart
class MySchoolAdapter extends SchoolAdapter {
  @override String get schoolName => '学校名';
  @override String get loginUrl => '教务系统登录页 URL';
  @override String get scheduleUrl => '课表页 URL';
  @override bool isSchedulePage(String url) => ...;
  @override String get extractJs => '提取课程的 JavaScript';
}
```

然后在 `school_adapter.dart` 的 `schoolAdapters` 列表中注册即可。

### 适配器开发要点

- `extractJs` 返回的 JSON 格式需符合 `ExtractedCourse.fromJson` 的要求
- 课程卡片文本格式：`[课程编号]\n[周次周] [节次节] 教室\n本科 - 课程名`
- 支持 `findDay` 函数通过 data 属性或位置匹配确定星期

## 贡献指南

欢迎提交 Issue 和 Pull Request！

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/xxx`)
3. 提交更改 (`git commit -m 'feat: xxx'`)
4. 推送分支 (`git push origin feature/xxx`)
5. 提交 Pull Request

### 代码规范

- 遵循 [Effective Dart](https://dart.dev/guides/language/effective-dart) 风格
- 提交前运行 `flutter analyze --fatal-infos --fatal-warnings` 确保无错误
- 提交前运行 `flutter test` 确保测试通过
- 新功能需包含单元测试

## License

[MIT](LICENSE)

## 致谢

- 课表配色参考 [WakeUp 课表](https://wakeup.cool/)
- 感谢所有贡献者和测试用户
