-- ============================================================
-- BOOKINGNOW — Datos de demostración
-- Ejecutar DESPUÉS de schema.sql y de registrar al menos un usuario en la
-- app (el primer usuario de auth.users será el owner de los negocios demo).
-- ============================================================

do $$
declare
  v_owner uuid;
  v_biz uuid;
  v_biz2 uuid;
  v_member uuid;
  v_member2 uuid;
  v_svc uuid;
  v_cust uuid;
  v_name text;
begin
  select id into v_owner from auth.users order by created_at limit 1;
  if v_owner is null then
    raise exception 'Registra un usuario en la app antes de ejecutar el seed';
  end if;
  select full_name into v_name from profiles where id = v_owner;

  -- ---------- Negocio 1: peluquería ----------
  insert into businesses (name, sector_id, slug, phone, description, created_by, is_published,
                          legal_name, tax_id, fiscal_address, fiscal_postal_code, fiscal_city, fiscal_province,
                          deposit_pct, cancellation_hours, cancellation_fee_pct, rating_avg, rating_count)
  values ('Studio Marta Peluquería', 'beauty', 'studio-marta', '+34 600 111 222',
          'Peluquería y color en el centro de Madrid. Especialistas en balayage y cortes a medida.',
          v_owner, true, 'Marta García López', '12345678Z', 'Calle Mayor 12', '28013', 'Madrid', 'Madrid',
          20, 24, 50, 4.8, 37)
  returning id into v_biz;

  insert into business_members (business_id, user_id, role, display_name, title, color)
  values (v_biz, v_owner, 'owner', coalesce(nullif(v_name,''), 'Marta'), 'Directora y estilista', '#4F46E5')
  returning id into v_member;
  insert into business_members (business_id, role, display_name, title, color)
  values (v_biz, 'staff', 'Lucía Fernández', 'Colorista', '#10B981')
  returning id into v_member2;

  insert into locations (business_id, name, address, postal_code, city, province, lat, lng, is_default)
  values (v_biz, 'Studio Marta', 'Calle Mayor 12', '28013', 'Madrid', 'Madrid', 40.4167, -3.7033, true);

  insert into invoice_series (business_id, prefix, year) values (v_biz, 'F', extract(year from now())::int);
  insert into notification_settings (business_id, reminder_hours, channels, ask_confirmation)
  values (v_biz, '{24,2}', '{push,email,whatsapp}', true);

  -- Horarios: L-V 9:30-19:30 ambas; sábado 10-14 solo Marta
  insert into working_hours (business_id, member_id, weekday, start_time, end_time)
  select v_biz, m, d, '09:30', '19:30' from unnest(array[v_member, v_member2]) m, generate_series(1,5) d;
  insert into working_hours (business_id, member_id, weekday, start_time, end_time)
  values (v_biz, v_member, 6, '10:00', '14:00');

  -- Servicios de plantilla + asignación
  insert into service_categories (business_id, name)
  select distinct v_biz, category_name from sector_service_templates where sector_id = 'beauty';
  insert into services (business_id, category_id, name, duration_min, price_cents, requires_deposit)
  select v_biz, c.id, t.name, t.duration_min, t.price_cents, t.price_cents >= 4500
  from sector_service_templates t join service_categories c on c.business_id = v_biz and c.name = t.category_name
  where t.sector_id = 'beauty';
  insert into service_staff (service_id, member_id)
  select s.id, m.id from services s join business_members m on m.business_id = v_biz where s.business_id = v_biz;

  -- Variantes para "Corte mujer"
  select id into v_svc from services where business_id = v_biz and name = 'Corte mujer';
  insert into service_variants (service_id, name, duration_min, price_cents) values
    (v_svc, 'Pelo corto', 30, 2200), (v_svc, 'Pelo medio', 45, 2500), (v_svc, 'Pelo largo', 60, 3000);

  -- Extras
  insert into service_addons (business_id, name, duration_min, price_cents) values
    (v_biz, 'Tratamiento hidratante', 15, 1000), (v_biz, 'Lavado con masaje', 10, 500);
  insert into service_addon_links (service_id, addon_id)
  select s.id, a.id from services s, service_addons a where s.business_id = v_biz and a.business_id = v_biz;

  -- Bonos y promociones
  insert into packages (business_id, type, name, description, price_cents, sessions, service_ids, validity_days)
  select v_biz, 'bundle', 'Bono 5 cortes', 'Cinco cortes al precio de cuatro', 10000, 5, array[v_svc], 365;
  insert into packages (business_id, type, name, description, price_cents, period, sessions_per_period, discount_pct)
  values (v_biz, 'membership', 'Club Studio', 'Un peinado al mes y 10 % en todo lo demás', 1900, 'monthly', 1, 10);
  insert into packages (business_id, type, name, price_cents) values (v_biz, 'gift_card', 'Tarjeta regalo 50 €', 5000);
  insert into promo_codes (business_id, code, discount_pct, first_visit_only) values (v_biz, 'BIENVENIDA', 15, true);

  -- Clientes demo
  insert into customers (business_id, full_name, email, phone, source, total_visits, tags) values
    (v_biz, 'Ana Ruiz', 'ana.ruiz@example.com', '+34611111111', 'manual', 12, '{vip}'),
    (v_biz, 'Carlos Pérez', 'carlos@example.com', '+34622222222', 'import', 3, '{}'),
    (v_biz, 'Elena Soto', null, '+34633333333', 'walk_in', 1, '{}');
  select id into v_cust from customers where business_id = v_biz and full_name = 'Ana Ruiz';

  -- Reservas: hoy y mañana
  insert into bookings (business_id, customer_id, member_id, starts_at, ends_at, status, source, total_cents)
  values
    (v_biz, v_cust, v_member, date_trunc('day', now()) + interval '11 hours', date_trunc('day', now()) + interval '11 hours 45 min', 'confirmed', 'app', 2500),
    (v_biz, (select id from customers where business_id = v_biz and full_name = 'Carlos Pérez'), v_member2,
     date_trunc('day', now()) + interval '1 day 16 hours', date_trunc('day', now()) + interval '1 day 18 hours 30 min', 'pending', 'app', 9000),
    (v_biz, (select id from customers where business_id = v_biz and full_name = 'Elena Soto'), v_member,
     now() - interval '7 days', now() - interval '7 days' + interval '45 min', 'completed', 'walk_in', 2500);
  insert into booking_items (booking_id, service_id, name, duration_min, price_cents)
  select b.id, v_svc, 'Corte mujer · Pelo medio', 45, 2500 from bookings b where b.business_id = v_biz and b.total_cents = 2500;
  insert into booking_items (booking_id, service_id, name, duration_min, price_cents)
  select b.id, s.id, s.name, s.duration_min, s.price_cents from bookings b
  join services s on s.business_id = v_biz and s.name = 'Mechas balayage' where b.business_id = v_biz and b.total_cents = 9000;

  -- ---------- Negocio 2: fisioterapia (muestra la adaptación a otro sector) ----------
  insert into businesses (name, sector_id, slug, phone, description, created_by, is_published, requires_confirmation, rating_avg, rating_count)
  values ('Clínica Fisio Vital', 'physio', 'fisio-vital', '+34 600 333 444',
          'Fisioterapia deportiva, suelo pélvico y readaptación. Primera valoración gratuita.',
          v_owner, true, true, 4.9, 112)
  returning id into v_biz2;
  insert into business_members (business_id, user_id, role, display_name, title, color)
  values (v_biz2, v_owner, 'owner', coalesce(nullif(v_name,''), 'Dr. Ortega'), 'Fisioterapeuta', '#0EA5E9');
  insert into locations (business_id, name, address, city, is_default) values (v_biz2, 'Consulta', 'Av. Diagonal 400', 'Barcelona', true);
  insert into invoice_series (business_id, prefix, year) values (v_biz2, 'F', extract(year from now())::int);
  insert into notification_settings (business_id) values (v_biz2);
  insert into working_hours (business_id, member_id, weekday, start_time, end_time)
  select v_biz2, m.id, d, '08:00', '20:00' from business_members m, generate_series(1,5) d where m.business_id = v_biz2;
  insert into service_categories (business_id, name)
  select distinct v_biz2, category_name from sector_service_templates where sector_id = 'physio';
  insert into services (business_id, category_id, name, duration_min, price_cents, vat_pct)
  select v_biz2, c.id, t.name, t.duration_min, t.price_cents, 0  -- sanidad: exento de IVA
  from sector_service_templates t join service_categories c on c.business_id = v_biz2 and c.name = t.category_name
  where t.sector_id = 'physio';
  insert into service_staff (service_id, member_id)
  select s.id, m.id from services s join business_members m on m.business_id = v_biz2 where s.business_id = v_biz2;
  insert into resources (business_id, name, type) values (v_biz2, 'Box 1', 'room'), (v_biz2, 'Box 2', 'room');

  raise notice 'Seed OK: negocios % y % creados para el usuario %', v_biz, v_biz2, v_owner;
end $$;
