import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';

/// Registro y autenticación (email + contraseña, OTP de email y de SMS).
class AuthService {
  final SupabaseClient _client = Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;
  bool get isLoggedIn => currentUser != null;
  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  /// Devuelve true si hay sesión inmediata; false si hay que verificar email.
  Future<bool> signUp({
    required String email,
    required String password,
    required String fullName,
    String? phone,
    String locale = 'es',
  }) async {
    final res = await _client.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName, 'locale': locale, if (phone != null) 'phone': phone},
    );
    if (res.user != null && (res.user!.identities?.isEmpty ?? true)) {
      throw Exception('user_already_exists');
    }
    return res.session != null;
  }

  Future<void> verifyEmailCode({required String email, required String token}) =>
      _client.auth.verifyOTP(type: OtpType.signup, email: email, token: token);

  Future<void> resendEmailCode(String email) =>
      _client.auth.resend(type: OtpType.signup, email: email);

  Future<void> signIn({required String email, required String password}) =>
      _client.auth.signInWithPassword(email: email, password: password);

  /// Enlace mágico / OTP por email (sin contraseña), útil para clientes.
  Future<void> signInWithOtp(String email) =>
      _client.auth.signInWithOtp(email: email);

  Future<void> verifyLoginOtp({required String email, required String token}) =>
      _client.auth.verifyOTP(type: OtpType.email, email: email, token: token);

  Future<void> resetPassword(String email) =>
      _client.auth.resetPasswordForEmail(email);

  Future<void> signOut() => _client.auth.signOut();

  Future<void> sendPhoneOtp(String phoneE164) =>
      _client.auth.updateUser(UserAttributes(phone: phoneE164));

  Future<void> verifyPhoneOtp({required String phoneE164, required String token}) async {
    await _client.auth.verifyOTP(type: OtpType.phoneChange, phone: phoneE164, token: token);
    await _client.from('profiles')
        .update({'phone_verified': true, 'phone': phoneE164})
        .eq('id', currentUser!.id);
  }

  Future<Profile?> fetchMyProfile() async {
    final user = currentUser;
    if (user == null) return null;
    final data = await _client.from('profiles').select().eq('id', user.id).maybeSingle();
    return data == null ? null : Profile.fromMap(data);
  }

  Future<void> updateMyProfile(Map<String, dynamic> fields) =>
      _client.from('profiles').update(fields).eq('id', currentUser!.id);
}
