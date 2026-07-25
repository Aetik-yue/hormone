package com.example.hormone

// Android 桌面小组件（App Widget）。读取 home_widget 共享的
// SharedPreferences 中由 Flutter 侧写入的「今日课程」数据并展示。
//
// 注意：此文件位于 native_templates/android/...，请复制到
// android/app/src/main/java/<你的应用包名>/CourseWidgetProvider.kt，
// 并将文件顶部的 package 改为你的真实 applicationId（见 WIDGET_SETUP.md）。

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews
import org.json.JSONArray

class CourseWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    private fun updateAppWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ) {
        // home_widget 在 Android 上将数据写入名为 HomeWidgetSharedPreferences 的偏好表。
        val prefs = context.getSharedPreferences(
            "HomeWidgetSharedPreferences",
            Context.MODE_PRIVATE
        )
        val title = prefs.getString("widget_title", "今天") ?: "今天"
        val raw = prefs.getString("courses", "[]") ?: "[]"

        val lines = mutableListOf<String>()
        try {
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                val time = o.optString("time", "")
                val name = o.optString("name", "")
                val loc = o.optString("location", "")
                val line = buildString {
                    if (time.isNotEmpty()) append("$time  ")
                    append(name)
                    if (loc.isNotEmpty()) append("  @$loc")
                }
                lines.add(line)
            }
        } catch (e: Exception) {
            // 解析失败则保持空列表
        }

        val content = if (lines.isEmpty()) "今天没有课 🎉" else lines.joinToString("\n")

        val views = RemoteViews(context.packageName, R.layout.course_widget)
        views.setTextViewText(R.id.widget_title, title)
        views.setTextViewText(R.id.widget_courses, content)
        appWidgetManager.updateAppWidget(appWidgetId, views)
    }
}
