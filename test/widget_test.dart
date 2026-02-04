import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app.dart';

void main() {
  testWidgets('App starts and shows login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const App());
    await tester.pump();
    // Allow async auth check to complete (no real API in test)
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('HanCity Work'), findsOneWidget);
  });
}
