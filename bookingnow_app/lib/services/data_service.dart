import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';

/// Acceso a datos del lado CLIENTE: marketplace, detalle de negocio,
/// disponibilidad, reservas propias, lista de espera, valoraciones.
class DataService {
  final SupabaseClient _client = Supabase.instance.client;

  String get _uid => _client.auth.currentUser!.id;

  // ---------- Catálogo ----------

  Future<List<Sector>> fetchSectors() async {
    final data = await _client.from('sectors').select().order('sort_order');
    return (data as List).map((m) => Sector.fromMap(m)).toList();
  }

  /// Negocios publicados. Filtro por texto (nombre/ciudad) y sector.
  Future<List<Business>> searchBusinesses({String? query, String? sectorId}) async {
    var q = _client.from('v_marketplace').select();
    if (sectorId != null && sectorId.isNotEmpty) q = q.eq('sector_id', sectorId);
    if (query != null && query.trim().isNotEmpty) {
      final t = '%${query.trim()}%';
      q = q.or('name.ilike.$t,city.ilike.$t,description.ilike.$t');
    }
    final data = await q.order('rating_avg', ascending: false).limit(100);
    return (data as List).map((m) => Business.fromMap(m)).toList();
  }

  Future<Business?> fetchBusiness(String id) async {
    final data = await _client.from('businesses').select().eq('id', id).maybeSingle();
    return data == null ? null : Business.fromMap(data);
  }

  Future<Business?> fetchBusinessBySlug(String slug) async {
    final data = await _client.from('businesses').select().eq('slug', slug).maybeSingle();
    return data == null ? null : Business.fromMap(data);
  }

  Future<List<Location>> fetchLocations(String businessId) async {
    final data = await _client.from('locations').select()
        .eq('business_id', businessId).eq('active', true).order('is_default', ascending: false);
    return (data as List).map((m) => Location.fromMap(m)).toList();
  }

  Future<List<ServiceCategory>> fetchCategories(String businessId) async {
    final data = await _client.from('service_categories').select()
        .eq('business_id', businessId).order('sort_order');
    return (data as List).map((m) => ServiceCategory.fromMap(m)).toList();
  }

  /// Servicios con variantes, extras y profesionales que los realizan.
  Future<List<Service>> fetchServices(String businessId, {bool onlyOnline = true}) async {
    var q = _client.from('services')
        .select('*, service_variants(*), service_addon_links(service_addons(*)), service_staff(member_id)')
        .eq('business_id', businessId).eq('active', true);
    if (onlyOnline) q = q.eq('online_bookable', true);
    final data = await q.order('sort_order');
    return (data as List).map((m) => Service.fromMap(m)).toList();
  }

  Future<List<Member>> fetchBookableMembers(String businessId) async {
    final data = await _client.from('business_members').select()
        .eq('business_id', businessId).eq('active', true).eq('bookable', true)
        .order('sort_order');
    return (data as List).map((m) => Member.fromMap(m)).toList();
  }

  Future<List<Review>> fetchReviews(String businessId, {int limit = 20}) async {
    final data = await _client.from('reviews').select('*, customers(full_name)')
        .eq('business_id', businessId).order('created_at', ascending: false).limit(limit);
    return (data as List).map((m) => Review.fromMap(m)).toList();
  }

  Future<List<Package>> fetchPackages(String businessId) async {
    final data = await _client.from('packages').select()
        .eq('business_id', businessId).eq('active', true).order('price_cents');
    return (data as List).map((m) => Package.fromMap(m)).toList();
  }

  // ---------- Disponibilidad ----------

  /// Huecos libres de un servicio en un día (calculados en servidor).
  Future<List<Slot>> fetchSlots({
    required String businessId,
    required String serviceId,
    required DateTime date,
    String? memberId,
    String? variantId,
    int stepMin = 15,
  }) async {
    final data = await _client.rpc('get_available_slots', params: {
      'p_business': businessId,
      'p_service': serviceId,
      'p_date': _dateOnly(date),
      'p_member': memberId,
      'p_variant': variantId,
      'p_step_min': stepMin,
    }) as List;
    return data.map((m) => Slot.fromMap(m)).toList();
  }

  /// Días con algún hueco en un rango (para marcar el calendario).
  Future<Set<DateTime>> fetchDaysWithSlots({
    required String businessId,
    required String serviceId,
    required DateTime from,
    required int days,
    String? memberId,
  }) async {
    final result = <DateTime>{};
    final futures = <Future<void>>[];
    for (var i = 0; i < days; i++) {
      final d = DateTime(from.year, from.month, from.day + i);
      futures.add(fetchSlots(
        businessId: businessId, serviceId: serviceId, date: d,
        memberId: memberId, stepMin: 30,
      ).then((s) { if (s.isNotEmpty) result.add(d); }).catchError((_) {}));
    }
    await Future.wait(futures);
    return result;
  }

  // ---------- Reservas ----------

  /// Crea la reserva (validación completa en servidor).
  /// [items]: [{service_id, variant_id?, addon_ids: []}]
  Future<Booking> createBooking({
    required String businessId,
    required String? memberId,
    required DateTime startsAt,
    required List<Map<String, dynamic>> items,
    String? notes,
    String? promoCode,
    String? locationId,
    String source = 'app',
  }) async {
    final data = await _client.rpc('create_booking', params: {
      'p_business': businessId,
      'p_member': memberId,
      'p_starts_at': startsAt.toUtc().toIso8601String(),
      'p_items': items,
      'p_notes': notes,
      'p_source': source,
      'p_promo_code': promoCode,
      'p_location': locationId,
    });
    return Booking.fromMap(data as Map<String, dynamic>);
  }

  Future<List<Booking>> fetchMyBookings({bool upcoming = true}) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    var q = _client.from('v_bookings_full').select();
    q = upcoming ? q.gte('ends_at', nowIso) : q.lt('ends_at', nowIso);
    final data = await q.order('starts_at', ascending: upcoming).limit(100);
    // RLS ya filtra a las reservas del usuario (cliente) — y a las de sus
    // negocios si además es miembro; filtramos las propias por customer.user_id
    final myCustomerIds = await _myCustomerIds();
    return (data as List).map((m) => Booking.fromMap(m))
        .where((b) => myCustomerIds.contains(b.customerId)).toList();
  }

  Future<Set<String>> _myCustomerIds() async {
    final data = await _client.from('customers').select('id').eq('user_id', _uid);
    return (data as List).map((m) => m['id'] as String).toSet();
  }

  Future<Booking?> fetchBooking(String id) async {
    final data = await _client.from('v_bookings_full').select().eq('id', id).maybeSingle();
    if (data == null) return null;
    final items = await _client.from('booking_items').select().eq('booking_id', id).order('sort_order');
    return Booking.fromMap({...data, 'booking_items': items});
  }

  Future<Booking> cancelBooking(String id, {String? reason}) async {
    final data = await _client.rpc('cancel_booking', params: {'p_booking': id, 'p_reason': reason});
    return Booking.fromMap(data as Map<String, dynamic>);
  }

  Future<Booking> rescheduleBooking(String id, DateTime startsAt, {String? memberId}) async {
    final data = await _client.rpc('reschedule_booking', params: {
      'p_booking': id,
      'p_starts_at': startsAt.toUtc().toIso8601String(),
      'p_member': memberId,
    });
    return Booking.fromMap(data as Map<String, dynamic>);
  }

  Future<int> makeRecurring(String bookingId, {required int everyDays, required int count}) async {
    final n = await _client.rpc('create_recurring_bookings', params: {
      'p_booking': bookingId, 'p_every_days': everyDays, 'p_count': count,
    });
    return (n as num).toInt();
  }

  Future<void> submitReview(String bookingId, int rating, {String? comment}) =>
      _client.rpc('submit_review', params: {
        'p_booking': bookingId, 'p_rating': rating, 'p_comment': comment,
      });

  // ---------- Lista de espera ----------

  Future<String> joinWaitlist({
    required String businessId,
    required String serviceId,
    required DateTime from,
    required DateTime to,
    String? memberId,
  }) async {
    final id = await _client.rpc('join_waitlist', params: {
      'p_business': businessId, 'p_service': serviceId,
      'p_date_from': _dateOnly(from), 'p_date_to': _dateOnly(to), 'p_member': memberId,
    });
    return id as String;
  }

  Future<List<WaitlistEntry>> fetchMyWaitlist() async {
    final ids = await _myCustomerIds();
    if (ids.isEmpty) return [];
    final data = await _client.from('waitlist').select('*, services(name)')
        .inFilter('customer_id', ids.toList()).inFilter('status', ['waiting', 'notified'])
        .order('date_from');
    return (data as List).map((m) => WaitlistEntry.fromMap(m)).toList();
  }

  Future<void> leaveWaitlist(String id) =>
      _client.from('waitlist').update({'status': 'cancelled'}).eq('id', id);

  // ---------- Mis bonos / facturas / notificaciones ----------

  Future<List<CustomerPackage>> fetchMyPackages() async {
    final ids = await _myCustomerIds();
    if (ids.isEmpty) return [];
    final data = await _client.from('customer_packages').select('*, packages(name)')
        .inFilter('customer_id', ids.toList()).order('created_at', ascending: false);
    return (data as List).map((m) => CustomerPackage.fromMap(m)).toList();
  }

  Future<List<Invoice>> fetchMyInvoices() async {
    final ids = await _myCustomerIds();
    if (ids.isEmpty) return [];
    final data = await _client.from('invoices').select('*, invoice_lines(*)')
        .inFilter('customer_id', ids.toList()).order('issue_date', ascending: false);
    return (data as List).map((m) => Invoice.fromMap(m)).toList();
  }

  Future<List<AppNotification>> fetchMyNotifications({int limit = 50}) async {
    final data = await _client.from('notifications').select()
        .eq('user_id', _uid).eq('channel', 'push')
        .inFilter('status', ['sent', 'read'])
        .order('created_at', ascending: false).limit(limit);
    return (data as List).map((m) => AppNotification.fromMap(m)).toList();
  }

  Future<void> markNotificationRead(int id) =>
      _client.from('notifications').update({'status': 'read'}).eq('id', id);

  /// Negocios de los que el usuario es miembro (para cambiar al modo negocio).
  Future<List<Member>> fetchMyMemberships() async {
    final data = await _client.from('business_members').select()
        .eq('user_id', _uid).eq('active', true);
    return (data as List).map((m) => Member.fromMap(m)).toList();
  }

  static String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
