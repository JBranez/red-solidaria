import { describe, expect, it } from 'vitest';
import { fmtFecha, fmtFechaHora, fmtMoneda, fmtNum, fmtPct, hoyISO, sumarDias } from './format';

describe('formato (es-PE)', () => {
  it('una fecha de calendario no se corre un día por la zona horaria', () => {
    // new Date('2026-01-15') es UTC: en Perú (UTC-5) mostraría el 14. fmtFecha debe mostrar siempre el 15.
    expect(fmtFecha('2026-01-15')).toMatch(/15/);
    expect(fmtFecha('2026-03-01')).toMatch(/01/);
  });
  it('fechas vacías o nulas se muestran como guion', () => {
    expect(fmtFecha(null)).toBe('—'); expect(fmtFecha('')).toBe('—'); expect(fmtFechaHora(undefined)).toBe('—');
  });
  it('moneda con símbolo y dos decimales', () => {
    expect(fmtMoneda(1234.5, 'PEN')).toMatch(/S\/\s?1,234\.50/); expect(fmtMoneda(null)).toBe('—');
  });
  it('números y porcentajes', () => {
    expect(fmtNum(1234567)).toContain('1,234,567'); expect(fmtPct(58.04, 1)).toMatch(/^58\s?%$/); expect(fmtPct(58.46, 1)).toMatch(/^58\.5\s?%$/); expect(fmtPct(null)).toBe('—');
  });
  it('una marca de tiempo sin zona se interpreta como UTC', () => {
    expect(fmtFechaHora('2026-11-14T15:00:00')).toBe(fmtFechaHora('2026-11-14T15:00:00Z'));
  });
  it('hoyISO y sumarDias', () => {
    expect(hoyISO()).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect(sumarDias('2026-02-27', 3)).toBe('2026-03-02'); expect(sumarDias('2026-12-30', 5)).toBe('2027-01-04');
  });
});
