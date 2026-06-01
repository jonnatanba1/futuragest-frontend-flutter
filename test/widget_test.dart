// Smoke test — verifies that the app bootstraps without crashing.
// The login screen requires a backend; we only test that the widget tree
// mounts and the app title renders correctly.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:futuragest_mobile/main.dart';

void main() {
  testWidgets('App mounts without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: FuturagestApp()),
    );
    // LoginScreen should be visible.
    expect(find.text('Iniciar sesión'), findsOneWidget);
  });
}
