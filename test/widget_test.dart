import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gesapp/app/gesapp_app.dart';

void main() {
  testWidgets('GesApp widget test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const GesApp());

    // Verify that the app can be created without errors.
    expect(find.byType(GesApp), findsOneWidget);
  });
}
