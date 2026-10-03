import 'package:supabase_flutter/supabase_flutter.dart';

/// Traduce errores técnicos (Supabase/PostgREST/RPC) a mensajes claros.
String friendlyError(Object error) {
  final raw = error is PostgrestException
      ? error.message
      : error is AuthException
          ? error.message
          : error is FunctionException
              ? (error.details?.toString() ?? error.reasonPhrase ?? 'Error')
              : error.toString();
  final msg = raw.replaceFirst('Exception: ', '');

  const map = <String, String>{
    'not_authenticated': 'Tienes que iniciar sesión.',
    'forbidden': 'No tienes permiso para esta acción.',
    'business_not_found': 'El negocio no existe.',
    'service_not_found': 'El servicio ya no está disponible.',
    'booking_not_found': 'La reserva no existe.',
    'slot_unavailable': 'Ese hueco ya no está disponible. Elige otro, por favor.',
    'too_soon': 'La hora elegida es demasiado próxima. Elige una más tarde.',
    'too_late_to_reschedule': 'Ya no se puede cambiar la hora: ha pasado el plazo de la política de cancelación.',
    'online_booking_disabled': 'Este negocio no admite reservas online ahora mismo.',
    'customer_blocked': 'No puedes reservar en este negocio. Contacta con ellos directamente.',
    'invalid_promo': 'El código promocional no es válido.',
    'invalid_state': 'La reserva ya está cerrada.',
    'empty_booking': 'Añade al menos un servicio.',
    'already_invoiced': 'Esta reserva ya tiene factura.',
    'not_reviewable': 'Solo puedes valorar citas completadas.',
    'user_already_exists': 'Ya existe una cuenta con ese email. Inicia sesión.',
    'Invalid login credentials': 'Email o contraseña incorrectos.',
    'Email not confirmed': 'Confirma tu email antes de entrar.',
    'duplicate key value violates unique constraint "businesses_slug_key"':
        'Esa dirección web ya está en uso. Elige otra.',
    'Token has expired or is invalid': 'El código ha caducado o no es válido.',
  };
  for (final e in map.entries) {
    if (msg.contains(e.key)) return e.value;
  }
  if (msg.contains('SocketException') || msg.contains('Failed host lookup')) {
    return 'Sin conexión. Comprueba tu internet.';
  }
  if (msg.contains('Password should be')) {
    return 'La contraseña debe tener al menos 6 caracteres.';
  }
  return msg.length > 160 ? 'Se ha producido un error. Inténtalo de nuevo.' : msg;
}
