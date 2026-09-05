import 'dart:io';

import 'package:flutter/services.dart';

class UpdateInstaller {
  static const _channel = MethodChannel('com.aetikyue.hormone/update');

  /// false 表示已打开授权页；用户授权后可复用已校验的安装包重试。
  Future<bool> install(File apk) async =>
      await _channel.invokeMethod<bool>('installApk', {'path': apk.path}) ??
      false;
}
