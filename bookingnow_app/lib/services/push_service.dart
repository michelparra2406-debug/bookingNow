import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Notificaciones push (FCM). En web se omite: ahí se usan email/WhatsApp.
/// Requiere google-services.json / GoogleService-Info.plist en el proyecto.
class PushService {
  static bool _ready = false;

  static Future<void> init() async {
    if (kIsWeb) return;
    try {
      await Firebase.initializeApp();
      _ready = true;
      final m = FirebaseMessaging.instance;
      await m.requestPermission(alert: true, badge: true, sound: true);
      m.onTokenRefresh.listen(_saveToken);
    } catch (e) {
      debugPrint('Push desactivado: $e');
    }
  }

  /// Registra el token del dispositivo para el usuario con sesión.
  static Future<void> register() async {
    if (!_ready) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _saveToken(token);
    } catch (e) {
      debugPrint('No se pudo registrar el token push: $e');
    }
  }

  static Future<void> _saveToken(String token) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    await Supabase.instance.client.from('device_tokens').upsert({
      'user_id': uid,
      'token': token,
      'platform': Platform.isIOS ? 'ios' : 'android',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static Future<void> unregister() async {
    if (!_ready) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (token != null && uid != null) {
        await Supabase.instance.client.from('device_tokens').delete()
            .eq('user_id', uid).eq('token', token);
      }
    } catch (_) {}
  }

  static Stream<RemoteMessage> get onMessage =>
      _ready ? FirebaseMessaging.onMessage : const Stream.empty();
}
