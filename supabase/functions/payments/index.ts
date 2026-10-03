// Edge Function `payments` — señales/depósitos y cobros online.
//
//   POST { "type": "create_checkout", "booking_id" }   (JWT cliente)
//     → crea un Stripe Checkout Session (tarjeta + Bizum) con la cuenta
//       Stripe del negocio (credenciales en `integrations`) y devuelve la URL.
//   POST webhook Stripe (/payments/stripe-webhook)  → marca la reserva pagada
//     y la confirma. Firma verificada con STRIPE_WEBHOOK_SECRET.
//
// Redsys: el flujo es equivalente generando el formulario firmado
// (Ds_MerchantParameters + Ds_Signature HMAC-SHA256) — ver docs/INTEGRACIONES.

import { createClient } from "npm:@supabase/supabase-js@2";
import Stripe from "npm:stripe@17";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const HOST = Deno.env.get("PUBLIC_BOOKING_HOST") ?? "https://bookingnow.app";

async function stripeFor(businessId: string): Promise<Stripe> {
  const { data } = await admin.from("integrations").select("credentials").eq("business_id", businessId).eq("provider", "stripe").eq("enabled", true).maybeSingle();
  const key = data?.credentials?.secret_key ?? Deno.env.get("STRIPE_SECRET_KEY");
  if (!key) throw new Error("Stripe no configurado para este negocio");
  return new Stripe(key, { apiVersion: "2024-12-18.acacia" });
}

async function createCheckout(req: Request, bookingId: string) {
  const userClient = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } });
  const { data: b } = await userClient.from("v_bookings_full").select("*").eq("id", bookingId).maybeSingle();
  if (!b) return Response.json({ error: "booking_not_found" }, { status: 404 });
  const amount = b.deposit_cents > 0 ? b.deposit_cents : b.total_cents;
  if (amount <= 0) return Response.json({ error: "nothing_to_pay" }, { status: 400 });
  const stripe = await stripeFor(b.business_id);
  const session = await stripe.checkout.sessions.create({
    mode: "payment",
    payment_method_types: ["card", "bizum"],
    customer_email: b.customer_email ?? undefined,
    line_items: [{
      price_data: { currency: "eur", unit_amount: amount, product_data: { name: `${b.deposit_cents > 0 ? "Señal" : "Pago"} · ${b.services_summary ?? "Cita"} · ${b.business_name}` } },
      quantity: 1,
    }],
    metadata: { booking_id: b.id, business_id: b.business_id, kind: b.deposit_cents > 0 ? "deposit" : "full" },
    success_url: `${HOST}/r/${b.code}?paid=1`,
    cancel_url: `${HOST}/r/${b.code}?paid=0`,
  });
  await admin.from("bookings").update({ payment_provider: "stripe", payment_ref: session.id }).eq("id", b.id);
  return Response.json({ url: session.url });
}

async function stripeWebhook(req: Request) {
  const sig = req.headers.get("stripe-signature") ?? "";
  const raw = await req.text();
  const secret = Deno.env.get("STRIPE_WEBHOOK_SECRET");
  if (!secret) return new Response("webhook secret missing", { status: 500 });
  const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY") ?? "sk_placeholder", { apiVersion: "2024-12-18.acacia" });
  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(raw, sig, secret);
  } catch (e) {
    return new Response(`invalid signature: ${(e as Error).message}`, { status: 400 });
  }
  if (event.type === "checkout.session.completed") {
    const s = event.data.object as Stripe.Checkout.Session;
    const bookingId = s.metadata?.booking_id;
    if (bookingId) {
      await admin.from("bookings").update({
        payment_status: s.metadata?.kind === "deposit" ? "authorized" : "paid",
        payment_provider: "stripe", payment_ref: s.payment_intent?.toString() ?? s.id,
        status: "confirmed", confirmed_at: new Date().toISOString(),
      }).eq("id", bookingId).eq("status", "pending");
      await admin.rpc("enqueue_booking_notifications", { p_booking: bookingId, p_template: "booking_confirmed" });
    }
  }
  return Response.json({ received: true });
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  if (req.method !== "POST") return new Response("method_not_allowed", { status: 405 });
  if (url.pathname.endsWith("/stripe-webhook")) return stripeWebhook(req);
  const body = await req.json().catch(() => ({}));
  if (body.type === "create_checkout") return createCheckout(req, body.booking_id);
  return Response.json({ error: "unknown_type" }, { status: 400 });
});
