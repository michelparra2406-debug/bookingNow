import 'package:supabase_flutter/supabase_flutter.dart';

import 'business_service.dart';

/// Consultas adicionales del panel de administración que no están en
/// [BusinessService] (que no se modifica porque lo usan otras pantallas).
extension AdminExtra on BusinessService {
  SupabaseClient get _db => Supabase.instance.client;

  // ---------- Catálogo ----------

  /// Actualiza columnas sueltas de un servicio (p. ej. `active`) sin tocar
  /// variantes ni asignaciones.
  Future<void> updateServiceFields(String id, Map<String, dynamic> fields) =>
      _db.from('services').update(fields).eq('id', id);

  Future<void> deleteAddon(String id) =>
      _db.from('service_addons').delete().eq('id', id);

  // ---------- Bonos / promociones ----------

  Future<void> deletePackage(String id) =>
      _db.from('packages').delete().eq('id', id);

  Future<void> deletePromoCode(String id) =>
      _db.from('promo_codes').delete().eq('id', id);

  // ---------- Negocio / sedes ----------

  /// Columnas del negocio que no expone el modelo `Business`
  /// (régimen de IVA, país fiscal, fin del plan).
  Future<Map<String, dynamic>> fetchBusinessExtras(String businessId) async {
    final data = await _db
        .from('businesses')
        .select('vat_regime, fiscal_country, plan_valid_until')
        .eq('id', businessId)
        .maybeSingle();
    return data ?? const {};
  }

  /// Sedes con todas las columnas (incluye `travel_radius_km`).
  Future<List<Map<String, dynamic>>> fetchLocationsRaw(String businessId) async {
    final data = await _db
        .from('locations')
        .select()
        .eq('business_id', businessId)
        .order('is_default', ascending: false)
        .order('name');
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<void> deleteLocation(String id) =>
      _db.from('locations').delete().eq('id', id);

  /// Deja una única sede como predeterminada.
  Future<void> setDefaultLocation(String businessId, String locationId) async {
    await _db
        .from('locations')
        .update({'is_default': false})
        .eq('business_id', businessId);
    await _db.from('locations').update({'is_default': true}).eq('id', locationId);
  }
}
