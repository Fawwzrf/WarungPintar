import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_service.dart';

enum AuthMode { login, signup, reset }

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController(), _pass = TextEditingController();
  AuthMode _mode = AuthMode.login;

  void _submit() {
    final auth = ref.read(authServiceProvider.notifier);
    if (_mode == AuthMode.login) {
      auth.signIn(_email.text, _pass.text);
    } else if (_mode == AuthMode.signup) {
      auth.signUp(_email.text, _pass.text);
    } else {
      auth.resetPassword(_email.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authServiceProvider);
    
    ref.listen(authServiceProvider, (prev, next) {
      if (next is AsyncError) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.error.toString())));
      }
    });

    return GestureDetector(
      onTap: () => ref.read(authServiceProvider.notifier).userActivity(),
      child: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Text(_mode.name.toUpperCase(), style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 32),
              TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
              const SizedBox(height: 16),
              if (_mode != AuthMode.reset) ...[
                TextField(controller: _pass, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()), obscureText: true),
                const SizedBox(height: 16),
              ],
              if (state.isLoading) const CircularProgressIndicator()
              else ElevatedButton(
                onPressed: _submit, 
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                child: Text(_mode == AuthMode.reset ? 'Send Reset Link' : 'Submit'),
              ),
              TextButton(
                onPressed: () => setState(() => _mode = _mode == AuthMode.login ? AuthMode.signup : AuthMode.login),
                child: Text(_mode == AuthMode.login ? 'Create Account' : 'Back to Login'),
              ),
              if (_mode == AuthMode.login) TextButton(
                onPressed: () => setState(() => _mode = AuthMode.reset),
                child: const Text('Forgot Password?'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
