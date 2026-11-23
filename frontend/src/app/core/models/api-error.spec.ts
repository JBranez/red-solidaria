import { HttpErrorResponse } from '@angular/common/http';
import { describe, expect, it } from 'vitest';
import { ApiError, toApiError } from './api-error';

describe('toApiError', () => {
  it('lee el formato de error de la API', () => {
    const e = toApiError(new HttpErrorResponse({ status: 422, error: { error: { codigo: 'REGLA_DE_NEGOCIO', mensaje: 'Solo campañas activas.', detalles: [{ campo: 'fecha', mensaje: 'x' }] } } }));
    expect(e).toBeInstanceOf(ApiError);
    expect(e.status).toBe(422); expect(e.codigo).toBe('REGLA_DE_NEGOCIO'); expect(e.message).toBe('Solo campañas activas.'); expect(e.detalles).toHaveLength(1);
  });
  it('un cuerpo de error recibido como texto JSON también se entiende', () => {
    const e = toApiError(new HttpErrorResponse({ status: 403, error: '{"error":{"codigo":"PROHIBIDO","mensaje":"No puede."}}' }));
    expect(e.codigo).toBe('PROHIBIDO'); expect(e.message).toBe('No puede.');
  });
  it('sin conexión (status 0) da un mensaje comprensible', () => {
    const e = toApiError(new HttpErrorResponse({ status: 0 }));
    expect(e.codigo).toBe('SIN_CONEXION'); expect(e.message).toMatch(/conectar/);
  });
  it('un cuerpo inesperado no rompe y no expone detalles', () => {
    expect(toApiError(new HttpErrorResponse({ status: 500, error: '<html>Traceback...</html>' })).message).toBe('No se pudo completar la operación.');
  });
  it('detecta la solicitud de confirmación (posible duplicado)', () => {
    expect(new ApiError(409, 'REQUIERE_CONFIRMACION', 'x').requiereConfirmacion).toBe(true);
    expect(new ApiError(409, 'CONFLICTO', 'x').requiereConfirmacion).toBe(false);
  });
  it('errores que no son HTTP', () => { expect(toApiError(new Error('boom')).message).toBe('boom'); });
});
