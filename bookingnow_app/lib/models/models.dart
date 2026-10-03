/// Modelos de dominio de BookingNow (espejo de supabase/schema.sql).
///
/// Convención: `fromMap` tolera nulos y tipos numéricos de PostgREST
/// (int/double/String). Los importes van siempre en céntimos.
library;

int _int(dynamic v, [int def = 0]) {
  if (v == null) return def;
  if (v is int) return v;
  if (v is double) return v.round();
  return int.tryParse(v.toString()) ?? def;
}

double _double(dynamic v, [double def = 0]) {
  if (v == null) return def;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? def;
}

bool _bool(dynamic v, [bool def = false]) => v is bool ? v : def;

DateTime? _dt(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

List<String> _strList(dynamic v) =>
    v is List ? v.map((e) => e.toString()).toList() : const [];

String formatEuros(int cents, {String currency = '€'}) {
  final euros = cents / 100;
  final s = euros.toStringAsFixed(2).replaceAll('.', ',');
  return '$s $currency';
}

// ---------------------------------------------------------------- Usuarios

class Profile {
  final String id;
  final String fullName;
  final String? email;
  final String? phone;
  final String? avatarUrl;
  final String locale;
  final bool phoneVerified;
  final bool isPlatformAdmin;

  Profile({
    required this.id,
    required this.fullName,
    this.email,
    this.phone,
    this.avatarUrl,
    this.locale = 'es',
    this.phoneVerified = false,
    this.isPlatformAdmin = false,
  });

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: m['id'],
        fullName: m['full_name'] ?? '',
        email: m['email'],
        phone: m['phone'],
        avatarUrl: m['avatar_url'],
        locale: m['locale'] ?? 'es',
        phoneVerified: _bool(m['phone_verified']),
        isPlatformAdmin: _bool(m['is_platform_admin']),
      );
}

// ---------------------------------------------------------------- Sectores

class Sector {
  final String id;
  final String nameEs;
  final String nameEn;
  final String icon;
  final String labelStaff;
  final String labelCustomer;
  final String labelBooking;
  final bool usesResources;
  final bool usesGroupSessions;

  Sector({
    required this.id,
    required this.nameEs,
    required this.nameEn,
    required this.icon,
    required this.labelStaff,
    required this.labelCustomer,
    required this.labelBooking,
    required this.usesResources,
    required this.usesGroupSessions,
  });

  factory Sector.fromMap(Map<String, dynamic> m) => Sector(
        id: m['id'],
        nameEs: m['name_es'] ?? '',
        nameEn: m['name_en'] ?? '',
        icon: m['icon'] ?? 'storefront',
        labelStaff: m['label_staff_es'] ?? 'Profesional',
        labelCustomer: m['label_customer_es'] ?? 'Cliente',
        labelBooking: m['label_booking_es'] ?? 'Cita',
        usesResources: _bool(m['uses_resources']),
        usesGroupSessions: _bool(m['uses_group_sessions']),
      );

  String name(String locale) => locale.startsWith('en') ? nameEn : nameEs;
}

// ---------------------------------------------------------------- Negocios

class Business {
  final String id;
  final String slug;
  final String name;
  final String sectorId;
  final String? sectorName;
  final String? description;
  final String? logoUrl;
  final String? coverUrl;
  final String? phone;
  final String? email;
  final String? website;
  final String? instagram;
  final String? legalName;
  final String? taxId;
  final String? fiscalAddress;
  final String? fiscalPostalCode;
  final String? fiscalCity;
  final String? fiscalProvince;
  final String timezone;
  final String currency;
  final int bookingLeadMin;
  final int bookingHorizonDays;
  final int cancellationHours;
  final int cancellationFeePct;
  final int noShowFeePct;
  final int depositPct;
  final bool requiresConfirmation;
  final bool allowWaitlist;
  final bool allowRecurring;
  final bool onlineBookingEnabled;
  final String plan;
  final bool isPublished;
  final double ratingAvg;
  final int ratingCount;
  // Campos de v_marketplace
  final String? city;
  final String? address;
  final double? lat;
  final double? lng;
  final int? minPriceCents;
  final int servicesCount;
  // Perfil enriquecido (migración 002)
  final List<String> amenities;
  final List<String> paymentMethods;
  final List<String> languages;
  final String? tagline;
  final String? facebook;
  final String? tiktok;
  final String? whatsapp;
  final int photosCount;

  Business({
    required this.id,
    required this.slug,
    required this.name,
    required this.sectorId,
    this.sectorName,
    this.description,
    this.logoUrl,
    this.coverUrl,
    this.phone,
    this.email,
    this.website,
    this.instagram,
    this.legalName,
    this.taxId,
    this.fiscalAddress,
    this.fiscalPostalCode,
    this.fiscalCity,
    this.fiscalProvince,
    this.timezone = 'Europe/Madrid',
    this.currency = 'EUR',
    this.bookingLeadMin = 60,
    this.bookingHorizonDays = 60,
    this.cancellationHours = 24,
    this.cancellationFeePct = 0,
    this.noShowFeePct = 0,
    this.depositPct = 0,
    this.requiresConfirmation = false,
    this.allowWaitlist = true,
    this.allowRecurring = true,
    this.onlineBookingEnabled = true,
    this.plan = 'free',
    this.isPublished = false,
    this.ratingAvg = 0,
    this.ratingCount = 0,
    this.city,
    this.address,
    this.lat,
    this.lng,
    this.minPriceCents,
    this.servicesCount = 0,
    this.amenities = const [],
    this.paymentMethods = const ['cash', 'card'],
    this.languages = const ['es'],
    this.tagline,
    this.facebook,
    this.tiktok,
    this.whatsapp,
    this.photosCount = 0,
  });

  factory Business.fromMap(Map<String, dynamic> m) => Business(
        id: m['id'],
        slug: m['slug'] ?? '',
        name: m['name'] ?? '',
        sectorId: m['sector_id'] ?? 'other',
        sectorName: m['sector_name'],
        description: m['description'],
        logoUrl: m['logo_url'],
        coverUrl: m['cover_url'],
        phone: m['phone'],
        email: m['email'],
        website: m['website'],
        instagram: m['instagram'],
        legalName: m['legal_name'],
        taxId: m['tax_id'],
        fiscalAddress: m['fiscal_address'],
        fiscalPostalCode: m['fiscal_postal_code'],
        fiscalCity: m['fiscal_city'],
        fiscalProvince: m['fiscal_province'],
        timezone: m['timezone'] ?? 'Europe/Madrid',
        currency: m['currency'] ?? 'EUR',
        bookingLeadMin: _int(m['booking_lead_min'], 60),
        bookingHorizonDays: _int(m['booking_horizon_days'], 60),
        cancellationHours: _int(m['cancellation_hours'], 24),
        cancellationFeePct: _int(m['cancellation_fee_pct']),
        noShowFeePct: _int(m['no_show_fee_pct']),
        depositPct: _int(m['deposit_pct']),
        requiresConfirmation: _bool(m['requires_confirmation']),
        allowWaitlist: _bool(m['allow_waitlist'], true),
        allowRecurring: _bool(m['allow_recurring'], true),
        onlineBookingEnabled: _bool(m['online_booking_enabled'], true),
        plan: m['plan'] ?? 'free',
        isPublished: _bool(m['is_published']),
        ratingAvg: _double(m['rating_avg']),
        ratingCount: _int(m['rating_count']),
        city: m['city'],
        address: m['address'],
        lat: m['lat'] == null ? null : _double(m['lat']),
        lng: m['lng'] == null ? null : _double(m['lng']),
        minPriceCents:
            m['min_price_cents'] == null ? null : _int(m['min_price_cents']),
        servicesCount: _int(m['services_count']),
        amenities: _strList(m['amenities']),
        paymentMethods: m['payment_methods'] == null ? const ['cash', 'card'] : _strList(m['payment_methods']),
        languages: m['languages'] == null ? const ['es'] : _strList(m['languages']),
        tagline: m['tagline'],
        facebook: m['facebook'],
        tiktok: m['tiktok'],
        whatsapp: m['whatsapp'],
        photosCount: _int(m['photos_count']),
      );
}

class Location {
  final String id;
  final String businessId;
  final String name;
  final String? address;
  final String? postalCode;
  final String? city;
  final String? province;
  final String? phone;
  final bool isMobileService;
  final int travelFeeCents;
  final bool isDefault;
  final bool active;

  Location({
    required this.id,
    required this.businessId,
    required this.name,
    this.address,
    this.postalCode,
    this.city,
    this.province,
    this.phone,
    this.isMobileService = false,
    this.travelFeeCents = 0,
    this.isDefault = false,
    this.active = true,
  });

  factory Location.fromMap(Map<String, dynamic> m) => Location(
        id: m['id'],
        businessId: m['business_id'],
        name: m['name'] ?? '',
        address: m['address'],
        postalCode: m['postal_code'],
        city: m['city'],
        province: m['province'],
        phone: m['phone'],
        isMobileService: _bool(m['is_mobile_service']),
        travelFeeCents: _int(m['travel_fee_cents']),
        isDefault: _bool(m['is_default']),
        active: _bool(m['active'], true),
      );
}

class Member {
  final String id;
  final String businessId;
  final String? userId;
  final String role; // owner | manager | staff | reception
  final String displayName;
  final String? title;
  final String? avatarUrl;
  final String color;
  final bool bookable;
  final bool active;
  final int commissionPct;

  Member({
    required this.id,
    required this.businessId,
    this.userId,
    required this.role,
    required this.displayName,
    this.title,
    this.avatarUrl,
    this.color = '#7C4DFF',
    this.bookable = true,
    this.active = true,
    this.commissionPct = 0,
  });

  factory Member.fromMap(Map<String, dynamic> m) => Member(
        id: m['id'],
        businessId: m['business_id'],
        userId: m['user_id'],
        role: m['role'] ?? 'staff',
        displayName: m['display_name'] ?? '',
        title: m['title'],
        avatarUrl: m['avatar_url'],
        color: m['color'] ?? '#7C4DFF',
        bookable: _bool(m['bookable'], true),
        active: _bool(m['active'], true),
        commissionPct: _int(m['commission_pct']),
      );

  bool get canManage => role == 'owner' || role == 'manager';
  bool get canInvoice => canManage || role == 'reception';
}

// ---------------------------------------------------------------- Catálogo

class ServiceCategory {
  final String id;
  final String businessId;
  final String name;
  final int sortOrder;
  ServiceCategory(
      {required this.id,
      required this.businessId,
      required this.name,
      this.sortOrder = 100});
  factory ServiceCategory.fromMap(Map<String, dynamic> m) => ServiceCategory(
      id: m['id'],
      businessId: m['business_id'],
      name: m['name'] ?? '',
      sortOrder: _int(m['sort_order'], 100));
}

class ServiceVariant {
  final String id;
  final String serviceId;
  final String name;
  final int durationMin;
  final int priceCents;
  ServiceVariant(
      {required this.id,
      required this.serviceId,
      required this.name,
      required this.durationMin,
      required this.priceCents});
  factory ServiceVariant.fromMap(Map<String, dynamic> m) => ServiceVariant(
      id: m['id'],
      serviceId: m['service_id'],
      name: m['name'] ?? '',
      durationMin: _int(m['duration_min'], 30),
      priceCents: _int(m['price_cents']));
}

class ServiceAddon {
  final String id;
  final String businessId;
  final String name;
  final int durationMin;
  final int priceCents;
  final bool active;
  ServiceAddon(
      {required this.id,
      required this.businessId,
      required this.name,
      this.durationMin = 0,
      this.priceCents = 0,
      this.active = true});
  factory ServiceAddon.fromMap(Map<String, dynamic> m) => ServiceAddon(
      id: m['id'],
      businessId: m['business_id'],
      name: m['name'] ?? '',
      durationMin: _int(m['duration_min']),
      priceCents: _int(m['price_cents']),
      active: _bool(m['active'], true));
}

class Service {
  final String id;
  final String businessId;
  final String? categoryId;
  final String name;
  final String? description;
  final int durationMin;
  final int bufferBeforeMin;
  final int bufferAfterMin;
  final int priceCents;
  final String priceType; // fixed | from | free | variable
  final double vatPct;
  final int capacity;
  final bool requiresResource;
  final bool onlineBookable;
  final bool requiresDeposit;
  final int? depositCents;
  final String? color;
  final String? imageUrl;
  final bool active;
  final int sortOrder;
  final List<ServiceVariant> variants;
  final List<ServiceAddon> addons;
  final List<String> staffIds;

  Service({
    required this.id,
    required this.businessId,
    this.categoryId,
    required this.name,
    this.description,
    required this.durationMin,
    this.bufferBeforeMin = 0,
    this.bufferAfterMin = 0,
    this.priceCents = 0,
    this.priceType = 'fixed',
    this.vatPct = 21,
    this.capacity = 1,
    this.requiresResource = false,
    this.onlineBookable = true,
    this.requiresDeposit = false,
    this.depositCents,
    this.color,
    this.imageUrl,
    this.active = true,
    this.sortOrder = 100,
    this.variants = const [],
    this.addons = const [],
    this.staffIds = const [],
  });

  factory Service.fromMap(Map<String, dynamic> m) => Service(
        id: m['id'],
        businessId: m['business_id'],
        categoryId: m['category_id'],
        name: m['name'] ?? '',
        description: m['description'],
        durationMin: _int(m['duration_min'], 30),
        bufferBeforeMin: _int(m['buffer_before_min']),
        bufferAfterMin: _int(m['buffer_after_min']),
        priceCents: _int(m['price_cents']),
        priceType: m['price_type'] ?? 'fixed',
        vatPct: _double(m['vat_pct'], 21),
        capacity: _int(m['capacity'], 1),
        requiresResource: _bool(m['requires_resource']),
        onlineBookable: _bool(m['online_bookable'], true),
        requiresDeposit: _bool(m['requires_deposit']),
        depositCents:
            m['deposit_cents'] == null ? null : _int(m['deposit_cents']),
        color: m['color'],
        imageUrl: m['image_url'],
        active: _bool(m['active'], true),
        sortOrder: _int(m['sort_order'], 100),
        variants: (m['service_variants'] as List? ?? const [])
            .map((v) => ServiceVariant.fromMap(v))
            .toList(),
        addons: (m['service_addon_links'] as List? ?? const [])
            .where((l) => l['service_addons'] != null)
            .map((l) => ServiceAddon.fromMap(l['service_addons']))
            .toList(),
        staffIds: (m['service_staff'] as List? ?? const [])
            .map((s) => s['member_id'].toString())
            .toList(),
      );

  String get priceLabel {
    switch (priceType) {
      case 'free':
        return 'Gratis';
      case 'variable':
        return 'A consultar';
      case 'from':
        return 'Desde ${formatEuros(priceCents)}';
      default:
        return formatEuros(priceCents);
    }
  }

  Map<String, dynamic> toInsert() => {
        'business_id': businessId,
        'category_id': categoryId,
        'name': name,
        'description': description,
        'duration_min': durationMin,
        'buffer_before_min': bufferBeforeMin,
        'buffer_after_min': bufferAfterMin,
        'price_cents': priceCents,
        'price_type': priceType,
        'vat_pct': vatPct,
        'capacity': capacity,
        'requires_resource': requiresResource,
        'online_bookable': onlineBookable,
        'requires_deposit': requiresDeposit,
        'deposit_cents': depositCents,
        'color': color,
        'image_url': imageUrl,
        'active': active,
        'sort_order': sortOrder,
      };
}

class WorkingHours {
  final String? id;
  final String businessId;
  final String? memberId;
  final int weekday; // 0 = domingo … 6 = sábado
  final String startTime; // 'HH:mm'
  final String endTime;
  WorkingHours(
      {this.id,
      required this.businessId,
      this.memberId,
      required this.weekday,
      required this.startTime,
      required this.endTime});
  factory WorkingHours.fromMap(Map<String, dynamic> m) => WorkingHours(
      id: m['id'],
      businessId: m['business_id'],
      memberId: m['member_id'],
      weekday: _int(m['weekday']),
      startTime: (m['start_time'] ?? '09:00').toString().substring(0, 5),
      endTime: (m['end_time'] ?? '18:00').toString().substring(0, 5));
  Map<String, dynamic> toInsert() => {
        'business_id': businessId,
        'member_id': memberId,
        'weekday': weekday,
        'start_time': startTime,
        'end_time': endTime,
      };
}

// ---------------------------------------------------------------- Clientes

class Customer {
  final String id;
  final String businessId;
  final String? userId;
  final String fullName;
  final String? email;
  final String? phone;
  final DateTime? birthdate;
  final String? taxId;
  final String? address;
  final String? notes;
  final List<String> tags;
  final String source;
  final bool blocked;
  final int noShowCount;
  final int totalVisits;
  final int totalSpentCents;
  final DateTime? lastVisitAt;
  final DateTime? createdAt;

  Customer({
    required this.id,
    required this.businessId,
    this.userId,
    required this.fullName,
    this.email,
    this.phone,
    this.birthdate,
    this.taxId,
    this.address,
    this.notes,
    this.tags = const [],
    this.source = 'manual',
    this.blocked = false,
    this.noShowCount = 0,
    this.totalVisits = 0,
    this.totalSpentCents = 0,
    this.lastVisitAt,
    this.createdAt,
  });

  factory Customer.fromMap(Map<String, dynamic> m) => Customer(
        id: m['id'],
        businessId: m['business_id'],
        userId: m['user_id'],
        fullName: m['full_name'] ?? '',
        email: m['email'],
        phone: m['phone'],
        birthdate: _dt(m['birthdate']),
        taxId: m['tax_id'],
        address: m['address'],
        notes: m['notes'],
        tags: _strList(m['tags']),
        source: m['source'] ?? 'manual',
        blocked: _bool(m['blocked']),
        noShowCount: _int(m['no_show_count']),
        totalVisits: _int(m['total_visits']),
        totalSpentCents: _int(m['total_spent_cents']),
        lastVisitAt: _dt(m['last_visit_at']),
        createdAt: _dt(m['created_at']),
      );

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

// ---------------------------------------------------------------- Reservas

class Slot {
  final String memberId;
  final DateTime startsAt;
  final DateTime endsAt;
  Slot({required this.memberId, required this.startsAt, required this.endsAt});
  factory Slot.fromMap(Map<String, dynamic> m) => Slot(
      memberId: m['member_id'],
      startsAt: _dt(m['starts_at'])!,
      endsAt: _dt(m['ends_at'])!);
}

class BookingItem {
  final String id;
  final String? serviceId;
  final String? variantId;
  final String? addonId;
  final String name;
  final int durationMin;
  final int priceCents;
  BookingItem(
      {required this.id,
      this.serviceId,
      this.variantId,
      this.addonId,
      required this.name,
      required this.durationMin,
      required this.priceCents});
  factory BookingItem.fromMap(Map<String, dynamic> m) => BookingItem(
      id: m['id'],
      serviceId: m['service_id'],
      variantId: m['variant_id'],
      addonId: m['addon_id'],
      name: m['name'] ?? '',
      durationMin: _int(m['duration_min']),
      priceCents: _int(m['price_cents']));
}

/// Reserva (fila de bookings o de la vista v_bookings_full).
class Booking {
  final String id;
  final String code;
  final String businessId;
  final String? locationId;
  final String customerId;
  final String? memberId;
  final DateTime startsAt;
  final DateTime endsAt;
  final String status;
  final String source;
  final String? customerNotes;
  final String? internalNotes;
  final int totalCents;
  final int depositCents;
  final String paymentStatus;
  final String? paymentProvider;
  final String? recurrenceId;
  final bool rated;
  final DateTime? cancelledAt;
  final String? cancelReason;
  // v_bookings_full
  final String? customerName;
  final String? customerPhone;
  final String? customerEmail;
  final int customerNoShows;
  final String? memberName;
  final String? memberColor;
  final String? businessName;
  final String? servicesSummary;
  final int durationMin;
  final bool invoiced;
  final List<BookingItem> items;

  Booking({
    required this.id,
    required this.code,
    required this.businessId,
    this.locationId,
    required this.customerId,
    this.memberId,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    this.source = 'app',
    this.customerNotes,
    this.internalNotes,
    this.totalCents = 0,
    this.depositCents = 0,
    this.paymentStatus = 'none',
    this.paymentProvider,
    this.recurrenceId,
    this.rated = false,
    this.cancelledAt,
    this.cancelReason,
    this.customerName,
    this.customerPhone,
    this.customerEmail,
    this.customerNoShows = 0,
    this.memberName,
    this.memberColor,
    this.businessName,
    this.servicesSummary,
    this.durationMin = 0,
    this.invoiced = false,
    this.items = const [],
  });

  factory Booking.fromMap(Map<String, dynamic> m) => Booking(
        id: m['id'],
        code: m['code'] ?? '',
        businessId: m['business_id'],
        locationId: m['location_id'],
        customerId: m['customer_id'],
        memberId: m['member_id'],
        startsAt: _dt(m['starts_at'])!,
        endsAt: _dt(m['ends_at'])!,
        status: m['status'] ?? 'pending',
        source: m['source'] ?? 'app',
        customerNotes: m['customer_notes'],
        internalNotes: m['internal_notes'],
        totalCents: _int(m['total_cents']),
        depositCents: _int(m['deposit_cents']),
        paymentStatus: m['payment_status'] ?? 'none',
        paymentProvider: m['payment_provider'],
        recurrenceId: m['recurrence_id'],
        rated: _bool(m['rated']),
        cancelledAt: _dt(m['cancelled_at']),
        cancelReason: m['cancel_reason'],
        customerName: m['customer_name'],
        customerPhone: m['customer_phone'],
        customerEmail: m['customer_email'],
        customerNoShows: _int(m['customer_no_shows']),
        memberName: m['member_name'],
        memberColor: m['member_color'],
        businessName: m['business_name'],
        servicesSummary: m['services_summary'],
        durationMin: _int(m['duration_min']),
        invoiced: _bool(m['invoiced']),
        items: (m['booking_items'] as List? ?? const [])
            .map((i) => BookingItem.fromMap(i))
            .toList(),
      );

  bool get isActive =>
      status == 'pending' || status == 'confirmed' || status == 'checked_in';
  bool get isPast => endsAt.isBefore(DateTime.now());
  bool get canReview => status == 'completed' && !rated;
}

class WaitlistEntry {
  final String id;
  final String businessId;
  final String customerId;
  final String serviceId;
  final String? memberId;
  final DateTime dateFrom;
  final DateTime dateTo;
  final String status;
  final String? customerName;
  final String? serviceName;
  WaitlistEntry(
      {required this.id,
      required this.businessId,
      required this.customerId,
      required this.serviceId,
      this.memberId,
      required this.dateFrom,
      required this.dateTo,
      required this.status,
      this.customerName,
      this.serviceName});
  factory WaitlistEntry.fromMap(Map<String, dynamic> m) => WaitlistEntry(
      id: m['id'],
      businessId: m['business_id'],
      customerId: m['customer_id'],
      serviceId: m['service_id'],
      memberId: m['member_id'],
      dateFrom: _dt(m['date_from'])!,
      dateTo: _dt(m['date_to'])!,
      status: m['status'] ?? 'waiting',
      customerName: m['customers']?['full_name'],
      serviceName: m['services']?['name']);
}

class Review {
  final String id;
  final String businessId;
  final int rating;
  final String? comment;
  final String? reply;
  final DateTime createdAt;
  final String? customerName;
  Review(
      {required this.id,
      required this.businessId,
      required this.rating,
      this.comment,
      this.reply,
      required this.createdAt,
      this.customerName});
  factory Review.fromMap(Map<String, dynamic> m) => Review(
      id: m['id'],
      businessId: m['business_id'],
      rating: _int(m['rating']),
      comment: m['comment'],
      reply: m['reply'],
      createdAt: _dt(m['created_at']) ?? DateTime.now(),
      customerName: m['customers']?['full_name']);
}

// ---------------------------------------------------------------- Bonos

class Package {
  final String id;
  final String businessId;
  final String type; // bundle | membership | gift_card
  final String name;
  final String? description;
  final int priceCents;
  final int? sessions;
  final List<String> serviceIds;
  final int? validityDays;
  final String? period;
  final int? sessionsPerPeriod;
  final int? discountPct;
  final bool active;
  Package(
      {required this.id,
      required this.businessId,
      required this.type,
      required this.name,
      this.description,
      required this.priceCents,
      this.sessions,
      this.serviceIds = const [],
      this.validityDays,
      this.period,
      this.sessionsPerPeriod,
      this.discountPct,
      this.active = true});
  factory Package.fromMap(Map<String, dynamic> m) => Package(
      id: m['id'],
      businessId: m['business_id'],
      type: m['type'] ?? 'bundle',
      name: m['name'] ?? '',
      description: m['description'],
      priceCents: _int(m['price_cents']),
      sessions: m['sessions'] == null ? null : _int(m['sessions']),
      serviceIds: _strList(m['service_ids']),
      validityDays: m['validity_days'] == null ? null : _int(m['validity_days']),
      period: m['period'],
      sessionsPerPeriod:
          m['sessions_per_period'] == null ? null : _int(m['sessions_per_period']),
      discountPct: m['discount_pct'] == null ? null : _int(m['discount_pct']),
      active: _bool(m['active'], true));
}

class CustomerPackage {
  final String id;
  final String packageId;
  final String customerId;
  final String code;
  final int? sessionsTotal;
  final int sessionsUsed;
  final int? balanceCents;
  final DateTime? validUntil;
  final String status;
  final String? packageName;
  CustomerPackage(
      {required this.id,
      required this.packageId,
      required this.customerId,
      required this.code,
      this.sessionsTotal,
      this.sessionsUsed = 0,
      this.balanceCents,
      this.validUntil,
      required this.status,
      this.packageName});
  factory CustomerPackage.fromMap(Map<String, dynamic> m) => CustomerPackage(
      id: m['id'],
      packageId: m['package_id'],
      customerId: m['customer_id'],
      code: m['code'] ?? '',
      sessionsTotal: m['sessions_total'] == null ? null : _int(m['sessions_total']),
      sessionsUsed: _int(m['sessions_used']),
      balanceCents: m['balance_cents'] == null ? null : _int(m['balance_cents']),
      validUntil: _dt(m['valid_until']),
      status: m['status'] ?? 'active',
      packageName: m['packages']?['name']);
}

// ---------------------------------------------------------------- Facturación

class Invoice {
  final String id;
  final String businessId;
  final String? customerId;
  final String? bookingId;
  final String fullNumber;
  final DateTime issueDate;
  final String type;
  final String recipientName;
  final String? recipientTaxId;
  final String? recipientAddress;
  final int subtotalCents;
  final int vatCents;
  final int totalCents;
  final String status;
  final String? paymentMethod;
  final String? pdfUrl;
  final String? verifactuHash;
  final String? verifactuQrUrl;
  final DateTime? verifactuSentAt;
  final String? externalProvider;
  final String? externalId;
  final DateTime? externalSyncedAt;
  final String? externalError;
  final List<InvoiceLine> lines;

  Invoice({
    required this.id,
    required this.businessId,
    this.customerId,
    this.bookingId,
    required this.fullNumber,
    required this.issueDate,
    this.type = 'F1',
    required this.recipientName,
    this.recipientTaxId,
    this.recipientAddress,
    required this.subtotalCents,
    required this.vatCents,
    required this.totalCents,
    required this.status,
    this.paymentMethod,
    this.pdfUrl,
    this.verifactuHash,
    this.verifactuQrUrl,
    this.verifactuSentAt,
    this.externalProvider,
    this.externalId,
    this.externalSyncedAt,
    this.externalError,
    this.lines = const [],
  });

  factory Invoice.fromMap(Map<String, dynamic> m) => Invoice(
        id: m['id'],
        businessId: m['business_id'],
        customerId: m['customer_id'],
        bookingId: m['booking_id'],
        fullNumber: m['full_number'] ?? '',
        issueDate: _dt(m['issue_date']) ?? DateTime.now(),
        type: m['type'] ?? 'F1',
        recipientName: m['recipient_name'] ?? '',
        recipientTaxId: m['recipient_tax_id'],
        recipientAddress: m['recipient_address'],
        subtotalCents: _int(m['subtotal_cents']),
        vatCents: _int(m['vat_cents']),
        totalCents: _int(m['total_cents']),
        status: m['status'] ?? 'issued',
        paymentMethod: m['payment_method'],
        pdfUrl: m['pdf_url'],
        verifactuHash: m['verifactu_hash'],
        verifactuQrUrl: m['verifactu_qr_url'],
        verifactuSentAt: _dt(m['verifactu_sent_at']),
        externalProvider: m['external_provider'],
        externalId: m['external_id'],
        externalSyncedAt: _dt(m['external_synced_at']),
        externalError: m['external_error'],
        lines: (m['invoice_lines'] as List? ?? const [])
            .map((l) => InvoiceLine.fromMap(l))
            .toList(),
      );
}

class InvoiceLine {
  final String description;
  final double quantity;
  final int unitPriceCents;
  final double vatPct;
  final int totalCents;
  InvoiceLine(
      {required this.description,
      required this.quantity,
      required this.unitPriceCents,
      required this.vatPct,
      required this.totalCents});
  factory InvoiceLine.fromMap(Map<String, dynamic> m) => InvoiceLine(
      description: m['description'] ?? '',
      quantity: _double(m['quantity'], 1),
      unitPriceCents: _int(m['unit_price_cents']),
      vatPct: _double(m['vat_pct'], 21),
      totalCents: _int(m['total_cents']));
}

/// Integración con un sistema externo (sin credenciales: v_integrations_public).
class Integration {
  final String id;
  final String businessId;
  final String provider;
  final String category;
  final bool enabled;
  final Map<String, dynamic> settings;
  final DateTime? lastSyncAt;
  final String? lastError;
  Integration(
      {required this.id,
      required this.businessId,
      required this.provider,
      required this.category,
      this.enabled = true,
      this.settings = const {},
      this.lastSyncAt,
      this.lastError});
  factory Integration.fromMap(Map<String, dynamic> m) => Integration(
      id: m['id'],
      businessId: m['business_id'],
      provider: m['provider'],
      category: m['category'],
      enabled: _bool(m['enabled'], true),
      settings: (m['settings'] as Map?)?.cast<String, dynamic>() ?? const {},
      lastSyncAt: _dt(m['last_sync_at']),
      lastError: m['last_error']);
}

/// Catálogo de proveedores integrables (lo que la pantalla de integraciones
/// ofrece). Las credenciales que pide cada uno se definen en `fields`.
class IntegrationProvider {
  final String id;
  final String name;
  final String category; // invoicing | payments | messaging | calendar | marketplace
  final String description;
  final List<IntegrationField> fields;
  const IntegrationProvider(
      {required this.id,
      required this.name,
      required this.category,
      required this.description,
      required this.fields});
}

class IntegrationField {
  final String key;
  final String label;
  final bool secret;
  final String? hint;
  const IntegrationField(this.key, this.label,
      {this.secret = false, this.hint});
}

/// Proveedores soportados por la Edge Function `invoice-sync` y resto.
const integrationProviders = <IntegrationProvider>[
  IntegrationProvider(
    id: 'holded',
    name: 'Holded',
    category: 'invoicing',
    description:
        'ERP en la nube certificado Verifactu. Sincroniza facturas y clientes.',
    fields: [IntegrationField('api_key', 'API Key', secret: true)],
  ),
  IntegrationProvider(
    id: 'quipu',
    name: 'Quipu',
    category: 'invoicing',
    description: 'Facturación para autónomos y pymes. OAuth2 (client credentials).',
    fields: [
      IntegrationField('app_id', 'App ID'),
      IntegrationField('app_secret', 'App Secret', secret: true),
    ],
  ),
  IntegrationProvider(
    id: 'contasimple',
    name: 'Cegid Contasimple',
    category: 'invoicing',
    description: 'Facturación y contabilidad para autónomos.',
    fields: [IntegrationField('api_key', 'API Key', secret: true)],
  ),
  IntegrationProvider(
    id: 'sage',
    name: 'Sage Accounting / Sage 50',
    category: 'invoicing',
    description: 'Sage Business Cloud Accounting (OAuth2) o exportación Sage 50.',
    fields: [
      IntegrationField('client_id', 'Client ID'),
      IntegrationField('client_secret', 'Client Secret', secret: true),
      IntegrationField('refresh_token', 'Refresh token', secret: true),
    ],
  ),
  IntegrationProvider(
    id: 'a3',
    name: 'Wolters Kluwer a3 (a3innuva / a3ERP)',
    category: 'invoicing',
    description: 'Envío de facturas a a3innuva Facturación vía API.',
    fields: [
      IntegrationField('api_key', 'Ocp-Apim-Subscription-Key', secret: true),
      IntegrationField('company_id', 'ID empresa'),
    ],
  ),
  IntegrationProvider(
    id: 'billin',
    name: 'Billin',
    category: 'invoicing',
    description: 'Facturación online para autónomos.',
    fields: [IntegrationField('api_key', 'API Key', secret: true)],
  ),
  IntegrationProvider(
    id: 'facturadirecta',
    name: 'FacturaDirecta',
    category: 'invoicing',
    description: 'Facturación y contabilidad online.',
    fields: [
      IntegrationField('account', 'Cuenta (subdominio)'),
      IntegrationField('api_key', 'API Key', secret: true),
    ],
  ),
  IntegrationProvider(
    id: 'verifactu_aeat',
    name: 'Verifactu (envío directo a la AEAT)',
    category: 'invoicing',
    description:
        'Remite los registros de facturación a la AEAT con certificado digital del negocio.',
    fields: [
      IntegrationField('cert_pem', 'Certificado (PEM)', secret: true),
      IntegrationField('key_pem', 'Clave privada (PEM)', secret: true),
      IntegrationField('environment', 'Entorno', hint: 'test | prod'),
    ],
  ),
  IntegrationProvider(
    id: 'webhook',
    name: 'Webhook genérico / Zapier / Make',
    category: 'invoicing',
    description: 'Envía cada factura en JSON a la URL que indiques.',
    fields: [
      IntegrationField('url', 'URL'),
      IntegrationField('secret', 'Secreto (firma HMAC)', secret: true),
    ],
  ),
  IntegrationProvider(
    id: 'stripe',
    name: 'Stripe (tarjeta + Bizum)',
    category: 'payments',
    description: 'Cobro de señales y pagos online. Bizum incluido.',
    fields: [IntegrationField('secret_key', 'Secret key', secret: true)],
  ),
  IntegrationProvider(
    id: 'redsys',
    name: 'Redsys (TPV virtual bancario)',
    category: 'payments',
    description: 'Pasarela de los bancos españoles. Tarjeta y Bizum.',
    fields: [
      IntegrationField('merchant_code', 'Código de comercio (FUC)'),
      IntegrationField('terminal', 'Terminal'),
      IntegrationField('secret_key', 'Clave SHA-256', secret: true),
    ],
  ),
  IntegrationProvider(
    id: 'whatsapp',
    name: 'WhatsApp Business (Meta Cloud API)',
    category: 'messaging',
    description: 'Recordatorios y confirmaciones por WhatsApp.',
    fields: [
      IntegrationField('phone_number_id', 'Phone number ID'),
      IntegrationField('access_token', 'Access token', secret: true),
    ],
  ),
  IntegrationProvider(
    id: 'twilio',
    name: 'Twilio SMS',
    category: 'messaging',
    description: 'Recordatorios por SMS.',
    fields: [
      IntegrationField('account_sid', 'Account SID'),
      IntegrationField('auth_token', 'Auth token', secret: true),
      IntegrationField('from', 'Remitente'),
    ],
  ),
  IntegrationProvider(
    id: 'google_calendar',
    name: 'Google Calendar',
    category: 'calendar',
    description: 'Sincroniza la agenda de cada profesional (feed iCal + API).',
    fields: [IntegrationField('refresh_token', 'Refresh token', secret: true)],
  ),
  IntegrationProvider(
    id: 'reserve_with_google',
    name: 'Reserve with Google',
    category: 'marketplace',
    description: 'Botón "Reservar" en Google Maps y Búsqueda.',
    fields: [IntegrationField('merchant_id', 'Merchant ID')],
  ),
];

// ---------------------------------------------------------------- Dashboard

class BusinessKpis {
  final int bookingsToday;
  final int completedMonth;
  final int revenueMonthCents;
  final int noShows30d;
  final int finished30d;
  final int customersTotal;
  final int customersNewMonth;
  final int waitlistWaiting;
  final int pendingConfirmation;
  BusinessKpis(
      {this.bookingsToday = 0,
      this.completedMonth = 0,
      this.revenueMonthCents = 0,
      this.noShows30d = 0,
      this.finished30d = 0,
      this.customersTotal = 0,
      this.customersNewMonth = 0,
      this.waitlistWaiting = 0,
      this.pendingConfirmation = 0});
  factory BusinessKpis.fromMap(Map<String, dynamic> m) => BusinessKpis(
      bookingsToday: _int(m['bookings_today']),
      completedMonth: _int(m['completed_month']),
      revenueMonthCents: _int(m['revenue_month_cents']),
      noShows30d: _int(m['no_shows_30d']),
      finished30d: _int(m['finished_30d']),
      customersTotal: _int(m['customers_total']),
      customersNewMonth: _int(m['customers_new_month']),
      waitlistWaiting: _int(m['waitlist_waiting']),
      pendingConfirmation: _int(m['pending_confirmation']));
  double get noShowRate => finished30d == 0 ? 0 : noShows30d / finished30d;
}

class AppNotification {
  final int id;
  final String channel;
  final String template;
  final Map<String, dynamic> payload;
  final String status;
  final String? bookingId;
  final DateTime createdAt;
  AppNotification(
      {required this.id,
      required this.channel,
      required this.template,
      this.payload = const {},
      required this.status,
      this.bookingId,
      required this.createdAt});
  factory AppNotification.fromMap(Map<String, dynamic> m) => AppNotification(
      id: _int(m['id']),
      channel: m['channel'] ?? 'push',
      template: m['template'] ?? '',
      payload: (m['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
      status: m['status'] ?? 'queued',
      bookingId: m['booking_id'],
      createdAt: _dt(m['created_at']) ?? DateTime.now());
}

// ---------------------------------------------------------------- Perfil enriquecido

class BusinessPhoto {
  final String id;
  final String businessId;
  final String url;
  final String? caption;
  final int sortOrder;
  BusinessPhoto(
      {required this.id,
      required this.businessId,
      required this.url,
      this.caption,
      this.sortOrder = 100});
  factory BusinessPhoto.fromMap(Map<String, dynamic> m) => BusinessPhoto(
      id: m['id'],
      businessId: m['business_id'],
      url: m['url'] ?? '',
      caption: m['caption'],
      sortOrder: _int(m['sort_order'], 100));
}

/// Horario público de apertura (unión del horario del equipo).
class PublicHours {
  final int weekday; // 0 = domingo … 6 = sábado
  final String opens; // 'HH:mm'
  final String closes;
  PublicHours({required this.weekday, required this.opens, required this.closes});
  factory PublicHours.fromMap(Map<String, dynamic> m) => PublicHours(
      weekday: _int(m['weekday']),
      opens: (m['opens'] ?? '').toString().substring(0, 5),
      closes: (m['closes'] ?? '').toString().substring(0, 5));
}

/// Catálogo de comodidades que un negocio puede marcar.
class Amenity {
  final String id;
  final String label;
  final int iconCodePoint; // Icons.*.codePoint, para no depender de Flutter aquí
  const Amenity(this.id, this.label, this.iconCodePoint);
}

const amenityCatalog = <Amenity>[
  Amenity('wifi', 'Wi-Fi gratis', 0xe63e),             // Icons.wifi
  Amenity('parking', 'Parking', 0xe54f),               // Icons.local_parking
  Amenity('accessible', 'Accesible', 0xe914),          // Icons.accessible
  Amenity('card', 'Pago con tarjeta', 0xe8a1),         // Icons.credit_card
  Amenity('online_payment', 'Pago online', 0xe8a1),
  Amenity('kids', 'Apto para niños', 0xe7f3),          // Icons.child_care
  Amenity('pets', 'Admite mascotas', 0xe91d),          // Icons.pets
  Amenity('air_conditioning', 'Aire acondicionado', 0xeb3c), // Icons.ac_unit
  Amenity('home_service', 'Servicio a domicilio', 0xe88a),  // Icons.home
  Amenity('late_hours', 'Horario ampliado', 0xe8b5),   // Icons.schedule
];

const paymentMethodLabels = <String, String>{
  'cash': 'Efectivo',
  'card': 'Tarjeta',
  'bizum': 'Bizum',
  'transfer': 'Transferencia',
  'online': 'Pago online',
};
