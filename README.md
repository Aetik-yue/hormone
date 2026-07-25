# Hormone 课表

一款简洁、轻量的大学课程表 App，支持 iOS 和 Android。

## 功能

- **周视图课表**：7 天 × 12 节次网格，左右滑动切换周数，彩色课程卡片
- **课程管理**：添加、编辑、删除课程，支持教师/教室/周次/颜色等属性
- **学期管理**：多学期切换，自动推算当前周
- **教务系统导入**：WebView 内登录学校教务系统，一键抓取课表
  - 重庆大学（金智教务）
  - 江西财经大学（青果教务）
- **文件导入**：支持 ICS 日历文件和 JSON 模板批量导入
- **节次时间自定义**：逐节修改开始时间，适配不同学校作息
- **数据导出**：一键导出全部学期和课程为 JSON 备份文件
- **桌面小组件**：显示今日课程（iOS WidgetKit / Android App Widget）
- **主题切换**：浅色 / 深色 / 跟随系统，重启后保留
- **ICS 时区处理**：导入时自动处理时区转换

## 技术栈

- **Flutter 3.5+** / Dart
- **状态管理**：flutter_riverpod（Provider / StateNotifier / StreamProvider）
- **数据库**：drift（SQLite），后台 isolate 打开
- **路由**：go_router
- **WebView**：webview_flutter（教务系统登录抓取）
- **桌面小组件**：home_widget
- **动画**：flutter_animate

## 项目结构

```
lib/
├── app/              # GoRouter 路由定义
├── core/             # 常量、领域模型、主题、工具函数
├── data/             # Drift 数据库、Repository、Mapper
└── features/         # 功能模块（feature-first）
    ├── course/       # 课程增删改
    ├── import/       # 文件导入 + 教务系统 WebView 导入
    ├── schedule/     # 周视图主界面
    ├── semester/     # 学期管理
    ├── settings/     # 设置（主题/节次时间/导入导出）
    └── widget/       # 桌面小组件数据桥接
```

## 开发环境

```bash
flutter pub get
flutter run
```

Android 平台目录（`android/`、`ios/` 等）已排除出版本控制，首次克隆后运行：

```bash
flutter create . --platforms=android,ios
```

然后将 `native_templates/` 中的小组件模板文件复制到对应平台目录（详见 `WIDGET_SETUP.md`）。

## 构建 APK

```bash
flutter build apk --release
```

APK 输出至 `build/app/outputs/flutter-apk/app-release.apk`。

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

## License

MIT
