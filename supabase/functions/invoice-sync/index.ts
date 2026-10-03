// Edge Function `invoice-sync` — sincroniza facturas (y clientes) con el
// software de facturación conectado por cada negocio.
//
// Patrón ADAPTADOR: cada proveedor implementa `pushInvoice` y `test`.
// La cola `sync_jobs` la alimenta `issue_invoice()` en la BD; esta función
// la procesa (pg_cron cada 5 min) con reintentos exponenciales.
//
// Llamadas:
//   { "type": "process_queue" }                         ← cron (header x-trigger-secret)
//   { "type": "test", "business_id", "provider" }       ← app (JWT del usuario)
//   { "type": "sync_invoice", "invoice_id" }            ← app (JWT), fuerza envío
//
// Secretos: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SYNC_TRIGGER_SECRET

import { createClient } from "npm:@supabase/supabase-js@2";
import { adapters, type Adapter, type InvoiceDTO } from "./adapters/index.ts";

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

// ---------- Carga de datos ----------

async function loadInvoice(invoiceId: string): Promise<InvoiceDTO | null> {
  const { data: inv } = await admin
    .from("invoices")
    .select("*, invoice_lines(*), customers(*), businesses(*)")
    .eq("id", invoiceId)
    .maybeSingle();
  if (!inv) return null;
  const b = inv.businesses;
  const c = inv.customers;
  return {
    id: inv.id,
    number: inv.full_number,
    series: inv.series,
    issueDate: inv.issue_date,
    type: inv.type,
    status: inv.status,
    paymentMethod: inv.payment_method,
    subtotal: inv.subtotal_cents / 100,
    vat: inv.vat_cents / 100,
    total: inv.total_cents / 100,
    notes: inv.notes,
    verifactuHash: inv.verifactu_hash,
    verifactuPrevHash: inv.verifactu_prev_hash,
    issuer: {
      name: b.legal_name ?? b.name,
      taxId: b.tax_id,
      address: b.fiscal_address,
      postalCode: b.fiscal_postal_code,
      city: b.fiscal_city,
      province: b.fiscal_province,
      country: b.fiscal_country ?? "ES",
    },
    recipient: {
      name: inv.recipient_name,
      taxId: inv.recipient_tax_id,
      address: inv.recipient_address,
      email: c?.email ?? null,
      phone: c?.phone ?? null,
      customerId: c?.id ?? null,
    },
    lines: (inv.invoice_lines ?? []).map((l: Record<string, unknown>) => ({
      description: l.description as string,
      quantity: Number(l.quantity),
      unitPrice: (l.unit_price_cents as number) / 100,
      vatPct: Number(l.vat_pct),
      discountPct: Number(l.discount_pct ?? 0),
      total: (l.total_cents as number) / 100,
    })),
  };
}

async function loadIntegration(businessId: string, provider: string) {
  const { data } = await admin
    .from("integrations")
    .select("*")
    .eq("business_id", businessId)
    .eq("provider", provider)
    .eq("enabled", true)
    .maybeSingle();
  return data;
}

// ---------- Procesado de la cola ----------

async function processQueue(): Promise<{ done: number; errors: number }> {
  const { data: jobs } = await admin
    .from("sync_jobs")
    .select("*")
    .eq("status", "queued")
    .lte("run_after", new Date().toISOString())
    .order("created_at")
    .limit(50);
  let done = 0, errors = 0;
  for (const job of jobs ?? []) {
    await admin.from("sync_jobs").update({ status: "running" }).eq("id", job.id);
    try {
      const adapter: Adapter | undefined = adapters[job.provider];
      if (!adapter) throw new Error(`Proveedor no soportado: ${job.provider}`);
      const integ = await loadIntegration(job.business_id, job.provider);
      if (!integ) throw new Error("Integración desactivada o sin credenciales");

      if (job.entity === "invoice") {
        const inv = await loadInvoice(job.entity_id);
        if (!inv) throw new Error("Factura no encontrada");
        const res = await adapter.pushInvoice(inv, integ.credentials, integ.settings ?? {});
        await admin.from("invoices").update({
          external_provider: job.provider,
          external_id: res.externalId,
          external_synced_at: new Date().toISOString(),
          external_error: null,
          pdf_url: res.pdfUrl ?? undefined,
          verifactu_sent_at: res.verifactuSentAt ?? undefined,
          verifactu_response: res.verifactuResponse ?? undefined,
        }).eq("id", inv.id);
      }
      await admin.from("sync_jobs").update({ status: "done", error: null }).eq("id", job.id);
      await admin.from("integrations").update({ last_sync_at: new Date().toISOString(), last_error: null })
        .eq("id", integ.id);
      done++;
    } catch (e) {
      errors++;
      const msg = (e as Error).message ?? String(e);
      const attempts = (job.attempts ?? 0) + 1;
      const giveUp = attempts >= 5;
      // Reintento exponencial: 2, 4, 8, 16 min
      const runAfter = new Date(Date.now() + Math.pow(2, attempts) * 60_000).toISOString();
      await admin.from("sync_jobs").update({
        status: giveUp ? "error" : "queued",
        attempts,
        error: msg,
        run_after: runAfter,
      }).eq("id", job.id);
      if (job.entity === "invoice") {
        await admin.from("invoices").update({ external_provider: job.provider, external_error: msg })
          .eq("id", job.entity_id);
      }
      await admin.from("integrations").update({ last_error: msg })
        .eq("business_id", job.business_id).eq("provider", job.provider);
    }
  }
  return { done, errors };
}

// ---------- Autorización de llamadas desde la app ----------

async function userCanManage(req: Request, businessId: string): Promise<boolean> {
  const auth = req.headers.get("Authorization") ?? "";
  const userClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: auth } } },
  );
  const { data } = await userClient.rpc("has_role", {
    p_business: businessId,
    p_roles: ["owner", "manager"],
  });
  return data === true;
}

// ---------- Entrada ----------

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const body = await req.json().catch(() => ({}));

  if (body.type === "process_queue") {
    if (req.headers.get("x-trigger-secret") !== Deno.env.get("SYNC_TRIGGER_SECRET")) {
      return json({ error: "unauthorized" }, 401);
    }
    return json(await processQueue());
  }

  if (body.type === "test") {
    if (!(await userCanManage(req, body.business_id))) return json({ ok: false, message: "forbidden" }, 403);
    const adapter = adapters[body.provider];
    if (!adapter) return json({ ok: false, message: "Proveedor no soportado" });
    const integ = await loadIntegration(body.business_id, body.provider);
    if (!integ) return json({ ok: false, message: "Sin credenciales guardadas" });
    try {
      const r = await adapter.test(integ.credentials, integ.settings ?? {});
      await admin.from("integrations").update({ last_error: r.ok ? null : r.message }).eq("id", integ.id);
      return json(r);
    } catch (e) {
      return json({ ok: false, message: (e as Error).message });
    }
  }

  if (body.type === "sync_invoice") {
    const { data: inv } = await admin.from("invoices").select("business_id").eq("id", body.invoice_id).maybeSingle();
    if (!inv || !(await userCanManage(req, inv.business_id))) return json({ ok: false }, 403);
    const { data: integs } = await admin.from("integrations").select("provider")
      .eq("business_id", inv.business_id).eq("category", "invoicing").eq("enabled", true);
    for (const i of integs ?? []) {
      await admin.from("sync_jobs").insert({
        business_id: inv.business_id, provider: i.provider, entity: "invoice", entity_id: body.invoice_id,
      });
    }
    return json(await processQueue());
  }

  return json({ error: "unknown_type" }, 400);
});
