// Verifactu — remisión directa de registros de facturación a la AEAT.
// RD 1007/2023 + Orden HAC/1177/2024. Servicio SOAP con certificado (mTLS):
//   Pruebas:    https://prewww1.aeat.es/wlpl/TIKE-CONT/ws/SistemaFacturacion/VerifactuSOAP
//   Producción: https://www1.agenciatributaria.gob.es/wlpl/TIKE-CONT/ws/SistemaFacturacion/VerifactuSOAP
//
// BookingNow calcula la huella (SHA-256 encadenada) en `issue_invoice()`;
// aquí se construye el XML `RegFactuSistemaFacturacion` y se envía con el
// certificado del negocio (cert_pem / key_pem guardados en integrations).
//
// Datos del SIF (sistema informático de facturación) — ajustar al darse de
// alta como productor de software: NombreSistemaInformatico, IdSistemaInformatico, Version.
import type { Adapter, InvoiceDTO } from "./index.ts";

const SIF = { nombreRazon: "BookingNow", nif: Deno.env.get("SIF_NIF") ?? "B00000000", nombre: "BookingNow", id: "BN", version: "1.0", instalacion: "1" };

const esc = (s: unknown) => String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const fmtDate = (iso: string) => { const [y, m, d] = iso.split("-"); return `${d}-${m}-${y}`; };
const money = (n: number) => n.toFixed(2);

function buildXml(inv: InvoiceDTO, genTime: string): string {
  // Desglose por tipo de IVA
  const byVat = new Map<number, { base: number; cuota: number }>();
  for (const l of inv.lines) {
    const base = l.unitPrice * l.quantity * (1 - l.discountPct / 100);
    const cur = byVat.get(l.vatPct) ?? { base: 0, cuota: 0 };
    cur.base += base; cur.cuota += base * l.vatPct / 100;
    byVat.set(l.vatPct, cur);
  }
  const desglose = [...byVat.entries()].map(([pct, v]) => `
          <sum1:DetalleDesglose>
            <sum1:Impuesto>01</sum1:Impuesto>
            <sum1:ClaveRegimen>01</sum1:ClaveRegimen>
            <sum1:CalificacionOperacion>${pct === 0 ? "N1" : "S1"}</sum1:CalificacionOperacion>
            <sum1:TipoImpositivo>${money(pct)}</sum1:TipoImpositivo>
            <sum1:BaseImponibleOimporteNoSujeto>${money(v.base)}</sum1:BaseImponibleOimporteNoSujeto>
            <sum1:CuotaRepercutida>${money(v.cuota)}</sum1:CuotaRepercutida>
          </sum1:DetalleDesglose>`).join("");

  const destinatario = inv.recipient.taxId ? `
        <sum1:Destinatarios>
          <sum1:IDDestinatario>
            <sum1:NombreRazon>${esc(inv.recipient.name)}</sum1:NombreRazon>
            <sum1:NIF>${esc(inv.recipient.taxId)}</sum1:NIF>
          </sum1:IDDestinatario>
        </sum1:Destinatarios>` : "";

  const encadenamiento = inv.verifactuPrevHash
    ? `<sum1:RegistroAnterior><sum1:Huella>${inv.verifactuPrevHash}</sum1:Huella></sum1:RegistroAnterior>`
    : `<sum1:PrimerRegistro>S</sum1:PrimerRegistro>`;

  return `<?xml version="1.0" encoding="UTF-8"?>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"
  xmlns:sum="https://www2.agenciatributaria.gob.es/static_files/common/internet/dep/aplicaciones/es/aeat/tike/cont/ws/SuministroLR.xsd"
  xmlns:sum1="https://www2.agenciatributaria.gob.es/static_files/common/internet/dep/aplicaciones/es/aeat/tike/cont/ws/SuministroInformacion.xsd">
  <soapenv:Header/>
  <soapenv:Body>
    <sum:RegFactuSistemaFacturacion>
      <sum:Cabecera>
        <sum1:ObligadoEmision>
          <sum1:NombreRazon>${esc(inv.issuer.name)}</sum1:NombreRazon>
          <sum1:NIF>${esc(inv.issuer.taxId)}</sum1:NIF>
        </sum1:ObligadoEmision>
      </sum:Cabecera>
      <sum:RegistroFactura>
        <sum1:RegistroAlta>
          <sum1:IDVersion>1.0</sum1:IDVersion>
          <sum1:IDFactura>
            <sum1:IDEmisorFactura>${esc(inv.issuer.taxId)}</sum1:IDEmisorFactura>
            <sum1:NumSerieFactura>${esc(inv.number)}</sum1:NumSerieFactura>
            <sum1:FechaExpedicionFactura>${fmtDate(inv.issueDate)}</sum1:FechaExpedicionFactura>
          </sum1:IDFactura>
          <sum1:NombreRazonEmisor>${esc(inv.issuer.name)}</sum1:NombreRazonEmisor>
          <sum1:TipoFactura>${inv.type}</sum1:TipoFactura>
          <sum1:DescripcionOperacion>Servicios reservados mediante BookingNow</sum1:DescripcionOperacion>${destinatario}
          <sum1:Desglose>${desglose}
          </sum1:Desglose>
          <sum1:CuotaTotal>${money(inv.vat)}</sum1:CuotaTotal>
          <sum1:ImporteTotal>${money(inv.total)}</sum1:ImporteTotal>
          <sum1:Encadenamiento>${encadenamiento}</sum1:Encadenamiento>
          <sum1:SistemaInformatico>
            <sum1:NombreRazon>${SIF.nombreRazon}</sum1:NombreRazon>
            <sum1:NIF>${SIF.nif}</sum1:NIF>
            <sum1:NombreSistemaInformatico>${SIF.nombre}</sum1:NombreSistemaInformatico>
            <sum1:IdSistemaInformatico>${SIF.id}</sum1:IdSistemaInformatico>
            <sum1:Version>${SIF.version}</sum1:Version>
            <sum1:NumeroInstalacion>${SIF.instalacion}</sum1:NumeroInstalacion>
            <sum1:TipoUsoPosibleSoloVerifactu>S</sum1:TipoUsoPosibleSoloVerifactu>
            <sum1:TipoUsoPosibleMultiOT>S</sum1:TipoUsoPosibleMultiOT>
            <sum1:IndicadorMultiplesOT>S</sum1:IndicadorMultiplesOT>
          </sum1:SistemaInformatico>
          <sum1:FechaHoraHusoGenRegistro>${genTime}</sum1:FechaHoraHusoGenRegistro>
          <sum1:TipoHuella>01</sum1:TipoHuella>
          <sum1:Huella>${inv.verifactuHash}</sum1:Huella>
        </sum1:RegistroAlta>
      </sum:RegistroFactura>
    </sum:RegFactuSistemaFacturacion>
  </soapenv:Body>
</soapenv:Envelope>`;
}

export const verifactuAeat: Adapter = {
  async pushInvoice(inv, cred, settings) {
    if (!inv.verifactuHash) throw new Error("La factura no tiene huella Verifactu");
    const prod = (cred.environment ?? settings.environment) === "prod";
    const url = prod
      ? "https://www1.agenciatributaria.gob.es/wlpl/TIKE-CONT/ws/SistemaFacturacion/VerifactuSOAP"
      : "https://prewww1.aeat.es/wlpl/TIKE-CONT/ws/SistemaFacturacion/VerifactuSOAP";
    const genTime = new Date().toISOString().replace(/\.\d{3}Z$/, "+00:00");
    const xml = buildXml(inv, genTime);
    // mTLS con el certificado del obligado tributario
    const client = Deno.createHttpClient({ certChain: cred.cert_pem, privateKey: cred.key_pem });
    const r = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "text/xml; charset=utf-8", SOAPAction: "" },
      body: xml,
      client,
    } as RequestInit & { client: Deno.HttpClient });
    const text = await r.text();
    client.close();
    const estado = /<(?:\w+:)?EstadoEnvio>(\w+)</.exec(text)?.[1];
    const csv = /<(?:\w+:)?CSV>([^<]+)</.exec(text)?.[1];
    if (!r.ok || estado === "Incorrecto") {
      const err = /<(?:\w+:)?DescripcionErrorRegistro>([^<]+)</.exec(text)?.[1] ?? text.slice(0, 300);
      throw new Error(`AEAT: ${err}`);
    }
    return {
      externalId: csv ?? inv.number,
      verifactuSentAt: new Date().toISOString(),
      verifactuResponse: { estado, csv, raw: text.slice(0, 2000) },
    };
  },
  async test(cred) {
    if (!cred.cert_pem || !cred.key_pem) return { ok: false, message: "Faltan certificado y clave" };
    try {
      const client = Deno.createHttpClient({ certChain: cred.cert_pem, privateKey: cred.key_pem });
      client.close();
      return { ok: true, message: "Certificado cargado. El primer envío validará el acceso a la AEAT." };
    } catch (e) { return { ok: false, message: `Certificado inválido: ${(e as Error).message}` }; }
  },
};
