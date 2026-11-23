import { Pipe, PipeTransform } from '@angular/core';

const LOCALE = 'es-PE';
const parseFecha = (v: string): Date => {
  // 'YYYY-MM-DD' se interpreta como fecha de calendario: new Date('2026-01-15') sería UTC y mostraría el día anterior en Perú.
  const [y, m, d] = v.slice(0, 10).split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d));
};
const parseMarca = (v: string): Date => new Date(/[zZ]|[+-]\d\d:?\d\d$/.test(v) ? v : v + 'Z'); // la API entrega UTC sin sufijo

export const fmtMoneda = (v: number | null | undefined, moneda = 'PEN'): string =>
  v === null || v === undefined ? '—' : new Intl.NumberFormat(LOCALE, { style: 'currency', currency: moneda, maximumFractionDigits: 2 }).format(v);
export const fmtNum = (v: number | null | undefined): string => (v === null || v === undefined ? '—' : new Intl.NumberFormat(LOCALE).format(v));
export const fmtPct = (v: number | null | undefined, dec = 0): string =>
  v === null || v === undefined ? '—' : `${new Intl.NumberFormat(LOCALE, { maximumFractionDigits: dec }).format(v)} %`;
export const fmtFecha = (v: string | null | undefined): string =>
  !v ? '—' : new Intl.DateTimeFormat(LOCALE, { day: '2-digit', month: 'short', year: 'numeric', timeZone: 'UTC' }).format(parseFecha(v)).replace('.', '');
export const fmtFechaHora = (v: string | null | undefined): string =>
  !v ? '—' : new Intl.DateTimeFormat(LOCALE, { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }).format(parseMarca(v)).replace('.', '');
export const hoyISO = (): string => {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};
export const sumarDias = (iso: string, dias: number): string => {
  const d = parseFecha(iso);
  d.setUTCDate(d.getUTCDate() + dias);
  return d.toISOString().slice(0, 10);
};

@Pipe({ name: 'moneda' }) export class MonedaPipe implements PipeTransform { transform(v: number | null | undefined, moneda = 'PEN'): string { return fmtMoneda(v, moneda); } }
@Pipe({ name: 'num' }) export class NumPipe implements PipeTransform { transform(v: number | null | undefined): string { return fmtNum(v); } }
@Pipe({ name: 'pct' }) export class PctPipe implements PipeTransform { transform(v: number | null | undefined, dec = 0): string { return fmtPct(v, dec); } }
@Pipe({ name: 'fecha' }) export class FechaPipe implements PipeTransform { transform(v: string | null | undefined): string { return fmtFecha(v); } }
@Pipe({ name: 'fechaHora' }) export class FechaHoraPipe implements PipeTransform { transform(v: string | null | undefined): string { return fmtFechaHora(v); } }

export const FORMATOS = [MonedaPipe, NumPipe, PctPipe, FechaPipe, FechaHoraPipe] as const;
