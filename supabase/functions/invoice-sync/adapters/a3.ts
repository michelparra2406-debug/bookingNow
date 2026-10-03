// Wolters Kluwer a3innuva Facturación — API Management (Azure APIM)
// Header: Ocp-Apim-Subscription-Key. Base: https://api.wolterskluwer.es/a3innuva/...
// Doc: https://developers.wolterskluwer.es  (la ruta exacta depende del producto
// contratado: a3innuva Facturación / a3ERP). Se parametriza con settings.base_url.
import { type Adapter, expectOk } from "./index.ts";

export const a3: Adapter = {
  async pushInvoice(inv, cred, settings) {
    const base = (settings.base_url as string) ?? "https://api.wolterskluwer.es/a3innuva/facturacion/v1";
    const headers = { "Ocp-Apim-Subscription-Key": cred.api_key, "Content-Type": "application/json" };
    const payload = {
      companyId: cred.company_id,
      serie: inv.series,
      number: inv.number,
      date: inv.issueDate,
      customer: {
        name: inv.recipient.name, taxId: inv.recipient.taxId ?? "", address: inv.recipient.address ?? "",
        email: inv.recipient.email ?? undefined, countryCode: "ES",
      },
      lines: inv.lines.map((l) => ({
        description: l.description, quantity: l.quantity, unitPrice: l.unitPrice,
        vatPercentage: l.vatPct, discountPercentage: l.discountPct,
      })),
      paymentMethod: inv.paymentMethod ?? "card",
      paid: true,
      externalReference: inv.id,
    };
    const res = await expectOk(await fetch(`${base}/invoices`, { method: "POST", headers, body: JSON.stringify(payload) }), "a3") as { id?: string; invoiceId?: string };
    const id = res.id ?? res.invoiceId;
    if (!id) throw new Error("a3: respuesta sin id");
    return { externalId: String(id) };
  },
  async test(cred, settings) {
    const base = (settings.base_url as string) ?? "https://api.wolterskluwer.es/a3innuva/facturacion/v1";
    const r = await fetch(`${base}/companies/${cred.company_id}`, { headers: { "Ocp-Apim-Subscription-Key": cred.api_key } });
    return r.ok ? { ok: true, message: "Conectado con a3" } : { ok: false, message: `a3 HTTP ${r.status}` };
  },
};
