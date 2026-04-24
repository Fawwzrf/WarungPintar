// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:warung_pintar/auth_service.dart';
import 'package:warung_pintar/main.dart';

// Use Fake instead of Mock to avoid Mockito complexity in simple widget tests
class FakeSupabaseClient extends Fake implements SupabaseClient {
  @override
  GoTrueClient get auth => FakeGoTrueClient();
}

class FakeGoTrueClient extends Fake implements GoTrueClient {
  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();
  
  @override
  User? get currentUser => null;
}

void main() {
  testWidgets('App starts and shows login screen', (WidgetTester tester) async {
    final fakeClient = FakeSupabaseClient();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWith((ref) => AuthStateNotifier(
            client: fakeClient,
          )),
        ],
        child: const WarungPintarApp(),
      ),
    );

    // Verify that the app title is present
    expect(find.text('WarungPintar Lite'), findsOneWidget);
  });
}
