// Webhook genérico — envía la factura en JSON firmada con HMAC-SHA256 a la
// URL del negocio. Sirve para Zapier/Make/n8n, conectores a Sage 50, ERPs a
// medida o gestorías.
//
// Cabeceras: X-BookingNow-Signature: sha256=<hex>, X-BookingNow-Event: invoice.issued
import type { Adapter } from "./index.ts";

async function sign(secret: string, body: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body)));
  return Array.from(sig).map((b) => b.toString(16).padStart(2, "0")).join("");
}

export const webhook: Adapter = {
  async pushInvoice(inv, cred) {
    const body = JSON.stringify({ event: "invoice.issued", sent_at: new Date().toISOString(), invoice: inv });
    const headers: Record<string, string> = { "Content-Type": "application/json", "X-BookingNow-Event": "invoice.issued" };
    if (cred.secret) headers["X-BookingNow-Signature"] = `sha256=${await sign(cred.secret, body)}`;
    const r = await fetch(cred.url, { method: "POST", headers, body });
    if (!r.ok) throw new Error(`Webhook HTTP ${r.status}`);
    let externalId = inv.number;
    try { const j = await r.json(); if (j?.id) externalId = String(j.id); } catch { /* respuesta vacía */ }
    return { externalId };
  },
  async test(cred) {
    const body = JSON.stringify({ event: "ping", sent_at: new Date().toISOString() });
    const headers: Record<string, string> = { "Content-Type": "application/json", "X-BookingNow-Event": "ping" };
    if (cred.secret) headers["X-BookingNow-Signature"] = `sha256=${await sign(cred.secret, body)}`;
    const r = await fetch(cred.url, { method: "POST", headers, body }).catch((e) => ({ ok: false, status: String(e) }));
    return r.ok ? { ok: true, message: "El webhook responde" } : { ok: false, message: `Webhook: ${r.status}` };
  },
};
