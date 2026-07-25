// Smoke test for the hormone app shell.
//
// This verifies the root widget tree builds without throwing. Detailed
// business-logic coverage lives in the unit test suites under test/.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hormone/main.dart';

void main() {
  testWidgets('HormoneApp builds without throwing', (WidgetTester tester) async {
    // Build the real app root inside a Riverpod scope. The router resolves
    // asynchronously; we only assert the widget tree mounts successfully.
    await tester.pumpWidget(const ProviderScope(child: HormoneApp()));
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
