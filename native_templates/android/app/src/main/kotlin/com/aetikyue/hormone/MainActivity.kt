package com.aetikyue.hormone

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class UpdateFileProvider : FileProvider()

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "com.aetikyue.hormone/update").setMethodCallHandler { call, result ->
            if (call.method != "installApk") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            try {
                val path = call.argument<String>("path")
                val allowed = File(cacheDir, "hormone_updates/update.apk").canonicalFile
                val apk = path?.let { File(it).canonicalFile }
                if (apk != allowed || !allowed.isFile) {
                    result.error("INVALID_APK", "安装包不存在，请重新下载", null)
                    return@setMethodCallHandler
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                    !packageManager.canRequestPackageInstalls()) {
                    startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:$packageName")))
                    result.success(false)
                    return@setMethodCallHandler
                }
                val uri = FileProvider.getUriForFile(this,
                    "$packageName.update_provider", allowed)
                startActivity(Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "application/vnd.android.package-archive")
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                })
                result.success(true)
            } catch (error: Exception) {
                result.error("INSTALL_FAILED", "无法打开系统安装页，请稍后重试", null)
            }
        }
    }
}
