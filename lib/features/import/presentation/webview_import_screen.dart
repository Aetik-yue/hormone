import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'package:hormone/core/models/course.dart';
import 'package:hormone/data/providers/database_providers.dart';
import 'package:hormone/features/semester/application/semester_providers.dart';
import 'package:hormone/features/widget/application/widget_service.dart';
import '../data/school_adapter.dart';

/// WebView 教务系统导入页：选学校 → 登录 → 自动抓取 → 预览 → 导入。
class WebviewImportScreen extends ConsumerStatefulWidget {
  const WebviewImportScreen({super.key});

  @override
  ConsumerState<WebviewImportScreen> createState() =>
      _WebviewImportScreenState();
}

class _WebviewImportScreenState extends ConsumerState<WebviewImportScreen> {
  SchoolAdapter? _adapter;
  WebViewController? _controller;
  bool _loading = true;
  bool _extracting = false;
  List<ExtractedCourse> _courses = [];
  final Set<int> _selectedIndices = {};
  int _skippedCount = 0;

  // ── 阶段：select → login → preview ──
  _Phase _phase = _Phase.select;

  /// 导航到课表页后的自动重试次数（frame 内导航不触发 onPageFinished）。
  int _navRetry = 0;

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
          if (_phase == _Phase.login)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '刷新',
              onPressed: () => _controller?.reload(),
            ),
          if (_phase == _Phase.login)
            TextButton(
              onPressed: _tryExtract,
              child: const Text('抓取课表'),
            ),
          if (_phase == _Phase.preview)
            TextButton(
              onPressed: _importSelected,
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '选择你的学校',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          '将在内置浏览器中打开教务系统，登录后自动抓取课程表。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        ...schoolAdapters.map((adapter) => Card(
              child: ListTile(
                leading: const Icon(Icons.school_outlined),
                title: Text(adapter.schoolName),
                subtitle: Text(adapter.loginUrl),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _startLogin(adapter),
              ),
            )),
      ],
    );
  }

  // ── WebView 登录 ──
  Widget _buildWebView() {
    if (_controller == null) return const SizedBox.shrink();
    return Stack(
      children: [
        WebViewWidget(controller: _controller!),
        if (_loading || _extracting)
          Container(
            color: Colors.black26,
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 48),
            const SizedBox(height: 12),
            Text('未抓取到课程数据',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('请确认已登录并进入课表页面，然后点击「抓取课表」',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => setState(() => _phase = _Phase.login),
              child: const Text('返回重试'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('共抓取 ${_courses.length} 门课程',
                      style: Theme.of(context).textTheme.bodyMedium),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() {
                      if (_selectedIndices.length == _courses.length) {
                        _selectedIndices.clear();
                      } else {
                        _selectedIndices
                            .addAll(List.generate(_courses.length, (i) => i));
                      }
                    }),
                    child: Text(_selectedIndices.length == _courses.length
                        ? '取消全选'
                        : '全选'),
                  ),
                ],
              ),
              if (_skippedCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '注意：有 $_skippedCount 门课程无法识别星期，已跳过',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: _courses.length,
            itemBuilder: (context, i) {
              final c = _courses[i];
              final selected = _selectedIndices.contains(i);
              return CheckboxListTile(
                value: selected,
                onChanged: (_) => setState(() {
                  if (selected) {
                    _selectedIndices.remove(i);
                  } else {
                    _selectedIndices.add(i);
                  }
                }),
                title: Text(c.name),
                subtitle: Text(
                  '周${_dayLabel(c.dayOfWeek)} 第${c.startSection}-${c.endSection}节'
                  '${c.location != null ? ' · ${c.location}' : ''}'
                  '${c.teacher != null ? ' · ${c.teacher}' : ''}',
                ),
                secondary: Text(
                  c.weeks.isEmpty ? '' : '${c.weeks.length}周',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── 逻辑 ──

  void _startLogin(SchoolAdapter adapter) {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      );

    controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (_) => setState(() => _loading = true),
        onPageFinished: (url) {
          setState(() => _loading = false);
          // 注入 viewport 确保移动端正确渲染
          _controller?.runJavaScript('''
            (function() {
              var meta = document.querySelector('meta[name="viewport"]');
              if (!meta) {
                meta = document.createElement('meta');
                meta.name = 'viewport';
                meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=3.0, user-scalable=yes';
                document.head.appendChild(meta);
              }
            })();
          ''');
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

  Future<void> _tryExtract() async {
    if (_adapter == null || _controller == null) return;
    if (_extracting) return; // 防止 onPageFinished 与手动点击并发
    setState(() => _extracting = true);

    try {
      // 等待 SPA 动态渲染完成
      await Future.delayed(const Duration(seconds: 2));

      // 注入 JS 提取课程
      final result = await _controller!
          .runJavaScriptReturningResult(_adapter!.extractJs);

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
            _showNavFailedDialog();
            return;
          }
          _navRetry++;
          await Future.delayed(
            decoded['__nav'] == true
                ? const Duration(seconds: 3)
                : const Duration(seconds: 2),
          );
          if (mounted) return _tryExtract();
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
      final allExtracted =
          list.map((e) => ExtractedCourse.fromJson(e as Map<String, dynamic>)).toList();
      // 过滤掉无法识别星期的课程（dayOfWeek=0 表示 findDay 未能推断）
      final courses = allExtracted.where((c) => c.dayOfWeek >= 1 && c.dayOfWeek <= 7).toList();
      final skippedCount = allExtracted.length - courses.length;

      if (courses.isEmpty) {
        // 抓取为空，捕获调试信息
        final debugInfo = await _controller!.runJavaScriptReturningResult(r'''
          (function() {
            var info = 'URL: ' + location.href + '\n\n';
            // 找包含课程编号的元素，输出其 outerHTML
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

      setState(() {
        _courses = courses;
        _skippedCount = skippedCount;
        _selectedIndices.clear();
        _selectedIndices.addAll(List.generate(courses.length, (i) => i));
        _phase = _Phase.preview;
        _extracting = false;
      });
    } catch (e) {
      setState(() => _extracting = false);
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
    var count = 0;
    for (final i in _selectedIndices) {
      final ec = _courses[i];
      if (ec.name.isEmpty || ec.weeks.isEmpty) continue;
      final course = Course(
        id: const Uuid().v4(),
        semesterId: semester.id,
        name: ec.name,
        teacher: ec.teacher,
        location: ec.location,
        dayOfWeek: ec.dayOfWeek,
        startSection: ec.startSection,
        endSection: ec.endSection,
        weeks: ec.weeks,
        colorValue: _autoColor(count),
      );
      await repo.upsert(course);
      count++;
    }

    ref.read(widgetServiceProvider).updateTodayWidget();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('成功导入 $count 门课程')),
      );
      context.pop();
    }
  }

  String _dayLabel(int day) {
    const labels = ['一', '二', '三', '四', '五', '六', '日'];
    return day >= 1 && day <= 7 ? labels[day - 1] : '?';
  }

  int _autoColor(int index) {
    // 与课程编辑页一致的柔和马卡龙色板。
    const palette = [
      0xFF5B8DEF, 0xFF3FBFA8, 0xFFF2A25C, 0xFF9B8AFB, 0xFFEF6E8D,
      0xFF4FA3E3, 0xFFE8BE50, 0xFF63C98D, 0xFFC08CE8, 0xFFF08C7C,
    ];
    return palette[index % palette.length];
  }
}

enum _Phase { select, login, preview }
