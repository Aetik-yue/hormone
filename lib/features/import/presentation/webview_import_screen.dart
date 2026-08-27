import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'package:hormone/core/constants/app_constants.dart';
import 'package:hormone/core/models/course.dart';
import 'package:hormone/data/providers/database_providers.dart';
import 'package:hormone/features/import/application/course_capture_orientation.dart';
import 'package:hormone/features/import/application/webview_import_provider.dart';
import 'package:hormone/features/import/domain/import_course.dart';
import 'package:hormone/features/semester/application/semester_providers.dart';
import 'package:hormone/features/settings/application/section_times_provider.dart';
import '../data/school_adapter.dart';
import 'import_confirm_dialog.dart';
import 'import_preview_list.dart';

/// Android WebView 会把无法重放的无缓存请求报为 ERR_CACHE_MISS。
bool isWebViewCacheMiss(String description) =>
    description.toUpperCase().contains('ERR_CACHE_MISS');

/// WebView 教务系统导入页：选学校 -> 登录 -> 自动抓取 -> 预览 -> 导入。
class WebviewImportScreen extends ConsumerStatefulWidget {
  final CourseCaptureOrientationController? orientationController;

  const WebviewImportScreen({
    super.key,
    this.orientationController,
  });

  @override
  ConsumerState<WebviewImportScreen> createState() =>
      _WebviewImportScreenState();
}

class _WebviewImportScreenState extends ConsumerState<WebviewImportScreen> {
  late final CourseCaptureOrientationController _orientationController;
  SchoolAdapter? _adapter;
  WebViewController? _controller;
  bool _cacheMissRecoveryAttempted = false;
  final TextEditingController _schoolSearchController = TextEditingController();
  String _schoolQuery = '';

  @override
  void initState() {
    super.initState();
    _orientationController =
        widget.orientationController ?? CourseCaptureOrientationController();
  }

  @override
  void dispose() {
    unawaited(_orientationController.leaveCaptureMode());
    _schoolSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(webviewImportProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(state.phase == WebviewPhase.select
            ? '从教务系统导入'
            : state.phase == WebviewPhase.login
                ? (_adapter?.schoolName ?? '登录')
                : '选择导入课程'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded),
            tooltip: '课程抓取说明',
            onPressed: () => context.push('/import/guide'),
          ),
          if (state.phase == WebviewPhase.login)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '刷新',
              onPressed: _refreshWebView,
            ),
          if (state.phase == WebviewPhase.login)
            TextButton(
              onPressed: state.extracting ? null : _tryExtract,
              child: const Text('抓取课表'),
            ),
          if (state.phase == WebviewPhase.preview)
            TextButton(
              onPressed: state.selectedCount == 0
                  ? null
                  : () => _confirmAndImport(state),
              child: Text('导入 (${state.selectedCount})'),
            ),
        ],
      ),
      body: _buildBody(state),
    );
  }

  Widget _buildBody(WebviewImportState state) {
    switch (state.phase) {
      case WebviewPhase.select:
        return _buildSchoolSelector();
      case WebviewPhase.login:
        return _buildWebView(state);
      case WebviewPhase.preview:
        return _buildPreview(state);
    }
  }

  // ── 学校选择 ──
  Widget _buildSchoolSelector() {
    final theme = Theme.of(context);
    final query = _schoolQuery.trim().toLowerCase();
    final eliteMatches = eliteUniversityAdapters
        .where((adapter) => _matchesSchool(adapter, query))
        .toList(growable: false);
    final otherMatches = otherSchoolAdapters
        .where((adapter) => _matchesSchool(adapter, query))
        .toList(growable: false);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer
                .withAlpha((0.3 * 255).round()),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '登录和浏览保持竖屏；点击抓取时会短暂切换横屏，保证七天课表列位置稳定。',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('通用入口',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            )),
        const SizedBox(height: 8),
        _CustomUrlCard(onSubmit: (url) {
          _startLogin(createGenericAdapter(url));
        }),
        const SizedBox(height: 16),
        Text('选择学校',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            )),
        const SizedBox(height: 8),
        TextField(
          key: const Key('school-search-field'),
          controller: _schoolSearchController,
          onChanged: (value) => setState(() => _schoolQuery = value),
          decoration: InputDecoration(
            hintText: '搜索学校或教务系统',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _schoolQuery.isEmpty
                ? null
                : IconButton(
                    tooltip: '清空搜索',
                    onPressed: () {
                      _schoolSearchController.clear();
                      setState(() => _schoolQuery = '');
                    },
                    icon: const Icon(Icons.clear),
                  ),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 16),
        if (eliteMatches.isNotEmpty) ...[
          Text(
            '重点高校（${eliteMatches.length}/${eliteUniversityAdapters.length}）',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ...eliteMatches.map(
            (adapter) => _SchoolCard(
              adapter: adapter,
              onTap: () => _startLogin(adapter),
            ),
          ),
        ],
        if (otherMatches.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            '其他专用适配',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ...otherMatches.map(
            (adapter) => _SchoolCard(
              adapter: adapter,
              onTap: () => _startLogin(adapter),
            ),
          ),
        ],
        if (eliteMatches.isEmpty && otherMatches.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              '没有匹配的学校，可使用上方自定义 URL。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.forum_outlined,
                size: 20,
                color: theme.colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '标记“系统兼容”的学校复用对应教务产品规则，标记“专用适配”的学校已针对页面结构调优；'
                  '如页面升级后无法抓取，或列表中没有你的学校，请通过应用商店或 GitHub 反馈学校与课表页信息。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  bool _matchesSchool(SchoolAdapter adapter, String query) {
    if (query.isEmpty) return true;
    return adapter.schoolName.toLowerCase().contains(query) ||
        adapter.systemName.toLowerCase().contains(query) ||
        adapter.loginUrl.toLowerCase().contains(query);
  }

  // ── WebView 登录 ──
  Widget _buildWebView(WebviewImportState state) {
    if (_controller == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Stack(
      children: [
        WebViewWidget(controller: _controller!),
        if (state.loading || state.extracting)
          Container(
            color: theme.colorScheme.scrim.withAlpha(74),
            child: Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(state.extracting ? '正在抓取课表...' : '加载中...'),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── 预览列表 ──
  Widget _buildPreview(WebviewImportState state) {
    if (state.courses.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off,
                  size: 56, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              Text('未抓取到课程数据',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                '请确认已登录并进入课表页面，然后点击右上角「抓取课表」',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.tonal(
                onPressed: () =>
                    ref.read(webviewImportProvider.notifier).backToLogin(),
                child: const Text('返回重试'),
              ),
            ],
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final notifier = ref.read(webviewImportProvider.notifier);
    // 合并模式需要与现有课表比对冲突；替换模式会清空现有课表，无意义。
    final existingCourses = state.mode == ImportMode.merge
        ? ref.watch(scheduleCoursesProvider).valueOrNull ??
            const <Course>[]
        : const <Course>[];
    final conflictedNames = _conflictNames(state, existingCourses);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: theme.colorScheme.surfaceContainerHighest
              .withAlpha((0.5 * 255).round()),
          child: Row(
            children: [
              Text('共 ${state.courses.length} 门课程',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  )),
              const Spacer(),
              TextButton.icon(
                onPressed: () => notifier.toggleSelectAll(),
                icon: Icon(
                  state.selectedCount == state.courses.length
                      ? Icons.deselect
                      : Icons.select_all,
                  size: 18,
                ),
                label: Text(
                    state.selectedCount == state.courses.length
                        ? '取消全选'
                        : '全选'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: SegmentedButton<ImportMode>(
            segments: const [
              ButtonSegment(
                value: ImportMode.replace,
                icon: Icon(Icons.restart_alt, size: 18),
                label: Text('替换'),
              ),
              ButtonSegment(
                value: ImportMode.merge,
                icon: Icon(Icons.library_add_outlined, size: 18),
                label: Text('合并'),
              ),
            ],
            selected: {state.mode},
            showSelectedIcon: false,
            onSelectionChanged: (s) =>
                ref.read(webviewImportProvider.notifier).setMode(s.first),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: theme.colorScheme.secondaryContainer,
          child: Text(
            state.mode == ImportMode.merge
                ? '合并模式：保留现有课表，追加所选课程。'
                : '替换模式：所选课程将替换当前学期的原有课表。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
        ),
        if (state.skippedCount > 0)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color:
                theme.colorScheme.errorContainer.withAlpha((0.3 * 255).round()),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 16, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '有 ${state.skippedCount} 门课程无法识别星期，已跳过',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (conflictedNames.isNotEmpty)
          ImportConflictBanner(
            names: conflictedNames,
            reason: state.mode == ImportMode.merge
                ? '与现有课程或彼此同时段重叠'
                : '所选课程彼此同时段重叠',
          ),
        Expanded(
          child: ImportPreviewList(
            courses: state.courses,
            conflictedNames: conflictedNames,
            onToggle: notifier.toggle,
          ),
        ),
      ],
    );
  }

  /// 返回存在时间冲突的已选课程名称集合（内部冲突 + 与现有课表冲突）。
  Set<String> _conflictNames(
    WebviewImportState state,
    List<Course> existingCourses,
  ) {
    final selected = state.courses.where((c) => c.selected).toList();
    final names = <String>{};
    for (var i = 0; i < selected.length; i++) {
      for (var j = i + 1; j < selected.length; j++) {
        if (coursesConflict(selected[i], selected[j])) {
          names
            ..add(selected[i].name)
            ..add(selected[j].name);
        }
      }
      for (final e in existingCourses) {
        if (conflictsWithCourse(selected[i], e)) {
          names.add(selected[i].name);
        }
      }
    }
    return names;
  }

  // ── 逻辑 ──

  void _startLogin(SchoolAdapter adapter) {
    final backgroundColor = Theme.of(context).colorScheme.surface;
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(backgroundColor)
      ..setUserAgent(
        // 使用桌面端 UA，确保教务系统返回桌面版课表页面。
        // 教务系统课表为表格布局，移动版会被压缩错位。
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      );

    controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (_) =>
            ref.read(webviewImportProvider.notifier).setLoading(true),
        onPageFinished: (url) {
          ref.read(webviewImportProvider.notifier).setLoading(false);
          // 不注入 width=device-width 的 viewport：教务系统课表需要桌面宽度渲染，
          // 强制 device-width 会把表格挤成一团。浏览器默认以 ~980px 桌面宽度渲染
          // 并缩放适配屏幕，用户可双指缩放查看细节。
          // 检测是否已到达课表页
          if (adapter.isSchedulePage(url)) {
            _tryExtract();
          }
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame != true) return;
          ref.read(webviewImportProvider.notifier).setLoading(false);
          if (isWebViewCacheMiss(error.description)) {
            unawaited(_recoverFromCacheMiss(adapter));
          }
        },
      ),
    );

    // Android 平台：允许混合内容（https 页面加载 http 资源）
    if (controller.platform is AndroidWebViewController) {
      (controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }

    _adapter = adapter;
    _controller = controller;
    _cacheMissRecoveryAttempted = false;
    ref.read(webviewImportProvider.notifier).startLogin();
    unawaited(_loadFresh(controller, adapter.loginUrl));
  }

  /// 使用新的 GET 请求打开页面，避免重放登录 POST 导致 ERR_CACHE_MISS。
  Future<void> _loadFresh(WebViewController controller, String url) {
    return controller.loadRequest(
      Uri.parse(url),
      method: LoadRequestMethod.get,
    );
  }

  Future<void> _refreshWebView() async {
    final controller = _controller;
    final adapter = _adapter;
    if (controller == null || adapter == null) return;

    final currentUrl = await controller.currentUrl();
    final currentUri = currentUrl == null ? null : Uri.tryParse(currentUrl);
    final canReloadCurrent = currentUri != null &&
        (currentUri.scheme == 'http' || currentUri.scheme == 'https');
    _cacheMissRecoveryAttempted = false;
    await _loadFresh(
      controller,
      canReloadCurrent ? currentUri.toString() : adapter.loginUrl,
    );
  }

  Future<void> _recoverFromCacheMiss(SchoolAdapter adapter) async {
    final controller = _controller;
    if (controller == null || _cacheMissRecoveryAttempted) return;
    _cacheMissRecoveryAttempted = true;
    await _loadFresh(controller, adapter.loginUrl);
  }

  Future<bool> _waitForLandscapeLayout() async {
    for (var attempt = 0; attempt < 20; attempt++) {
      if (!mounted) return false;
      final size = MediaQuery.sizeOf(context);
      if (size.width > size.height) return true;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return false;
  }

  Future<void> _tryExtract() async {
    if (_adapter == null || _controller == null) return;
    final notifier = ref.read(webviewImportProvider.notifier);
    if (ref.read(webviewImportProvider).extracting) {
      return; // 防止 onPageFinished 与手动点击并发
    }
    notifier.setExtracting(true);

    try {
      // 登录和浏览阶段保持正常竖屏，只在坐标敏感的抓取瞬间临时横屏。
      final landscapeReady = await _orientationController.enterCaptureMode();
      if (!mounted) {
        await _orientationController.leaveCaptureMode();
        return;
      }
      if (!landscapeReady) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法自动切换横屏，请手动将手机旋转为横屏后再抓取')),
        );
      } else {
        // 等待 Android 完成 Activity 与 WebView 尺寸变更，避免读取旧的竖屏坐标。
        final layoutChanged = await _waitForLandscapeLayout();
        if (!mounted) {
          await _orientationController.leaveCaptureMode();
          return;
        }
        if (!layoutChanged) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('屏幕尚未切换为横屏，请手动旋转手机后再抓取')),
          );
        }
      }

      // 等待 SPA 动态渲染完成
      await Future.delayed(const Duration(seconds: 2));

      // 注入 JS 提取课程
      final result =
          await _controller!.runJavaScriptReturningResult(_adapter!.extractJs);
      final decoded = decodeWebviewExtractResult(result);

      // 适配器导航/等待信号：已跳转课表页或课表仍在加载，延迟后自动重试
      if (decoded is Map<String, dynamic>) {
        if (decoded['__nav'] == true || decoded['__pending'] == true) {
          notifier.setExtracting(false);
          if (notifier.navRetry >= 3) {
            notifier.navRetry = 0;
            await _orientationController.leaveCaptureMode();
            if (!mounted) return;
            _showNavFailedDialog();
            return;
          }
          notifier.navRetry++;
          await Future.delayed(
            decoded['__nav'] == true
                ? const Duration(seconds: 3)
                : const Duration(seconds: 2),
          );
          if (mounted) await _tryExtract();
          return;
        }
      }
      notifier.navRetry = 0;
      if (decoded == null) {
        throw Exception('未抓取到课程数据，请确认已进入课表页面后重试');
      }
      if (decoded is! List) {
        throw Exception('课表数据格式异常，请确认已进入课表页面后重试');
      }

      final (courses, skippedCount) = importCoursesFromDecoded(decoded);

      if (courses.isEmpty) {
        // 抓取为空，捕获调试信息
        final debugInfo = await _controller!.runJavaScriptReturningResult(r'''
          (function() {
            var info = 'URL: ' + location.href + '\n\n';
            var els = document.body.querySelectorAll('*');
            var found = false;
            for (var i = 0; i < els.length; i++) {
              var t = (els[i].textContent || '');
              if (/\[\d{4,}-\d{2,}/.test(t) && t.length < 300 && t.length > 10) {
                info += '=== 课程元素 outerHTML ===\n';
                info += els[i].outerHTML.substring(0, 800) + '\n\n';
                info += '=== 父元素 outerHTML (前1500字符) ===\n';
                var p = els[i].parentElement;
                if (p) info += p.outerHTML.substring(0, 1500);
                found = true;
                break;
              }
            }
            if (!found) {
              info += '未找到含课程编号的元素\n\n';
              info += '=== body.innerText 前1500字符 ===\n';
              info += (document.body ? document.body.innerText : '').substring(0, 1500);
            }
            return info;
          })()
        ''');
        final debugStr = debugInfo is String ? debugInfo : debugInfo.toString();
        notifier.setExtracting(false);
        await _orientationController.leaveCaptureMode();
        if (!mounted) return;
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('未找到课程数据'),
              content: const SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('请确认：'),
                    SizedBox(height: 8),
                    Text('1. 已成功登录教务系统'),
                    Text('2. 当前页面是课程表页面'),
                    Text('3. 点击右上角「抓取课表」重试'),
                    SizedBox(height: 8),
                    Text('如果仍无法抓取，说明你的学校教务系统暂不支持。'),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('关闭'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _showDebugInfo(context, debugStr);
                  },
                  child: const Text('查看详情'),
                ),
              ],
            ),
          );
        }
        return;
      }

      await _orientationController.leaveCaptureMode();
      if (!mounted) return;
      notifier.showPreview(courses, skippedCount);
    } catch (e) {
      if (mounted) notifier.setExtracting(false);
      await _orientationController.leaveCaptureMode();
      if (!mounted) return;
      // 跳转进行中注入异常（JS 上下文销毁）时静默等待，onPageFinished 会自动重试
      final currentUrl = await _controller?.currentUrl();
      if (currentUrl != null && _adapter!.isSchedulePage(currentUrl)) {
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('抓取失败：$e')),
        );
      }
    }
  }

  /// 自动导航课表页多次仍失败时的提示。
  void _showNavFailedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('未能跳转到课表页'),
        content: const Text(
          '请确认已成功登录教务系统，并在页面中点击进入「学生个人课表」后，'
          '再点击右上角「抓取课表」。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _showDebugInfo(BuildContext context, String debugStr) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('调试信息'),
        content: SingleChildScrollView(
          child: SelectableText(
            debugStr,
            style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndImport(WebviewImportState state) async {
    // 二次确认：替换/合并都先向用户说明影响面。
    final existing = await _existingCourseCount();
    if (!mounted) return;
    final ok = await showImportConfirmDialog(
      context,
      mode: state.mode,
      importCount: state.selectedCount,
      existingCount: existing,
    );
    if (ok && mounted) await _importSelected();
  }

  Future<int> _existingCourseCount() async {
    final repo = ref.read(courseRepositoryProvider);
    final semester =
        await ref.read(semesterRepositoryProvider).getActiveSemester();
    if (semester == null) return 0;
    return (await repo.getCourses(semester.id)).length;
  }

  Future<void> _importSelected() async {
    final semester = ref.read(activeSemesterProvider).value;
    if (semester == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先创建学期')),
      );
      return;
    }

    final repo = ref.read(courseRepositoryProvider);
    final sectionTimes = ref.read(sectionTimesProvider);
    final uuid = const Uuid();
    final state = ref.read(webviewImportProvider);
    final replacements = <Course>[];
    for (final c in state.courses.where((c) => c.selected)) {
      if (c.name.isEmpty || c.weeks.isEmpty) continue;
      // 教案上没有直接的时间，但节次时间表已知：startSection 对应开始时间，
      // endSection 对应结束时间，补上后桌面小组件才能显示具体钟点。
      final startTime = sectionTimes[c.startSection]?.startTime;
      final endTime = sectionTimes[c.endSection]?.endTime;
      replacements.add(Course(
        id: uuid.v4(),
        semesterId: semester.id,
        name: c.name,
        teacher: c.teacher,
        location: c.location,
        dayOfWeek: c.dayOfWeek,
        startSection: c.startSection,
        endSection: c.endSection,
        startTime: startTime,
        endTime: endTime,
        weeks: c.weeks,
        colorValue: AppConstants.courseAutoColor(replacements.length),
      ));
    }

    if (replacements.isEmpty) return;
    if (state.mode == ImportMode.merge) {
      await repo.addCourses(semester.id, replacements);
    } else {
      await repo.replaceForSemester(semester.id, replacements);
    }
    final count = replacements.length;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(state.mode == ImportMode.merge
              ? '已在现有课表中追加 $count 门课程'
              : '已用 $count 门课程替换当前课表'),
        ),
      );
      context.pop();
    }
  }
}

/// 学校卡片。
class _SchoolCard extends StatelessWidget {
  final SchoolAdapter adapter;
  final VoidCallback onTap;

  const _SchoolCard({required this.adapter, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color:
                      theme.colorScheme.primary.withAlpha((0.1 * 255).round()),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.school_outlined,
                    color: theme.colorScheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(adapter.schoolName,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        )),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          adapter.systemName,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        _SupportBadge(level: adapter.supportLevel),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      adapter.loginUrl,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupportBadge extends StatelessWidget {
  final AdapterSupportLevel level;

  const _SupportBadge({required this.level});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = switch (level) {
      AdapterSupportLevel.schoolVerified => '专用',
      AdapterSupportLevel.systemCompatible => '系统兼容',
      AdapterSupportLevel.generic => '通用抓取',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

/// 自定义 URL 输入卡片。
class _CustomUrlCard extends StatefulWidget {
  final void Function(String url) onSubmit;

  const _CustomUrlCard({required this.onSubmit});

  @override
  State<_CustomUrlCard> createState() => _CustomUrlCardState();
}

class _CustomUrlCardState extends State<_CustomUrlCard> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.link, color: theme.colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text('自定义教务系统 URL',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      )),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '适用于未列出的学校。输入教务系统网址，登录后点击「抓取课表」。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: 'https://jwxt.yourschool.edu.cn',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.url,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return '请输入 URL';
                        final uri = Uri.tryParse(v.trim());
                        if (uri == null || !uri.hasScheme) {
                          return '请输入完整 URL（含 https://）';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      if (_formKey.currentState?.validate() ?? false) {
                        widget.onSubmit(_controller.text.trim());
                      }
                    },
                    child: const Text('打开'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
