import 'package:flutter_test/flutter_test.dart';
import 'package:greenmind/main.dart';

void main() {
  testWidgets('GreenMind app renders welcome screen', (WidgetTester tester) async {
    await tester.pumpWidget(const GreenMindApp());

    // Verify the app title and welcome text are displayed
    expect(find.text('GreenMind AI'), findsWidgets);
    expect(find.text('Load Model'), findsOneWidget);
  });
}
