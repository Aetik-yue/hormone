import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hormone/features/schedule/presentation/schedule_screen.dart';
import 'package:hormone/features/course/presentation/course_edit_screen.dart';
import 'package:hormone/features/semester/presentation/semester_screen.dart';
import 'package:hormone/features/import/presentation/import_screen.dart';
import 'package:hormone/features/import/presentation/webview_import_screen.dart';
import 'package:hormone/features/settings/presentation/settings_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const ScheduleScreen(),
    ),
    GoRoute(
      path: '/course/edit',
      builder: (context, state) =>
          CourseEditScreen(courseId: state.extra as String?),
    ),
    GoRoute(
      path: '/semester',
      builder: (context, state) => const SemesterScreen(),
    ),
    GoRoute(
      path: '/import',
      builder: (context, state) => const ImportScreen(),
    ),
    GoRoute(
      path: '/import/webview',
      builder: (context, state) => const WebviewImportScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: Center(child: Text('页面未找到: ${state.uri}')),
  ),
);
