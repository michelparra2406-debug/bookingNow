// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appName => 'BookingNow';

  @override
  String get tabExplore => 'Explorar';

  @override
  String get tabBookings => 'Mis citas';

  @override
  String get tabProfile => 'Perfil';

  @override
  String get navDashboard => 'Inicio';

  @override
  String get navAgenda => 'Agenda';

  @override
  String get navCustomers => 'Clientes';

  @override
  String get navServices => 'Servicios';

  @override
  String get navTeam => 'Equipo';

  @override
  String get navInvoices => 'Facturas';

  @override
  String get navPackages => 'Bonos';

  @override
  String get navWaitlist => 'Lista de espera';

  @override
  String get navReports => 'Informes';

  @override
  String get navIntegrations => 'Integraciones';

  @override
  String get navSettings => 'Ajustes';

  @override
  String get navMarketing => 'Marketing';

  @override
  String get switchToClient => 'Modo cliente';

  @override
  String get switchToBusiness => 'Modo negocio';

  @override
  String get createBusiness => 'Crear mi negocio';

  @override
  String get signOut => 'Cerrar sesión';

  @override
  String get login => 'Iniciar sesión';

  @override
  String get register => 'Crear cuenta';

  @override
  String get email => 'Email';

  @override
  String get password => 'Contraseña';

  @override
  String get fullName => 'Nombre completo';

  @override
  String get phone => 'Teléfono';

  @override
  String get continueLabel => 'Continuar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get save => 'Guardar';

  @override
  String get delete => 'Eliminar';

  @override
  String get search => 'Buscar';

  @override
  String get today => 'Hoy';

  @override
  String get notConfigured =>
      'La app no está conectada a Supabase. Compila con --dart-define=SUPABASE_URL y SUPABASE_ANON_KEY.';
}
