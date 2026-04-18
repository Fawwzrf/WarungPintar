import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final authServiceProvider = StateNotifierProvider<AuthStateNotifier, AsyncValue<User?>>((ref) => AuthStateNotifier());

class AuthStateNotifier extends StateNotifier<AsyncValue<User?>> {
  final SupabaseClient _client;
  final FlutterSecureStorage _storage;
  Timer? _timeoutTimer;
  // [MED-06 FIX] Store subscription to cancel on dispose
  StreamSubscription<AuthState>? _authSub;

  AuthStateNotifier({SupabaseClient? client, FlutterSecureStorage? storage}) 
    : _client = client ?? Supabase.instance.client,
      _storage = storage ?? const FlutterSecureStorage(),
      super(const AsyncLoading()) {
    _init();
  }

  Future<void> _init() async {
    // [FIX] Subscribe to auth state FIRST so it emits immediately and clears the loading screen.
    // If placed after await _storage.read(), any hang in SecureStorage will cause an infinite loading screen.
    _authSub = _client.auth.onAuthStateChange.listen((data) {
      if (data.session != null) {
        _storage.write(key: 'session', value: data.session!.accessToken).catchError((_) {});
        _resetInactivityTimer();
      } else {
        _storage.delete(key: 'session').catchError((_) {});
        _timeoutTimer?.cancel();
      }
      state = AsyncData(data.session?.user);
    });

    try {
      final sessionStr = await _storage.read(key: 'session').timeout(const Duration(seconds: 2));
      if (sessionStr != null) {
        _resetInactivityTimer();
      }
    } catch (e) {
      // Ignore secure storage hang/timeout errors, Supabase internal auth state is the source of truth
    }
  }

  void _resetInactivityTimer() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(hours: 1), signOut);
  }

  Future<void> _handleAuth(Future<AuthResponse> Function() action) async {
    state = const AsyncLoading();
    try {
      await action();
      _resetInactivityTimer();
    } on AuthException catch (e) {
      state = AsyncError(e.message, StackTrace.current);
    } catch (e) {
      state = AsyncError('Unexpected error occurred', StackTrace.current);
    }
  }

  Future<void> signIn(String email, String password) => 
    _handleAuth(() => _client.auth.signInWithPassword(email: email, password: password));

  Future<void> signUp(String email, String password) => 
    _handleAuth(() => _client.auth.signUp(email: email, password: password));

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

  void userActivity() => _resetInactivityTimer();

  // [MED-06 FIX] Cancel stream subscription and timer on dispose
  @override
  void dispose() {
    _authSub?.cancel();
    _timeoutTimer?.cancel();
    super.dispose();
  }
}
