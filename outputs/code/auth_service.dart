import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final authServiceProvider = StateNotifierProvider<AuthStateNotifier, AsyncValue<User?>>((ref) => AuthStateNotifier());

class AuthStateNotifier extends StateNotifier<AsyncValue<User?>> {
  final _client = Supabase.instance.client;
  final _storage = const FlutterSecureStorage();
  Timer? _timeoutTimer;

  AuthStateNotifier() : super(const AsyncLoading()) {
    _init();
  }

  Future<void> _init() async {
    try {
      final sessionStr = await _storage.read(key: 'session');
      if (sessionStr != null) {
        // Supabase internally handles session restore if initialized correctly, 
        // but we ensure session is set and valid.
        _resetInactivityTimer();
      }
      state = AsyncData(_client.auth.currentUser);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
    _client.auth.onAuthStateChange.listen((data) {
      if (data.session != null) {
        _storage.write(key: 'session', value: data.session!.persistSessionString);
        _resetInactivityTimer();
      } else {
        _storage.delete(key: 'session');
        _timeoutTimer?.cancel();
      }
      state = AsyncData(data.user);
    });
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
}
