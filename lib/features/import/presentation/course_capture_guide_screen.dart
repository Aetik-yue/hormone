import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 教务系统课程抓取说明。
///
/// 按真实操作顺序解释 WebView 导入流程，并提供常见问题排查与抓取入口。
class CourseCaptureGuideScreen extends StatelessWidget {
  final VoidCallback? onStartCapture;

  const CourseCaptureGuideScreen({
    super.key,
    this.onStartCapture,
  });

  static const _steps = [
    _GuideStep(
      icon: Icons.school_outlined,
      title: '选择学校',
      description: '优先选择列表中的学校；学校未列出时，选择“自定义教务系统 URL”并填写完整网址。',
    ),
    _GuideStep(
      icon: Icons.login_rounded,
      title: '登录教务系统',
      description: '内置浏览器会自动切换为横屏。验证码、短信验证或统一身份认证需要按学校页面提示手动完成。',
    ),
    _GuideStep(
      icon: Icons.calendar_view_week_outlined,
      title: '打开个人课表',
      description: '进入“学生个人课表”“我的课表”等页面。内置学校会尝试自动跳转，未跳转时请手动打开。',
    ),
    _GuideStep(
      icon: Icons.fact_check_outlined,
      title: '抓取、核对并导入',
      description: '等待课表完整显示后点击右上角“抓取课表”，核对星期、节次和周数，取消不需要的课程后再导入。',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('课程抓取使用说明'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '返回',
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            _IntroCard(colors: colors),
            const SizedBox(height: 24),
            Text('开始前', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            const _PreparationCard(),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text('抓取流程', style: theme.textTheme.titleMedium),
                ),
                Text(
                  '通常只需 1–2 分钟',
                  style: theme.textTheme.labelMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            const _StepTimeline(steps: _steps),
            const SizedBox(height: 24),
            Text('没有抓取到课程？', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            const _TroubleshootingCard(),
            const SizedBox(height: 20),
            _PrivacyNote(colors: colors),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('start-course-capture'),
              onPressed:
                  onStartCapture ?? () => context.push('/import/webview'),
              icon: const Icon(Icons.travel_explore_outlined),
              label: const Text('开始抓取课程'),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  final ColorScheme colors;

  const _IntroCard({required this.colors});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              Icons.web_asset_outlined,
              color: colors.onPrimary,
              size: 25,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '把教务课表带进 Hormone',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: colors.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '在学校页面完成登录，打开个人课表后即可识别课程。导入前仍可逐门核对和取消选择。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreparationCard extends StatelessWidget {
  const _PreparationCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            _ChecklistItem(
              text: '已创建并切换到要导入课程的学期',
            ),
            Divider(height: 17),
            _ChecklistItem(
              text: '教务系统当前可以正常访问，课表已经发布',
            ),
            Divider(height: 17),
            _ChecklistItem(
              text: '如学校要求校园网或 VPN，请先完成连接',
            ),
            Divider(height: 17),
            _ChecklistItem(
              text: '抓取期间保持横屏，课程预览时会自动恢复竖屏',
            ),
          ],
        ),
      ),
    );
  }
}

class _ChecklistItem extends StatelessWidget {
  final String text;

  const _ChecklistItem({required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(
          Icons.check_circle_rounded,
          size: 19,
          color: colors.primary,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    );
  }
}

class _StepTimeline extends StatelessWidget {
  final List<_GuideStep> steps;

  const _StepTimeline({required this.steps});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        child: Column(
          children: [
            for (var index = 0; index < steps.length; index++)
              _StepRow(
                step: steps[index],
                number: index + 1,
                isLast: index == steps.length - 1,
              ),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final _GuideStep step;
  final int number;
  final bool isLast;

  const _StepRow({
    required this.step,
    required this.number,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 36,
            child: Column(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$number',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      color: colors.primary.withAlpha(72),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(step.icon, size: 19, color: colors.primary),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          step.title,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(step.description, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TroubleshootingCard extends StatelessWidget {
  const _TroubleshootingCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          children: [
            _TroubleshootingItem(
              icon: Icons.hourglass_top_rounded,
              title: '页面已经打开，但没有自动抓取',
              description: '等待课表完全显示，再点击右上角“抓取课表”。必要时先刷新页面。',
            ),
            Divider(height: 1),
            _TroubleshootingItem(
              icon: Icons.find_in_page_outlined,
              title: '提示未找到课程数据',
              description: '确认当前是个人课表而非首页、考试安排或选课页面，然后重新抓取。',
            ),
            Divider(height: 1),
            _TroubleshootingItem(
              icon: Icons.tune_rounded,
              title: '学校不在列表或结果有偏差',
              description: '尝试自定义 URL；导入前先核对星期、节次和周数，异常课程不要勾选。',
            ),
          ],
        ),
      ),
    );
  }
}

class _TroubleshootingItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _TroubleshootingItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 21, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 3),
                Text(description, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  final ColorScheme colors;

  const _PrivacyNote({required this.colors});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withAlpha(145),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, size: 21, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '账号、密码和验证码只需在学校教务页面中填写。Hormone 不会要求你在其他表单中提交教务账号。',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideStep {
  final IconData icon;
  final String title;
  final String description;

  const _GuideStep({
    required this.icon,
    required this.title,
    required this.description,
  });
}
