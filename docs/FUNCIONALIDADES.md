# Funcionalidades: Booksy como base y qué añade BookingNow

Fuentes consultadas (octubre 2026): precios y comparativas de Booksy, Fresha,
Treatwell y Timp en España; reseñas de Booksy Biz en Capterra, Trustpilot,
Software Advice y App Store; documentación Verifactu (RD 1007/2023, Orden
HAC/1177/2024, plazos 2027).

## 1. Lo que Booksy hace (y BookingNow replica)

| Área | Booksy | BookingNow |
|---|---|---|
| Reserva online 24/7 | ✅ | ✅ Flujo en 4 pasos con huecos reales calculados en servidor |
| Marketplace de clientes | ✅ (belleza) | ✅ Multi-sector (16 sectores, vocabulario adaptado) |
| Agenda con colores por profesional, drag & drop | ✅ | ✅ Día/semana por profesional, bloqueos, alta manual (drag & drop en roadmap) |
| Recordatorios SMS/email | ✅ | ✅ Push, email, SMS **y WhatsApp**, configurables (24 h, 2 h…), con "responde SI para confirmar" |
| Gestión de clientes | ✅ | ✅ + importación CSV, exportación, etiquetas, notas, RGPD, bloqueo, contador de no-shows |
| Protección frente a no-shows | ✅ solo con Booksy Payments | ✅ Señal por **Bizum/tarjeta (Stripe o Redsys)**, tasas de cancelación tardía y no-show, confirmación manual, sin obligar a un procesador propio |
| Lista de espera | ✅ | ✅ Automática: al cancelarse una cita se avisa a quienes esperaban ese rango |
| Paquetes, membresías, tarjetas regalo | ✅ | ✅ Bonos de sesiones (se consumen al completar), membresías, tarjetas regalo |
| Extras y combos, reservas en paralelo, servicios a domicilio | ✅ | ✅ Variantes, extras, aforo (clases), buffers, sedes a domicilio con radio y tarifa |
| Marketing (email/SMS, promociones, Boost) | ✅ (Boost cobra 30 % de la 1ª visita) | ✅ Campañas segmentadas y códigos promocionales **sin comisión** |
| Reserve with Google, Instagram/Facebook | ✅ | ✅ Integración preparada (Merchant ID) + página pública con QR |
| Informes | ✅ | ✅ Ingresos, por profesional/servicio, ocupación por día/hora, tasa de no-show, exportación CSV |
| Inventario | ✅ | ⏳ Roadmap fase 2 |
| Pagos integrados | ✅ Booksy Payments | ✅ Stripe (tarjeta + Bizum), Redsys; efectivo/TPV registrados al facturar |

## 2. Lo que a Booksy le falta (quejas recurrentes) y BookingNow resuelve

| Carencia detectada | Solución en BookingNow |
|---|---|
| **Facturación**: Booksy no emite facturas legales ni se integra con software de facturación español; Verifactu obliga desde 2027 | Facturas con numeración correlativa por serie, snapshot del receptor, **huella SHA-256 encadenada y QR Verifactu**; sincronización automática con **Holded, Quipu, Contasimple, Sage, a3, Billin, FacturaDirecta**, webhook genérico (Zapier/Make/gestoría) y envío directo a la **AEAT** |
| Protección no-show atada a su pasarela, comisiones poco transparentes | Señales con la pasarela que elija el negocio (Stripe/Redsys/Bizum), políticas configurables, precios fijos sin comisión por cliente |
| Alta manual de clientes tediosa | Importación CSV con mapeo automático de columnas, exportación completa (los datos son del negocio) |
| Panel de escritorio pobre, app "mobile-first" | La misma app compila a web con **menú lateral y vistas multicolumna** (agenda por profesional, formularios a dos columnas) |
| Solo belleza/bienestar | Sectores: belleza, barbería, uñas, salud, fisio, dental, psicología, fitness, taller, hogar, mascotas, legal, formación, tatuaje, foto, otros. Cada sector trae vocabulario (Paciente/Alumno/Cliente, Consulta/Clase/Cita), plantillas de servicios, recursos (salas/boxes) y clases con aforo |
| Sin recursos físicos (salas, equipos) | Tabla `resources` + asignación por servicio (disponibilidad por recurso en roadmap) |
| Soporte lento, actualizaciones que rompen cosas | Código propio, CI con análisis y tests, auditoría en BD |
| Sin formularios de admisión / consentimientos | `intake_forms` por negocio (consentimiento informado, anamnesis, RGPD) |
| Recordatorios solo SMS/email | WhatsApp Business (plantillas Meta) además de push/email/SMS |
| Citas recurrentes limitadas | Repetición semanal/quincenal/mensual (cliente o negocio), saltando huecos ocupados |
| Multi-sede y roles limitados | Sedes ilimitadas, roles owner/manager/staff/reception con permisos en RLS, comisiones por profesional |

## 3. Funcionalidades extra "BookingNow"

- Confirmación por respuesta ("SI") en recordatorio; auto no-show tras 2 h sin check-in.
- Valoraciones **verificadas** (solo tras cita completada) con respuesta del negocio.
- Código y QR por reserva para check-in rápido.
- Google Calendar: "Añadir al calendario" en cliente; feed/sync para profesionales (integración).
- Idiomas es/en (ARB) y tema claro/oscuro.
- Auditoría completa (`audit_log`) y cola de sincronización con reintentos.
- Plan SaaS (`free`/`pro`/`business`) preparado en el modelo.

## 4. Roadmap

**Fase 2**: página pública de reservas sin app (Flutter web `/b/<slug>`),
PDF de factura (Edge Function + Storage), drag & drop en agenda, inventario y
venta de productos, disponibilidad por recurso, Reserve with Google (feed de
disponibilidad), Google Calendar bidireccional, firma de consentimientos.

**Fase 3**: app de cliente con pago in-app (Stripe Payment Sheet), programa de
fidelización por puntos, TPV físico (Stripe Terminal / Redsys), facturas
rectificativas R1–R5 y Facturae/FACe para administraciones, marketplace con
geolocalización y mapa, IA para sugerir huecos y recuperar clientes inactivos.
