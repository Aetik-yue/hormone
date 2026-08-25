import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 课前提醒的设置项。
class ReminderSettings {
  final bool enabled;
  final int leadMinutes;

  const ReminderSettings({this.enabled = false, this.leadMinutes = 10});

  ReminderSettings copyWith({bool? enabled, int? leadMinutes}) =>
      ReminderSettings(
        enabled: enabled ?? this.enabled,
        leadMinutes: leadMinutes ?? this.leadMinutes,
      );
}

/// 可选的提前提醒分钟数。
const List<int> reminderLeadOptions = [5, 10, 15, 30];

/// 课前提醒设置 Provider。持久化到 SharedPreferences。
final reminderSettingsProvider =
    StateNotifierProvider<ReminderSettingsNotifier, ReminderSettings>((ref) {
  return ReminderSettingsNotifier();
});

class ReminderSettingsNotifier extends StateNotifier<ReminderSettings> {
  static const _keyEnabled = 'reminder_enabled';
  static const _keyLead = 'reminder_lead_minutes';

  ReminderSettingsNotifier() : super(const ReminderSettings()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_keyEnabled) ?? false;
    final lead = prefs.getInt(_keyLead) ?? 10;
    state = ReminderSettings(enabled: enabled, leadMinutes: lead);
  }

  Future<void> setEnabled(bool v) async {
    state = state.copyWith(enabled: v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, v);
  }

  Future<void> setLeadMinutes(int v) async {
    state = state.copyWith(leadMinutes: v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLead, v);
  }
}