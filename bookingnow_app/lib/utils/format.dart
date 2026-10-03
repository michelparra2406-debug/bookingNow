import 'package:intl/intl.dart';

/// Formateadores de fecha/hora en español (Europe/Madrid vía hora local).
class Fmt {
  static final _time = DateFormat('HH:mm', 'es');
  static final _dayShort = DateFormat('EEE d MMM', 'es');
  static final _dayLong = DateFormat("EEEE d 'de' MMMM", 'es');
  static final _date = DateFormat('dd/MM/yyyy', 'es');
  static final _dateTime = DateFormat("EEE d MMM · HH:mm", 'es');
  static final _month = DateFormat('MMMM yyyy', 'es');

  static String time(DateTime d) => _time.format(d);
  static String dayShort(DateTime d) => _cap(_dayShort.format(d));
  static String dayLong(DateTime d) => _cap(_dayLong.format(d));
  static String date(DateTime d) => _date.format(d);
  static String dateTime(DateTime d) => _cap(_dateTime.format(d));
  static String month(DateTime d) => _cap(_month.format(d));
  static String range(DateTime a, DateTime b) => '${time(a)} – ${time(b)}';

  static String duration(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '$h h' : '$h h $m min';
  }

  static String relativeDay(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = day.difference(today).inDays;
    if (diff == 0) return 'Hoy';
    if (diff == 1) return 'Mañana';
    if (diff == -1) return 'Ayer';
    return dayShort(d);
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static const weekdaysShort = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'];
  static const weekdaysLong = ['Domingo', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado'];

  static String bookingStatus(String s) {
    switch (s) {
      case 'pending':
        return 'Pendiente';
      case 'confirmed':
        return 'Confirmada';
      case 'checked_in':
        return 'En curso';
      case 'completed':
        return 'Completada';
      case 'cancelled':
        return 'Cancelada';
      case 'no_show':
        return 'No presentado';
      default:
        return s;
    }
  }

  static String paymentMethod(String? s) {
    switch (s) {
      case 'cash':
        return 'Efectivo';
      case 'card':
        return 'Tarjeta';
      case 'bizum':
        return 'Bizum';
      case 'transfer':
        return 'Transferencia';
      case 'stripe':
        return 'Online (Stripe)';
      case 'redsys':
        return 'Online (Redsys)';
      case 'package':
        return 'Bono';
      default:
        return s ?? '—';
    }
  }
}
