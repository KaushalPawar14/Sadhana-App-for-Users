import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/JapaCounter.dart';
import 'package:folk_app/pages/RduaSession.dart';

void main() {
  testWidgets('japa counter starts at zero and increments', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: JapaCounterPage()),
    );

    expect(find.text('0'), findsOneWidget);
    expect(find.text('of 108 · tap to count'), findsOneWidget);

    await tester.tap(find.text('0'));
    await tester.pump();

    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('RDUA preview preserves the four-step sequence', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: RduaSessionPage()),
    );

    expect(find.textContaining('Step 1 of 4'), findsOneWidget);
    expect(find.text('Finished reading'), findsOneWidget);

    await tester.tap(find.text('Finished reading'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Step 2 of 4'), findsOneWidget);
    expect(find.text('We discussed it'), findsOneWidget);
  });
}
