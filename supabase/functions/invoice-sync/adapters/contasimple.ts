// Cegid Contasimple — https://api.contasimple.com (API REST, OAuth2 con API key)
// Token: POST /api/v2/token (grant_type=api_key)
// Facturas: POST /api/v2/accounting/invoices/issued
import { type Adapter, expectOk } from "./index.ts";

const BASE = "https://api.contasimple.com/api/v2";

async function token(cred: Record<string, string>): Promise<string> {
  const r = await expectOk(await fetch(`${BASE}/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=api_key&api_key=${encodeURIComponent(cred.api_key)}`,
  }), "Contasimple") as { access_token: string };
  return r.access_token;
}

export const contasimple: Adapter = {
  async pushInvoice(inv, cred) {
    const tk = await token(cred);
    const headers = { Authorization: `Bearer ${tk}`, "Content-Type": "application/json" };
    const payload = {
      number: inv.number,
      date: inv.issueDate,
      entity: {
        name: inv.recipient.name, nif: inv.recipient.taxId ?? "", address: inv.recipient.address ?? "",
        email: inv.recipient.email ?? undefined, countryISOCode: "ES",
      },
      lines: inv.lines.map((l) => ({
        concept: l.description, quantity: l.quantity, unitAmount: l.unitPrice,
        vatPercentage: l.vatPct, discountPercentage: l.discountPct, retentionPercentage: 0,
      })),
      paymentMethod: inv.paymentMethod === "cash" ? "Cash" : "Card",
      paid: true,
    };
    const res = await expectOk(await fetch(`${BASE}/accounting/invoices/issued`, {
      method: "POST", headers, body: JSON.stringify(payload),
    }), "Contasimple") as { data?: { id?: string | number }; id?: string | number };
    const id = res.data?.id ?? res.id;
    if (!id) throw new Error("Contasimple: respuesta sin id");
    return { externalId: String(id) };
  },
  async test(cred) {
    try { await token(cred); return { ok: true, message: "Conectado con Contasimple" }; }
    catch (e) { return { ok: false, message: (e as Error).message }; }
  },
};
