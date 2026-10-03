// Edge Function `send-notifications` — procesa la cola `notifications`:
// push (FCM HTTP v1), email (Resend), SMS (Twilio) y WhatsApp (Meta Cloud API).
//
// Secretos: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, NOTIF_TRIGGER_SECRET,
//   FCM_SERVICE_ACCOUNT (JSON), RESEND_API_KEY, EMAIL_FROM,
//   (Twilio/WhatsApp se leen de `integrations` de cada negocio; si el negocio
//    no tiene, se usan TWILIO_* / WHATSAPP_* globales de la plataforma si existen)
//
// Llamada (pg_cron cada minuto): { "type": "process_queue" } + x-trigger-secret

import { createClient } from "npm:@supabase/supabase-js@2";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

// ---------- Plantillas (es) ----------

type Ctx = {
  business: string; customer: string; service: string; when: string; code: string; member?: string;
  hoursBefore?: number; askConfirm?: boolean; title?: string; body?: string; manageUrl: string;
};

const T: Record<string, (c: Ctx) => { title: string; body: string }> = {
  booking_created: (c) => ({ title: `Reserva recibida en ${c.business}`, body: `${c.service} · ${c.when}${c.member ? ` con ${c.member}` : ""}. Código ${c.code}.` }),
  booking_confirmed: (c) => ({ title: `Cita confirmada · ${c.business}`, body: `${c.service} · ${c.when}. ¡Te esperamos!` }),
  booking_rescheduled: (c) => ({ title: `Cita cambiada · ${c.business}`, body: `Nueva fecha: ${c.when} (${c.service}).` }),
  booking_cancelled: (c) => ({ title: `Cita cancelada · ${c.business}`, body: `${c.service} del ${c.when} ha sido cancelada.` }),
  reminder: (c) => ({
    title: `Recordatorio: ${c.service} ${c.hoursBefore && c.hoursBefore <= 3 ? "en breve" : "mañana"}`,
    body: `${c.business} · ${c.when}.${c.askConfirm ? " Responde SI para confirmar o abre la app para cambiarla." : ""}`,
  }),
  waitlist_slot: (c) => ({ title: `¡Se ha liberado un hueco en ${c.business}!`, body: `${c.when}. Reserva ahora desde la app antes de que se ocupe.` }),
  review_request: (c) => ({ title: `¿Qué tal en ${c.business}?`, body: `Valora tu ${c.service}. Tu opinión ayuda a otros clientes.` }),
  marketing: (c) => ({ title: c.title ?? c.business, body: c.body ?? "" }),
  booking_created_staff: (c) => ({ title: `Nueva reserva: ${c.customer}`, body: `${c.service} · ${c.when}` }),
  booking_confirmed_staff: (c) => ({ title: `Confirmada: ${c.customer}`, body: `${c.service} · ${c.when}` }),
  booking_rescheduled_staff: (c) => ({ title: `Cambio de hora: ${c.customer}`, body: `${c.service} · ${c.when}` }),
  booking_cancelled_staff: (c) => ({ title: `Cancelación: ${c.customer}`, body: `${c.service} · ${c.when}` }),
};

const fmtWhen = (iso: string, tz: string) =>
  new Intl.DateTimeFormat("es-ES", { timeZone: tz, weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }).format(new Date(iso));

// ---------- Canales ----------

async function sendPush(userId: string, title: string, body: string, data: Record<string, string>) {
  const sa = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "null");
  if (!sa) throw new Error("FCM no configurado");
  const { data: tokens } = await admin.from("device_tokens").select("token").eq("user_id", userId);
  if (!tokens?.length) throw new Error("sin_dispositivos");
  const accessToken = await fcmToken(sa);
  let ok = 0;
  for (const t of tokens) {
    const r = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
      method: "POST", headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
      body: JSON.stringify({ message: { token: t.token, notification: { title, body }, data } }),
    });
    if (r.ok) ok++;
    else {
      const e = await r.text();
      if (e.includes("UNREGISTERED") || e.includes("INVALID_ARGUMENT")) await admin.from("device_tokens").delete().eq("token", t.token);
    }
  }
  if (!ok) throw new Error("push_failed");
}

async function sendEmail(to: string, subject: string, html: string) {
  const key = Deno.env.get("RESEND_API_KEY");
  if (!key) throw new Error("Email no configurado (RESEND_API_KEY)");
  const r = await fetch("https://api.resend.com/emails", {
    method: "POST", headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from: Deno.env.get("EMAIL_FROM") ?? "BookingNow <no-reply@bookingnow.app>", to, subject, html }),
  });
  if (!r.ok) throw new Error(`Resend ${r.status}: ${await r.text()}`);
}

async function sendSms(businessId: string | null, to: string, text: string) {
  const cred = await credsFor(businessId, "twilio") ?? {
    account_sid: Deno.env.get("TWILIO_ACCOUNT_SID"), auth_token: Deno.env.get("TWILIO_AUTH_TOKEN"), from: Deno.env.get("TWILIO_FROM"),
  };
  if (!cred.account_sid) throw new Error("SMS no configurado");
  const r = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${cred.account_sid}/Messages.json`, {
    method: "POST",
    headers: { Authorization: `Basic ${btoa(`${cred.account_sid}:${cred.auth_token}`)}`, "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ To: to, From: cred.from!, Body: text }),
  });
  if (!r.ok) throw new Error(`Twilio ${r.status}: ${await r.text()}`);
}

async function sendWhatsApp(businessId: string | null, to: string, template: string, ctx: Ctx) {
  const cred = await credsFor(businessId, "whatsapp") ?? {
    phone_number_id: Deno.env.get("WHATSAPP_PHONE_NUMBER_ID"), access_token: Deno.env.get("WHATSAPP_ACCESS_TOKEN"),
  };
  if (!cred.phone_number_id) throw new Error("WhatsApp no configurado");
  // Meta exige plantillas aprobadas para mensajes iniciados por el negocio.
  // Nombre de plantilla = bn_<template>; parámetros: negocio, servicio, fecha, código.
  const r = await fetch(`https://graph.facebook.com/v21.0/${cred.phone_number_id}/messages`, {
    method: "POST", headers: { Authorization: `Bearer ${cred.access_token}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      messaging_product: "whatsapp", to: to.replace(/\D/g, ""), type: "template",
      template: {
        name: `bn_${template}`, language: { code: "es" },
        components: [{ type: "body", parameters: [ctx.business, ctx.service, ctx.when, ctx.code].map((t) => ({ type: "text", text: t })) }],
      },
    }),
  });
  if (!r.ok) throw new Error(`WhatsApp ${r.status}: ${await r.text()}`);
}

async function credsFor(businessId: string | null, provider: string): Promise<Record<string, string> | null> {
  if (!businessId) return null;
  const { data } = await admin.from("integrations").select("credentials").eq("business_id", businessId).eq("provider", provider).eq("enabled", true).maybeSingle();
  return data?.credentials ?? null;
}

// ---------- FCM OAuth (service account RS256) ----------

let cached: { token: string; exp: number } | null = null;
async function fcmToken(sa: { client_email: string; private_key: string; token_uri: string }): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cached && cached.exp > now + 60) return cached.token;
  const b64 = (s: string | Uint8Array) => btoa(typeof s === "string" ? s : String.fromCharCode(...s)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const header = b64(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64(JSON.stringify({ iss: sa.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging", aud: sa.token_uri, iat: now, exp: now + 3600 }));
  const pem = sa.private_key.replace(/-----[A-Z ]+-----/g, "").replace(/\s/g, "");
  const raw = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", raw.buffer, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claims}`)));
  const jwt = `${header}.${claims}.${b64(sig)}`;
  const res = await fetch(sa.token_uri, { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt }) });
  const json = await res.json();
  cached = { token: json.access_token, exp: now + 3500 };
  return json.access_token;
}

// ---------- Procesado ----------

async function processQueue() {
  const { data: rows } = await admin.from("notifications").select("*")
    .eq("status", "queued").lte("scheduled_for", new Date().toISOString()).order("scheduled_for").limit(200);
  let sent = 0, failed = 0;
  for (const n of rows ?? []) {
    try {
      // Contexto de la reserva
      let ctx: Ctx = { business: "", customer: "", service: "", when: "", code: "", manageUrl: "" };
      let email: string | null = null, phone: string | null = null;
      if (n.booking_id) {
        const { data: b } = await admin.from("v_bookings_full").select("*").eq("id", n.booking_id).maybeSingle();
        if (!b) throw new Error("reserva_no_encontrada");
        // Si la reserva se canceló, no enviar recordatorios pendientes
        if (n.template === "reminder" && b.status !== "confirmed" && b.status !== "pending") {
          await admin.from("notifications").update({ status: "failed", error: "cancelada" }).eq("id", n.id);
          continue;
        }
        ctx = {
          business: b.business_name, customer: b.customer_name, service: b.services_summary ?? "Cita",
          when: fmtWhen(b.starts_at, b.timezone ?? "Europe/Madrid"), code: b.code, member: b.member_name ?? undefined,
          hoursBefore: n.payload?.hours_before, askConfirm: n.payload?.ask_confirmation,
          manageUrl: `${Deno.env.get("PUBLIC_BOOKING_HOST") ?? "https://bookingnow.app"}/r/${b.code}`,
        };
        email = b.customer_email; phone = b.customer_phone;
      } else if (n.customer_id) {
        const { data: c } = await admin.from("customers").select("full_name, email, phone, businesses(name, timezone)").eq("id", n.customer_id).maybeSingle();
        ctx.customer = c?.full_name ?? ""; ctx.business = c?.businesses?.name ?? ""; email = c?.email; phone = c?.phone;
        if (n.template === "waitlist_slot" && n.payload?.starts_at) ctx.when = fmtWhen(n.payload.starts_at, c?.businesses?.timezone ?? "Europe/Madrid");
      }
      ctx.title = n.payload?.title; ctx.body = n.payload?.body;
      const tpl = T[n.template] ?? T.marketing;
      const { title, body } = tpl(ctx);

      switch (n.channel) {
        case "push":
          if (!n.user_id) throw new Error("sin_usuario");
          await sendPush(n.user_id, title, body, { booking_id: n.booking_id ?? "", template: n.template });
          break;
        case "email":
          if (!email) throw new Error("sin_email");
          await sendEmail(email, title, `<p>${body}</p>${n.booking_id ? `<p><a href="${ctx.manageUrl}">Ver o gestionar la cita</a></p>` : ""}`);
          break;
        case "sms":
          if (!phone) throw new Error("sin_telefono");
          await sendSms(n.business_id, phone, `${title}. ${body}`);
          break;
        case "whatsapp":
          if (!phone) throw new Error("sin_telefono");
          await sendWhatsApp(n.business_id, phone, n.template, ctx);
          break;
      }
      await admin.from("notifications").update({ status: "sent", sent_at: new Date().toISOString() }).eq("id", n.id);
      if (n.template === "reminder" && n.booking_id) await admin.from("bookings").update({ reminder_sent_at: new Date().toISOString() }).eq("id", n.booking_id);
      sent++;
    } catch (e) {
      failed++;
      await admin.from("notifications").update({ status: "failed", error: (e as Error).message }).eq("id", n.id);
    }
  }
  return { sent, failed };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("method_not_allowed", { status: 405 });
  if (req.headers.get("x-trigger-secret") !== Deno.env.get("NOTIF_TRIGGER_SECRET")) return new Response("unauthorized", { status: 401 });
  const body = await req.json().catch(() => ({}));
  if (body.type === "process_queue") return Response.json(await processQueue());
  return Response.json({ error: "unknown_type" }, { status: 400 });
});
