// Billin — https://www.billin.net (API REST con API key)
// Base: https://api.billin.net/v1  · Header: Authorization: Bearer <api_key>
import { type Adapter, expectOk } from "./index.ts";

const BASE = "https://api.billin.net/v1";

export const billin: Adapter = {
  async pushInvoice(inv, cred) {
    const headers = { Authorization: `Bearer ${cred.api_key}`, "Content-Type": "application/json" };
    const payload = {
      number: inv.number,
      date: inv.issueDate,
      contact: {
        name: inv.recipient.name, tax_id: inv.recipient.taxId ?? undefined, email: inv.recipient.email ?? undefined,
        address: inv.recipient.address ?? undefined, country: "ES",
      },
      lines: inv.lines.map((l) => ({
        description: l.description, quantity: l.quantity, price: l.unitPrice, tax: l.vatPct, discount: l.discountPct,
      })),
      paid: true,
      payment_method: inv.paymentMethod ?? "card",
    };
    const res = await expectOk(await fetch(`${BASE}/invoices`, { method: "POST", headers, body: JSON.stringify(payload) }), "Billin") as { id?: string | number; data?: { id?: string | number } };
    const id = res.id ?? res.data?.id;
    if (!id) throw new Error("Billin: respuesta sin id");
    return { externalId: String(id) };
  },
  async test(cred) {
    const r = await fetch(`${BASE}/me`, { headers: { Authorization: `Bearer ${cred.api_key}` } });
    return r.ok ? { ok: true, message: "Conectado con Billin" } : { ok: false, message: `Billin HTTP ${r.status}` };
  },
};
