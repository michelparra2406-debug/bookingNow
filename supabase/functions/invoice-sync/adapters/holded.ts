// Holded — https://developers.holded.com
// Auth: header `key: <API_KEY>` (Ajustes > Desarrolladores > Credenciales).
// Facturas: POST https://api.holded.com/api/invoicing/v1/documents/invoice
// Contactos: GET/POST https://api.holded.com/api/invoicing/v1/contacts
import { type Adapter, expectOk, toEpoch } from "./index.ts";

const BASE = "https://api.holded.com/api/invoicing/v1";

async function findOrCreateContact(key: string, p: { name: string; taxId: string | null; email?: string | null; phone?: string | null; address?: string | null; city?: string | null; postalCode?: string | null }) {
  const headers = { key, "Content-Type": "application/json" };
  if (p.taxId) {
    const list = await expectOk(await fetch(`${BASE}/contacts?code=${encodeURIComponent(p.taxId)}`, { headers }), "Holded") as Array<{ id: string }>;
    if (Array.isArray(list) && list.length > 0) return list[0].id;
  }
  const created = await expectOk(await fetch(`${BASE}/contacts`, {
    method: "POST", headers,
    body: JSON.stringify({
      name: p.name, code: p.taxId ?? undefined, email: p.email ?? undefined, mobile: p.phone ?? undefined,
      type: "client", isperson: !p.taxId || /^[0-9]{8}[A-Z]$|^[XYZ]/i.test(p.taxId),
      billAddress: p.address ? { address: p.address, city: p.city ?? "", postalCode: p.postalCode ?? "", country: "ES" } : undefined,
    }),
  }), "Holded") as { id: string };
  return created.id;
}

export const holded: Adapter = {
  async pushInvoice(inv, cred, settings) {
    const key = cred.api_key;
    const contactId = await findOrCreateContact(key, inv.recipient);
    const payload = {
      contactId,
      date: toEpoch(inv.issueDate),
      numSerie: settings.num_serie ?? inv.series,         // serie configurada en Holded
      customNumber: settings.use_own_numbering ? undefined : inv.number,
      notes: inv.notes ?? `Reserva BookingNow`,
      items: inv.lines.map((l) => ({
        name: l.description, units: l.quantity, subtotal: l.unitPrice,
        tax: l.vatPct, discount: l.discountPct,
      })),
      // Marcar como pagada con el método indicado
      paymentMethodId: settings.payment_method_id ?? undefined,
    };
    const res = await expectOk(await fetch(`${BASE}/documents/invoice`, {
      method: "POST", headers: { key, "Content-Type": "application/json" }, body: JSON.stringify(payload),
    }), "Holded") as { id: string; status?: number; info?: string };
    if (!res.id) throw new Error(`Holded: ${res.info ?? "respuesta sin id"}`);
    if (inv.paymentMethod && settings.mark_paid !== false) {
      await fetch(`${BASE}/documents/invoice/${res.id}/pay`, {
        method: "POST", headers: { key, "Content-Type": "application/json" },
        body: JSON.stringify({ date: toEpoch(inv.issueDate), amount: inv.total }),
      }).catch(() => {});
    }
    return { externalId: res.id, pdfUrl: null };
  },
  async test(cred) {
    const r = await fetch(`${BASE}/contacts?limit=1`, { headers: { key: cred.api_key } });
    return r.ok ? { ok: true, message: "Conectado con Holded" } : { ok: false, message: `Holded HTTP ${r.status}` };
  },
};
