# Arquitectura

Misma base que **Top 20 Local**: Flutter + Supabase, lógica en PostgreSQL con
RLS y funciones `security definer`, Edge Functions en Deno para tareas con
servicios externos, Codemagic para compilar.

```
┌────────────────────────────┐   ┌────────────────────────────┐
│  App cliente (Flutter)     │   │  App negocio / Panel web   │
│  Android · iOS             │   │  Android · iOS · Web       │
└─────────────┬──────────────┘   └─────────────┬──────────────┘
              │ supabase_flutter (JWT)          │
              ▼                                 ▼
┌───────────────────────────────────────────────────────────────┐
│ Supabase                                                      │
│  Auth (email, OTP, SMS)                                       │
│  PostgREST  ──► tablas con RLS multi-tenant (business_id)     │
│  RPC        ──► get_available_slots, create_booking,          │
│                 cancel_booking, reschedule_booking,           │
│                 set_booking_status, issue_invoice,            │
│                 join_waitlist, import_customers, create_business │
│  Vistas     ──► v_marketplace, v_bookings_full, v_business_kpis │
│  Colas      ──► notifications, sync_jobs                      │
│  pg_cron    ──► cada min / 5 min / hora / día                 │
└──────┬──────────────────┬──────────────────┬──────────────────┘
       ▼                  ▼                  ▼
 send-notifications   invoice-sync        payments
 FCM · Resend ·       adapters/           Stripe Checkout
 Twilio · WhatsApp    holded, quipu…      (tarjeta + Bizum)
```

## Un solo código Flutter, dos modos y dos formatos

- `AppSession` (singleton `ChangeNotifier`) guarda el perfil, los negocios de
  los que el usuario es miembro y el **negocio activo**. Si hay negocio activo
  la app arranca en `BusinessShell`; si no, en `ClientShell`. Se cambia de modo
  desde Perfil / menú.
- `BusinessShell` es **adaptativo**: `< 900 px` → `NavigationBar` inferior +
  menú "Más"; `≥ 900 px` (web/escritorio) → menú lateral con las 12 secciones.
  Así el panel web de administración es la misma app compilada con
  `flutter build web`.
- Permisos por rol en UI (`Member.canManage`) y en servidor (RLS `has_role`).

## Modelo de datos (resumen)

- **Tenant**: `businesses` (datos fiscales, políticas, plan) → `locations`,
  `business_members` (roles), `invoice_series`, `notification_settings`,
  `integrations`.
- **Catálogo**: `service_categories`, `services` (duración, buffers, precio,
  IVA, aforo, señal), `service_variants`, `service_addons`, `service_staff`,
  `resources`.
- **Disponibilidad**: `working_hours` (semanal por profesional),
  `schedule_overrides` (días), `time_blocks` (bloqueos puntuales).
- **CRM**: `customers` (ficha por negocio; `user_id` opcional), `intake_forms`.
- **Reservas**: `bookings` (+ exclusion constraint anti-solape),
  `booking_items`, `waitlist`, `reviews`.
- **Ventas**: `packages`, `customer_packages`, `promo_codes`.
- **Facturación**: `invoices` (Verifactu + sync externo), `invoice_lines`,
  `sync_jobs`.
- **Notificaciones**: `device_tokens`, `notifications` (cola multicanal).
- **Auditoría**: `audit_log`.

## Motor de huecos (`get_available_slots`)

1. Profesionales que realizan el servicio (`service_staff`), activos y
   reservables (o el indicado).
2. Ventana de trabajo del día: `schedule_overrides` del día > `working_hours`
   del profesional > horario general del negocio. Si hay cierre, sin huecos.
3. Candidatos cada `p_step_min` minutos dentro de la ventana que quepan con la
   duración (variante si la hay).
4. Se descartan los que chocan con reservas activas (aplicando buffers del
   servicio) o con `time_blocks`, y los anteriores a `now() + booking_lead_min`.
5. `create_booking` vuelve a comprobar el hueco; el `exclusion constraint`
   garantiza que dos transacciones simultáneas no puedan solapar.

## Seguridad

- RLS por tabla; datos públicos solo para negocios `is_published`.
- Inserciones de reservas, facturas y votos de valoración **solo por RPC**.
- `integrations.credentials`: lectura exclusiva del `service_role`; la app
  consulta `v_integrations_public`.
- Edge Functions internas protegidas con secreto compartido (`x-trigger-secret`);
  las que invoca la app verifican el JWT y el rol con `has_role`.

## Decisiones

- **Sin paquete de estado**: `setState` + un `ChangeNotifier`, como en Top 20.
- **Importes en céntimos** (int) en BD y modelos; se formatean al pintar.
- **Fechas en UTC** en BD; `timezone` por negocio para calcular días y mostrar.
- **Textos en español** en pantallas; ARB preparado para añadir idiomas sin
  tocar lógica.
