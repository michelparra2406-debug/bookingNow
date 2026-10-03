import 'package:bookingnow_app/models/models.dart';
import 'package:bookingnow_app/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async => initializeDateFormatting('es'));

  group('formatEuros', () {
    test('formatea céntimos con coma decimal', () {
      expect(formatEuros(2500), '25,00 €');
      expect(formatEuros(1999), '19,99 €');
      expect(formatEuros(0), '0,00 €');
    });
  });

  group('Service', () {
    test('priceLabel según tipo de precio', () {
      Service s(String type) => Service(
          id: '1', businessId: 'b', name: 'Corte', durationMin: 30,
          priceCents: 2500, priceType: type);
      expect(s('fixed').priceLabel, '25,00 €');
      expect(s('from').priceLabel, 'Desde 25,00 €');
      expect(s('free').priceLabel, 'Gratis');
      expect(s('variable').priceLabel, 'A consultar');
    });

    test('fromMap parsea variantes, extras y profesionales anidados', () {
      final s = Service.fromMap({
        'id': 's1', 'business_id': 'b1', 'name': 'Corte', 'duration_min': 45,
        'price_cents': '2500', 'vat_pct': '21.00',
        'service_variants': [
          {'id': 'v1', 'service_id': 's1', 'name': 'Largo', 'duration_min': 60, 'price_cents': 3000}
        ],
        'service_addon_links': [
          {'service_addons': {'id': 'a1', 'business_id': 'b1', 'name': 'Hidratante', 'price_cents': 1000}},
          {'service_addons': null},
        ],
        'service_staff': [{'member_id': 'm1'}, {'member_id': 'm2'}],
      });
      expect(s.priceCents, 2500);
      expect(s.vatPct, 21);
      expect(s.variants.single.name, 'Largo');
      expect(s.addons.single.priceCents, 1000);
      expect(s.staffIds, ['m1', 'm2']);
    });
  });

  group('Booking', () {
    test('fromMap tolera la vista v_bookings_full y calcula estados', () {
      final b = Booking.fromMap({
        'id': 'bk', 'code': 'ABC12345', 'business_id': 'b', 'customer_id': 'c',
        'starts_at': '2030-01-01T10:00:00Z', 'ends_at': '2030-01-01T10:45:00Z',
        'status': 'confirmed', 'total_cents': 2500, 'customer_name': 'Ana',
        'services_summary': 'Corte + Lavado', 'duration_min': '45', 'invoiced': false,
      });
      expect(b.isActive, isTrue);
      expect(b.isPast, isFalse);
      expect(b.canReview, isFalse);
      expect(b.durationMin, 45);
      expect(b.servicesSummary, 'Corte + Lavado');
    });

    test('canReview solo cuando está completada y sin valorar', () {
      Booking b(String status, bool rated) => Booking(
          id: '1', code: 'X', businessId: 'b', customerId: 'c',
          startsAt: DateTime(2026, 1, 1, 10), endsAt: DateTime(2026, 1, 1, 11),
          status: status, rated: rated);
      expect(b('completed', false).canReview, isTrue);
      expect(b('completed', true).canReview, isFalse);
      expect(b('confirmed', false).canReview, isFalse);
    });
  });

  group('Customer', () {
    test('iniciales', () {
      Customer c(String n) => Customer(id: '1', businessId: 'b', fullName: n);
      expect(c('Ana Ruiz').initials, 'AR');
      expect(c('Ana').initials, 'A');
      expect(c('  ').initials, '?');
    });
  });

  group('BusinessKpis', () {
    test('tasa de no-show', () {
      expect(BusinessKpis(noShows30d: 2, finished30d: 10).noShowRate, 0.2);
      expect(BusinessKpis().noShowRate, 0);
    });
  });

  group('Fmt', () {
    test('duración legible', () {
      expect(Fmt.duration(30), '30 min');
      expect(Fmt.duration(60), '1 h');
      expect(Fmt.duration(90), '1 h 30 min');
    });
    test('estados traducidos', () {
      expect(Fmt.bookingStatus('no_show'), 'No presentado');
      expect(Fmt.paymentMethod('bizum'), 'Bizum');
    });
  });

  group('integrationProviders', () {
    test('incluye los sistemas de facturación españoles y Verifactu', () {
      final ids = integrationProviders.map((p) => p.id).toSet();
      for (final id in ['holded', 'quipu', 'contasimple', 'sage', 'a3', 'billin', 'facturadirecta', 'verifactu_aeat', 'stripe', 'redsys', 'whatsapp']) {
        expect(ids, contains(id));
      }
      expect(integrationProviders.where((p) => p.category == 'invoicing').length, greaterThanOrEqualTo(8));
    });
  });
}
