import 'package:supabase_flutter/supabase_flutter.dart';

/// Provides a thin, testable abstraction over Supabase Auth operations.
class AuthService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Returns the currently authenticated [User], or `null` if not signed in.
  User? get currentUser => _client.auth.currentUser;

  /// Creates a new account with [email] and [password].
  ///
  /// Throws an [AuthException] if sign-up fails (e.g. email already taken).
  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async {
    return _client.auth.signUp(email: email, password: password);
  }

  /// Signs in an existing user with [email] and [password].
  ///
  /// Throws an [AuthException] on failure (e.g. wrong credentials).
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  /// Signs out the current user and clears the local session.
  Future<void> signOut() async {
    await _client.auth.signOut();
  }
}
