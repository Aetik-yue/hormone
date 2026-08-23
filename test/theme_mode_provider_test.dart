import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hormone/features/settings/application/theme_mode_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('读取已保存的主题模式', () async {
    SharedPreferences.setMockInitialValues({
      'theme_mode': ThemeMode.dark.index,
    });
    final notifier = ThemeModeNotifier();

    await pumpEventQueue();

    expect(notifier.state, ThemeMode.dark);
    notifier.dispose();
  });

  test('切换主题后立即更新并持久化', () async {
    SharedPreferences.setMockInitialValues({});
    final notifier = ThemeModeNotifier();
    await pumpEventQueue();

    await notifier.setThemeMode(ThemeMode.light);

    expect(notifier.state, ThemeMode.light);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('theme_mode'), ThemeMode.light.index);
    notifier.dispose();
  });
}
