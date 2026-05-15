// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// ignore: depend_on_referenced_packages
// import 'package:new_app/main.dart';

import '../Backend/app/uploads/main.dart';

void main() {
  testWidgets('App builds (smoke)', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 2000));

    // The app reads dotenv values during initialization (ApiClient.initialize).
    // Provide a minimal test env so widget tests do not crash.
    dotenv.testLoad(fileInput: 'BASE_URL=https://example.com/api\n');

    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(MaterialApp), findsWidgets);
  });
}
