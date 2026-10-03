/// Configuración de la app. Los valores se inyectan en compilación:
///
/// flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///             --dart-define=SUPABASE_ANON_KEY=eyJ...
class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://TU-PROYECTO.supabase.co',
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'TU_ANON_KEY',
  );

  /// Dominio público de la página de reservas (web): https://<host>/b/<slug>
  static const publicBookingHost = String.fromEnvironment(
    'PUBLIC_BOOKING_HOST',
    defaultValue: 'https://bookingnow.app',
  );

  /// Clave publicable de Stripe (señales/depósitos con tarjeta y Bizum).
  static const stripePublishableKey =
      String.fromEnvironment('STRIPE_PUBLISHABLE_KEY', defaultValue: '');

  static bool get isConfigured =>
      !supabaseUrl.contains('TU-PROYECTO') && supabaseAnonKey != 'TU_ANON_KEY';

  /// Ancho a partir del cual se muestra el panel web (NavigationRail).
  static const double desktopBreakpoint = 900;
}
