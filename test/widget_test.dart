import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_rag_app_flutter/main.dart';

void main() {
  testWidgets('VoiceRagApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const VoiceRagApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
