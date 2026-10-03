// Quipu — https://getquipu.com/es/api (JSON:API, OAuth2 client_credentials)
// Token:  POST https://getquipu.com/oauth/token  (app_id / app_secret)
// Facturas: POST https://getquipu.com/invoices
import { type Adapter, expectOk } from "./index.ts";

const BASE = "https://getquipu.com";

async function token(cred: Record<string, string>): Promise<string> {
  const basic = btoa(`${cred.app_id}:${cred.app_secret}`);
  const r = await expectOk(await fetch(`${BASE}/oauth/token`, {
    method: "POST",
    headers: { Authorization: `Basic ${basic}`, "Content-Type": "application/x-www-form-urlencoded" },
    body: "grant_type=client_credentials&scope=ecommerce",
  }), "Quipu") as { access_token: string };
  return r.access_token;
}

async function findOrCreateContact(tk: string, p: { name: string; taxId: string | null; email?: string | null; phone?: string | null; address?: string | null; city?: string | null; postalCode?: string | null }) {
  const headers = { Authorization: `Bearer ${tk}`, Accept: "application/vnd.quipu.v1+json", "Content-Type": "application/vnd.quipu.v1+json" };
  if (p.taxId) {
    const list = await expectOk(await fetch(`${BASE}/contacts?filter[tax_id]=${encodeURIComponent(p.taxId)}`, { headers }), "Quipu") as { data: Array<{ id: string }> };
    if (list.data?.length) return list.data[0].id;
  }
  const created = await expectOk(await fetch(`${BASE}/contacts`, {
    method: "POST", headers,
    body: JSON.stringify({ data: { type: "contacts", attributes: {
      name: p.name, tax_id: p.taxId ?? undefined, email: p.email ?? undefined, phone: p.phone ?? undefined,
      address: p.address ?? undefined, town: p.city ?? undefined, zip_code: p.postalCode ?? undefined, country_code: "ES",
    } } }),
  }), "Quipu") as { data: { id: string } };
  return created.data.id;
}

export const quipu: Adapter = {
  async pushInvoice(inv, cred) {
    const tk = await token(cred);
    const contactId = await findOrCreateContact(tk, inv.recipient);
    const headers = { Authorization: `Bearer ${tk}`, Accept: "application/vnd.quipu.v1+json", "Content-Type": "application/vnd.quipu.v1+json" };
    const payload = {
      data: {
        type: "invoices",
        attributes: {
          kind: "income",
          number: inv.number,
          issue_date: inv.issueDate,
          paid_at: inv.issueDate,
          payment_method: mapPayment(inv.paymentMethod),
          notes: inv.notes ?? undefined,
        },
        relationships: {
          contact: { data: { id: contactId, type: "contacts" } },
          items: { data: inv.lines.map((l) => ({ type: "book_entry_items", attributes: {
            concept: l.description, unitary_amount: l.unitPrice, quantity: l.quantity, vat_percent: l.vatPct, retention_percent: 0,
          } })) },
        },
      },
    };
    const res = await expectOk(await fetch(`${BASE}/invoices`, { method: "POST", headers, body: JSON.stringify(payload) }), "Quipu") as { data: { id: string } };
    return { externalId: res.data.id };
  },
  async test(cred) {
    try { await token(cred); return { ok: true, message: "Conectado con Quipu" }; }
    catch (e) { return { ok: false, message: (e as Error).message }; }
  },
};

function mapPayment(m: string | null) {
  switch (m) {
    case "cash": return "cash";
    case "transfer": return "bank_transfer";
    case "bizum": return "bank_transfer";
    default: return "bank_card";
  }
}
