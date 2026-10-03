-- ============================================================
-- BOOKINGNOW — Esquema de base de datos (Supabase / PostgreSQL)
-- Plataforma multi-tenant de reservas de citas para cualquier servicio.
-- Ejecutar completo en: Supabase Dashboard > SQL Editor > New query
-- ============================================================

create extension if not exists pgcrypto;
create extension if not exists btree_gist;   -- exclusion constraints (solapes)
create extension if not exists unaccent;     -- búsqueda sin acentos

-- ============================================================
-- 1. TIPOS
-- ============================================================

do $$ begin
  create type booking_status as enum (
    'pending',      -- creada, pendiente de confirmación (o de pago de señal)
    'confirmed',    -- confirmada
    'checked_in',   -- cliente ha llegado
    'completed',    -- servicio realizado
    'cancelled',    -- cancelada por cliente o negocio
    'no_show'       -- cliente no se presentó
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type member_role as enum ('owner', 'manager', 'staff', 'reception');
exception when duplicate_object then null; end $$;

do $$ begin
  create type payment_status as enum ('none','pending','authorized','paid','refunded','failed');
exception when duplicate_object then null; end $$;

do $$ begin
  create type invoice_status as enum ('draft','issued','sent','paid','cancelled','rectified');
exception when duplicate_object then null; end $$;

do $$ begin
  create type notif_channel as enum ('push','email','sms','whatsapp');
exception when duplicate_object then null; end $$;

-- ============================================================
-- 2. SECTORES Y PLANTILLAS (la app se adapta a cualquier servicio)
-- ============================================================

-- Catálogo de sectores: cada uno trae vocabulario y plantillas de servicios
create table if not exists sectors (
  id text primary key,                      -- 'beauty', 'health', 'fitness', 'auto', 'legal', 'home', 'pets', 'education', 'other'
  name_es text not null,
  name_en text not null,
  icon text not null default 'storefront',  -- nombre de icono Material
  -- Vocabulario adaptable: cómo llama este sector a "profesional", "cliente", "cita"
  label_staff_es text not null default 'Profesional',
  label_customer_es text not null default 'Cliente',
  label_booking_es text not null default 'Cita',
  uses_resources boolean not null default false,  -- salas, boxes, elevadores, pistas…
  uses_group_sessions boolean not null default false, -- clases con aforo
  sort_order int not null default 100
);

create table if not exists sector_service_templates (
  id serial primary key,
  sector_id text not null references sectors (id) on delete cascade,
  category_name text not null,
  name text not null,
  duration_min int not null default 30,
  price_cents int not null default 0
);

-- ============================================================
-- 3. USUARIOS
-- ============================================================

-- Perfil de todo usuario (cliente final y/o miembro de un negocio)
create table if not exists profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null default '',
  email text,
  phone text,
  avatar_url text,
  locale text not null default 'es',
  phone_verified boolean not null default false,
  is_platform_admin boolean not null default false,  -- superadmin del SaaS
  marketing_opt_in boolean not null default false,
  created_at timestamptz not null default now()
);

-- ============================================================
-- 4. NEGOCIOS (tenants), SEDES, EQUIPO
-- ============================================================

create table if not exists businesses (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,                 -- bookingnow.app/b/<slug>
  name text not null,
  sector_id text not null references sectors (id),
  description text,
  logo_url text,
  cover_url text,
  phone text,
  email text,
  website text,
  instagram text,
  -- Datos fiscales (facturación / Verifactu)
  legal_name text,
  tax_id text,                               -- NIF/CIF
  fiscal_address text,
  fiscal_postal_code text,
  fiscal_city text,
  fiscal_province text,
  fiscal_country text not null default 'ES',
  vat_regime text not null default 'general', -- general | simplified | exempt | recargo
  -- Ajustes de reservas
  timezone text not null default 'Europe/Madrid',
  currency text not null default 'EUR',
  booking_lead_min int not null default 60,        -- antelación mínima
  booking_horizon_days int not null default 60,    -- hasta cuántos días vista
  cancellation_hours int not null default 24,      -- límite cancelación gratuita
  cancellation_fee_pct int not null default 0,     -- % del servicio si cancela tarde
  no_show_fee_pct int not null default 0,          -- % si no se presenta
  deposit_pct int not null default 0,              -- % de señal exigida al reservar
  requires_confirmation boolean not null default false, -- el negocio confirma manualmente
  allow_waitlist boolean not null default true,
  allow_recurring boolean not null default true,
  online_booking_enabled boolean not null default true,
  -- Plan SaaS
  plan text not null default 'free' check (plan in ('free','pro','business')),
  plan_valid_until date,
  is_published boolean not null default false,     -- visible en marketplace
  rating_avg numeric(3,2) not null default 0,
  rating_count int not null default 0,
  created_by uuid references profiles (id),
  created_at timestamptz not null default now()
);

create table if not exists locations (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses (id) on delete cascade,
  name text not null,
  address text,
  postal_code text,
  city text,
  province text,
  country text not null default 'ES',
  lat double precision,
  lng double precision,
  phone text,
  is_mobile_service boolean not null default false,  -- servicio a domicilio
  travel_radius_km int,
  travel_fee_cents int not null default 0,
  is_default boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists idx_locations_business on locations (business_id);

-- Equipo del negocio (profesionales, recepción, gestores)
create table if not exists business_members (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses (id) on delete cascade,
  user_id uuid references profiles (id) on delete set null, -- null = profesional sin cuenta
  role member_role not null default 'staff',
  display_name text not null,
  title text,                                 -- "Estilista senior", "Fisioterapeuta"
  avatar_url text,
  color text not null default '#7C4DFF',      -- color en la agenda
  bookable boolean not null default true,     -- aparece como opción al reservar
  commission_pct int not null default 0,
  active boolean not null default true,
  sort_order int not null default 100,
  created_at timestamptz not null default now(),
  unique (business_id, user_id)
);
create index if not exists idx_members_business on business_members (business_id);

-- Invitaciones de equipo por email
create table if not exists member_invites (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses (id) on delete cascade,
  email text not null,
  role member_role not null default 'staff',
  token text not null unique default encode(gen_random_bytes(16), 'hex'),
  accepted_at timestamptz,
  created_at timestamptz not null default now()
);

-- ============================================================
-- 5. CATÁLOGO: CATEGORÍAS, SERVICIOS, VARIANTES, EXTRAS, RECURSOS
-- ============================================================

create table if not exists service_categories (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses (id) on delete cascade,
  name text not null,
  sort_order int not null default 100
);

create table if not exists services (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses (id) on delete cascade,
  category_id uuid references service_categories (id) on delete set null,
  name text not null,
  description text,
  duration_min int not null check (duration_min > 0),
  buffer_before_min int not null default 0,
  buffer_after_min int not null default 0,
  price_cents int not null default 0,
  price_type text not null default 'fixed' check (price_type in ('fixed','from','free','variable')),
  vat_pct numeric(5,2) not null default 21,
  capacity int not null default 1,              -- >1 = sesión grupal / clase
  requires_resource boolean not null default false,
  online_bookable boolean not null default true,
  requires_deposit boolean not null default false,
  deposit_cents int,                              -- señal fija (si null se usa % del negocio)
  color text,
  image_url text,
  active boolean not null default true,
  sort_order int not null default 100,
  created_at timestamptz not null default now()
);
create index if not exists idx_services_business on services (business_id, active);

-- Variantes (ej. "Corte · pelo corto 30 min / pelo largo 45 min")
create table if not exists service_variants (
  id uuid primary key default gen_random_uuid(),
  service_id uuid not null references services (id) on delete cascade,
  name text not null,
  duration_min int not null,
  price_cents int not null,
  sort_order int not null default 100
);

-- Extras / add-ons (ej. "tratamiento hidratante +10 €")
create table if not exists service_addons (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses (id) on delete cascade,
  name text not null,
  duration_min int not null default 0,
  price_cents int not null default 0,
  active boolean not null default true
);
create table if not exists service_addon_links (
  service_id uuid references services (id) on delete cascade,
  addon_id uuid references service_addons (id) on delete cascade,
  primary key (service_id, addon_id)
);

-- Qué profesionales realizan cada servicio (con precio/duración opcional propio)
create table if not exists service_staff (
  service_id uuid references services (id) on delete cascade,
  member_id uuid references business_members (id) on delete cascade,
  duration_override_min int,
  price_override_cents int,
  primary key (service_id, member_id)
);

-- Recursos físicos: salas, boxes, sillones, elevadores, pistas, equipos
create table if not exists resources (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses (id) on delete cascade,
  location_id uuid references locations (id) on delete cascade,
  name text not null,
  type text not null default 'room',
  capacity int not null default 1,
  active boolean not null default true
);
create table if not exists service_resources (
  service_id uuid references services (id) on delete cascade,
  resource_id uuid references resources (id) on delete cascade,
  primary key (service_id, resource_id)
);

-- ============================================================
-- 6. DISPONIBILIDAD: HORARIOS, EXCEPCIONES, FESTIVOS, BLOQUEOS
-- ============================================================

-- Horario semanal por profesional (o del negocio si member_id es null)
create table if not exists working_hours (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses (id) on delete cascade,
  location_id uuid references locations (id) on delete cascade,
  member_id uuid references business_members (id) on delete cascade,
  weekday smallint not null check (weekday between 0 and 6),  -- 0=domingo … 6=sábado
  start_time time not null,
  end_time time not null,
  check (end_time > start_time)
);
create index if not exists idx_wh_member on working_hours (business_id, member_id, weekday);

-- Excepciones de un día concreto (vacaciones, horario especial, festivo)
create table if not exists schedule_overrides (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses (id) on delete cascade,
  member_id uuid references business_members (id) on delete cascade, -- null = todo el negocio
  date date not null,
  is_closed boolean not null default true,
  start_time time,
  end_time time,
  reason text
);
create index if not exists idx_overrides on schedule_overrides (business_id, date);

-- Bloqueos puntuales en la agenda (descanso, reunión, formación)
create table if not exists time_blocks (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses (id) on delete cascade,
  member_id uuid references business_members (id) on delete cascade,
  resource_id uuid references resources (id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  title text,
  check (ends_at > starts_at)
);
create index if not exists idx_blocks on time_blocks (business_id, starts_at);

-- ============================================================
-- 7. CLIENTES DEL NEGOCIO (CRM)
-- ============================================================

-- Ficha de cliente propia de cada negocio. user_id enlaza con la cuenta de
-- la app si el cliente la tiene; si no, es un cliente "manual" (walk-in,
-- teléfono, importado por CSV). Los datos pertenecen al negocio (exportables).
create table if not exists customers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses (id) on delete cascade,
  user_id uuid references profiles (id) on delete set null,
  full_name text not null,
  email text,
  phone text,
  birthdate date,
  gender text,
  tax_id text,                       -- NIF para facturar
  address text,
  notes text,                        -- notas internas (alergias, preferencias…)
  tags text[] not null default '{}',
  source text not null default 'app',   -- app | manual | import | walk_in | google
  blocked boolean not null default false, -- no puede reservar online
  no_show_count int not null default 0,
  total_visits int not null default 0,
  total_spent_cents bigint not null default 0,
  last_visit_at timestamptz,
  gdpr_consent_at timestamptz,
  created_at timestamptz not null default now(),
  unique (business_id, user_id)
);
create index if not exists idx_customers_business on customers (business_id);
create index if not exists idx_customers_search on customers
  using gin (to_tsvector('simple', coalesce(full_name,'') || ' ' || coalesce(email,'') || ' ' || coalesce(phone,'')));

-- Formularios de admisión / consentimientos (RGPD, consentimiento informado)
create table if not exists intake_forms (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses (id) on delete cascade,
  name text not null,
  schema jsonb not null default '[]'::jsonb,  -- [{key,label,type,required}]
  required_for_service_ids uuid[] not null default '{}',
  active boolean not null default true
);
create table if not exists intake_responses (
  id uuid primary key default gen_random_uuid(),
  form_id uuid not null references intake_forms (id) on delete cascade,
  customer_id uuid not null references customers (id) on delete cascade,
  booking_id uuid,
  answers jsonb not null,
  signed_at timestamptz not null default now()
);

-- ============================================================
-- 8. RESERVAS
-- ============================================================

create table if not exists bookings (
  id uuid primary key default gen_random_uuid(),
  code text not null unique default upper(substr(encode(gen_random_bytes(5),'hex'),1,8)),
  business_id uuid not null references businesses (id) on delete cascade,
  location_id uuid references locations (id) on delete set null,
  customer_id uuid not null references customers (id) on delete restrict,
  member_id uuid references business_members (id) on delete set null,
  resource_id uuid references resources (id) on delete set null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status booking_status not null default 'pending',
  source text not null default 'app',       -- app | web | admin | google | walk_in | recurring
  customer_notes text,
  internal_notes text,
  total_cents int not null default 0,
  deposit_cents int not null default 0,
  payment_status payment_status not null default 'none',
  payment_provider text,                     -- stripe | redsys | bizum | cash | tpv
  payment_ref text,
  recurrence_id uuid,                        -- agrupa reservas recurrentes
  reminder_sent_at timestamptz,
  confirmed_at timestamptz,
  cancelled_at timestamptz,
  cancelled_by uuid references profiles (id),
  cancel_reason text,
  rated boolean not null default false,
  created_by uuid references profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at),
  -- Un profesional no puede tener dos reservas activas solapadas
  exclude using gist (
    member_id with =,
    tstzrange(starts_at, ends_at) with &&
  ) where (member_id is not null and status in ('pending','confirmed','checked_in'))
);
create index if not exists idx_bookings_business_date on bookings (business_id, starts_at);
create index if not exists idx_bookings_customer on bookings (customer_id, starts_at desc);
create index if not exists idx_bookings_member_date on bookings (member_id, starts_at);

-- Líneas de la reserva (varios servicios + extras en la misma cita)
create table if not exists booking_items (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references bookings (id) on delete cascade,
  service_id uuid references services (id) on delete set null,
  variant_id uuid references service_variants (id) on delete set null,
  addon_id uuid references service_addons (id) on delete set null,
  name text not null,                 -- snapshot del nombre
  duration_min int not null,
  price_cents int not null,
  vat_pct numeric(5,2) not null default 21,
  sort_order int not null default 0
);
create index if not exists idx_booking_items on booking_items (booking_id);

-- Lista de espera: si se libera un hueco se avisa automáticamente
create table if not exists waitlist (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses (id) on delete cascade,
  customer_id uuid not null references customers (id) on delete cascade,
  service_id uuid not null references services (id) on delete cascade,
  member_id uuid references business_members (id) on delete set null,
  date_from date not null,
  date_to date not null,
  time_from time,
  time_to time,
  status text not null default 'waiting' check (status in ('waiting','notified','booked','expired','cancelled')),
  notified_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists idx_waitlist on waitlist (business_id, status, date_from);

-- Valoraciones verificadas (solo tras una reserva completada)
create table if not exists reviews (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses (id) on delete cascade,
  booking_id uuid not null unique references bookings (id) on delete cascade,
  customer_id uuid not null references customers (id) on delete cascade,
  member_id uuid references business_members (id) on delete set null,
  rating smallint not null check (rating between 1 and 5),
  comment text,
  reply text,
  replied_at timestamptz,
  created_at timestamptz not null default now()
);

-- ============================================================
-- 9. BONOS, MEMBRESÍAS, TARJETAS REGALO, PROMOCIONES
-- ============================================================

-- Definición de producto vendible
create table if not exists packages (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses (id) on delete cascade,
  type text not null check (type in ('bundle','membership','gift_card')),
  name text not null,
  description text,
  price_cents int not null,
  vat_pct numeric(5,2) not null default 21,
  sessions int,                   -- bundle: nº de sesiones
  service_ids uuid[] not null default '{}',   -- servicios canjeables
  validity_days int,              -- caducidad desde la compra
  period text check (period in ('monthly','yearly')),  -- membership
  sessions_per_period int,        -- membership: sesiones incluidas por periodo
  discount_pct int,               -- membership: descuento en resto de servicios
  active boolean not null default true
);

-- Compra concreta de un cliente
create table if not exists customer_packages (
  id uuid primary key default gen_random_uuid(),
  package_id uuid not null references packages (id),
  customer_id uuid not null references customers (id) on delete cascade,
  business_id uuid not null references businesses (id) on delete cascade,
  code text not null unique default upper(substr(encode(gen_random_bytes(6),'hex'),1,12)),
  sessions_total int,
  sessions_used int not null default 0,
  balance_cents int,              -- gift card
  valid_from date not null default current_date,
  valid_until date,
  status text not null default 'active' check (status in ('active','expired','consumed','cancelled')),
  payment_ref text,
  created_at timestamptz not null default now()
);

-- Códigos promocionales
create table if not exists promo_codes (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses (id) on delete cascade,
  code text not null,
  discount_pct int,
  discount_cents int,
  valid_from date,
  valid_until date,
  max_uses int,
  uses int not null default 0,
  first_visit_only boolean not null default false,
  active boolean not null default true,
  unique (business_id, code)
);

-- ============================================================
-- 10. FACTURACIÓN (Verifactu-ready) E INTEGRACIONES
-- ============================================================

-- Series de facturación por negocio (ej. 'F' para facturas, 'R' rectificativas)
create table if not exists invoice_series (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses (id) on delete cascade,
  prefix text not null default 'F',
  year int not null,
  next_number int not null default 1,
  unique (business_id, prefix, year)
);

create table if not exists invoices (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses (id) on delete cascade,
  customer_id uuid references customers (id) on delete set null,
  booking_id uuid references bookings (id) on delete set null,
  series text not null,
  number int not null,
  full_number text not null,                     -- 'F2026-000123'
  issue_date date not null default current_date,
  type text not null default 'F1' check (type in ('F1','F2','R1','R2','R3','R4','R5')), -- tipos Verifactu
  rectifies_invoice_id uuid references invoices (id),
  -- Receptor (snapshot)
  recipient_name text not null,
  recipient_tax_id text,
  recipient_address text,
  -- Importes
  subtotal_cents int not null default 0,
  vat_cents int not null default 0,
  total_cents int not null default 0,
  status invoice_status not null default 'issued',
  payment_method text,                           -- cash | card | bizum | transfer | stripe | redsys
  paid_at timestamptz,
  notes text,
  pdf_url text,
  -- Verifactu: registro de facturación encadenado (huella SHA-256)
  verifactu_hash text,
  verifactu_prev_hash text,
  verifactu_qr_url text,
  verifactu_sent_at timestamptz,
  verifactu_response jsonb,
  -- Sincronización con el software de facturación externo
  external_provider text,                        -- holded | quipu | contasimple | sage | a3 | billin | facturadirecta | webhook
  external_id text,
  external_synced_at timestamptz,
  external_error text,
  created_at timestamptz not null default now(),
  unique (business_id, full_number)
);
create index if not exists idx_invoices_business on invoices (business_id, issue_date desc);

create table if not exists invoice_lines (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references invoices (id) on delete cascade,
  description text not null,
  quantity numeric(10,2) not null default 1,
  unit_price_cents int not null,
  vat_pct numeric(5,2) not null default 21,
  discount_pct numeric(5,2) not null default 0,
  total_cents int not null,
  sort_order int not null default 0
);

-- Conexión del negocio con sistemas externos (facturación, pagos, mensajería, calendario)
create table if not exists integrations (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references businesses (id) on delete cascade,
  provider text not null,                        -- holded | quipu | contasimple | sage | a3 | billin | facturadirecta | verifactu_aeat | webhook
                                                 -- stripe | redsys | whatsapp | twilio | google_calendar | reserve_with_google
  category text not null check (category in ('invoicing','payments','messaging','calendar','marketplace')),
  enabled boolean not null default true,
  -- Credenciales cifradas con pgsodium/Vault en producción; aquí se guardan
  -- como jsonb y SOLO las lee el service_role (Edge Functions). Las RLS
  -- impiden que el cliente las lea: ver vista v_integrations_public.
  credentials jsonb not null default '{}'::jsonb,
  settings jsonb not null default '{}'::jsonb,   -- ej. {"auto_sync": true, "default_account": "700"}
  last_sync_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  unique (business_id, provider)
);

-- Cola de sincronización saliente (procesada por la Edge Function invoice-sync)
create table if not exists sync_jobs (
  id bigserial primary key,
  business_id uuid not null references businesses (id) on delete cascade,
  provider text not null,
  entity text not null,                          -- invoice | customer
  entity_id uuid not null,
  attempts int not null default 0,
  status text not null default 'queued' check (status in ('queued','running','done','error')),
  error text,
  run_after timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index if not exists idx_sync_jobs on sync_jobs (status, run_after);

-- ============================================================
-- 11. NOTIFICACIONES
-- ============================================================

create table if not exists device_tokens (
  user_id uuid not null references profiles (id) on delete cascade,
  token text not null,
  platform text not null default 'android',
  updated_at timestamptz not null default now(),
  primary key (user_id, token)
);

-- Preferencias de recordatorios por negocio
create table if not exists notification_settings (
  business_id uuid primary key references businesses (id) on delete cascade,
  reminder_hours int[] not null default '{24,2}',       -- recordatorios antes de la cita
  channels notif_channel[] not null default '{push,email}',
  ask_confirmation boolean not null default true,       -- "responde SI para confirmar"
  review_request_hours int not null default 2,          -- tras completar, pedir valoración
  template_overrides jsonb not null default '{}'::jsonb
);

-- Cola de envío (procesada por la Edge Function send-notifications)
create table if not exists notifications (
  id bigserial primary key,
  business_id uuid references businesses (id) on delete cascade,
  user_id uuid references profiles (id) on delete cascade,
  customer_id uuid references customers (id) on delete cascade,
  booking_id uuid references bookings (id) on delete cascade,
  channel notif_channel not null,
  template text not null,                 -- booking_created | booking_confirmed | reminder | cancelled | waitlist_slot | review_request | marketing
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'queued' check (status in ('queued','sent','failed','read')),
  scheduled_for timestamptz not null default now(),
  sent_at timestamptz,
  error text,
  created_at timestamptz not null default now()
);
create index if not exists idx_notifications_queue on notifications (status, scheduled_for);
create index if not exists idx_notifications_user on notifications (user_id, created_at desc);

-- ============================================================
-- 12. AUDITORÍA
-- ============================================================

create table if not exists audit_log (
  id bigserial primary key,
  business_id uuid,
  user_id uuid,
  action text not null,
  entity text not null,
  entity_id uuid,
  data jsonb,
  created_at timestamptz not null default now()
);
create index if not exists idx_audit_business on audit_log (business_id, created_at desc);

-- ============================================================
-- 13. FUNCIONES AUXILIARES
-- ============================================================

-- ¿Es el usuario actual miembro (activo) del negocio?
create or replace function is_member(p_business uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from business_members
    where business_id = p_business and user_id = auth.uid() and active
  );
$$;

-- ¿Tiene el usuario un rol concreto o superior?
create or replace function has_role(p_business uuid, p_roles member_role[])
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from business_members
    where business_id = p_business and user_id = auth.uid() and active
      and role = any (p_roles)
  );
$$;

-- Perfil automático al registrarse
create or replace function handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, full_name, email, phone, locale)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    new.email,
    new.phone,
    coalesce(new.raw_user_meta_data ->> 'locale', 'es')
  );
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users for each row execute function handle_new_user();

create or replace function touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end; $$;
drop trigger if exists trg_bookings_touch on bookings;
create trigger trg_bookings_touch before update on bookings
  for each row execute function touch_updated_at();

-- Crear negocio: el creador queda como owner, con sede, serie y ajustes por defecto
create or replace function create_business(
  p_name text, p_sector text, p_slug text, p_phone text default null,
  p_city text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
  v_uid uuid := auth.uid();
  v_name text;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  insert into businesses (name, sector_id, slug, phone, created_by)
  values (p_name, p_sector, lower(p_slug), p_phone, v_uid)
  returning id into v_id;

  select full_name into v_name from profiles where id = v_uid;
  insert into business_members (business_id, user_id, role, display_name)
  values (v_id, v_uid, 'owner', coalesce(nullif(v_name,''), p_name));

  insert into locations (business_id, name, city, is_default)
  values (v_id, p_name, p_city, true);

  insert into invoice_series (business_id, prefix, year)
  values (v_id, 'F', extract(year from now())::int);

  insert into notification_settings (business_id) values (v_id);

  -- Horario por defecto L-V 9:00-18:00 para el owner
  insert into working_hours (business_id, member_id, weekday, start_time, end_time)
  select v_id, m.id, d, '09:00', '18:00'
  from business_members m, generate_series(1,5) d
  where m.business_id = v_id and m.user_id = v_uid;

  -- Servicios de plantilla del sector
  insert into service_categories (business_id, name)
  select distinct v_id, category_name from sector_service_templates where sector_id = p_sector;
  insert into services (business_id, category_id, name, duration_min, price_cents)
  select v_id, c.id, t.name, t.duration_min, t.price_cents
  from sector_service_templates t
  join service_categories c on c.business_id = v_id and c.name = t.category_name
  where t.sector_id = p_sector;
  insert into service_staff (service_id, member_id)
  select s.id, m.id from services s join business_members m on m.business_id = v_id
  where s.business_id = v_id;

  return v_id;
end;
$$;

-- ============================================================
-- 14. MOTOR DE DISPONIBILIDAD
-- ============================================================

-- Huecos disponibles de un servicio en un día, por profesional.
-- Devuelve el inicio de cada hueco (en UTC) y el profesional.
-- p_member null = cualquiera disponible.
create or replace function get_available_slots(
  p_business uuid,
  p_service uuid,
  p_date date,
  p_member uuid default null,
  p_variant uuid default null,
  p_step_min int default 15
) returns table (member_id uuid, starts_at timestamptz, ends_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare
  v_biz businesses%rowtype;
  v_duration int;
  v_buffer_before int;
  v_buffer_after int;
  v_dow int := extract(dow from p_date);
  v_now timestamptz := now();
  v_min_start timestamptz;
  v_max_date date;
begin
  select * into v_biz from businesses where id = p_business;
  if not found then return; end if;

  select coalesce(v.duration_min, s.duration_min), s.buffer_before_min, s.buffer_after_min
    into v_duration, v_buffer_before, v_buffer_after
  from services s left join service_variants v on v.id = p_variant
  where s.id = p_service and s.business_id = p_business and s.active;
  if v_duration is null then return; end if;

  v_min_start := v_now + make_interval(mins => v_biz.booking_lead_min);
  v_max_date := (v_now at time zone v_biz.timezone)::date + v_biz.booking_horizon_days;
  if p_date > v_max_date then return; end if;

  return query
  with staff as (
    select m.id from business_members m
    join service_staff ss on ss.member_id = m.id and ss.service_id = p_service
    where m.business_id = p_business and m.active and m.bookable
      and (p_member is null or m.id = p_member)
  ),
  -- Ventanas de trabajo del día (override del día > horario semanal)
  windows as (
    select s.id as member_id,
           ((p_date::text || ' ' || coalesce(o.start_time, w.start_time)::text)::timestamp at time zone v_biz.timezone) as w_start,
           ((p_date::text || ' ' || coalesce(o.end_time, w.end_time)::text)::timestamp at time zone v_biz.timezone) as w_end
    from staff s
    left join schedule_overrides o
      on o.business_id = p_business and o.date = p_date
     and (o.member_id = s.id or o.member_id is null)
    join working_hours w
      on w.business_id = p_business and w.weekday = v_dow
     and (w.member_id = s.id or (w.member_id is null and not exists (
          select 1 from working_hours w2 where w2.member_id = s.id and w2.business_id = p_business)))
    where not exists (
      select 1 from schedule_overrides o2
      where o2.business_id = p_business and o2.date = p_date and o2.is_closed
        and (o2.member_id = s.id or o2.member_id is null))
  ),
  candidates as (
    select w.member_id,
           gs as c_start,
           gs + make_interval(mins => v_duration) as c_end
    from windows w
    cross join lateral generate_series(w.w_start, w.w_end - make_interval(mins => v_duration), make_interval(mins => p_step_min)) gs
  )
  select c.member_id, c.c_start, c.c_end
  from candidates c
  where c.c_start >= v_min_start
    and not exists (
      select 1 from bookings b
      where b.member_id = c.member_id
        and b.status in ('pending','confirmed','checked_in')
        and tstzrange(b.starts_at - make_interval(mins => v_buffer_after),
                      b.ends_at + make_interval(mins => v_buffer_before))
            && tstzrange(c.c_start, c.c_end))
    and not exists (
      select 1 from time_blocks t
      where (t.member_id = c.member_id or t.member_id is null)
        and t.business_id = p_business
        and tstzrange(t.starts_at, t.ends_at) && tstzrange(c.c_start, c.c_end))
  order by c.c_start, c.member_id;
end;
$$;

-- ============================================================
-- 15. CICLO DE VIDA DE LA RESERVA (toda la lógica en servidor)
-- ============================================================

-- Obtiene (o crea) la ficha de cliente del usuario actual en un negocio
create or replace function ensure_customer(p_business uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
  v_p profiles%rowtype;
begin
  select id into v_id from customers where business_id = p_business and user_id = v_uid;
  if v_id is not null then return v_id; end if;
  select * into v_p from profiles where id = v_uid;
  insert into customers (business_id, user_id, full_name, email, phone, source)
  values (p_business, v_uid, coalesce(nullif(v_p.full_name,''), 'Cliente'), v_p.email, v_p.phone, 'app')
  returning id into v_id;
  return v_id;
end;
$$;

-- Crea una reserva validando disponibilidad, calcula precio y encola avisos.
-- p_items: [{"service_id": uuid, "variant_id": uuid|null, "addon_ids": [uuid]}]
create or replace function create_booking(
  p_business uuid,
  p_member uuid,
  p_starts_at timestamptz,
  p_items jsonb,
  p_customer uuid default null,       -- solo personal del negocio puede fijarlo
  p_notes text default null,
  p_source text default 'app',
  p_promo_code text default null,
  p_location uuid default null
) returns bookings language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_biz businesses%rowtype;
  v_customer uuid;
  v_item jsonb;
  v_svc services%rowtype;
  v_var service_variants%rowtype;
  v_addon service_addons%rowtype;
  v_duration int := 0;
  v_total int := 0;
  v_deposit int := 0;
  v_booking bookings%rowtype;
  v_ends timestamptz;
  v_is_staff boolean;
  v_cust customers%rowtype;
  v_promo promo_codes%rowtype;
  v_aid text;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  select * into v_biz from businesses where id = p_business;
  if not found then raise exception 'business_not_found'; end if;

  v_is_staff := is_member(p_business);
  if p_customer is not null and not v_is_staff then
    raise exception 'forbidden';
  end if;
  v_customer := coalesce(p_customer, ensure_customer(p_business));
  select * into v_cust from customers where id = v_customer;
  if v_cust.blocked and not v_is_staff then raise exception 'customer_blocked'; end if;

  if not v_is_staff then
    if not v_biz.online_booking_enabled then raise exception 'online_booking_disabled'; end if;
    if p_starts_at < now() + make_interval(mins => v_biz.booking_lead_min) then
      raise exception 'too_soon';
    end if;
  end if;

  -- Calcular duración y precio a partir de las líneas
  for v_item in select * from jsonb_array_elements(p_items) loop
    select * into v_svc from services
      where id = (v_item->>'service_id')::uuid and business_id = p_business and active;
    if not found then raise exception 'service_not_found'; end if;
    v_var := null;
    if v_item->>'variant_id' is not null then
      select * into v_var from service_variants where id = (v_item->>'variant_id')::uuid and service_id = v_svc.id;
    end if;
    v_duration := v_duration + coalesce(v_var.duration_min, v_svc.duration_min);
    v_total := v_total + coalesce(v_var.price_cents, v_svc.price_cents);
    if v_svc.requires_deposit then
      v_deposit := v_deposit + coalesce(v_svc.deposit_cents,
                     (coalesce(v_var.price_cents, v_svc.price_cents) * v_biz.deposit_pct) / 100);
    end if;
    for v_aid in select jsonb_array_elements_text(coalesce(v_item->'addon_ids','[]'::jsonb)) loop
      select * into v_addon from service_addons where id = v_aid::uuid and business_id = p_business;
      if found then
        v_duration := v_duration + v_addon.duration_min;
        v_total := v_total + v_addon.price_cents;
      end if;
    end loop;
  end loop;
  if v_duration = 0 then raise exception 'empty_booking'; end if;
  v_ends := p_starts_at + make_interval(mins => v_duration);

  -- Señal global del negocio si no hay señal por servicio
  if v_deposit = 0 and v_biz.deposit_pct > 0 then
    v_deposit := (v_total * v_biz.deposit_pct) / 100;
  end if;

  -- Código promocional
  if p_promo_code is not null then
    select * into v_promo from promo_codes
      where business_id = p_business and code = upper(p_promo_code) and active
        and (valid_from is null or valid_from <= current_date)
        and (valid_until is null or valid_until >= current_date)
        and (max_uses is null or uses < max_uses)
        and (not first_visit_only or v_cust.total_visits = 0);
    if not found then raise exception 'invalid_promo'; end if;
    v_total := greatest(0, v_total - coalesce(v_promo.discount_cents, 0)
                         - (v_total * coalesce(v_promo.discount_pct,0)) / 100);
    update promo_codes set uses = uses + 1 where id = v_promo.id;
  end if;

  -- Comprobar que el profesional está disponible (horario + sin solapes)
  if p_member is not null and not v_is_staff then
    if not exists (
      select 1 from get_available_slots(p_business, (p_items->0->>'service_id')::uuid,
               (p_starts_at at time zone v_biz.timezone)::date, p_member,
               (p_items->0->>'variant_id')::uuid, 5) s
      where s.starts_at = p_starts_at
    ) then
      raise exception 'slot_unavailable';
    end if;
  end if;

  insert into bookings (business_id, location_id, customer_id, member_id, starts_at, ends_at,
                        status, source, customer_notes, total_cents, deposit_cents,
                        payment_status, created_by)
  values (p_business,
          coalesce(p_location, (select id from locations where business_id = p_business and is_default limit 1)),
          v_customer, p_member, p_starts_at, v_ends,
          case when v_deposit > 0 and not v_is_staff then 'pending'
               when v_biz.requires_confirmation and not v_is_staff then 'pending'
               else 'confirmed' end,
          p_source, p_notes, v_total, v_deposit,
          case when v_deposit > 0 then 'pending' else 'none' end,
          v_uid)
  returning * into v_booking;

  -- Líneas
  for v_item in select * from jsonb_array_elements(p_items) loop
    select * into v_svc from services where id = (v_item->>'service_id')::uuid;
    v_var := null;
    if v_item->>'variant_id' is not null then
      select * into v_var from service_variants where id = (v_item->>'variant_id')::uuid;
    end if;
    insert into booking_items (booking_id, service_id, variant_id, name, duration_min, price_cents, vat_pct)
    values (v_booking.id, v_svc.id, v_var.id,
            v_svc.name || coalesce(' · ' || v_var.name, ''),
            coalesce(v_var.duration_min, v_svc.duration_min),
            coalesce(v_var.price_cents, v_svc.price_cents), v_svc.vat_pct);
    for v_aid in select jsonb_array_elements_text(coalesce(v_item->'addon_ids','[]'::jsonb)) loop
      select * into v_addon from service_addons where id = v_aid::uuid;
      if found then
        insert into booking_items (booking_id, addon_id, name, duration_min, price_cents, vat_pct)
        values (v_booking.id, v_addon.id, v_addon.name, v_addon.duration_min, v_addon.price_cents, v_svc.vat_pct);
      end if;
    end loop;
  end loop;

  -- Notificaciones: confirmación al cliente + aviso al negocio + recordatorios
  perform enqueue_booking_notifications(v_booking.id, 'booking_created');

  insert into audit_log (business_id, user_id, action, entity, entity_id, data)
  values (p_business, v_uid, 'create', 'booking', v_booking.id, to_jsonb(v_booking));

  return v_booking;
exception
  when exclusion_violation then
    raise exception 'slot_unavailable';
end;
$$;

-- Encola avisos (confirmación inmediata + recordatorios según ajustes)
create or replace function enqueue_booking_notifications(p_booking uuid, p_template text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_b bookings%rowtype;
  v_c customers%rowtype;
  v_s notification_settings%rowtype;
  v_h int;
  v_ch notif_channel;
  v_owner uuid;
begin
  select * into v_b from bookings where id = p_booking;
  select * into v_c from customers where id = v_b.customer_id;
  select * into v_s from notification_settings where business_id = v_b.business_id;

  -- Aviso inmediato al cliente por cada canal configurado
  foreach v_ch in array coalesce(v_s.channels, '{push,email}'::notif_channel[]) loop
    if (v_ch = 'push' and v_c.user_id is not null)
       or (v_ch = 'email' and v_c.email is not null)
       or (v_ch in ('sms','whatsapp') and v_c.phone is not null) then
      insert into notifications (business_id, user_id, customer_id, booking_id, channel, template)
      values (v_b.business_id, v_c.user_id, v_c.id, v_b.id, v_ch, p_template);
    end if;
  end loop;

  -- Aviso push al equipo (owner/manager y profesional asignado)
  for v_owner in
    select distinct m.user_id from business_members m
    where m.business_id = v_b.business_id and m.user_id is not null and m.active
      and (m.role in ('owner','manager') or m.id = v_b.member_id)
  loop
    insert into notifications (business_id, user_id, booking_id, channel, template)
    values (v_b.business_id, v_owner, v_b.id, 'push', p_template || '_staff');
  end loop;

  -- Recordatorios programados (solo al crear/confirmar)
  if p_template in ('booking_created','booking_confirmed') then
    delete from notifications where booking_id = v_b.id and template = 'reminder' and status = 'queued';
    foreach v_h in array coalesce(v_s.reminder_hours, '{24,2}') loop
      if v_b.starts_at - make_interval(hours => v_h) > now() then
        foreach v_ch in array coalesce(v_s.channels, '{push,email}'::notif_channel[]) loop
          insert into notifications (business_id, user_id, customer_id, booking_id, channel, template, scheduled_for, payload)
          values (v_b.business_id, v_c.user_id, v_c.id, v_b.id, v_ch, 'reminder',
                  v_b.starts_at - make_interval(hours => v_h),
                  jsonb_build_object('hours_before', v_h, 'ask_confirmation', v_s.ask_confirmation));
        end loop;
      end if;
    end loop;
  end if;
end;
$$;

-- Cambiar estado de reserva (confirmar, check-in, completar, no-show) — personal
create or replace function set_booking_status(p_booking uuid, p_status booking_status)
returns bookings language plpgsql security definer set search_path = public as $$
declare
  v_b bookings%rowtype;
begin
  select * into v_b from bookings where id = p_booking;
  if not found then raise exception 'booking_not_found'; end if;
  if not is_member(v_b.business_id) then raise exception 'forbidden'; end if;

  update bookings set status = p_status,
    confirmed_at = case when p_status = 'confirmed' then now() else confirmed_at end
    where id = p_booking returning * into v_b;

  if p_status = 'confirmed' then
    perform enqueue_booking_notifications(p_booking, 'booking_confirmed');
  elsif p_status = 'completed' then
    update customers set total_visits = total_visits + 1,
      total_spent_cents = total_spent_cents + v_b.total_cents,
      last_visit_at = v_b.starts_at where id = v_b.customer_id;
    -- Petición de valoración
    insert into notifications (business_id, user_id, customer_id, booking_id, channel, template, scheduled_for)
    select v_b.business_id, c.user_id, c.id, v_b.id, 'push', 'review_request',
           now() + make_interval(hours => coalesce(s.review_request_hours, 2))
    from customers c left join notification_settings s on s.business_id = v_b.business_id
    where c.id = v_b.customer_id and c.user_id is not null;
    -- Consumir sesión de bono si procede
    perform consume_package_session(v_b.id);
  elsif p_status = 'no_show' then
    update customers set no_show_count = no_show_count + 1 where id = v_b.customer_id;
  end if;

  insert into audit_log (business_id, user_id, action, entity, entity_id, data)
  values (v_b.business_id, auth.uid(), 'status:' || p_status, 'booking', p_booking, null);
  return v_b;
end;
$$;

-- Cancelar (cliente o negocio). Aplica política de cancelación y avisa a la lista de espera.
create or replace function cancel_booking(p_booking uuid, p_reason text default null)
returns bookings language plpgsql security definer set search_path = public as $$
declare
  v_b bookings%rowtype;
  v_biz businesses%rowtype;
  v_uid uuid := auth.uid();
  v_is_staff boolean;
  v_is_owner boolean;
  v_fee int := 0;
begin
  select * into v_b from bookings where id = p_booking;
  if not found then raise exception 'booking_not_found'; end if;
  select * into v_biz from businesses where id = v_b.business_id;
  v_is_staff := is_member(v_b.business_id);
  v_is_owner := exists (select 1 from customers c where c.id = v_b.customer_id and c.user_id = v_uid);
  if not (v_is_staff or v_is_owner) then raise exception 'forbidden'; end if;
  if v_b.status in ('cancelled','completed','no_show') then raise exception 'invalid_state'; end if;

  -- Cancelación tardía del cliente: se aplica la tasa configurada
  if v_is_owner and not v_is_staff
     and v_b.starts_at - make_interval(hours => v_biz.cancellation_hours) < now() then
    v_fee := (v_b.total_cents * v_biz.cancellation_fee_pct) / 100;
  end if;

  update bookings set status = 'cancelled', cancelled_at = now(), cancelled_by = v_uid,
    cancel_reason = p_reason,
    internal_notes = case when v_fee > 0
      then coalesce(internal_notes,'') || E'\n[Cancelación tardía: tasa ' || (v_fee/100.0)::text || ' €]'
      else internal_notes end
    where id = p_booking returning * into v_b;

  perform enqueue_booking_notifications(p_booking, 'booking_cancelled');
  perform notify_waitlist(v_b.business_id, v_b.member_id, v_b.starts_at);

  insert into audit_log (business_id, user_id, action, entity, entity_id, data)
  values (v_b.business_id, v_uid, 'cancel', 'booking', p_booking, jsonb_build_object('fee_cents', v_fee, 'reason', p_reason));
  return v_b;
end;
$$;

-- Reprogramar (cliente dentro de la política, o personal siempre)
create or replace function reschedule_booking(p_booking uuid, p_starts_at timestamptz, p_member uuid default null)
returns bookings language plpgsql security definer set search_path = public as $$
declare
  v_b bookings%rowtype;
  v_biz businesses%rowtype;
  v_uid uuid := auth.uid();
  v_is_staff boolean;
  v_dur interval;
begin
  select * into v_b from bookings where id = p_booking;
  if not found then raise exception 'booking_not_found'; end if;
  select * into v_biz from businesses where id = v_b.business_id;
  v_is_staff := is_member(v_b.business_id);
  if not (v_is_staff or exists (select 1 from customers c where c.id = v_b.customer_id and c.user_id = v_uid)) then
    raise exception 'forbidden';
  end if;
  if not v_is_staff and v_b.starts_at - make_interval(hours => v_biz.cancellation_hours) < now() then
    raise exception 'too_late_to_reschedule';
  end if;
  v_dur := v_b.ends_at - v_b.starts_at;
  update bookings set starts_at = p_starts_at, ends_at = p_starts_at + v_dur,
    member_id = coalesce(p_member, member_id), reminder_sent_at = null
    where id = p_booking returning * into v_b;
  perform enqueue_booking_notifications(p_booking, 'booking_rescheduled');
  return v_b;
exception
  when exclusion_violation then raise exception 'slot_unavailable';
end;
$$;

-- Reservas recurrentes: crea N repeticiones semanales/quincenales/mensuales
create or replace function create_recurring_bookings(
  p_booking uuid, p_every_days int, p_count int
) returns int language plpgsql security definer set search_path = public as $$
declare
  v_b bookings%rowtype;
  v_i int;
  v_rec uuid := gen_random_uuid();
  v_created int := 0;
  v_new bookings%rowtype;
begin
  select * into v_b from bookings where id = p_booking;
  if not found then raise exception 'booking_not_found'; end if;
  if not is_member(v_b.business_id) and not exists (
    select 1 from customers c where c.id = v_b.customer_id and c.user_id = auth.uid()) then
    raise exception 'forbidden';
  end if;
  update bookings set recurrence_id = v_rec where id = p_booking;
  for v_i in 1..least(p_count, 52) loop
    begin
      insert into bookings (business_id, location_id, customer_id, member_id, starts_at, ends_at,
                            status, source, total_cents, recurrence_id, created_by)
      values (v_b.business_id, v_b.location_id, v_b.customer_id, v_b.member_id,
              v_b.starts_at + make_interval(days => p_every_days * v_i),
              v_b.ends_at + make_interval(days => p_every_days * v_i),
              v_b.status, 'recurring', v_b.total_cents, v_rec, auth.uid())
      returning * into v_new;
      insert into booking_items (booking_id, service_id, variant_id, addon_id, name, duration_min, price_cents, vat_pct)
      select v_new.id, service_id, variant_id, addon_id, name, duration_min, price_cents, vat_pct
      from booking_items where booking_id = p_booking;
      v_created := v_created + 1;
    exception when exclusion_violation then
      null; -- ese hueco ya estaba ocupado: se salta
    end;
  end loop;
  return v_created;
end;
$$;

-- Lista de espera
create or replace function join_waitlist(
  p_business uuid, p_service uuid, p_date_from date, p_date_to date,
  p_member uuid default null, p_time_from time default null, p_time_to time default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  insert into waitlist (business_id, customer_id, service_id, member_id, date_from, date_to, time_from, time_to)
  values (p_business, ensure_customer(p_business), p_service, p_member, p_date_from, p_date_to, p_time_from, p_time_to)
  returning id into v_id;
  return v_id;
end;
$$;

-- Al liberarse un hueco, avisa a quienes esperaban
create or replace function notify_waitlist(p_business uuid, p_member uuid, p_starts_at timestamptz)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_tz text;
  v_w record;
begin
  select timezone into v_tz from businesses where id = p_business;
  for v_w in
    select w.*, c.user_id from waitlist w join customers c on c.id = w.customer_id
    where w.business_id = p_business and w.status = 'waiting'
      and (w.member_id is null or w.member_id = p_member)
      and (p_starts_at at time zone v_tz)::date between w.date_from and w.date_to
      and (w.time_from is null or (p_starts_at at time zone v_tz)::time >= w.time_from)
      and (w.time_to is null or (p_starts_at at time zone v_tz)::time <= w.time_to)
    limit 5
  loop
    insert into notifications (business_id, user_id, customer_id, channel, template, payload)
    values (p_business, v_w.user_id, v_w.customer_id, 'push', 'waitlist_slot',
            jsonb_build_object('starts_at', p_starts_at, 'service_id', v_w.service_id, 'member_id', p_member));
    update waitlist set status = 'notified', notified_at = now() where id = v_w.id;
  end loop;
end;
$$;

-- Consumir sesión de bono/membresía al completar una reserva
create or replace function consume_package_session(p_booking uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  v_b bookings%rowtype;
  v_cp customer_packages%rowtype;
begin
  select * into v_b from bookings where id = p_booking;
  select cp.* into v_cp from customer_packages cp join packages p on p.id = cp.package_id
  where cp.customer_id = v_b.customer_id and cp.status = 'active'
    and p.type = 'bundle' and cp.sessions_used < cp.sessions_total
    and (cp.valid_until is null or cp.valid_until >= current_date)
    and exists (select 1 from booking_items bi where bi.booking_id = p_booking and bi.service_id = any (p.service_ids))
  order by cp.valid_until nulls last limit 1;
  if not found then return false; end if;
  update customer_packages set sessions_used = sessions_used + 1,
    status = case when sessions_used + 1 >= sessions_total then 'consumed' else 'active' end
    where id = v_cp.id;
  update bookings set payment_status = 'paid', payment_provider = 'package', payment_ref = v_cp.code
    where id = p_booking;
  return true;
end;
$$;

-- Valorar una reserva completada (solo el cliente) y recalcular media
create or replace function submit_review(p_booking uuid, p_rating int, p_comment text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_b bookings%rowtype;
begin
  select * into v_b from bookings where id = p_booking;
  if not found or v_b.status <> 'completed' then raise exception 'not_reviewable'; end if;
  if not exists (select 1 from customers c where c.id = v_b.customer_id and c.user_id = auth.uid()) then
    raise exception 'forbidden';
  end if;
  insert into reviews (business_id, booking_id, customer_id, member_id, rating, comment)
  values (v_b.business_id, p_booking, v_b.customer_id, v_b.member_id, p_rating, p_comment);
  update bookings set rated = true where id = p_booking;
  update businesses b set
    rating_avg = (select round(avg(rating)::numeric, 2) from reviews where business_id = b.id),
    rating_count = (select count(*) from reviews where business_id = b.id)
    where b.id = v_b.business_id;
end;
$$;

-- ============================================================
-- 16. FACTURACIÓN: emitir factura desde una reserva (Verifactu-ready)
-- ============================================================

-- Emite la factura: numeración correlativa por serie/año, snapshot del
-- receptor, huella SHA-256 encadenada con la anterior (modelo Verifactu) y
-- encola la sincronización con el software externo si está configurado.
create or replace function issue_invoice(
  p_booking uuid,
  p_payment_method text default 'card',
  p_recipient_name text default null,
  p_recipient_tax_id text default null,
  p_recipient_address text default null,
  p_series text default 'F'
) returns invoices language plpgsql security definer set search_path = public as $$
declare
  v_b bookings%rowtype;
  v_biz businesses%rowtype;
  v_c customers%rowtype;
  v_year int := extract(year from now())::int;
  v_num int;
  v_inv invoices%rowtype;
  v_sub int := 0; v_vat int := 0; v_tot int := 0;
  v_prev text;
  v_payload text;
  v_item booking_items%rowtype;
  v_provider text;
begin
  select * into v_b from bookings where id = p_booking;
  if not found then raise exception 'booking_not_found'; end if;
  if not has_role(v_b.business_id, '{owner,manager,reception}') then raise exception 'forbidden'; end if;
  if exists (select 1 from invoices where booking_id = p_booking and status <> 'cancelled') then
    raise exception 'already_invoiced';
  end if;
  select * into v_biz from businesses where id = v_b.business_id;
  select * into v_c from customers where id = v_b.customer_id;

  -- Numeración correlativa (bloqueo de fila para evitar duplicados)
  insert into invoice_series (business_id, prefix, year) values (v_biz.id, p_series, v_year)
    on conflict (business_id, prefix, year) do nothing;
  update invoice_series set next_number = next_number + 1
    where business_id = v_biz.id and prefix = p_series and year = v_year
    returning next_number - 1 into v_num;

  -- Totales
  for v_item in select * from booking_items where booking_id = p_booking loop
    v_sub := v_sub + v_item.price_cents;
    v_vat := v_vat + round(v_item.price_cents * v_item.vat_pct / 100);
  end loop;
  -- Si hubo descuento en la reserva, se prorratea sobre el total
  if v_b.total_cents < v_sub and v_sub > 0 then
    v_vat := round(v_vat * v_b.total_cents::numeric / v_sub);
    v_sub := v_b.total_cents;
  end if;
  v_tot := v_sub + v_vat;

  -- Huella anterior de la cadena del negocio
  select verifactu_hash into v_prev from invoices
    where business_id = v_biz.id and verifactu_hash is not null
    order by created_at desc limit 1;

  insert into invoices (business_id, customer_id, booking_id, series, number, full_number,
                        recipient_name, recipient_tax_id, recipient_address,
                        subtotal_cents, vat_cents, total_cents, payment_method, paid_at,
                        verifactu_prev_hash)
  values (v_biz.id, v_c.id, p_booking, p_series, v_num,
          p_series || v_year::text || '-' || lpad(v_num::text, 6, '0'),
          coalesce(p_recipient_name, v_c.full_name),
          coalesce(p_recipient_tax_id, v_c.tax_id),
          coalesce(p_recipient_address, v_c.address),
          v_sub, v_vat, v_tot, p_payment_method, now(), v_prev)
  returning * into v_inv;

  insert into invoice_lines (invoice_id, description, quantity, unit_price_cents, vat_pct, total_cents, sort_order)
  select v_inv.id, name, 1, price_cents, vat_pct, price_cents + round(price_cents * vat_pct / 100), sort_order
  from booking_items where booking_id = p_booking;

  -- Huella Verifactu: SHA-256 de los campos del registro + huella anterior
  -- (orden de campos según especificación AEAT: IDEmisorFactura, NumSerieFactura,
  --  FechaExpedicionFactura, TipoFactura, CuotaTotal, ImporteTotal, Huella, FechaHoraHusoGenRegistro)
  v_payload := 'IDEmisorFactura=' || coalesce(v_biz.tax_id,'') ||
               '&NumSerieFactura=' || v_inv.full_number ||
               '&FechaExpedicionFactura=' || to_char(v_inv.issue_date, 'DD-MM-YYYY') ||
               '&TipoFactura=' || v_inv.type ||
               '&CuotaTotal=' || (v_vat/100.0)::numeric(12,2)::text ||
               '&ImporteTotal=' || (v_tot/100.0)::numeric(12,2)::text ||
               '&Huella=' || coalesce(v_prev,'') ||
               '&FechaHoraHusoGenRegistro=' || to_char(now() at time zone 'Europe/Madrid', 'YYYY-MM-DD"T"HH24:MI:SS') || '+01:00';
  update invoices set
    verifactu_hash = upper(encode(digest(v_payload, 'sha256'), 'hex')),
    verifactu_qr_url = 'https://www2.agenciatributaria.gob.es/wlpl/TIKE-CONT/ValidarQR?nif=' ||
       coalesce(v_biz.tax_id,'') || '&numserie=' || v_inv.full_number ||
       '&fecha=' || to_char(v_inv.issue_date, 'DD-MM-YYYY') || '&importe=' || (v_tot/100.0)::numeric(12,2)::text
    where id = v_inv.id returning * into v_inv;

  update bookings set payment_status = 'paid', payment_provider = p_payment_method where id = p_booking;
  update customers set tax_id = coalesce(tax_id, p_recipient_tax_id), address = coalesce(address, p_recipient_address)
    where id = v_c.id;

  -- Encolar sincronización con el software de facturación conectado
  for v_provider in
    select provider from integrations
    where business_id = v_biz.id and category = 'invoicing' and enabled
  loop
    insert into sync_jobs (business_id, provider, entity, entity_id)
    values (v_biz.id, v_provider, 'invoice', v_inv.id);
  end loop;

  insert into audit_log (business_id, user_id, action, entity, entity_id, data)
  values (v_biz.id, auth.uid(), 'issue', 'invoice', v_inv.id, jsonb_build_object('number', v_inv.full_number, 'total', v_tot));
  return v_inv;
end;
$$;

-- Importar clientes por CSV (jsonb array) — evita el "alta manual" que critican a Booksy
create or replace function import_customers(p_business uuid, p_rows jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare v_n int := 0; v_r jsonb;
begin
  if not has_role(p_business, '{owner,manager,reception}') then raise exception 'forbidden'; end if;
  for v_r in select * from jsonb_array_elements(p_rows) loop
    insert into customers (business_id, full_name, email, phone, tax_id, notes, source)
    values (p_business, coalesce(v_r->>'full_name', v_r->>'name', 'Cliente'),
            nullif(v_r->>'email',''), nullif(v_r->>'phone',''), nullif(v_r->>'tax_id',''),
            v_r->>'notes', 'import');
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

-- ============================================================
-- 17. VISTAS
-- ============================================================

-- Marketplace: negocios publicados con sede principal y servicio más barato
create or replace view v_marketplace as
select b.id, b.slug, b.name, b.sector_id, s.name_es as sector_name, b.description,
       b.logo_url, b.cover_url, b.rating_avg, b.rating_count,
       l.city, l.address, l.lat, l.lng,
       (select min(price_cents) from services sv where sv.business_id = b.id and sv.active and sv.online_bookable) as min_price_cents,
       (select count(*) from services sv where sv.business_id = b.id and sv.active) as services_count
from businesses b
join sectors s on s.id = b.sector_id
left join locations l on l.business_id = b.id and l.is_default
where b.is_published and b.online_booking_enabled;

-- Agenda: reservas con datos de cliente, profesional y servicios
create or replace view v_bookings_full as
select b.*,
       c.full_name as customer_name, c.phone as customer_phone, c.email as customer_email,
       c.no_show_count as customer_no_shows,
       m.display_name as member_name, m.color as member_color,
       bz.name as business_name, bz.timezone,
       (select string_agg(bi.name, ' + ' order by bi.sort_order) from booking_items bi where bi.booking_id = b.id) as services_summary,
       (select coalesce(sum(bi.duration_min),0) from booking_items bi where bi.booking_id = b.id) as duration_min,
       exists (select 1 from invoices i where i.booking_id = b.id and i.status <> 'cancelled') as invoiced
from bookings b
join customers c on c.id = b.customer_id
left join business_members m on m.id = b.member_id
join businesses bz on bz.id = b.business_id;

-- Integraciones sin credenciales (lo que puede ver la app)
create or replace view v_integrations_public as
select id, business_id, provider, category, enabled, settings, last_sync_at, last_error, created_at
from integrations;

-- KPIs del negocio (dashboard)
create or replace view v_business_kpis as
select b.id as business_id,
  (select count(*) from bookings x where x.business_id = b.id and x.starts_at::date = (now() at time zone b.timezone)::date and x.status not in ('cancelled')) as bookings_today,
  (select count(*) from bookings x where x.business_id = b.id and x.starts_at >= date_trunc('month', now()) and x.status = 'completed') as completed_month,
  (select coalesce(sum(total_cents),0) from bookings x where x.business_id = b.id and x.starts_at >= date_trunc('month', now()) and x.status = 'completed') as revenue_month_cents,
  (select count(*) from bookings x where x.business_id = b.id and x.starts_at >= now() - interval '30 days' and x.status = 'no_show') as no_shows_30d,
  (select count(*) from bookings x where x.business_id = b.id and x.starts_at >= now() - interval '30 days' and x.status in ('completed','no_show')) as finished_30d,
  (select count(*) from customers x where x.business_id = b.id) as customers_total,
  (select count(*) from customers x where x.business_id = b.id and x.created_at >= date_trunc('month', now())) as customers_new_month,
  (select count(*) from waitlist x where x.business_id = b.id and x.status = 'waiting') as waitlist_waiting,
  (select count(*) from bookings x where x.business_id = b.id and x.status = 'pending') as pending_confirmation
from businesses b;

-- ============================================================
-- 18. SEGURIDAD (RLS)
-- ============================================================

alter table sectors enable row level security;
alter table sector_service_templates enable row level security;
alter table profiles enable row level security;
alter table businesses enable row level security;
alter table locations enable row level security;
alter table business_members enable row level security;
alter table member_invites enable row level security;
alter table service_categories enable row level security;
alter table services enable row level security;
alter table service_variants enable row level security;
alter table service_addons enable row level security;
alter table service_addon_links enable row level security;
alter table service_staff enable row level security;
alter table resources enable row level security;
alter table service_resources enable row level security;
alter table working_hours enable row level security;
alter table schedule_overrides enable row level security;
alter table time_blocks enable row level security;
alter table customers enable row level security;
alter table intake_forms enable row level security;
alter table intake_responses enable row level security;
alter table bookings enable row level security;
alter table booking_items enable row level security;
alter table waitlist enable row level security;
alter table reviews enable row level security;
alter table packages enable row level security;
alter table customer_packages enable row level security;
alter table promo_codes enable row level security;
alter table invoice_series enable row level security;
alter table invoices enable row level security;
alter table invoice_lines enable row level security;
alter table integrations enable row level security;
alter table sync_jobs enable row level security;
alter table device_tokens enable row level security;
alter table notification_settings enable row level security;
alter table notifications enable row level security;
alter table audit_log enable row level security;

-- Catálogos públicos
create policy "sectors readable" on sectors for select using (true);
create policy "templates readable" on sector_service_templates for select using (true);

-- Perfiles
create policy "profiles self read" on profiles for select using (auth.uid() = id or is_platform_admin);
create policy "profiles self update" on profiles for update using (auth.uid() = id);

-- Negocios: públicos si están publicados; el equipo siempre
create policy "businesses public read" on businesses for select
  using (is_published or is_member(id) or created_by = auth.uid());
create policy "businesses owner update" on businesses for update
  using (has_role(id, '{owner,manager}'));
-- (el insert se hace vía create_business)

-- Tablas de catálogo visibles públicamente para negocios publicados; edición por equipo
create policy "locations read" on locations for select
  using (exists (select 1 from businesses b where b.id = business_id and (b.is_published or is_member(b.id))));
create policy "locations write" on locations for all
  using (has_role(business_id, '{owner,manager}')) with check (has_role(business_id, '{owner,manager}'));

create policy "members read" on business_members for select
  using (exists (select 1 from businesses b where b.id = business_id and (b.is_published or is_member(b.id))));
create policy "members write" on business_members for all
  using (has_role(business_id, '{owner,manager}')) with check (has_role(business_id, '{owner,manager}'));

create policy "invites manage" on member_invites for all
  using (has_role(business_id, '{owner,manager}')) with check (has_role(business_id, '{owner,manager}'));

create policy "categories read" on service_categories for select
  using (exists (select 1 from businesses b where b.id = business_id and (b.is_published or is_member(b.id))));
create policy "categories write" on service_categories for all
  using (has_role(business_id, '{owner,manager}')) with check (has_role(business_id, '{owner,manager}'));

create policy "services read" on services for select
  using (exists (select 1 from businesses b where b.id = business_id and (b.is_published or is_member(b.id))));
create policy "services write" on services for all
  using (has_role(business_id, '{owner,manager}')) with check (has_role(business_id, '{owner,manager}'));

create policy "variants read" on service_variants for select
  using (exists (select 1 from services s join businesses b on b.id = s.business_id
                 where s.id = service_id and (b.is_published or is_member(b.id))));
create policy "variants write" on service_variants for all
  using (exists (select 1 from services s where s.id = service_id and has_role(s.business_id, '{owner,manager}')));

create policy "addons read" on service_addons for select
  using (exists (select 1 from businesses b where b.id = business_id and (b.is_published or is_member(b.id))));
create policy "addons write" on service_addons for all
  using (has_role(business_id, '{owner,manager}')) with check (has_role(business_id, '{owner,manager}'));
create policy "addon links read" on service_addon_links for select using (true);
create policy "addon links write" on service_addon_links for all
  using (exists (select 1 from services s where s.id = service_id and has_role(s.business_id, '{owner,manager}')));

create policy "service staff read" on service_staff for select using (true);
create policy "service staff write" on service_staff for all
  using (exists (select 1 from services s where s.id = service_id and has_role(s.business_id, '{owner,manager}')));

create policy "resources read" on resources for select using (is_member(business_id));
create policy "resources write" on resources for all
  using (has_role(business_id, '{owner,manager}')) with check (has_role(business_id, '{owner,manager}'));
create policy "service resources all" on service_resources for all
  using (exists (select 1 from services s where s.id = service_id and is_member(s.business_id)));

-- Horarios: lectura pública (necesaria para calcular huecos vía RPC, que es security definer; aquí solo equipo)
create policy "working hours read" on working_hours for select using (is_member(business_id));
create policy "working hours write" on working_hours for all
  using (has_role(business_id, '{owner,manager}')) with check (has_role(business_id, '{owner,manager}'));
create policy "overrides all" on schedule_overrides for all
  using (is_member(business_id)) with check (is_member(business_id));
create policy "blocks all" on time_blocks for all
  using (is_member(business_id)) with check (is_member(business_id));

-- Clientes: el equipo ve y edita; el propio cliente ve su ficha
create policy "customers staff" on customers for all
  using (is_member(business_id)) with check (is_member(business_id));
create policy "customers self read" on customers for select using (user_id = auth.uid());
create policy "customers self update" on customers for update using (user_id = auth.uid());

create policy "intake forms read" on intake_forms for select
  using (exists (select 1 from businesses b where b.id = business_id and (b.is_published or is_member(b.id))));
create policy "intake forms write" on intake_forms for all
  using (has_role(business_id, '{owner,manager}'));
create policy "intake responses staff" on intake_responses for select
  using (exists (select 1 from intake_forms f where f.id = form_id and is_member(f.business_id)));
create policy "intake responses self" on intake_responses for all
  using (exists (select 1 from customers c where c.id = customer_id and c.user_id = auth.uid()))
  with check (exists (select 1 from customers c where c.id = customer_id and c.user_id = auth.uid()));

-- Reservas: equipo todo; cliente las suyas (inserción solo vía create_booking)
create policy "bookings staff" on bookings for all
  using (is_member(business_id)) with check (is_member(business_id));
create policy "bookings self read" on bookings for select
  using (exists (select 1 from customers c where c.id = customer_id and c.user_id = auth.uid()));
create policy "booking items read" on booking_items for select
  using (exists (select 1 from bookings b where b.id = booking_id
                 and (is_member(b.business_id) or exists (
                   select 1 from customers c where c.id = b.customer_id and c.user_id = auth.uid()))));
create policy "booking items staff write" on booking_items for all
  using (exists (select 1 from bookings b where b.id = booking_id and is_member(b.business_id)));

create policy "waitlist staff" on waitlist for all using (is_member(business_id));
create policy "waitlist self" on waitlist for select
  using (exists (select 1 from customers c where c.id = customer_id and c.user_id = auth.uid()));
create policy "waitlist self cancel" on waitlist for update
  using (exists (select 1 from customers c where c.id = customer_id and c.user_id = auth.uid()));

create policy "reviews read" on reviews for select using (true);
create policy "reviews reply" on reviews for update using (has_role(business_id, '{owner,manager}'));

create policy "packages read" on packages for select
  using (exists (select 1 from businesses b where b.id = business_id and (b.is_published or is_member(b.id))));
create policy "packages write" on packages for all using (has_role(business_id, '{owner,manager}'));
create policy "customer packages staff" on customer_packages for all using (is_member(business_id));
create policy "customer packages self" on customer_packages for select
  using (exists (select 1 from customers c where c.id = customer_id and c.user_id = auth.uid()));

create policy "promos staff" on promo_codes for all using (has_role(business_id, '{owner,manager}'));

-- Facturación: solo equipo con rol; el cliente ve sus facturas
create policy "series staff" on invoice_series for select using (is_member(business_id));
create policy "invoices staff" on invoices for select using (is_member(business_id));
create policy "invoices staff update" on invoices for update using (has_role(business_id, '{owner,manager,reception}'));
create policy "invoices self" on invoices for select
  using (exists (select 1 from customers c where c.id = customer_id and c.user_id = auth.uid()));
create policy "invoice lines read" on invoice_lines for select
  using (exists (select 1 from invoices i where i.id = invoice_id and (is_member(i.business_id) or exists (
    select 1 from customers c where c.id = i.customer_id and c.user_id = auth.uid()))));

-- Integraciones: solo owner/manager. Las credenciales nunca salen por la API
-- (la app usa v_integrations_public; el insert/update sí puede enviar credenciales).
create policy "integrations owner" on integrations for all
  using (has_role(business_id, '{owner,manager}')) with check (has_role(business_id, '{owner,manager}'));
create policy "sync jobs read" on sync_jobs for select using (is_member(business_id));

-- Notificaciones
create policy "device tokens self" on device_tokens for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "notif settings" on notification_settings for all
  using (has_role(business_id, '{owner,manager}')) with check (has_role(business_id, '{owner,manager}'));
create policy "notifications self" on notifications for select using (user_id = auth.uid());
create policy "notifications self mark" on notifications for update using (user_id = auth.uid());
create policy "notifications staff" on notifications for select using (is_member(business_id));

create policy "audit staff" on audit_log for select using (has_role(business_id, '{owner,manager}'));

-- Las vistas heredan RLS de las tablas base (security_invoker)
alter view v_marketplace set (security_invoker = true);
alter view v_bookings_full set (security_invoker = true);
alter view v_integrations_public set (security_invoker = true);
alter view v_business_kpis set (security_invoker = true);

-- ============================================================
-- 19. DATOS INICIALES: SECTORES Y PLANTILLAS
-- ============================================================

insert into sectors (id, name_es, name_en, icon, label_staff_es, label_customer_es, label_booking_es, uses_resources, uses_group_sessions, sort_order) values
  ('beauty',    'Belleza y peluquería',     'Beauty & hair',        'content_cut',        'Profesional', 'Cliente',  'Cita',    false, false, 10),
  ('barber',    'Barbería',                 'Barbershop',           'face',               'Barbero',     'Cliente',  'Cita',    false, false, 11),
  ('nails',     'Uñas y estética',          'Nails & aesthetics',   'spa',                'Esteticista', 'Cliente',  'Cita',    false, false, 12),
  ('health',    'Salud y clínicas',         'Health & clinics',     'medical_services',   'Especialista','Paciente', 'Consulta',true,  false, 20),
  ('physio',    'Fisioterapia y masaje',    'Physio & massage',     'healing',            'Terapeuta',   'Paciente', 'Sesión',  true,  false, 21),
  ('dental',    'Clínica dental',           'Dental clinic',        'dentistry',          'Odontólogo',  'Paciente', 'Consulta',true,  false, 22),
  ('psychology','Psicología y coaching',    'Psychology & coaching','psychology',         'Terapeuta',   'Paciente', 'Sesión',  false, false, 23),
  ('fitness',   'Fitness y yoga',           'Fitness & yoga',       'fitness_center',     'Entrenador',  'Alumno',   'Clase',   true,  true,  30),
  ('auto',      'Taller y automoción',      'Auto repair',          'car_repair',         'Mecánico',    'Cliente',  'Cita',    true,  false, 40),
  ('home',      'Servicios a domicilio',    'Home services',        'home_repair_service','Técnico',     'Cliente',  'Visita',  false, false, 50),
  ('pets',      'Veterinaria y mascotas',   'Vets & pets',          'pets',               'Veterinario', 'Cliente',  'Cita',    false, false, 60),
  ('legal',     'Asesoría y despachos',     'Legal & consulting',   'gavel',              'Asesor',      'Cliente',  'Reunión', false, false, 70),
  ('education', 'Clases y formación',       'Tutoring & education', 'school',             'Profesor',    'Alumno',   'Clase',   true,  true,  80),
  ('tattoo',    'Tatuajes y piercing',      'Tattoo & piercing',    'brush',              'Artista',     'Cliente',  'Cita',    false, false, 90),
  ('photo',     'Fotografía y eventos',     'Photo & events',       'photo_camera',       'Fotógrafo',   'Cliente',  'Sesión',  false, false, 95),
  ('other',     'Otros servicios',          'Other services',       'storefront',         'Profesional', 'Cliente',  'Cita',    false, false, 999)
on conflict (id) do update set name_es = excluded.name_es, name_en = excluded.name_en, icon = excluded.icon;

insert into sector_service_templates (sector_id, category_name, name, duration_min, price_cents) values
  ('beauty','Corte','Corte mujer',45,2500),('beauty','Corte','Corte hombre',30,1500),('beauty','Color','Tinte raíz',90,4500),('beauty','Color','Mechas balayage',150,9000),('beauty','Peinado','Peinado y brushing',30,2000),
  ('barber','Corte','Corte clásico',30,1500),('barber','Corte','Corte + barba',45,2200),('barber','Barba','Arreglo de barba',20,1000),('barber','Barba','Afeitado con toalla caliente',30,1800),
  ('nails','Manicura','Manicura semipermanente',45,2500),('nails','Manicura','Uñas acrílicas',90,4500),('nails','Pedicura','Pedicura spa',60,3000),('nails','Facial','Limpieza facial',60,4500),
  ('health','Consultas','Primera consulta',30,6000),('health','Consultas','Revisión',20,4000),
  ('physio','Sesiones','Fisioterapia 45 min',45,4000),('physio','Sesiones','Masaje descontracturante',60,4500),('physio','Sesiones','Punción seca',30,3500),
  ('dental','Consultas','Revisión + limpieza',45,5000),('dental','Tratamientos','Empaste',45,7000),('dental','Tratamientos','Blanqueamiento',60,25000),
  ('psychology','Sesiones','Sesión individual',50,6000),('psychology','Sesiones','Sesión de pareja',60,8000),('psychology','Sesiones','Sesión online',50,5500),
  ('fitness','Clases','Yoga grupal',60,1200),('fitness','Clases','HIIT',45,1200),('fitness','Personal','Entrenamiento personal',60,4000),
  ('auto','Mantenimiento','Cambio de aceite y filtros',60,8000),('auto','Mantenimiento','Pre-ITV',45,4000),('auto','Neumáticos','Cambio de neumáticos',60,6000),('auto','Diagnosis','Diagnosis electrónica',30,4500),
  ('home','Limpieza','Limpieza del hogar (3 h)',180,6000),('home','Reparaciones','Visita de fontanero',60,5000),('home','Reparaciones','Visita de electricista',60,5000),
  ('pets','Veterinaria','Consulta veterinaria',30,4000),('pets','Veterinaria','Vacunación',15,3000),('pets','Peluquería','Baño y corte',90,3500),
  ('legal','Asesoría','Consulta inicial',30,6000),('legal','Asesoría','Reunión de seguimiento',60,9000),
  ('education','Clases','Clase particular 1 h',60,2500),('education','Clases','Clase grupal',60,1500),
  ('tattoo','Tatuaje','Consulta y diseño',30,0),('tattoo','Tatuaje','Sesión de tatuaje (2 h)',120,20000),('tattoo','Piercing','Piercing',20,3500),
  ('photo','Sesiones','Sesión de retrato',60,12000),('photo','Sesiones','Sesión familiar',90,18000),
  ('other','General','Servicio 30 min',30,3000),('other','General','Servicio 60 min',60,5000)
on conflict do nothing;

-- ============================================================
-- 20. TAREAS PROGRAMADAS (pg_cron, activar en Database > Extensions)
-- ============================================================
-- Procesar la cola de notificaciones cada minuto y sincronizar facturas
-- cada 5 min, llamando a las Edge Functions con el secreto compartido:
--
-- select cron.schedule('bn-notifications', '* * * * *', $$
--   select net.http_post(
--     url := 'https://TU-PROYECTO.supabase.co/functions/v1/send-notifications',
--     headers := '{"Content-Type":"application/json","x-trigger-secret":"TU_SECRETO"}'::jsonb,
--     body := '{"type":"process_queue"}'::jsonb);
-- $$);
-- select cron.schedule('bn-invoice-sync', '*/5 * * * *', $$
--   select net.http_post(
--     url := 'https://TU-PROYECTO.supabase.co/functions/v1/invoice-sync',
--     headers := '{"Content-Type":"application/json","x-trigger-secret":"TU_SECRETO"}'::jsonb,
--     body := '{"type":"process_queue"}'::jsonb);
-- $$);
-- -- Marcar como no_show las reservas confirmadas que pasaron sin check-in (cada hora)
-- select cron.schedule('bn-auto-noshow', '15 * * * *', $$
--   update bookings set status = 'no_show'
--   where status = 'confirmed' and ends_at < now() - interval '2 hours';
-- $$);
-- -- Caducar bonos y lista de espera
-- select cron.schedule('bn-expire', '0 3 * * *', $$
--   update customer_packages set status = 'expired' where status = 'active' and valid_until < current_date;
--   update waitlist set status = 'expired' where status in ('waiting','notified') and date_to < current_date;
-- $$);
