// Adaptadores de facturación. Cada uno traduce `InvoiceDTO` al formato del
// proveedor. Añadir un proveedor nuevo = añadir un archivo aquí y registrarlo.
//
// NOTA: los endpoints reflejan la documentación pública de cada proveedor en
// la fecha de creación; verifica en su portal de desarrolladores antes de
// producción (docs/INTEGRACIONES_FACTURACION.md tiene los enlaces).

import { holded } from "./holded.ts";
import { quipu } from "./quipu.ts";
import { contasimple } from "./contasimple.ts";
import { sage } from "./sage.ts";
import { a3 } from "./a3.ts";
import { billin } from "./billin.ts";
import { facturadirecta } from "./facturadirecta.ts";
import { webhook } from "./webhook.ts";
import { verifactuAeat } from "./verifactu_aeat.ts";

export interface Party {
  name: string;
  taxId: string | null;
  address?: string | null;
  postalCode?: string | null;
  city?: string | null;
  province?: string | null;
  country?: string;
  email?: string | null;
  phone?: string | null;
  customerId?: string | null;
}

export interface InvoiceLine {
  description: string;
  quantity: number;
  unitPrice: number;   // sin IVA, en euros
  vatPct: number;
  discountPct: number;
  total: number;       // con IVA
}

export interface InvoiceDTO {
  id: string;
  number: string;       // 'F2026-000123'
  series: string;
  issueDate: string;    // 'YYYY-MM-DD'
  type: string;         // F1 | F2 | R1..R5
  status: string;
  paymentMethod: string | null;
  subtotal: number;
  vat: number;
  total: number;
  notes: string | null;
  verifactuHash: string | null;
  verifactuPrevHash: string | null;
  issuer: Party;
  recipient: Party;
  lines: InvoiceLine[];
}

export interface PushResult {
  externalId: string;
  pdfUrl?: string | null;
  verifactuSentAt?: string | null;
  verifactuResponse?: unknown;
}

export interface Adapter {
  /** Crea (o actualiza) la factura en el sistema externo. */
  pushInvoice(inv: InvoiceDTO, credentials: Record<string, string>, settings: Record<string, unknown>): Promise<PushResult>;
  /** Comprueba credenciales. */
  test(credentials: Record<string, string>, settings: Record<string, unknown>): Promise<{ ok: boolean; message: string }>;
}

export const adapters: Record<string, Adapter> = {
  holded,
  quipu,
  contasimple,
  sage,
  a3,
  billin,
  facturadirecta,
  webhook,
  verifactu_aeat: verifactuAeat,
};

// ---------- utilidades comunes ----------

export async function expectOk(res: Response, provider: string): Promise<unknown> {
  const text = await res.text();
  if (!res.ok) throw new Error(`${provider} HTTP ${res.status}: ${text.slice(0, 300)}`);
  try { return JSON.parse(text); } catch { return text; }
}

/** Fecha 'YYYY-MM-DD' → epoch segundos (Holded usa timestamps). */
export const toEpoch = (d: string) => Math.floor(new Date(d + "T00:00:00Z").getTime() / 1000);
