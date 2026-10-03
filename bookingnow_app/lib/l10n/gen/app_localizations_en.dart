// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'BookingNow';

  @override
  String get tabExplore => 'Explore';

  @override
  String get tabBookings => 'My bookings';

  @override
  String get tabProfile => 'Profile';

  @override
  String get navDashboard => 'Home';

  @override
  String get navAgenda => 'Calendar';

  @override
  String get navCustomers => 'Customers';

  @override
  String get navServices => 'Services';

  @override
  String get navTeam => 'Team';

  @override
  String get navInvoices => 'Invoices';

  @override
  String get navPackages => 'Packages';

  @override
  String get navWaitlist => 'Waitlist';

  @override
  String get navReports => 'Reports';

  @override
  String get navIntegrations => 'Integrations';

  @override
  String get navSettings => 'Settings';

  @override
  String get navMarketing => 'Marketing';

  @override
  String get switchToClient => 'Client mode';

  @override
  String get switchToBusiness => 'Business mode';

  @override
  String get createBusiness => 'Create my business';

  @override
  String get signOut => 'Sign out';

  @override
  String get login => 'Sign in';

  @override
  String get register => 'Create account';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get fullName => 'Full name';

  @override
  String get phone => 'Phone';

  @override
  String get continueLabel => 'Continue';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get search => 'Search';

  @override
  String get today => 'Today';

  @override
  String get notConfigured =>
      'The app is not connected to Supabase. Build with --dart-define=SUPABASE_URL and SUPABASE_ANON_KEY.';
}
