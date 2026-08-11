import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';

void main() {
  testWidgets('Antigravity Remote App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const AntigravityRemoteApp());

    // Verify session title render
    expect(find.textContaining('Poème Sur La Gravité'), findsOneWidget);
  });
}
