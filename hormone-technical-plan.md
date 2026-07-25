# hormone 跨平台课程表应用 · 技术方案（草案·待确认）

> **定位**：纯净、简洁的大学生课程表 APP，无广告、无冗余，聚焦课程表核心体验。
> **设计参考**：WakeUp 课表 —— 卡片式布局、清爽配色、直观时间轴、极简美学。
> **状态**：本文件为技术方案草案，待你确认技术选型与范围后进入开发。

---

## 1. 技术选型

### 1.1 跨平台框架推荐：**Flutter**

| 维度 | 为何 Flutter 更适合本项目 |
|---|---|
| 视觉一致性 | 自绘引擎（Skia/Impeller），WakeUp 式极简卡片、时间轴在 iOS/Android 像素级一致，不依赖系统控件 |
| 动画/手势 | 一等公民动画体系（implicit/explicit animation、Hero、CustomPainter），满足"流畅过渡 + 手势操作" |
| 主题 | `ThemeData` + Material 3 动态取色，浅色/深色切换成本低 |
| 性能 | AOT 编译为原生机器码，冷启动与内存可控（目标 <3s / <100MB） |
| 维护 | 单 Dart 代码库，跨端 bug 修复一次完成 |

### 1.2 备选方案：**React Native**
- 优势：JS/TS 生态、原生组件更贴近平台、Expo 工具链成熟、小组件有 `expo-widgets` 等方案。
- 劣势：跨端视觉一致需更多打磨（样式隔离、阴影/模糊差异），极简定制 UI 成本高于 Flutter。
- 若团队更熟悉 React 生态可选，但本方案默认以 Flutter 展开。

### 1.3 核心依赖（Flutter 生态）
| 能力 | 选型 | 说明 |
|---|---|---|
| 状态管理 | **Riverpod** | 编译安全、可测试，适合课程/学期/设置多状态 |
| 路由 | **go_router** | 声明式路由，支持小组件/快捷方式深链 |
| 本地存储 | **drift（SQLite）** | 类型安全的关系型数据库，课程/学期关联查询友好 |
| 桌面小组件 | **home_widget** | 桥接 iOS WidgetKit + Android App Widget，数据由 Flutter 推送 |
| 动画 | **flutter_animate** + 原生 | 轻量声明式动画 |
| 日历导入 | **icalendar_parser** | 解析 `.ics` 课程日历 |
| 崩溃/分析 | **Sentry**（或 Firebase Crashlytics） | 崩溃率监控，目标 >99.5% 无崩溃 |
| 响应式/布局 | 原生 `LayoutBuilder`/`MediaQuery` | 适配手机/平板 |

### 1.4 目标平台
- **iOS**：最低 **14.0+**（WidgetKit 要求；建议 15+）
- **Android**：`minSdk 21`，`targetSdk 34`

---

## 2. 架构设计

采用 **Clean Architecture + Feature-first** 分层，依赖单向（表现层 → 状态层 → 数据层），平台能力通过接口隔离。

```
┌─────────────────────────────────────────────┐
│  Presentation (UI)                            │
│  features/schedule · course · semester ·     │
│  import · settings  + shared widgets         │
├─────────────────────────────────────────────┤
│  State / Domain (Riverpod providers)         │
│  usecases: 当前周计算 / 课程查询 / 主题状态    │
├─────────────────────────────────────────────┤
│  Data Layer                                  │
│  repositories → drift DB (SQLite)            │
│  models: Course / Semester / Settings        │
├─────────────────────────────────────────────┤
│  Platform / Integration                      │
│  home_widget bridge · 原生 Widget UI ·       │
│  jwxt parser (pluggable) · notifications     │
└─────────────────────────────────────────────┘
```

---

## 3. 数据模型与周次逻辑

```dart
Semester { id, name, startDate, totalWeeks, currentWeekOverride? }
Course {
  id, semesterId, name, teacher, location,
  dayOfWeek,            // 1..7
  startSection, endSection,    // 节次
  startTime, endTime,          // 具体时间(用于时间轴)
  weeks: List<int>,            // 上课周次，如 [1,2,3,5..18]
  color, notes
}
```

**当前周计算**：`week = ((today - semester.startDate).inDays / 7).floor() + 1`；支持手动覆盖（调课/假期）。核心体验依赖于"周次 × 星期 × 节次/时间"的三维定位。

---

## 4. 模块划分

| 模块 | 职责 |
|---|---|
| `core/` | 模型、主题（配色/字体/间距）、常量、周次工具 |
| `data/` | drift 数据库 schema、repositories、种子数据 |
| `features/schedule` | 周视图主页：时间轴网格、课程卡片定位、周选择器、手势切换 |
| `features/course` | 课程增删改查、表单校验、颜色分配 |
| `features/semester` | 学期管理、当前周设置 |
| `features/import` | ICS / JSON 模板导入；jwxt 解析器接口（Phase 2） |
| `features/settings` | 浅色/深色主题切换、关于 |
| `platform/widgets` | home_widget 桥接 + 原生 WidgetKit(SwiftUI)/App Widget(Kotlin) UI |
| `app/` | main、Provider 装配、go_router 路由 |

---

## 5. 关键功能实现要点

- **周视图**：左侧时间轴（节次/时间）+ 右侧 7 列网格；课程卡片按 `startSection/endSection` 或 `startTime/endTime` 计算 `top/height` 定位，重叠课程按列平分宽度。
- **周次切换**：左右滑动手势切周 + 顶部周选择器（"第 N 周 / 全部"）；切周带平滑过渡动画。
- **课程 CRUD**：表单含课程名/教师/教室/星期/节次/周次多选/颜色/备注；周次选择用直观的"周次格子"多选。
- **学期管理**：增删学期、设当前学期、设开学日期与总周数，自动推算当前周。
- **导入**：
  - MVP：手动录入 + **ICS 日历导入** + JSON 模板导入（纯客户端、无后端）。
  - Phase 2：教务系统（jwxt）导入 —— 见第 8 节风险说明。
- **桌面小组件**：`home_widget` 推送"当日课程"数据；iOS 用 SwiftUI WidgetKit、Android 用 Kotlin App Widget 渲染；点击跳转 App 对应日期。
- **主题**：浅色/深色 `ThemeData` + Material 3 动态取色；配色参考 WakeUp（柔白底 + 低饱和强调色）。

---

## 6. 开发计划（单人估算，可按实际排期伸缩）

| 阶段 | 内容 | 周期 |
|---|---|---|
| P0 环境搭建 | Flutter 工程、CI、目录结构、设计系统（配色/字体/间距）、Riverpod/go_router/drift 装配 | 约 1 周 |
| P1 数据核心 | 模型 + drift schema、repositories、当前周算法、种子数据 | 约 1–2 周 |
| P2 周视图 | 时间轴网格、课程卡片定位、周选择器、手势、动画、空状态、深浅主题 | 约 2 周 |
| P3 课程 CRUD | 增删改查、表单校验、颜色分配、周次多选 UI | 约 1–2 周 |
| P4 学期管理 | 学期列表、当前学期、当前周自动+手动覆盖、总周数 | 约 1 周 |
| P5 导入（MVP） | ICS 解析导入、JSON 模板导入、手动录入打磨；jwxt 架构预留 | 约 1–2 周 |
| P6 小组件 | iOS WidgetKit + Android App Widget + home_widget 桥接，展示当日课程 | 约 2 周 |
| P7 打磨与 QA | 动画/手势/响应式（平板）、无障碍、性能（启动/内存）、崩溃上报、真机测试 | 约 1–2 周 |
| P8 发布 | App Store / Google Play 元数据、截图、分阶段发布、CI/CD | 约 1 周 |

**合计约 10–14 周**（单人）。可并行压缩（如 P3/P4 与 P2 部分重叠）。

---

## 7. 质量与性能目标

- 冷启动 < 3s；核心功能内存 < 100MB；活跃使用耗电 < 5%/h。
- 无崩溃率 > 99.5%；应用商店评分目标 > 4.5。
- 离线优先：全部数据本地（drift），无网络亦可完整使用；仅导入时需网络。

---

## 8. 风险与待确认决策

1. **教务系统（jwxt）导入是最大不确定项**：各高校系统（正方/树维/URP/强智等）差异大、多有反爬/验证码，纯客户端抓取脆弱且 iOS 审核风险高。**稳健做法**是 MVP 先交付"手动 + ICS 日历 + JSON 模板"导入，jwxt 作为 Phase 2 的可插拔解析器（常见做法需轻量后端代理登录与解析）。需在确认时明确范围。
2. **桌面小组件需原生代码**：iOS（SwiftUI/WidgetKit）、Android（Kotlin App Widget）无法纯 Flutter 实现，届时会涉及原生工程改动。
3. **设计稿**：若已有 WakeUp 式具体设计稿/规范，开发前请提供，可进一步收敛 UI 细节。

---
*本方案为草案，确认技术选型与范围后进入开发。*
