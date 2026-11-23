import { HttpErrorResponse } from '@angular/common/http';

export interface DetalleError { campo: string; mensaje: string }

/** Error normalizado: la interfaz nunca depende de la forma cruda de la respuesta del servidor. */
export class ApiError extends Error {
  constructor(
    public readonly status: number,
    public readonly codigo: string,
    mensaje: string,
    public readonly detalles: DetalleError[] = [],
  ) {
    super(mensaje);
    this.name = 'ApiError';
  }
  get requiereConfirmacion(): boolean { return this.codigo === 'REQUIERE_CONFIRMACION'; }
}

export function toApiError(err: unknown): ApiError {
  if (err instanceof ApiError) return err;
  if (err instanceof HttpErrorResponse) {
    if (err.status === 0) return new ApiError(0, 'SIN_CONEXION', 'No se pudo conectar con el servidor. Verifique su conexión e intente de nuevo.');
    let crudo: unknown = err.error;
    if (typeof crudo === 'string') { try { crudo = JSON.parse(crudo); } catch { crudo = null; } }  // respuestas pedidas como texto
    const cuerpo = (crudo as { error?: { codigo?: string; mensaje?: string; detalles?: DetalleError[] } } | null)?.error;
    return new ApiError(err.status, cuerpo?.codigo ?? `HTTP_${err.status}`, cuerpo?.mensaje ?? 'No se pudo completar la operación.', cuerpo?.detalles ?? []);
  }
  return new ApiError(-1, 'DESCONOCIDO', err instanceof Error ? err.message : 'Ocurrió un error inesperado.');
}
