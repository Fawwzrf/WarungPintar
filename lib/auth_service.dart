import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final authServiceProvider = StateNotifierProvider<AuthStateNotifier, AsyncValue<User?>>((ref) => AuthStateNotifier());

class AuthStateNotifier extends StateNotifier<AsyncValue<User?>> {
  final SupabaseClient _client;
  final FlutterSecureStorage _storage;
  Timer? _timeoutTimer;
  StreamSubscription<AuthState>? _authSub;

  // [RBAC-FIX] Flag to detect brand-new sign-ups vs existing logins
  bool isNewUser = false;

  AuthStateNotifier({SupabaseClient? client, FlutterSecureStorage? storage})
    : _client = client ?? Supabase.instance.client,
      _storage = storage ?? const FlutterSecureStorage(),
      super(const AsyncLoading()) {
    _init();
  }

  Future<void> _init() async {
    _authSub = _client.auth.onAuthStateChange.listen((data) {
      if (data.session != null) {
        _storage.write(key: 'session', value: data.session!.accessToken).catchError((_) {});
        _resetInactivityTimer();
      } else {
        _storage.delete(key: 'session').catchError((_) {});
        _timeoutTimer?.cancel();
        // Clear new-user flag on logout so it doesn't persist to next session
        isNewUser = false;
      }
      state = AsyncData(data.session?.user);
    });

    try {
      final sessionStr = await _storage.read(key: 'session').timeout(const Duration(seconds: 2));
      if (sessionStr != null) {
        _resetInactivityTimer();
      }
    } catch (e) {
      // Ignore secure storage hang/timeout errors — Supabase internal state is source of truth
    }
  }

  void _resetInactivityTimer() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(hours: 1), signOut);
  }

  Future<void> _handleAuth(Future<AuthResponse> Function() action, {bool markAsNew = false}) async {
    state = const AsyncLoading();
    try {
      // [RBAC-FIX] Set flag BEFORE await so it's ready when the auth state listener fires
      if (markAsNew) isNewUser = true;
      await action();
      _resetInactivityTimer();
    } on AuthException catch (e) {
      isNewUser = false;
      state = AsyncError(e.message, StackTrace.current);
    } catch (e) {
      isNewUser = false;
      state = AsyncError('Unexpected error occurred', StackTrace.current);
    }
  }

  Future<void> signIn(String email, String password) =>
    _handleAuth(
      () => _client.auth.signInWithPassword(email: email, password: password),
      markAsNew: false,
    );

  Future<void> signUp(String email, String password) =>
    _handleAuth(
      () => _client.auth.signUp(email: email, password: password),
      markAsNew: true,
    );

  Future<void> resetPassword(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email);
    } catch (e) {
      state = AsyncError('Reset failed', StackTrace.current);
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
    await _storage.delete(key: 'session');
    _timeoutTimer?.cancel();
    state = const AsyncData(null);
  }

  // [RBAC-FIX] Called by MainNavigationHub after onboarding has been shown once
  void clearNewUserFlag() => isNewUser = false;

  void userActivity() => _resetInactivityTimer();

  @override
  void dispose() {
    _authSub?.cancel();
    _timeoutTimer?.cancel();
    super.dispose();
  }
}
