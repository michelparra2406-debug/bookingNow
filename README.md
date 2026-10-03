# BookingNow — Reservas de citas para cualquier servicio

App móvil (Android/iOS) para **clientes** y **negocios** + **panel web de
administración**, pensada para cualquier sector que trabaje con citas:
peluquerías y barberías, clínicas, fisioterapia, psicología, fitness,
talleres, veterinarias, asesorías, clases, tatuadores, fotógrafos…

Toma como referencia Booksy y añade lo que a Booksy le falta (ver
[docs/FUNCIONALIDADES.md](docs/FUNCIONALIDADES.md)): facturación integrada
**Verifactu-ready** y sincronizada con los programas de facturación más usados
en España (Holded, Quipu, Contasimple, Sage, a3, Billin, FacturaDirecta),
señales por Bizum/tarjeta sin obligar a un procesador propio, panel web
completo, recursos y clases con aforo, importación/exportación de clientes,
WhatsApp, lista de espera automática, bonos y membresías.

## Stack (misma arquitectura que Top 20 Local)

| Capa | Tecnología |
|---|---|
| App móvil + panel web | **Flutter** (un solo código: Android, iOS y web). El modo negocio se adapta: barra inferior en móvil, menú lateral en escritorio |
| Backend | **Supabase** (PostgreSQL + Auth + API automática + Realtime + Storage) |
| Lógica de negocio | Funciones SQL `security definer` (huecos, reservas, cancelaciones, facturas) + Row Level Security multi-tenant |
| Tareas | **Edge Functions** (Deno): `invoice-sync`, `send-notifications`, `payments` + **pg_cron** |
| Push | Firebase Cloud Messaging (HTTP v1) |
| Email / SMS / WhatsApp | Resend / Twilio / Meta WhatsApp Cloud API |
| Pagos | Stripe (tarjeta + Bizum) y Redsys |
| CI | Codemagic (`codemagic.yaml`): Android, iOS y web |

## Estructura

```
BookingNow/
├── bookingnow_app/              # Proyecto Flutter
│   └── lib/
│       ├── main.dart            # Arranque, tema claro/oscuro, i18n es/en
│       ├── config.dart          # --dart-define (SUPABASE_URL, ANON_KEY…)
│       ├── app_theme.dart
│       ├── models/models.dart   # Modelos de dominio + catálogo de integraciones
│       ├── services/            # auth, data (cliente), business (negocio), push, sesión
│       ├── utils/               # errores amigables, formatos de fecha
│       ├── widgets/common.dart
│       ├── l10n/                # app_es.arb, app_en.arb
│       └── screens/
│           ├── auth/            # login, registro, verificación
│           ├── client/          # explorar, detalle negocio, flujo de reserva,
│           │                    # mis citas, detalle cita, perfil
│           └── business/        # onboarding, dashboard, agenda, clientes,
│                                # servicios, equipo, lista de espera, facturas,
│                                # bonos, marketing, informes, integraciones, ajustes
├── supabase/
│   ├── schema.sql               # Esquema completo (tablas, RPC, vistas, RLS, sectores)
│   ├── seed-demo.sql            # Datos de demostración (2 negocios)
│   └── functions/
│       ├── invoice-sync/        # Cola de facturas → adaptadores por proveedor
│       │   └── adapters/        # holded, quipu, contasimple, sage, a3, billin,
│       │                        # facturadirecta, webhook, verifactu_aeat
│       ├── send-notifications/  # push, email, SMS, WhatsApp (recordatorios…)
│       └── payments/            # Stripe Checkout (tarjeta+Bizum) + webhook
├── docs/
│   ├── ARQUITECTURA.md
│   ├── FUNCIONALIDADES.md       # Booksy vs BookingNow, roadmap
│   └── INTEGRACIONES_FACTURACION.md
├── codemagic.yaml
└── README.md
```

## Puesta en marcha

### 1. Supabase

1. Crea un proyecto en https://supabase.com.
2. **SQL Editor → New query**: pega `supabase/schema.sql` completo y ejecútalo.
   Crea tablas, funciones, vistas, RLS y los 16 sectores con plantillas de
   servicios.
3. **Authentication → Providers → Email**: activa email. Para pruebas puedes
   desactivar "Confirm email". Opcional: **Phone** con Twilio para verificar
   teléfonos.
4. Copia de **Settings → API** la `Project URL` y la `anon public key`.
5. (Opcional) Tras registrar tu primer usuario en la app, ejecuta
   `supabase/seed-demo.sql` para tener dos negocios de ejemplo.

### 2. Edge Functions y tareas programadas

```bash
supabase functions deploy invoice-sync
supabase functions deploy send-notifications
supabase functions deploy payments --no-verify-jwt
supabase secrets set SYNC_TRIGGER_SECRET=... NOTIF_TRIGGER_SECRET=... \
  FCM_SERVICE_ACCOUNT='{...}' RESEND_API_KEY=... EMAIL_FROM='BookingNow <no-reply@tudominio>' \
  STRIPE_SECRET_KEY=... STRIPE_WEBHOOK_SECRET=... PUBLIC_BOOKING_HOST=https://tudominio
```

Activa **pg_cron** y **pg_net** (Database → Extensions) y ejecuta los
`cron.schedule` comentados al final de `schema.sql` (cola de notificaciones
cada minuto, sincronización de facturas cada 5 min, no-shows automáticos,
caducidad de bonos y lista de espera).

### 3. Compilar la app

```bash
cd bookingnow_app
flutter pub get
flutter run --dart-define=SUPABASE_URL=https://TU-PROYECTO.supabase.co \
            --dart-define=SUPABASE_ANON_KEY=TU_ANON_KEY
```

- **Panel web**: `flutter run -d chrome` con los mismos `--dart-define`, o
  `flutter build web --release` y despliega `build/web` (Netlify, Vercel,
  Cloudflare Pages…).
- **Android en este equipo**: el antivirus corporativo bloquea Gradle; usa el
  contenedor Docker como en Top 20 (ver abajo) o Codemagic.
- **iOS**: Codemagic (`ios-sin-firma` o `ios-testflight`).
- **Push**: añade `google-services.json` (Android) y
  `GoogleService-Info.plist` (iOS) de tu proyecto Firebase. Sin ellos la app
  funciona igual (el push se desactiva solo).

```powershell
docker run --rm `
  -v "C:\Users\michel.parra\Documents\Claude\BookingNow\bookingnow_app:/app" `
  -v bn-gradle:/root/.gradle -v bn-androidsdk:/opt/android-sdk-linux `
  -w /app ghcr.io/cirruslabs/flutter:stable `
  bash -c "git config --global --add safe.directory '*'; mv -f android/local.properties /tmp/lp.bak 2>/dev/null; flutter pub get > /dev/null && flutter build apk --debug --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=..."
```

El APK queda en `bookingnow_app\build\app\outputs\flutter-apk\app-debug.apk`.
La primera vez tarda unos 25 min (descarga el SDK a los volúmenes `bn-*`);
después unos 10 min. Si cambias la versión de algún plugin, borra
`bookingnow_app\build` (excepto `web`) antes de compilar: la caché incremental
de Kotlin de la versión anterior provoca errores "Unresolved reference" en el
plugin. Para release: `flutter build apk --release` (mismo comando).

### 4. Primer uso

1. Regístrate en la app → entras en **modo cliente** (explorar negocios).
2. Perfil → **Crear mi negocio** → eliges sector (la app adapta vocabulario y
   crea servicios de ejemplo) → entras en **modo negocio**.
3. Ajustes → **Fiscal** (NIF, razón social) para poder facturar; **Página
   pública** → publicar para aparecer en el marketplace.
4. Integraciones → conecta tu programa de facturación (Holded, Quipu…).

## Funcionalidades (resumen)

**Clientes**: marketplace por sector/ciudad, ficha de negocio con servicios,
equipo, bonos y opiniones verificadas; reserva en 4 pasos (varios servicios +
variantes + extras, profesional o "cualquiera", calendario con huecos reales,
código promocional, señal); mis citas (cancelar según política, cambiar hora,
repetir, valorar, QR, añadir a Google Calendar); lista de espera con aviso
automático; bonos, facturas y notificaciones; verificación de teléfono.

**Negocios**: onboarding por sector; dashboard con KPIs (hoy, pendientes,
ingresos, no-show, lista de espera); agenda día/semana por profesional con
bloqueos y alta manual (walk-in/teléfono); ficha de cliente (historial,
no-shows, notas, bloqueo, RGPD, bonos), importación CSV y exportación;
servicios con variantes, extras, aforo, buffers y señal; equipo con roles,
horarios y ausencias; lista de espera; facturas con numeración correlativa,
huella Verifactu y QR, sincronizadas con el software de facturación; bonos,
membresías y tarjetas regalo; promociones y campañas (push/email/SMS/WhatsApp);
informes; integraciones (facturación, pagos, mensajería, calendario, Reserve
with Google); ajustes de políticas (antelación, cancelación, tasas no-show,
señal, confirmación manual); página pública con QR.

Detalle y comparativa con Booksy en [docs/FUNCIONALIDADES.md](docs/FUNCIONALIDADES.md).

## Seguridad

- RLS en todas las tablas; multi-tenant por `business_id` con funciones
  `is_member()` / `has_role()`.
- Toda la lógica sensible (huecos, creación/cancelación de reservas,
  facturas, importaciones) va por RPC `security definer` validada en servidor.
- Las credenciales de integraciones se guardan en `integrations.credentials`
  y **solo las leen las Edge Functions** (la app usa `v_integrations_public`).
  En producción se recomienda cifrarlas con Supabase Vault.
- Los solapes de agenda los impide un `exclusion constraint` en PostgreSQL.
- `audit_log` registra creación/cambios de reservas y facturas.

## Estado

Fase 1 (este repositorio): esquema completo, app cliente, app negocio y panel
web, Edge Functions de facturación/notificaciones/pagos, CI. Pendiente para
producción: **firma Android con keystore propio** (ahora la release va con la clave
de depuración y Play Protect la bloquea; crear keystore, `key.properties` y
`signingConfigs` como en Top 20), generación de PDF de factura, alta como productor de software
Verifactu (datos del SIF), verificación de cada API de proveedor con cuenta
real, página pública de reservas sin app (web) y Reserve with Google.
