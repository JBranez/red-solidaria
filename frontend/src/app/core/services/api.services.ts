import { HttpClient, HttpParams } from '@angular/common/http';
import { inject, Injectable } from '@angular/core';
import { map, Observable } from 'rxjs';
import {
  Auditoria, Beneficiario, Campana, Categoria, CierreCampana, Donacion, Donante, Entrega, Feedback, Gasto, Kpis, MatrizRoles,
  MetodoPago, Necesidad, Pagina, PorCategoria, PorSector, PublicoCampana, PublicoResumen, Rol, Sector, SerieMensual, TopDonante,
  UsuarioAdmin, Voluntario,
} from '../models/api.models';

export type Filtros = Record<string, string | number | boolean | null | undefined>;
type Cuerpo = Record<string, unknown>;

/** Quita los filtros vacíos: la API rechaza parámetros en blanco y los desconocidos. */
export function aParams(f: Filtros = {}): HttpParams {
  let p = new HttpParams();
  for (const [k, v] of Object.entries(f)) if (v !== null && v !== undefined && v !== '' && v !== false) p = p.set(k, String(v));
  return p;
}

abstract class Recurso {
  protected readonly http = inject(HttpClient);
  protected abstract readonly base: string;
  protected lista<T>(f?: Filtros): Observable<Pagina<T>> { return this.http.get<Pagina<T>>(this.base, { params: aParams(f) }); }
  protected uno<T>(id: number): Observable<T> { return this.http.get<T>(`${this.base}/${id}`); }
  protected crear<T>(b: Cuerpo): Observable<T> { return this.http.post<T>(this.base, b); }
  protected editar<T>(id: number, b: Cuerpo): Observable<T> { return this.http.put<T>(`${this.base}/${id}`, b); }
  protected estado<T>(id: number, b: Cuerpo, verbo: 'post' | 'patch' = 'post'): Observable<T> { return this.http[verbo]<T>(`${this.base}/${id}/estado`, b); }
  /** CSV como texto: si falla, el cuerpo de error JSON llega legible. Se antepone el BOM para que Excel respete las tildes. */
  protected csv(ruta: string, f?: Filtros): Observable<Blob> {
    return this.http.get(`${this.base}${ruta}`, { params: aParams(f), responseType: 'text' }).pipe(
      map((t) => new Blob(['\ufeff', t.replace(/^\ufeff/, '')], { type: 'text/csv;charset=utf-8' })),
    );
  }
}

@Injectable({ providedIn: 'root' })
export class CatalogoService {
  private readonly http = inject(HttpClient);
  categorias(): Observable<Categoria[]> { return this.http.get<Categoria[]>('/api/v1/categorias'); }
  categoriasActivas(): Observable<Categoria[]> { return this.http.get<Categoria[]>('/api/v1/categorias', { params: { solo_activas: true } }); }
  guardarCategoria(id: number | null, b: Cuerpo): Observable<Categoria> {
    return id ? this.http.put<Categoria>(`/api/v1/categorias/${id}`, b) : this.http.post<Categoria>('/api/v1/categorias', b);
  }
  estadoCategoria(id: number, activo: boolean): Observable<Categoria> { return this.http.patch<Categoria>(`/api/v1/categorias/${id}/estado`, { activo }); }
  sectores(): Observable<Sector[]> { return this.http.get<Sector[]>('/api/v1/sectores'); }
  sectoresActivos(): Observable<Sector[]> { return this.http.get<Sector[]>('/api/v1/sectores', { params: { solo_activos: true } }); }
  guardarSector(id: number | null, b: Cuerpo): Observable<Sector> {
    return id ? this.http.put<Sector>(`/api/v1/sectores/${id}`, b) : this.http.post<Sector>('/api/v1/sectores', b);
  }
  estadoSector(id: number, activo: boolean): Observable<Sector> { return this.http.patch<Sector>(`/api/v1/sectores/${id}/estado`, { activo }); }
  metodosPago(): Observable<MetodoPago[]> { return this.http.get<MetodoPago[]>('/api/v1/metodos-pago'); }
}

@Injectable({ providedIn: 'root' })
export class CampanaService extends Recurso {
  protected readonly base = '/api/v1/campanas';
  listar(f?: Filtros): Observable<Pagina<Campana>> { return this.lista(f); }
  obtener(id: number): Observable<Campana> { return this.uno(id); }
  guardar(id: number | null, b: Cuerpo): Observable<Campana> { return id ? this.editar(id, b) : this.crear(b); }
  cambiarEstado(id: number, estado: string, motivo?: string): Observable<Campana> { return this.estado(id, { estado, motivo: motivo || null }); }
  cierre(id: number): Observable<CierreCampana> { return this.http.get<CierreCampana>(`${this.base}/${id}/cierre`); }
}

@Injectable({ providedIn: 'root' })
export class DonanteService extends Recurso {
  protected readonly base = '/api/v1/donantes';
  listar(f?: Filtros): Observable<Pagina<Donante>> { return this.lista(f); }
  guardar(id: number | null, b: Cuerpo): Observable<Donante> { return id ? this.editar(id, b) : this.crear(b); }
  cambiarEstado(id: number, activo: boolean): Observable<Donante> { return this.estado(id, { activo }, 'patch'); }
}

@Injectable({ providedIn: 'root' })
export class DonacionService extends Recurso {
  protected readonly base = '/api/v1/donaciones';
  listar(f?: Filtros): Observable<Pagina<Donacion>> { return this.lista(f); }
  registrar(b: Cuerpo): Observable<Donacion> { return this.crear(b); }
  cambiarEstado(id: number, estado: string, motivo?: string): Observable<Donacion> { return this.estado(id, { estado, motivo: motivo || null }); }
  exportar(f?: Filtros): Observable<Blob> { return this.csv('/export', f); }
}

@Injectable({ providedIn: 'root' })
export class GastoService extends Recurso {
  protected readonly base = '/api/v1/gastos';
  listar(f?: Filtros): Observable<Pagina<Gasto>> { return this.lista(f); }
  registrar(b: Cuerpo): Observable<Gasto> { return this.crear(b); }
  cambiarEstado(id: number, estado: string, motivo?: string): Observable<Gasto> { return this.estado(id, { estado, motivo: motivo || null }); }
}

@Injectable({ providedIn: 'root' })
export class BeneficiarioService extends Recurso {
  protected readonly base = '/api/v1/beneficiarios';
  listar(f?: Filtros): Observable<Pagina<Beneficiario>> { return this.lista(f); }
  guardar(id: number | null, b: Cuerpo): Observable<Beneficiario> { return id ? this.editar(id, b) : this.crear(b); }
  cambiarEstado(id: number, activo: boolean): Observable<Beneficiario> { return this.estado(id, { activo }, 'patch'); }
}

@Injectable({ providedIn: 'root' })
export class NecesidadService extends Recurso {
  protected readonly base = '/api/v1/necesidades';
  listar(f?: Filtros): Observable<Pagina<Necesidad>> { return this.lista(f); }
  guardar(id: number | null, b: Cuerpo): Observable<Necesidad> { return id ? this.editar(id, b) : this.crear(b); }
  cambiarEstado(id: number, estado: string, motivo?: string): Observable<Necesidad> { return this.estado(id, { estado, motivo: motivo || null }); }
}

@Injectable({ providedIn: 'root' })
export class VoluntarioService extends Recurso {
  protected readonly base = '/api/v1/voluntarios';
  listar(f?: Filtros): Observable<Pagina<Voluntario>> { return this.lista(f); }
  guardar(id: number | null, b: Cuerpo): Observable<Voluntario> { return id ? this.editar(id, b) : this.crear(b); }
  cambiarEstado(id: number, activo: boolean): Observable<Voluntario> { return this.estado(id, { activo }, 'patch'); }
}

@Injectable({ providedIn: 'root' })
export class EntregaService extends Recurso {
  protected readonly base = '/api/v1/entregas';
  listar(f?: Filtros): Observable<Pagina<Entrega>> { return this.lista(f); }
  registrar(b: Cuerpo): Observable<Entrega> { return this.crear(b); }
  cambiarEstado(id: number, estado: string, motivo?: string, fecha?: string): Observable<Entrega> {
    return this.estado(id, { estado, motivo: motivo || null, fecha: fecha || null });
  }
  exportar(f?: Filtros): Observable<Blob> { return this.csv('/export', f); }
}

@Injectable({ providedIn: 'root' })
export class FeedbackService extends Recurso {
  protected readonly base = '/api/v1/feedback';
  listar(f?: Filtros): Observable<Pagina<Feedback>> { return this.lista(f); }
  registrar(b: Cuerpo): Observable<void> { return this.http.post<void>(this.base, b); }
  gestionar(id: number, b: Cuerpo): Observable<Feedback> { return this.http.post<Feedback>(`${this.base}/${id}/gestionar`, b); }
}

@Injectable({ providedIn: 'root' })
export class UsuarioService extends Recurso {
  protected readonly base = '/api/v1/usuarios';
  listar(f?: Filtros): Observable<Pagina<UsuarioAdmin>> { return this.lista(f); }
  guardar(id: number | null, b: Cuerpo): Observable<UsuarioAdmin> { return id ? this.editar(id, b) : this.crear(b); }
  cambiarEstado(id: number, activo: boolean): Observable<UsuarioAdmin> { return this.estado(id, { activo }, 'patch'); }
  restablecer(id: number, passwordNueva: string, debeCambiar: boolean): Observable<void> {
    return this.http.post<void>(`${this.base}/${id}/password`, { password_nueva: passwordNueva, debe_cambiar_password: debeCambiar });
  }
  roles(): Observable<Rol[]> { return this.http.get<Rol[]>('/api/v1/roles'); }
  matriz(): Observable<MatrizRoles> { return this.http.get<MatrizRoles>('/api/v1/roles/matriz'); }
}

@Injectable({ providedIn: 'root' })
export class AuditoriaService extends Recurso {
  protected readonly base = '/api/v1/auditoria';
  listar(f?: Filtros): Observable<Pagina<Auditoria>> { return this.lista(f); }
}

@Injectable({ providedIn: 'root' })
export class ReporteService {
  private readonly http = inject(HttpClient);
  kpis(): Observable<Kpis> { return this.http.get<Kpis>('/api/v1/dashboard/kpis'); }
  series(meses = 12): Observable<SerieMensual[]> { return this.http.get<SerieMensual[]>('/api/v1/dashboard/series', { params: { meses } }); }
  porCategoria(): Observable<PorCategoria[]> { return this.http.get<PorCategoria[]>('/api/v1/dashboard/categorias'); }
  porSector(): Observable<PorSector[]> { return this.http.get<PorSector[]>('/api/v1/dashboard/sectores'); }
  topDonantes(limite = 5): Observable<TopDonante[]> { return this.http.get<TopDonante[]>('/api/v1/reportes/top-donantes', { params: { limite } }); }
}

@Injectable({ providedIn: 'root' })
export class PublicoService {
  private readonly http = inject(HttpClient);
  resumen(): Observable<PublicoResumen> { return this.http.get<PublicoResumen>('/api/v1/public/resumen'); }
  campanas(): Observable<PublicoCampana[]> { return this.http.get<PublicoCampana[]>('/api/v1/public/campanas'); }
}

@Injectable({ providedIn: 'root' })
export class MiPortalService {
  private readonly http = inject(HttpClient);
  donaciones(f?: Filtros): Observable<Pagina<Donacion>> { return this.http.get<Pagina<Donacion>>('/api/v1/mi/donaciones', { params: aParams(f) }); }
  entregas(f?: Filtros): Observable<Pagina<Entrega>> { return this.http.get<Pagina<Entrega>>('/api/v1/mi/entregas', { params: aParams(f) }); }
}
