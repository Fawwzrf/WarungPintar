// Widget test for WarungPintar
//
// Uses Fake classes instead of Mockito to avoid complex mock generation
// and Supabase initialization requirements during testing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:warung_pintar/auth_service.dart';
import 'package:warung_pintar/main.dart';

// ──────────────────────────────────────────────
// Fake Supabase dependencies
// ──────────────────────────────────────────────

class FakeGoTrueClient extends Fake implements GoTrueClient {
  // [FIX] Emit a single null-session event so AuthStateNotifier resolves
  // from AsyncLoading → AsyncData(null), which triggers the LoginScreen.
  @override
  Stream<AuthState> get onAuthStateChange => Stream.value(
    AuthState(AuthChangeEvent.initialSession, null),
  );

  @override
  User? get currentUser => null;

  @override
  Session? get currentSession => null;
}

class FakeSupabaseClient extends Fake implements SupabaseClient {
  @override
  GoTrueClient get auth => FakeGoTrueClient();
}

// Fake secure storage that does nothing (no platform channel needed in tests)
class FakeSecureStorage extends Fake implements FlutterSecureStorage {
  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => null;

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {}

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {}
}

// ──────────────────────────────────────────────
// Tests
// ──────────────────────────────────────────────

void main() {
  testWidgets('App starts and shows login screen', (WidgetTester tester) async {
    final fakeClient = FakeSupabaseClient();
    final fakeStorage = FakeSecureStorage();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWith(
            (ref) => AuthStateNotifier(
              client: fakeClient,
              storage: fakeStorage,
            ),
          ),
        ],
        child: const WarungPintarApp(),
      ),
    );

    // Allow the Stream event to propagate and the widget tree to rebuild
    await tester.pump();

    // [FIX] Check for a widget that is actually visible on the LoginScreen,
    // not the MaterialApp 'title' which only appears in the browser tab.
    expect(find.widgetWithText(ElevatedButton, 'Masuk'), findsOneWidget);
  });
}
