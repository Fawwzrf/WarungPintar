// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mockito/mockito.dart';
import 'package:warung_pintar/auth_service.dart';
import 'package:warung_pintar/main.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockGoTrueClient extends Mock implements GoTrueClient {
  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();
}

void main() {
  testWidgets('App starts and shows login screen', (WidgetTester tester) async {
    // Build our app and trigger a frame with a mocked auth state to avoid Supabase initialization errors
    final mockAuth = MockGoTrueClient();
    final mockClient = MockSupabaseClient();
    when(mockClient.auth).thenReturn(mockAuth);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWith((ref) => AuthStateNotifier(
            client: mockClient,
          )),
        ],
        child: const WarungPintarApp(),
      ),
    );

    // Verify that login screen or at least the app title is present
    expect(find.text('WarungPintar Lite'), findsOneWidget);
  });
}
