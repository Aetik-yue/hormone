import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hormone/features/import/domain/import_course.dart';
import 'package:hormone/features/import/presentation/import_confirm_dialog.dart';

void main() {
  testWidgets('替换模式确认弹窗文案与返回 true', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showImportConfirmDialog(
                context,
                mode: ImportMode.replace,
                importCount: 3,
                existingCount: 5,
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('替换当前课表？'), findsOneWidget);
    expect(find.textContaining('删除当前学期的 5 门现有课程'), findsOneWidget);
    expect(find.textContaining('导入所选 3 门课程'), findsOneWidget);

    await tester.tap(find.text('替换'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('合并模式弹窗文案与返回 false（取消）', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showImportConfirmDialog(
                context,
                mode: ImportMode.merge,
                importCount: 2,
                existingCount: 4,
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('合并到当前课表？'), findsOneWidget);
    expect(find.textContaining('追加导入 2 门课程'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });
}