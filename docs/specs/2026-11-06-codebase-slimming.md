# Spec：精简代码库，删除死代码并把重复收进已有 module

> 状态：待实施。基线为 `develop @ 4cceddf`，下文行号都以此为准；批次 1 落地后行号会移动，请按符号名定位。
>
> 所有行数都是估算。这份规格没有经过构建、测试或真机验证。

## Problem Statement

`lib/` 约 14.2k 行（不含生成代码），其中 `features/import` 占 42%。代码没有整体臃肿，但有四类可以消除的负担：

- 没有读取方的 interface 和方法，以及只有测试还在用的 shim。
- 学校脚本之间大块相似的 JS，修一个问题要改多处。
- 文件导入和 WebView 导入各有一份预览逻辑。
- 最难测的 WebView 重试协议困在 widget State 里。

## Solution

分 6 批实施，每批一个提交，可以独立验收和回退。除“决定”一节明确列出的变化外，用户可见行为一律不变。预计净减 700–850 行（不含批次 6 新增的约 100 行测试）。

| 批次 | 内容 | 估算净减 | 风险 |
|---|---|---|---|
| 1 | 死代码和小块重复 | 约 200 | 很低 |
| 2 | 周次钳制收进 `week_calculator`，修结束日期 | 10–15 | 低 |
| 3 | 两个导入入口共用预览逻辑 | 90–120 | 低 |
| 4 | 学校脚本共享提取 runtime | 200–265 | 中 |
| 5 | 学校目录合成一张数据表 | 170–200 | 很低 |
| 6 | WebView 提取协议移出 widget State | 30–50 | 中，需要真机 |

批次 1 必须最先做，之后 2、3、5 可以任意排序。批次 4 在批次 3 之后做，因为两批都动 `school_adapter.dart`。批次 6 放最后；如果当前没有真机，就停在批次 5 并告诉用户。

## 开工前

1. 确认 Node 可用，学校脚本测试通过 `Process.run('node', ...)` 运行。
2. 跑一遍基线，记录结果。如果基线本身就不通过，先报告用户，不要开始改：

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze --fatal-infos --fatal-warnings
flutter test
```

3. 阅读 `AGENTS.md` 和 `GLOSSARY.md`。不要重新讨论 `docs/adr/` 里的决定。

## 批次 1：死代码和小块重复

**删除（已用 grep 确认 `lib/` 内没有读取方）：**

- `SchoolAdapter.scheduleUrl`、各 adapter 的 override，以及 `ConfiguredSchoolAdapter` 的 `scheduleUrl` 参数和 `_scheduleUrl` 字段。同时删掉 `test/{cqu,jgsu,jufe,ncu}_adapter_test.dart` 里的断言。
- `SchoolAdapter.isBuiltin`（`school_adapter.dart:78`）。
- `ConfiguredSchoolAdapter.scheduleMarkers`。它从未被传入，所以 `isSchedulePage` 直接返回 `false`。这个行为必须保持，见“决定”。
- `SemesterRepository.watchSemesters`、`CourseFormNotifier.setWeekRange`、`nextWeek`、`prevWeek`（`schedule_providers.dart:49,51`）。
- `CourseRepository.deleteBySemester`。
- `CoursePlatformRepository.deleteBySemester`，以及 `test/course_platform_repository_test.dart:84` 对应的测试内容。
- `ImportState.totalWeeks`、`AppColors.success`。
- `WidgetService` 的 `_initialized`、`_ensureInit`、`_onWidgetClicked`。它们只把监听接到一个空函数上。
- `ncu_adapter.dart` 和 `syuct_adapter.dart` 脚本里未被读取的 JS 变量 `wins`。

**合并：**

- 三份 `_LoadFailedView`（`course_edit_screen.dart:188`、`week_view.dart:471`、`semester_screen.dart:85`）合成一个共享 widget，参数为 `title`、`message`、`onRetry`。现有文案逐字保留。各处的重试 invalidate 仍由调用方传入。
- 8 份星期标签（`course_edit_screen.dart:17`、`import_course.dart:63`、`import_preview_list.dart:80`、`reminder_scheduler.dart:77`、`course_detail_sheet.dart:15`、`course_search_delegate.dart:116`、`schedule_screen.dart:580`、`week_view.dart:41`）合成一份常量，放在 `core/constants/app_constants.dart`。带“周”的写法由它派生。
- `backup_repository.dart:147-177` 和 `json_importer.dart:188-210` 的 `_toInt`、可选字符串、`_parseColor` 合成一份 helper。**颜色回退值必须由调用方传入：**备份恢复继续用 `0xFF5B8DEF`（`test/backup_repository_test.dart:233` 有断言），JSON 导入继续用 `AppConstants.defaultCourseColor`（`0xFF4399F1`）。
- `course_repository.dart:88-107` 和 `:129-148` 的校验合成一个私有方法，错误类型和消息不变。

**迁移：** `importCoursesFromDecoded`（`webview_course_parser.dart:18`）只有测试在用（18 处）。在测试支持代码里加一个 helper，内部调用 `previewWebviewCourses`，用足够大的 `totalWeeks`，返回课程和 `skippedCount`，然后删掉这个 shim。如果语义对不上，就保留 shim 并在提交说明里写明原因。

**同步文档：**

- `AGENTS.md:55`：去掉 `scheduleUrl`。
- `AGENTS.md:63` 和 `widget_service.dart:255`：刷新现在由 `main.dart` 集中触发，不再是“导入或编辑后调用”。
- `school_adapter.dart:25` 的流程注释。

## 批次 2：周次规则

- 在 `core/utils/week_calculator.dart` 新增一个把周数钳制到 `1..totalWeeks` 的函数，替换 `schedule_providers.dart:32-34`、`semester_screen.dart:341-347` 和 `:358-360` 三处内联写法。
- `semester_screen.dart:142-143` 改用 `lastSemesterDay(semester)`，并补一个非周一开学的测试。例如 2026-09-01（周二）开学、18 周时，结束日期应显示 2027-01-03，而不是现在的 2027-01-04。

## 批次 3：导入预览

- 把 `_conflictNames`（`import_screen.dart:272-293`、`webview_import_screen.dart:445-466`）移到 `domain/import_course.dart`，形如 `conflictNames(List<ImportCourse> courses, List<Course> existing)`，并新增集合级单测。
- `coursesConflict` 和 `conflictsWithCourse` 的相同规则合成一个私有函数，两个公开函数保留。
- 在 `ImportCourse` 上加 `withSelected(bool)`，删掉 `_copyWithSelected`（`import_provider.dart:262-279`）和 `_withSelected`（`webview_import_provider.dart:106-122`）。**`selected` 保持可变**，`test/import_commit_test.dart:891,940` 依赖这一点验证快照隔离。
- 把模式选择按钮和提示（`import_screen.dart:212-249`、`webview_import_screen.dart:352-385`）合成一个共享 widget。
- 让校验直接产出 `ImportCourse`：把 `ExtractedCourse.fromJson` 的校验（`school_adapter.dart:101-145`）移到 `domain/webview_course_parser.dart`，删除 `ExtractedCourse` 和 `toImportCourse`，错误消息逐字保留。同步更新 `AGENTS.md:55`。

**不要做：**

- 不合并两个 Notifier 或状态机。文件导入有 picking，WebView 导入有 login 和预览上下文校验。
- 不统一全选交互和文案（“全不选”“取消全选”“共解析 N 门”“共 N 门课程”）。
- 不动抓取后的确认流程。

## 批次 4：学校脚本共享提取 runtime

新增一段共享 JS（建议 `school_extraction_runtime.dart`，内含现有 `schoolWeekParserJs`），标识符沿用 `school` 前缀，避免和各脚本的局部变量冲突。adapter 只保留配置和本校差异。

**先补保护测试。** 现有 `__nav`/`__pending` 用例只覆盖部分学校，`syuct` 没有专门的测试文件。在搬动之前，先给 `jgsu`、`ncu`、`jufe`、`syuct`、正方（`ConfiguredSchoolAdapter`）补上它们实际具备的路径的 fixture，并确认在旧代码上通过：

- 在 frame 里找到课表。
- 点入口链接返回 `__nav`。
- 容器存在但未渲染时返回 `__pending`。
- 去重。

**第一步，机械 helper（估算净减 140–185）：**

| 重复块 | 位置 |
|---|---|
| 透传的周次、节次解析函数 | `cqu:307`、`jgsu:59-66`、`ncu:44-51`、`jufe:46-48`、`syuct:40-47`、`generic:358-364`、`configured:80-82` |
| `dayMap` | 6 个提取脚本 |
| 同源 frame 收集 | `jgsu:178-187`、`ncu:198-206`、`jufe:214-221`、`syuct:128-136` |
| 点入口并返回 `__nav` | `jgsu:253-271`、`ncu:241-257`、`jufe:234-248`、`syuct:152-169` |
| 容器探测并返回 `__pending` | `ncu:233-238`、`jufe:229-231`、`syuct:145-149` |
| 去重 + `results.push` | `jgsu:68-83`、`ncu:53-72`、`jufe:107-125`、`configured:84-103`、`syuct:109-121`、`generic:117-129,186-198,232-244` |

**这些块只是结构相似，并非逐字相同。** 必须遵守：

- 每所学校的链接文字正则、href 正则和选择器都作为参数保留。例如 NCU 和 JUFE 的正则就不同。
- 每个 adapter 现有的去重 key 公式原样保留，由调用方传入。至少有 5 种写法，无法判断是否有意，**不要统一**。
- frame 收集取防御最全的写法（JUFE 判断 `querySelectorAll`，JGSU 外层有 try）。

**第二步，API 探测（估算净减 60–80，偏乐观）：** `jgsu:90-175`、`ncu:75-141`、`configured:105-136`。三者的 URL、请求体、学期推断差异不小。参数化时必须保持请求顺序和请求体不变。**如果 helper 的调用不比原文明显短，就放弃这一步，并在提交说明里写明。**

**不要动：**

- `CQU` 的解析逻辑（`findDay`、折叠处理）。CQU 只替换透传函数和相同的 helper。
- 表格和单元格解析（`generic:79-132,253-262,304-356`、`jufe:58-105,145-181`、`jgsu:196-247`、`ncu:144-195`、`syuct:50-125`），它们已经分叉，合并属于行为变更。

Node 测试 harness 在多个测试文件里重复。批次 4 需要写新 fixture，可以顺手抽一个共享 helper，但不要改已有断言。

## 批次 5：学校目录

- `school_adapter.dart:151-343` 和 `:367-411` 合成一张表，每所学校一条记录：名称、拼音、登录 URL、系统类型。
- 5 个专用 adapter（CQU、JGSU、JUFE、NCU、SYUCT）各自提供拼音。
- `schoolAlphabeticalKey` 的调用方（`webview_import_screen.dart:251` 和目录测试）保持可用。
- 实施前先把 `schoolAdapters` 的顺序、名称、URL、系统类型导出一份，实施后比对，必须完全一致。

## 批次 6：WebView 提取协议

把 `_tryExtract`（`webview_import_screen.dart:570-735`）的协议移到屏幕之外的 module。依赖注入“执行 JS”、等待和屏幕方向控制；返回明确的结果（预览、未找到及调试信息、跳转失败、异常）。屏幕只把结果映射成 UI，并删掉 `navRetry`（`webview_import_provider.dart:59`）。

必须逐项保留：

- 注入前等待 2 秒。
- `__nav`/`__pending` 最多重试 3 次，`__nav` 后等 3 秒，`__pending` 后等 2 秒。
- 超过上限时显示跳转失败对话框。
- 所有退出路径都离开横屏采集模式、复位 extracting。
- 注入异常且当前已在课表页时静默等待（`:724-728`）。
- 空结果调试对话框，包括其中的 CQU 正则。
- `mounted` 检查。

新增测试：用 fake 执行器覆盖重试上限、两种等待时长、重试计数复位和异常路径。真机验证：横竖屏切换、一次成功导入、一次跳转失败。

## Implementation Decisions

- **保留“自动提取不触发”：** 38 所配置学校的 `isSchedulePage` 现在恒为 false，删除 `scheduleMarkers` 后仍然如此。启用自动提取是另一个功能。
- **有意的用户可见变化只有两处：** 批次 2 的结束日期修正；批次 3 共享模式选择后，WebView 页的模式提示改用文件导入页的样式。
- **颜色：** 不统一 `0xFF5B8DEF` 和 `0xFF4399F1`，两者都有现存用途。
- **改之前先确认：** 重构过程中如果发现测试断言的行为和这份规格矛盾，以测试为准，并报告用户。

## Out of Scope

| 不做 | 原因 |
|---|---|
| 统一课次展开，让提醒跟随手动当前周 | `docs/specs/2026-10-22-current-week-validity.md:50` 明确保留提醒规则；净减接近 0，是行为变更 |
| 统一 HH:mm 解析 | 不同行为是有意的：`test/reminder_scheduler_test.dart` 保留 `25:75` 的溢出归一化，`test/section_time_shift_test.dart` 要求拒绝 `24:00` |
| 删除 `CourseFormNotifier` 的 setter | 周次操作和空串转 null 都是真实逻辑，删掉只会回到 Screen |
| 改 `save()` 的三态返回值 | 不减代码，可以另开任务 |
| 新增学期阶段函数 | 只有两处使用，文案不同，每处一行，抽出来不减代码 |
| 合并学校脚本的表格解析和 `parseCellText` | 属于行为变更，又没有真实学校账号可验证 |
| 更新镜像和多源下载 | 产品决定：国内用户可能需要 |
| 删除旧设计文档 | `docs/specs/2026-10-22-own-identity.md` 曾决定保留，由用户决定 |
| `setAllTimes`、`ImportCourse.source` | 测试在用或牵涉大量构造调用，收益太小 |

## Testing Decisions

- 测试走外部行为：学校脚本用 Node + fake DOM 跑 `extractJs`，其余走现有 flow 测试。
- 除“批次 1”“批次 3”明确列出的调整外，不改已有断言。
- 新增测试：`conflictNames` 集合级、周次钳制、非周一结束日期、批次 4 的保护 fixture、批次 6 的重试协议。

## 验收

每批提交前都要满足：

```bash
dart run build_runner build --delete-conflicting-outputs
flutter analyze --fatal-infos --fatal-warnings
flutter test
```

全部完成后再确认：

- `git diff --stat 4cceddf -- lib` 显示净减行数；如果明显低于 700 行，说明哪一批没达到估算及原因。
- `schoolAdapters` 比对结果完全一致，仍为 43 所。
- 学校脚本只用 fixture 验证过，真实教务页面未验证，提交说明要如实写明。

提交信息用 `<type>(<scope>): <简述>`，每批一个提交。推送和发布由用户决定。
