// Sage Business Cloud Accounting (España) — https://developer.sage.com/accounting/
// OAuth2: refresh_token → access_token (https://oauth.accounting.sage.com/token)
// Facturas de venta: POST https://api.accounting.sage.com/v3.1/sales_invoices
// Para Sage 50 (escritorio) se usa el adaptador `webhook` + conector local.
import { type Adapter, expectOk } from "./index.ts";

const API = "https://api.accounting.sage.com/v3.1";

async function accessToken(cred: Record<string, string>): Promise<string> {
  const r = await expectOk(await fetch("https://oauth.accounting.sage.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "refresh_token", refresh_token: cred.refresh_token,
      client_id: cred.client_id, client_secret: cred.client_secret,
    }),
  }), "Sage") as { access_token: string };
  return r.access_token;
}

async function findOrCreateContact(tk: string, p: { name: string; taxId: string | null; email?: string | null }) {
  const headers = { Authorization: `Bearer ${tk}`, "Content-Type": "application/json" };
  if (p.taxId) {
    const list = await expectOk(await fetch(`${API}/contacts?search=${encodeURIComponent(p.taxId)}&contact_type_id=CUSTOMER`, { headers }), "Sage") as { $items: Array<{ id: string }> };
    if (list.$items?.length) return list.$items[0].id;
  }
  const created = await expectOk(await fetch(`${API}/contacts`, {
    method: "POST", headers,
    body: JSON.stringify({ contact: { name: p.name, contact_type_ids: ["CUSTOMER"], tax_number: p.taxId ?? undefined, email: p.email ?? undefined } }),
  }), "Sage") as { id: string };
  return created.id;
}

export const sage: Adapter = {
  async pushInvoice(inv, cred, settings) {
    const tk = await accessToken(cred);
    const headers = { Authorization: `Bearer ${tk}`, "Content-Type": "application/json" };
    const contactId = await findOrCreateContact(tk, inv.recipient);
    const ledger = settings.ledger_account_id as string | undefined; // cuenta 705 por defecto en Sage ES
    const payload = {
      sales_invoice: {
        contact_id: contactId,
        date: inv.issueDate,
        reference: inv.number,
        notes: inv.notes ?? undefined,
        invoice_lines: inv.lines.map((l) => ({
          description: l.description, quantity: l.quantity, unit_price: l.unitPrice,
          ledger_account_id: ledger, tax_rate_id: taxRate(l.vatPct), discount_percentage: l.discountPct,
        })),
      },
    };
    const res = await expectOk(await fetch(`${API}/sales_invoices`, { method: "POST", headers, body: JSON.stringify(payload) }), "Sage") as { id: string };
    return { externalId: res.id };
  },
  async test(cred) {
    try {
      const tk = await accessToken(cred);
      const r = await fetch(`${API}/businesses`, { headers: { Authorization: `Bearer ${tk}` } });
      return r.ok ? { ok: true, message: "Conectado con Sage" } : { ok: false, message: `Sage HTTP ${r.status}` };
    } catch (e) { return { ok: false, message: (e as Error).message }; }
  },
};

// IDs de tipos de IVA en Sage ES (configurables; los habituales):
function taxRate(pct: number) {
  if (pct === 21) return "ES_STANDARD";
  if (pct === 10) return "ES_REDUCED";
  if (pct === 4) return "ES_SUPER_REDUCED";
  return "ES_EXEMPT";
}
