# Integraciones de facturación, pagos y mensajería

## Cómo funciona

1. El negocio completa sus **datos fiscales** (Ajustes → Fiscal) y conecta su
   software en **Integraciones** (las credenciales van a
   `integrations.credentials`; la app nunca las vuelve a leer).
2. Al pulsar **Emitir factura** sobre una cita completada, la función SQL
   `issue_invoice()`:
   - asigna número correlativo por serie y año (`F2026-000123`),
   - guarda el snapshot del receptor y las líneas con IVA,
   - calcula la **huella SHA-256 encadenada** con la factura anterior y la
     **URL del QR** de verificación (modelo Verifactu),
   - encola un `sync_jobs` por cada integración de facturación activa.
3. La Edge Function `invoice-sync` (pg_cron cada 5 min, o inmediata con
   `sync_invoice`) ejecuta el **adaptador** del proveedor, guarda
   `external_id`, fecha de sincronización o error, y reintenta con espera
   exponencial hasta 5 veces.

```
issue_invoice() ──► sync_jobs ──► invoice-sync ──► adapters/<proveedor>.ts ──► API externa
                       ▲                                   │
                       └──────── reintento (2,4,8,16 min) ◄┘
```

Añadir un proveedor = un archivo en `supabase/functions/invoice-sync/adapters/`
con `pushInvoice()` y `test()`, registrarlo en `adapters/index.ts` y en la
lista `integrationProviders` de `models.dart` (campos de credenciales).

## Verifactu (RD 1007/2023, Orden HAC/1177/2024)

| Plazo | Obligados |
|---|---|
| 1 ene 2027 | Sociedades (Impuesto sobre Sociedades) |
| 1 jul 2027 | Autónomos y resto de contribuyentes |
| 29 jul 2027 | Fabricantes de software: productos adaptados |

Requisitos que BookingNow ya cubre en BD: registro inmutable, huella
encadenada (`verifactu_hash` / `verifactu_prev_hash`), QR verificable en sede
AEAT, tipos de factura F1/F2/R1–R5, numeración correlativa por serie, log de
auditoría. Dos formas de cumplir:

- **A través del software conectado** (Holded, Quipu, Contasimple, Sage, a3…):
  todos están homologados; BookingNow les envía la factura y ellos remiten a
  la AEAT. Es la vía recomendada.
- **Envío directo** (`verifactu_aeat`): el adaptador construye el XML
  `RegFactuSistemaFacturacion` y lo envía al servicio SOAP de la AEAT con el
  certificado del negocio (mTLS). Para producción hay que darse de alta como
  productor de software (datos del bloque `SistemaInformatico`: NIF del
  productor, nombre, ID y versión del SIF) y presentar la declaración
  responsable. Entorno de pruebas: `prewww1.aeat.es`.

Lo que **falta** para ser SIF completo: generación del PDF con QR, registro de
anulación, firma electrónica en modo "no Verifactu", exportación del libro de
registros en formato AEAT. Está planificado para la fase 2.

## Proveedores de facturación

| Proveedor | Auth | Endpoint principal | Notas |
|---|---|---|---|
| **Holded** | header `key` (API Key, planes de pago) | `POST https://api.holded.com/api/invoicing/v1/documents/invoice` | Crea el contacto si no existe (por NIF). Opcional `settings.num_serie`, `payment_method_id`. Doc: https://developers.holded.com |
| **Quipu** | OAuth2 client_credentials (`app_id`/`app_secret`) | `POST https://getquipu.com/invoices` (JSON:API) | API en planes superiores. Doc: https://getquipu.com/es/api |
| **Cegid Contasimple** | API key → token | `POST https://api.contasimple.com/api/v2/accounting/invoices/issued` | Verificar rutas en el portal de desarrolladores de Cegid |
| **Sage Accounting** | OAuth2 (refresh token) | `POST https://api.accounting.sage.com/v3.1/sales_invoices` | Para **Sage 50** (escritorio) usar `webhook` + conector local o exportación. Doc: https://developer.sage.com/accounting/ |
| **Wolters Kluwer a3** | `Ocp-Apim-Subscription-Key` | `settings.base_url` (a3innuva Facturación / a3ERP) | Requiere alta en https://developers.wolterskluwer.es |
| **Billin** | Bearer API key | `POST https://api.billin.net/v1/invoices` | Verificar en su documentación |
| **FacturaDirecta** | Basic (api_key:x) | `https://<cuenta>.facturadirecta.com/api/invoices` | Doc: https://www.facturadirecta.com/api |
| **Webhook** | HMAC-SHA256 (`X-BookingNow-Signature`) | URL del negocio | Para Zapier, Make, n8n, gestorías, ERPs a medida, Sage 50, Factusol, TeamSystem… |
| **Verifactu AEAT** | Certificado digital (mTLS) | SOAP `VerifactuSOAP` | Ver sección anterior |

> Los endpoints se han escrito a partir de la documentación pública de cada
> proveedor. Antes de producción, prueba cada adaptador con una cuenta real
> (botón **Probar conexión**) y ajusta los campos que cada API exija.

## Pagos y señales

- **Stripe** (`payments` Edge Function): Checkout Session con `card` + `bizum`.
  El webhook `checkout.session.completed` marca la reserva como pagada
  (`authorized` si es señal) y la confirma. Cada negocio puede usar su propia
  cuenta (credencial `secret_key`) o la de la plataforma (Stripe Connect en
  roadmap).
- **Redsys**: TPV virtual de los bancos españoles (tarjeta y Bizum). Flujo:
  generar `Ds_MerchantParameters` (base64 del JSON con importe, pedido, FUC,
  terminal, URLs) y `Ds_Signature` (HMAC-SHA256 con clave derivada 3DES del
  número de pedido) y redirigir al cliente; la notificación `Ds_Response <
  100` confirma el pago. Pendiente de implementar en `payments` (credenciales
  ya modeladas).
- Efectivo, TPV físico y bono se registran al emitir la factura.

## Mensajería

- **Push**: FCM HTTP v1 con service account (igual que Top 20).
- **Email**: Resend (`RESEND_API_KEY`, `EMAIL_FROM`).
- **SMS**: Twilio por negocio (`integrations`) o global (`TWILIO_*`).
- **WhatsApp**: Meta Cloud API; requiere plantillas aprobadas con nombre
  `bn_<template>` (`bn_reminder`, `bn_booking_confirmed`…) y 4 parámetros:
  negocio, servicio, fecha, código.

Las plantillas de texto están en `send-notifications/index.ts` y se pueden
personalizar por negocio en `notification_settings.template_overrides`.

## Calendario y marketplace

- **Google Calendar**: credencial `refresh_token` por profesional; sincronización
  en roadmap (fase 2). Mientras tanto, el cliente puede "Añadir al calendario".
- **Reserve with Google**: requiere alta como partner y feeds de
  disponibilidad; el modelo guarda el `merchant_id`.
