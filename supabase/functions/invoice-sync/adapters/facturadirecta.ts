// FacturaDirecta — https://www.facturadirecta.com/api
// Base: https://<cuenta>.facturadirecta.com/api  · Auth: Basic <api_key>:x
import { type Adapter, expectOk } from "./index.ts";

export const facturadirecta: Adapter = {
  async pushInvoice(inv, cred) {
    const base = `https://${cred.account}.facturadirecta.com/api`;
    const headers = { Authorization: `Basic ${btoa(`${cred.api_key}:x`)}`, "Content-Type": "application/json", Accept: "application/json" };
    // Cliente
    const contact = await expectOk(await fetch(`${base}/contacts`, {
      method: "POST", headers,
      body: JSON.stringify({ contact: {
        name: inv.recipient.name, vatNumber: inv.recipient.taxId ?? undefined, email: inv.recipient.email ?? undefined,
        address: inv.recipient.address ?? undefined, country: "ES", isClient: true,
      } }),
    }), "FacturaDirecta") as { contact: { id: string | number } };
    const payload = {
      invoice: {
        contactId: contact.contact.id, number: inv.number, date: inv.issueDate, paid: true,
        lines: inv.lines.map((l) => ({
          description: l.description, quantity: l.quantity, unitPrice: l.unitPrice, vat: l.vatPct, discount: l.discountPct,
        })),
      },
    };
    const res = await expectOk(await fetch(`${base}/invoices`, { method: "POST", headers, body: JSON.stringify(payload) }), "FacturaDirecta") as { invoice: { id: string | number } };
    return { externalId: String(res.invoice.id) };
  },
  async test(cred) {
    const r = await fetch(`https://${cred.account}.facturadirecta.com/api/contacts?limit=1`, {
      headers: { Authorization: `Basic ${btoa(`${cred.api_key}:x`)}`, Accept: "application/json" },
    });
    return r.ok ? { ok: true, message: "Conectado con FacturaDirecta" } : { ok: false, message: `FacturaDirecta HTTP ${r.status}` };
  },
};
