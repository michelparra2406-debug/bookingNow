import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'auth_service.dart';
import 'business_service.dart';
import 'data_service.dart';

/// Estado global de sesión: perfil, negocio activo (modo negocio) y rol.
/// Un mismo usuario puede ser cliente y además miembro de uno o varios
/// negocios; la app cambia de "modo" según `activeBusiness`.
class AppSession extends ChangeNotifier {
  static final AppSession instance = AppSession._();
  AppSession._();

  final auth = AuthService();
  final data = DataService();
  final biz = BusinessService();

  Profile? profile;
  List<Member> memberships = [];
  Business? activeBusiness;
  Member? activeMembership;
  Sector? activeSector;
  List<Sector> sectors = [];

  bool get isLoggedIn => auth.isLoggedIn;
  bool get isBusinessMode => activeBusiness != null;
  bool get hasBusinesses => memberships.isNotEmpty;

  /// Etiqueta adaptada al sector ("Paciente", "Alumno", "Cliente"…).
  String get customerLabel => activeSector?.labelCustomer ?? 'Cliente';
  String get staffLabel => activeSector?.labelStaff ?? 'Profesional';
  String get bookingLabel => activeSector?.labelBooking ?? 'Cita';

  Future<void> load() async {
    if (!auth.isLoggedIn) {
      profile = null;
      memberships = [];
      activeBusiness = null;
      activeMembership = null;
      notifyListeners();
      return;
    }
    profile = await auth.fetchMyProfile();
    memberships = await data.fetchMyMemberships();
    if (sectors.isEmpty) {
      try {
        sectors = await data.fetchSectors();
      } catch (_) {}
    }
    // Restaurar el último negocio activo
    final prefs = await SharedPreferences.getInstance();
    final lastId = prefs.getString('active_business');
    final restore = memberships.where((m) => m.businessId == lastId).toList();
    if (restore.isNotEmpty) {
      await switchToBusiness(restore.first.businessId, persist: false);
    } else {
      notifyListeners();
    }
  }

  Future<void> switchToBusiness(String businessId, {bool persist = true}) async {
    activeBusiness = await biz.fetchBusiness(businessId);
    activeMembership = memberships.where((m) => m.businessId == businessId).firstOrNull
        ?? await biz.fetchMyMembership(businessId);
    activeSector = sectors.where((s) => s.id == activeBusiness?.sectorId).firstOrNull;
    if (persist) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active_business', businessId);
    }
    notifyListeners();
  }

  Future<void> switchToClientMode() async {
    activeBusiness = null;
    activeMembership = null;
    activeSector = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('active_business');
    notifyListeners();
  }

  Future<void> refreshActiveBusiness() async {
    if (activeBusiness != null) {
      activeBusiness = await biz.fetchBusiness(activeBusiness!.id);
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await auth.signOut();
    await switchToClientMode();
    await load();
  }
}
