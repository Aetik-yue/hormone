import 'dart:async';
import 'dart:convert';

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
import 'package:hormone/features/semester/application/semester_providers.dart';
import '../data/school_adapter.dart';

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
  bool _loading = true;
  bool _extracting = false;
  List<ExtractedCourse> _courses = [];
  final Set<int> _selectedIndices = {};
  int _skippedCount = 0;

  // ── 阶段：select -> login -> preview ──
  _Phase _phase = _Phase.select;

  /// 导航到课表页后的自动重试次数（frame 内导航不触发 onPageFinished）。
  int _navRetry = 0;

  @override
  void initState() {
    super.initState();
    _orientationController =
        widget.orientationController ?? CourseCaptureOrientationController();
  }

  @override
  void dispose() {
    unawaited(_orientationController.leaveCaptureMode());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_phase == _Phase.select
            ? '从教务系统导入'
            : _phase == _Phase.login
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
          if (_phase == _Phase.login)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '刷新',
              onPressed: () => _controller?.reload(),
            ),
          if (_phase == _Phase.login)
            TextButton(
              onPressed: _extracting ? null : _tryExtract,
              child: const Text('抓取课表'),
            ),
          if (_phase == _Phase.preview)
            TextButton(
              onPressed: _selectedIndices.isEmpty ? null : _importSelected,
              child: Text('导入 (${_selectedIndices.length})'),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _Phase.select:
        return _buildSchoolSelector();
      case _Phase.login:
        return _buildWebView();
      case _Phase.preview:
        return _buildPreview();
    }
  }

  // ── 学校选择 ──
  Widget _buildSchoolSelector() {
    final theme = Theme.of(context);
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
        Text('内置学校',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            )),
        const SizedBox(height: 8),
        ...schoolAdapters.map(
          (adapter) => _SchoolCard(
            adapter: adapter,
            onTap: () => _startLogin(adapter),
          ),
        ),
        const SizedBox(height: 20),
        Text('通用',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            )),
        const SizedBox(height: 8),
        _CustomUrlCard(onSubmit: (url) {
          _startLogin(createGenericAdapter(url));
        }),
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
                  '如果没有你的学校，请在应用商店或 GitHub 给我留言，我会尽快进行适配。',
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

  // ── WebView 登录 ──
  Widget _buildWebView() {
    if (_controller == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Stack(
      children: [
        WebViewWidget(controller: _controller!),
        if (_loading || _extracting)
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
                      Text(_extracting ? '正在抓取课表...' : '加载中...'),
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
  Widget _buildPreview() {
    if (_courses.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off,
                  size: 56, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              Text('未抓取到课程数据', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                '请确认已登录并进入课表页面，然后点击右上角「抓取课表」',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.tonal(
                onPressed: () => setState(() => _phase = _Phase.login),
                child: const Text('返回重试'),
              ),
            ],
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    // 按星期分组
    final grouped = <int, List<int>>{};
    for (var i = 0; i < _courses.length; i++) {
      grouped.putIfAbsent(_courses[i].dayOfWeek, () => []).add(i);
    }
    final sortedDays = grouped.keys.toList()..sort();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: theme.colorScheme.surfaceContainerHighest
              .withAlpha((0.5 * 255).round()),
          child: Row(
            children: [
              Text('共 ${_courses.length} 门课程',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  )),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() {
                  if (_selectedIndices.length == _courses.length) {
                    _selectedIndices.clear();
                  } else {
                    _selectedIndices
                        .addAll(List.generate(_courses.length, (i) => i));
                  }
                }),
                icon: Icon(
                  _selectedIndices.length == _courses.length
                      ? Icons.deselect
                      : Icons.select_all,
                  size: 18,
                ),
                label: Text(
                    _selectedIndices.length == _courses.length ? '取消全选' : '全选'),
              ),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: theme.colorScheme.secondaryContainer,
          child: Text(
            '确认导入后，所选课程将替换当前学期的原有课表。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
        ),
        if (_skippedCount > 0)
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
                    '有 $_skippedCount 门课程无法识别星期，已跳过',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: sortedDays.length,
            itemBuilder: (context, dayIdx) {
              final day = sortedDays[dayIdx];
              final indices = grouped[day]!;
              return _DayGroup(
                day: day,
                indices: indices,
                courses: _courses,
                selectedIndices: _selectedIndices,
                onToggle: (i) => setState(() {
                  if (_selectedIndices.contains(i)) {
                    _selectedIndices.remove(i);
                  } else {
                    _selectedIndices.add(i);
                  }
                }),
              );
            },
          ),
        ),
      ],
    );
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
        onPageStarted: (_) => setState(() => _loading = true),
        onPageFinished: (url) {
          setState(() => _loading = false);
          // 不注入 width=device-width 的 viewport：教务系统课表需要桌面宽度渲染，
          // 强制 device-width 会把表格挤成一团。浏览器默认以 ~980px 桌面宽度渲染
          // 并缩放适配屏幕，用户可双指缩放查看细节。
          // 检测是否已到达课表页
          if (adapter.isSchedulePage(url)) {
            _tryExtract();
          }
        },
      ),
    );

    controller.loadRequest(Uri.parse(adapter.loginUrl));

    // Android 平台：允许混合内容（https 页面加载 http 资源）
    if (controller.platform is AndroidWebViewController) {
      (controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }

    setState(() {
      _adapter = adapter;
      _controller = controller;
      _phase = _Phase.login;
    });
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
    if (_extracting) return; // 防止 onPageFinished 与手动点击并发
    setState(() => _extracting = true);

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

      var jsonStr = result is String ? result : result.toString();
      // WebView 可能返回双重编码的 JSON（字符串内再包一层字符串）
      dynamic decoded = jsonDecode(jsonStr);
      if (decoded is String) {
        decoded = jsonDecode(decoded);
      }
      // 适配器导航/等待信号：已跳转课表页或课表仍在加载，延迟后自动重试
      if (decoded is Map<String, dynamic>) {
        if (decoded['__nav'] == true || decoded['__pending'] == true) {
          setState(() => _extracting = false);
          if (_navRetry >= 3) {
            _navRetry = 0;
            await _orientationController.leaveCaptureMode();
            if (!mounted) return;
            _showNavFailedDialog();
            return;
          }
          _navRetry++;
          await Future.delayed(
            decoded['__nav'] == true
                ? const Duration(seconds: 3)
                : const Duration(seconds: 2),
          );
          if (mounted) await _tryExtract();
          return;
        }
      }
      _navRetry = 0;
      if (decoded == null) {
        throw Exception('未抓取到课程数据，请确认已进入课表页面后重试');
      }
      if (decoded is! List) {
        throw Exception('课表数据格式异常，请确认已进入课表页面后重试');
      }
      final List<dynamic> list = decoded;
      final allExtracted = list
          .map((e) => ExtractedCourse.fromJson(e as Map<String, dynamic>))
          .toList();
      // 过滤掉无法识别星期的课程（dayOfWeek=0 表示 findDay 未能推断）
      final courses = allExtracted
          .where((c) => c.dayOfWeek >= 1 && c.dayOfWeek <= 7)
          .toList();
      final skippedCount = allExtracted.length - courses.length;

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
        setState(() => _extracting = false);
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
      setState(() {
        _courses = courses;
        _skippedCount = skippedCount;
        _selectedIndices.clear();
        _selectedIndices.addAll(List.generate(courses.length, (i) => i));
        _phase = _Phase.preview;
        _extracting = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _extracting = false);
      }
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

  Future<void> _importSelected() async {
    final semester = ref.read(activeSemesterProvider).value;
    if (semester == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先创建学期')),
      );
      return;
    }

    final repo = ref.read(courseRepositoryProvider);
    final uuid = const Uuid();
    final replacements = <Course>[];
    for (final i in _selectedIndices) {
      final ec = _courses[i];
      if (ec.name.isEmpty || ec.weeks.isEmpty) continue;
      replacements.add(Course(
        id: uuid.v4(),
        semesterId: semester.id,
        name: ec.name,
        teacher: ec.teacher,
        location: ec.location,
        dayOfWeek: ec.dayOfWeek,
        startSection: ec.startSection,
        endSection: ec.endSection,
        weeks: ec.weeks,
        colorValue: AppConstants.courseAutoColor(replacements.length),
      ));
    }

    if (replacements.isEmpty) return;
    await repo.replaceForSemester(semester.id, replacements);
    final count = replacements.length;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已用 $count 门课程替换当前课表')),
      );
      context.pop();
    }
  }
}

enum _Phase { select, login, preview }

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

/// 按星期分组的课程列表。
class _DayGroup extends StatelessWidget {
  final int day;
  final List<int> indices;
  final List<ExtractedCourse> courses;
  final Set<int> selectedIndices;
  final void Function(int index) onToggle;

  const _DayGroup({
    required this.day,
    required this.indices,
    required this.courses,
    required this.selectedIndices,
    required this.onToggle,
  });

  String get _dayLabel {
    const labels = ['一', '二', '三', '四', '五', '六', '日'];
    return day >= 1 && day <= 7 ? '周${labels[day - 1]}' : '未知';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            _dayLabel,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        ...indices.map((i) {
          final c = courses[i];
          final selected = selectedIndices.contains(i);
          return _CourseTile(
            course: c,
            selected: selected,
            onTap: () => onToggle(i),
          );
        }),
      ],
    );
  }
}

/// 单条课程预览项。
class _CourseTile extends StatelessWidget {
  final ExtractedCourse course;
  final bool selected;
  final VoidCallback onTap;

  const _CourseTile({
    required this.course,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer
                  .withAlpha((0.3 * 255).round())
              : theme.colorScheme.surfaceContainerHighest
                  .withAlpha((0.3 * 255).round()),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? theme.colorScheme.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 20,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(course.name,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 2),
                  Text(
                    [
                      '第${course.startSection}-${course.endSection}节',
                      if (course.location != null) course.location!,
                      if (course.teacher != null) course.teacher!,
                      if (course.weeks.isNotEmpty) '${course.weeks.length}周',
                    ].join('  ·  '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
