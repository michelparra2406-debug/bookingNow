import 'package:supabase_flutter/supabase_flutter.dart';

import 'business_service.dart';

/// Consultas auxiliares de las pantallas de agenda/CRM que no están en
/// [BusinessService]. Las extensiones no acceden a `_client`, por lo que
/// usamos el cliente global.
extension AgendaExtra on BusinessService {
  SupabaseClient get _db => Supabase.instance.client;

  /// Fecha de consentimiento RGPD del cliente (no está en el modelo Customer).
  Future<DateTime?> fetchGdprConsent(String customerId) async {
    final data = await _db
        .from('customers')
        .select('gdpr_consent_at')
        .eq('id', customerId)
        .maybeSingle();
    final v = data?['gdpr_consent_at'];
    return v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
  }

  /// Marca el consentimiento RGPD como otorgado ahora (o lo retira con null).
  Future<void> setGdprConsent(String customerId, DateTime? at) => _db
      .from('customers')
      .update({'gdpr_consent_at': at?.toUtc().toIso8601String()})
      .eq('id', customerId);

  /// Actualización parcial de un cliente (evita el upsert con columnas NOT NULL).
  Future<void> patchCustomer(String customerId, Map<String, dynamic> fields) =>
      _db.from('customers').update(fields).eq('id', customerId);
}
