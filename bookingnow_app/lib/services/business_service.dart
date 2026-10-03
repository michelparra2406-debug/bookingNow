import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';

/// Acceso a datos del lado NEGOCIO (app Biz y panel web): agenda, clientes,
/// catálogo, equipo, horarios, facturación, integraciones, ajustes.
class BusinessService {
  final SupabaseClient _client = Supabase.instance.client;

  String get _uid => _client.auth.currentUser!.id;

  // ---------- Negocio ----------

  Future<String> createBusiness({
    required String name,
    required String sectorId,
    required String slug,
    String? phone,
    String? city,
  }) async {
    final id = await _client.rpc('create_business', params: {
      'p_name': name, 'p_sector': sectorId, 'p_slug': slug, 'p_phone': phone, 'p_city': city,
    });
    return id as String;
  }

  Future<bool> isSlugTaken(String slug) async {
    final data = await _client.from('businesses').select('id').eq('slug', slug.toLowerCase()).limit(1);
    return (data as List).isNotEmpty;
  }

  Future<Business?> fetchBusiness(String id) async {
    final data = await _client.from('businesses').select().eq('id', id).maybeSingle();
    return data == null ? null : Business.fromMap(data);
  }

  Future<void> updateBusiness(String id, Map<String, dynamic> fields) =>
      _client.from('businesses').update(fields).eq('id', id);

  Future<BusinessKpis> fetchKpis(String businessId) async {
    final data = await _client.from('v_business_kpis').select().eq('business_id', businessId).maybeSingle();
    return data == null ? BusinessKpis() : BusinessKpis.fromMap(data);
  }

  Future<List<Sector>> fetchSectors() async {
    final data = await _client.from('sectors').select().order('sort_order');
    return (data as List).map((m) => Sector.fromMap(m)).toList();
  }

  // ---------- Sedes ----------

  Future<List<Location>> fetchLocations(String businessId) async {
    final data = await _client.from('locations').select()
        .eq('business_id', businessId).order('is_default', ascending: false);
    return (data as List).map((m) => Location.fromMap(m)).toList();
  }

  Future<void> upsertLocation(Map<String, dynamic> fields) =>
      _client.from('locations').upsert(fields);

  // ---------- Equipo ----------

  Future<List<Member>> fetchMembers(String businessId, {bool onlyActive = false}) async {
    var q = _client.from('business_members').select().eq('business_id', businessId);
    if (onlyActive) q = q.eq('active', true);
    final data = await q.order('sort_order');
    return (data as List).map((m) => Member.fromMap(m)).toList();
  }

  Future<Member?> fetchMyMembership(String businessId) async {
    final data = await _client.from('business_members').select()
        .eq('business_id', businessId).eq('user_id', _uid).maybeSingle();
    return data == null ? null : Member.fromMap(data);
  }

  Future<Member> upsertMember(Map<String, dynamic> fields) async {
    final data = await _client.from('business_members').upsert(fields).select().single();
    return Member.fromMap(data);
  }

  Future<void> inviteMember(String businessId, String email, String role) =>
      _client.from('member_invites').insert({'business_id': businessId, 'email': email, 'role': role});

  // ---------- Horarios ----------

  Future<List<WorkingHours>> fetchWorkingHours(String businessId, {String? memberId}) async {
    var q = _client.from('working_hours').select().eq('business_id', businessId);
    if (memberId != null) q = q.eq('member_id', memberId);
    final data = await q.order('weekday').order('start_time');
    return (data as List).map((m) => WorkingHours.fromMap(m)).toList();
  }

  /// Sustituye el horario semanal completo de un profesional.
  Future<void> replaceWorkingHours(String businessId, String memberId, List<WorkingHours> hours) async {
    await _client.from('working_hours').delete().eq('business_id', businessId).eq('member_id', memberId);
    if (hours.isNotEmpty) {
      await _client.from('working_hours').insert(hours.map((h) => h.toInsert()).toList());
    }
  }

  Future<void> addScheduleOverride({
    required String businessId, String? memberId, required DateTime date,
    bool isClosed = true, String? startTime, String? endTime, String? reason,
  }) => _client.from('schedule_overrides').insert({
        'business_id': businessId, 'member_id': memberId, 'date': _dateOnly(date),
        'is_closed': isClosed, 'start_time': startTime, 'end_time': endTime, 'reason': reason,
      });

  Future<List<Map<String, dynamic>>> fetchScheduleOverrides(String businessId, DateTime from, DateTime to) async {
    final data = await _client.from('schedule_overrides').select().eq('business_id', businessId)
        .gte('date', _dateOnly(from)).lte('date', _dateOnly(to)).order('date');
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<void> deleteScheduleOverride(String id) =>
      _client.from('schedule_overrides').delete().eq('id', id);

  Future<void> addTimeBlock({
    required String businessId, String? memberId, required DateTime startsAt,
    required DateTime endsAt, String? title,
  }) => _client.from('time_blocks').insert({
        'business_id': businessId, 'member_id': memberId,
        'starts_at': startsAt.toUtc().toIso8601String(),
        'ends_at': endsAt.toUtc().toIso8601String(), 'title': title,
      });

  Future<List<Map<String, dynamic>>> fetchTimeBlocks(String businessId, DateTime from, DateTime to) async {
    final data = await _client.from('time_blocks').select().eq('business_id', businessId)
        .gte('starts_at', from.toUtc().toIso8601String()).lt('starts_at', to.toUtc().toIso8601String());
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<void> deleteTimeBlock(String id) => _client.from('time_blocks').delete().eq('id', id);

  // ---------- Catálogo ----------

  Future<List<ServiceCategory>> fetchCategories(String businessId) async {
    final data = await _client.from('service_categories').select()
        .eq('business_id', businessId).order('sort_order');
    return (data as List).map((m) => ServiceCategory.fromMap(m)).toList();
  }

  Future<ServiceCategory> upsertCategory(Map<String, dynamic> fields) async {
    final data = await _client.from('service_categories').upsert(fields).select().single();
    return ServiceCategory.fromMap(data);
  }

  Future<void> deleteCategory(String id) => _client.from('service_categories').delete().eq('id', id);

  Future<List<Service>> fetchServices(String businessId, {bool includeInactive = true}) async {
    var q = _client.from('services')
        .select('*, service_variants(*), service_addon_links(service_addons(*)), service_staff(member_id)')
        .eq('business_id', businessId);
    if (!includeInactive) q = q.eq('active', true);
    final data = await q.order('sort_order');
    return (data as List).map((m) => Service.fromMap(m)).toList();
  }

  /// Crea/actualiza un servicio con sus variantes y profesionales asignados.
  Future<String> saveService({
    String? id,
    required Map<String, dynamic> fields,
    required List<Map<String, dynamic>> variants,   // {name, duration_min, price_cents}
    required List<String> staffIds,
    List<String> addonIds = const [],
  }) async {
    final row = await _client.from('services').upsert({if (id != null) 'id': id, ...fields}).select('id').single();
    final sid = row['id'] as String;
    await _client.from('service_variants').delete().eq('service_id', sid);
    if (variants.isNotEmpty) {
      await _client.from('service_variants').insert(
          variants.map((v) => {...v, 'service_id': sid}).toList());
    }
    await _client.from('service_staff').delete().eq('service_id', sid);
    if (staffIds.isNotEmpty) {
      await _client.from('service_staff').insert(
          staffIds.map((m) => {'service_id': sid, 'member_id': m}).toList());
    }
    await _client.from('service_addon_links').delete().eq('service_id', sid);
    if (addonIds.isNotEmpty) {
      await _client.from('service_addon_links').insert(
          addonIds.map((a) => {'service_id': sid, 'addon_id': a}).toList());
    }
    return sid;
  }

  Future<void> deleteService(String id) => _client.from('services').delete().eq('id', id);

  Future<List<ServiceAddon>> fetchAddons(String businessId) async {
    final data = await _client.from('service_addons').select().eq('business_id', businessId).order('name');
    return (data as List).map((m) => ServiceAddon.fromMap(m)).toList();
  }

  Future<void> upsertAddon(Map<String, dynamic> fields) => _client.from('service_addons').upsert(fields);

  // ---------- Clientes ----------

  Future<List<Customer>> fetchCustomers(String businessId, {String? query, int limit = 200}) async {
    var q = _client.from('customers').select().eq('business_id', businessId);
    if (query != null && query.trim().isNotEmpty) {
      final t = '%${query.trim()}%';
      q = q.or('full_name.ilike.$t,email.ilike.$t,phone.ilike.$t');
    }
    final data = await q.order('full_name').limit(limit);
    return (data as List).map((m) => Customer.fromMap(m)).toList();
  }

  Future<Customer?> fetchCustomer(String id) async {
    final data = await _client.from('customers').select().eq('id', id).maybeSingle();
    return data == null ? null : Customer.fromMap(data);
  }

  Future<Customer> upsertCustomer(Map<String, dynamic> fields) async {
    final data = await _client.from('customers').upsert(fields).select().single();
    return Customer.fromMap(data);
  }

  /// Importación masiva (CSV ya parseado a filas con full_name/email/phone/tax_id/notes).
  Future<int> importCustomers(String businessId, List<Map<String, dynamic>> rows) async {
    final n = await _client.rpc('import_customers', params: {'p_business': businessId, 'p_rows': rows});
    return (n as num).toInt();
  }

  Future<List<Booking>> fetchCustomerBookings(String customerId) async {
    final data = await _client.from('v_bookings_full').select()
        .eq('customer_id', customerId).order('starts_at', ascending: false).limit(50);
    return (data as List).map((m) => Booking.fromMap(m)).toList();
  }

  Future<List<CustomerPackage>> fetchCustomerPackages(String customerId) async {
    final data = await _client.from('customer_packages').select('*, packages(name)')
        .eq('customer_id', customerId).order('created_at', ascending: false);
    return (data as List).map((m) => CustomerPackage.fromMap(m)).toList();
  }

  // ---------- Agenda / reservas ----------

  Future<List<Booking>> fetchBookings(String businessId, {
    required DateTime from, required DateTime to, String? memberId, List<String>? statuses,
  }) async {
    var q = _client.from('v_bookings_full').select().eq('business_id', businessId)
        .gte('starts_at', from.toUtc().toIso8601String())
        .lt('starts_at', to.toUtc().toIso8601String());
    if (memberId != null) q = q.eq('member_id', memberId);
    if (statuses != null) q = q.inFilter('status', statuses);
    final data = await q.order('starts_at');
    return (data as List).map((m) => Booking.fromMap(m)).toList();
  }

  Future<List<Booking>> fetchPendingBookings(String businessId) async {
    final data = await _client.from('v_bookings_full').select().eq('business_id', businessId)
        .eq('status', 'pending').gte('starts_at', DateTime.now().toUtc().toIso8601String())
        .order('starts_at');
    return (data as List).map((m) => Booking.fromMap(m)).toList();
  }

  Future<Booking?> fetchBooking(String id) async {
    final data = await _client.from('v_bookings_full').select().eq('id', id).maybeSingle();
    if (data == null) return null;
    final items = await _client.from('booking_items').select().eq('booking_id', id).order('sort_order');
    return Booking.fromMap({...data, 'booking_items': items});
  }

  /// Alta manual desde la agenda (walk-in, teléfono). Sin validación de
  /// antelación; sí de solapes.
  Future<Booking> createBooking({
    required String businessId,
    required String customerId,
    required String? memberId,
    required DateTime startsAt,
    required List<Map<String, dynamic>> items,
    String? notes,
    String source = 'admin',
  }) async {
    final data = await _client.rpc('create_booking', params: {
      'p_business': businessId,
      'p_member': memberId,
      'p_starts_at': startsAt.toUtc().toIso8601String(),
      'p_items': items,
      'p_customer': customerId,
      'p_notes': notes,
      'p_source': source,
    });
    return Booking.fromMap(data as Map<String, dynamic>);
  }

  Future<Booking> setStatus(String bookingId, String status) async {
    final data = await _client.rpc('set_booking_status', params: {'p_booking': bookingId, 'p_status': status});
    return Booking.fromMap(data as Map<String, dynamic>);
  }

  Future<Booking> cancel(String bookingId, {String? reason}) async {
    final data = await _client.rpc('cancel_booking', params: {'p_booking': bookingId, 'p_reason': reason});
    return Booking.fromMap(data as Map<String, dynamic>);
  }

  Future<Booking> reschedule(String bookingId, DateTime startsAt, {String? memberId}) async {
    final data = await _client.rpc('reschedule_booking', params: {
      'p_booking': bookingId, 'p_starts_at': startsAt.toUtc().toIso8601String(), 'p_member': memberId,
    });
    return Booking.fromMap(data as Map<String, dynamic>);
  }

  Future<void> updateBookingNotes(String bookingId, String notes) =>
      _client.from('bookings').update({'internal_notes': notes}).eq('id', bookingId);

  Future<int> makeRecurring(String bookingId, {required int everyDays, required int count}) async {
    final n = await _client.rpc('create_recurring_bookings', params: {
      'p_booking': bookingId, 'p_every_days': everyDays, 'p_count': count,
    });
    return (n as num).toInt();
  }

  Future<List<Slot>> fetchSlots({
    required String businessId, required String serviceId, required DateTime date,
    String? memberId, int stepMin = 15,
  }) async {
    final data = await _client.rpc('get_available_slots', params: {
      'p_business': businessId, 'p_service': serviceId, 'p_date': _dateOnly(date),
      'p_member': memberId, 'p_step_min': stepMin,
    }) as List;
    return data.map((m) => Slot.fromMap(m)).toList();
  }

  // ---------- Lista de espera ----------

  Future<List<WaitlistEntry>> fetchWaitlist(String businessId) async {
    final data = await _client.from('waitlist').select('*, customers(full_name), services(name)')
        .eq('business_id', businessId).inFilter('status', ['waiting', 'notified']).order('date_from');
    return (data as List).map((m) => WaitlistEntry.fromMap(m)).toList();
  }

  Future<void> updateWaitlistStatus(String id, String status) =>
      _client.from('waitlist').update({'status': status}).eq('id', id);

  // ---------- Valoraciones ----------

  Future<List<Review>> fetchReviews(String businessId) async {
    final data = await _client.from('reviews').select('*, customers(full_name)')
        .eq('business_id', businessId).order('created_at', ascending: false).limit(100);
    return (data as List).map((m) => Review.fromMap(m)).toList();
  }

  Future<void> replyReview(String id, String reply) =>
      _client.from('reviews').update({'reply': reply, 'replied_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);

  // ---------- Bonos, membresías, promociones ----------

  Future<List<Package>> fetchPackages(String businessId) async {
    final data = await _client.from('packages').select().eq('business_id', businessId).order('name');
    return (data as List).map((m) => Package.fromMap(m)).toList();
  }

  Future<void> upsertPackage(Map<String, dynamic> fields) => _client.from('packages').upsert(fields);

  Future<void> sellPackage({
    required String businessId, required String packageId, required String customerId,
    int? sessionsTotal, int? balanceCents, DateTime? validUntil, String? paymentRef,
  }) => _client.from('customer_packages').insert({
        'business_id': businessId, 'package_id': packageId, 'customer_id': customerId,
        'sessions_total': sessionsTotal, 'balance_cents': balanceCents,
        'valid_until': validUntil == null ? null : _dateOnly(validUntil), 'payment_ref': paymentRef,
      });

  Future<List<Map<String, dynamic>>> fetchPromoCodes(String businessId) async {
    final data = await _client.from('promo_codes').select().eq('business_id', businessId).order('code');
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<void> upsertPromoCode(Map<String, dynamic> fields) =>
      _client.from('promo_codes').upsert({...fields, 'code': (fields['code'] as String).toUpperCase()});

  // ---------- Facturación ----------

  Future<Invoice> issueInvoice({
    required String bookingId,
    String paymentMethod = 'card',
    String? recipientName,
    String? recipientTaxId,
    String? recipientAddress,
    String series = 'F',
  }) async {
    final data = await _client.rpc('issue_invoice', params: {
      'p_booking': bookingId, 'p_payment_method': paymentMethod,
      'p_recipient_name': recipientName, 'p_recipient_tax_id': recipientTaxId,
      'p_recipient_address': recipientAddress, 'p_series': series,
    });
    return Invoice.fromMap(data as Map<String, dynamic>);
  }

  Future<List<Invoice>> fetchInvoices(String businessId, {DateTime? from, DateTime? to, int limit = 200}) async {
    var q = _client.from('invoices').select('*, invoice_lines(*)').eq('business_id', businessId);
    if (from != null) q = q.gte('issue_date', _dateOnly(from));
    if (to != null) q = q.lte('issue_date', _dateOnly(to));
    final data = await q.order('issue_date', ascending: false).order('number', ascending: false).limit(limit);
    return (data as List).map((m) => Invoice.fromMap(m)).toList();
  }

  Future<Invoice?> fetchInvoice(String id) async {
    final data = await _client.from('invoices').select('*, invoice_lines(*)').eq('id', id).maybeSingle();
    return data == null ? null : Invoice.fromMap(data);
  }

  /// Reencola la sincronización de una factura con el software externo.
  Future<void> resyncInvoice(String businessId, String invoiceId, String provider) =>
      _client.from('sync_jobs').insert({
        'business_id': businessId, 'provider': provider, 'entity': 'invoice', 'entity_id': invoiceId,
      });

  Future<List<Map<String, dynamic>>> fetchSyncJobs(String businessId, {int limit = 50}) async {
    final data = await _client.from('sync_jobs').select().eq('business_id', businessId)
        .order('created_at', ascending: false).limit(limit);
    return (data as List).cast<Map<String, dynamic>>();
  }

  // ---------- Integraciones ----------

  Future<List<Integration>> fetchIntegrations(String businessId) async {
    final data = await _client.from('v_integrations_public').select().eq('business_id', businessId);
    return (data as List).map((m) => Integration.fromMap(m)).toList();
  }

  /// Guarda credenciales. Solo las Edge Functions (service_role) las leen.
  Future<void> saveIntegration({
    required String businessId,
    required String provider,
    required String category,
    required Map<String, dynamic> credentials,
    Map<String, dynamic> settings = const {},
    bool enabled = true,
  }) => _client.from('integrations').upsert({
        'business_id': businessId, 'provider': provider, 'category': category,
        'credentials': credentials, 'settings': settings, 'enabled': enabled,
      }, onConflict: 'business_id,provider');

  Future<void> setIntegrationEnabled(String id, bool enabled) =>
      _client.from('integrations').update({'enabled': enabled}).eq('id', id);

  Future<void> deleteIntegration(String id) => _client.from('integrations').delete().eq('id', id);

  /// Prueba la conexión invocando la Edge Function (valida credenciales).
  Future<Map<String, dynamic>> testIntegration(String businessId, String provider) async {
    final res = await _client.functions.invoke('invoice-sync', body: {
      'type': 'test', 'business_id': businessId, 'provider': provider,
    });
    return (res.data as Map?)?.cast<String, dynamic>() ?? {'ok': false};
  }

  // ---------- Notificaciones ----------

  Future<Map<String, dynamic>?> fetchNotificationSettings(String businessId) async {
    final data = await _client.from('notification_settings').select().eq('business_id', businessId).maybeSingle();
    return data;
  }

  Future<void> saveNotificationSettings(String businessId, Map<String, dynamic> fields) =>
      _client.from('notification_settings').upsert({'business_id': businessId, ...fields});

  /// Envío de campaña (email/SMS/WhatsApp/push) a un segmento de clientes.
  Future<int> sendCampaign({
    required String businessId, required String channel, required String title,
    required String body, List<String>? customerIds,
  }) async {
    final customers = customerIds != null
        ? await _client.from('customers').select('id, user_id, email, phone').inFilter('id', customerIds)
        : await _client.from('customers').select('id, user_id, email, phone').eq('business_id', businessId);
    final rows = (customers as List).map((c) => {
          'business_id': businessId, 'customer_id': c['id'], 'user_id': c['user_id'],
          'channel': channel, 'template': 'marketing',
          'payload': {'title': title, 'body': body},
        }).toList();
    if (rows.isNotEmpty) await _client.from('notifications').insert(rows);
    return rows.length;
  }

  // ---------- Informes ----------

  /// Reservas completadas agrupadas por día en un rango (para gráficos).
  Future<List<Booking>> fetchCompletedBookings(String businessId, DateTime from, DateTime to) =>
      fetchBookings(businessId, from: from, to: to, statuses: ['completed', 'no_show', 'cancelled']);

  Future<List<Map<String, dynamic>>> fetchAuditLog(String businessId, {int limit = 100}) async {
    final data = await _client.from('audit_log').select().eq('business_id', businessId)
        .order('created_at', ascending: false).limit(limit);
    return (data as List).cast<Map<String, dynamic>>();
  }

  static String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
