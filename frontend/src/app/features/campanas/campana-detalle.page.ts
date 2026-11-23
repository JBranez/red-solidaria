import { ChangeDetectionStrategy, Component, computed, effect, inject, input, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { toApiError } from '../../core/models/api-error';
import { Campana, CierreCampana, Donacion, Entrega, Gasto, Categoria } from '../../core/models/api.models';
import { CampanaService, CatalogoService, DonacionService, EntregaService, GastoService } from '../../core/services/api.services';
import { AuthService } from '../../core/services/auth.service';
import { ConfirmService } from '../../core/services/confirm.service';
import { ToastService } from '../../core/services/toast.service';
import { FORMATOS, fmtMoneda } from '../../core/util/format';
import { Barras, DatoBarra, Progreso } from '../../shared/charts';
import { Carga, Estado, Kpi, Vacio } from '../../shared/ui';
import { CampanaForm } from './campana-form';

type Pestana = 'resumen' | 'donaciones' | 'gastos' | 'entregas' | 'cierre';
interface Transicion { a: string; texto: string; icono: string; clase: string; motivo?: boolean; mensaje?: string }

const TRANSICIONES: Record<string, Transicion[]> = {
  Borrador: [
    { a: 'Activa', texto: 'Activar', icono: 'play-circle', clase: 'btn-success', mensaje: 'La campaña empezará a aceptar donaciones y entregas.' },
    { a: 'Cancelada', texto: 'Cancelar', icono: 'x-octagon', clase: 'btn-outline-danger', motivo: true },
  ],
  Activa: [
    { a: 'Pausada', texto: 'Pausar', icono: 'pause-circle', clase: 'btn-outline-warning', mensaje: 'No se registrarán donaciones ni entregas mientras esté pausada.' },
    { a: 'Finalizada', texto: 'Finalizar', icono: 'flag', clase: 'btn-primary', mensaje: 'Se cerrará la campaña. Antes deben resolverse las donaciones pendientes y las entregas programadas.' },
    { a: 'Cancelada', texto: 'Cancelar', icono: 'x-octagon', clase: 'btn-outline-danger', motivo: true },
  ],
  Pausada: [
    { a: 'Activa', texto: 'Reanudar', icono: 'play-circle', clase: 'btn-success', mensaje: 'La campaña volverá a aceptar donaciones y entregas.' },
    { a: 'Finalizada', texto: 'Finalizar', icono: 'flag', clase: 'btn-primary', mensaje: 'Se cerrará la campaña.' },
    { a: 'Cancelada', texto: 'Cancelar', icono: 'x-octagon', clase: 'btn-outline-danger', motivo: true },
  ],
};

@Component({
  selector: 'rs-campana-detalle',
  imports: [RouterLink, Estado, Kpi, Progreso, Barras, Carga, Vacio, CampanaForm, ...FORMATOS],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <nav aria-label="Ruta de navegación" class="mb-2"><a routerLink="/campanas" class="small text-decoration-none"><i class="bi bi-arrow-left me-1"></i>Campañas</a></nav>
    @if (error(); as e) { <div class="alert alert-danger" role="alert">{{ e }}</div> }
    @if (c(); as c) {
      <div class="d-flex flex-wrap align-items-start justify-content-between gap-3 mb-4">
        <div>
          <div class="d-flex align-items-center gap-2 flex-wrap"><h1 class="rs-page-title">{{ c.nombre }}</h1><rs-estado [valor]="c.estado" /></div>
          <p class="rs-page-sub">{{ c.categoria }} · {{ c.fecha_inicio | fecha }} – {{ c.fecha_fin | fecha }}
            @if (c.estado === 'Activa') { · <span [class]="c.dias_restantes < 0 ? 'text-danger fw-semibold' : ''">{{ c.dias_restantes < 0 ? 'venció hace ' + (-c.dias_restantes) + ' días' : c.dias_restantes + ' días restantes' }}</span> }</p>
        </div>
        <div class="d-flex flex-wrap gap-2">
          @if (auth.tiene('campanas:escribir') && editable()) { <button class="btn btn-outline-secondary" type="button" (click)="formulario.set(true)"><i class="bi bi-pencil me-1"></i>Editar</button> }
          @if (auth.tiene('campanas:estado')) {
            @for (t of transiciones(); track t.a) { <button class="btn" [class]="t.clase" type="button" [disabled]="cambiando()" (click)="cambiar(t)"><i class="bi me-1" [class]="'bi-' + t.icono"></i>{{ t.texto }}</button> }
          }
        </div>
      </div>

      <ul class="nav nav-tabs mb-3" role="tablist">
        @for (p of pestanas(); track p.id) {
          <li class="nav-item" role="presentation"><button class="nav-link" [class.active]="pestana() === p.id" type="button" role="tab" [attr.aria-selected]="pestana() === p.id" (click)="ir(p.id)">{{ p.texto }}</button></li>
        }
      </ul>

      @switch (pestana()) {
        @case ('resumen') {
          <div class="row g-3 mb-3">
            <div class="col-6 col-lg-3"><rs-kpi etiqueta="Recaudado y verificado" [valor]="c.recaudado_confirmado | moneda: c.moneda" [pista]="c.donaciones_confirmadas + ' donaciones · ' + c.donantes + ' donantes'" acento="dar" icono="cash-coin" /></div>
            <div class="col-6 col-lg-3"><rs-kpi etiqueta="Gasto aprobado" [valor]="c.gastado_aprobado | moneda: c.moneda" acento="dar" icono="receipt" /></div>
            <div class="col-6 col-lg-3"><rs-kpi etiqueta="Saldo disponible" [valor]="c.saldo_disponible | moneda: c.moneda" pista="Recaudado − gasto aprobado" acento="dar" icono="wallet2" /></div>
            <div class="col-6 col-lg-3"><rs-kpi etiqueta="Por verificar" [valor]="c.recaudado_pendiente | moneda: c.moneda" [pista]="c.donaciones_pendientes + ' donaciones'" [acento]="c.donaciones_pendientes ? 'alerta' : 'neutro'" icono="hourglass-split" /></div>
          </div>
          <div class="row g-3">
            <div class="col-lg-7"><div class="card h-100"><div class="card-header">Avance frente a las metas</div><div class="card-body d-grid gap-4">
              <rs-progreso etiqueta="Meta económica" [valor]="c.pct_meta_recaudacion" [texto]="(c.recaudado_confirmado | moneda: c.moneda) + ' de ' + (c.meta_recaudacion | moneda: c.moneda) + ' · ' + (c.pct_meta_recaudacion | pct)" color="var(--rs-dar)" />
              @if (c.meta_hogares) { <rs-progreso etiqueta="Meta social: hogares atendidos" [valor]="c.pct_meta_hogares" [texto]="c.hogares_atendidos + ' de ' + c.meta_hogares + ' · ' + (c.pct_meta_hogares | pct)" color="var(--rs-recibe)" /> }
              @else { <div class="small text-secondary"><i class="bi bi-people me-1"></i>{{ c.hogares_atendidos }} hogares atendidos (sin meta social definida).</div> }
              @if (c.meta_unidades) { <rs-progreso etiqueta="Meta física: unidades entregadas" [valor]="c.pct_meta_unidades" [texto]="(c.unidades_entregadas | num) + ' de ' + (c.meta_unidades | num)" color="var(--rs-campana)" /> }
              @else { <div class="small text-secondary"><i class="bi bi-box-seam me-1"></i>{{ c.unidades_entregadas | num }} unidades entregadas (sin meta física definida).</div> }
              <p class="small text-secondary mb-0">La meta económica, la social y la física son independientes: recaudar mucho no significa haber llegado a los hogares previstos.</p>
            </div></div></div>
            <div class="col-lg-5"><div class="card h-100"><div class="card-header">Ficha</div><div class="card-body">
              <dl class="row small mb-0 gy-2">
                <dt class="col-5 fw-normal text-secondary">Objetivo social</dt><dd class="col-7 mb-0">{{ c.objetivo_social || '—' }}</dd>
                <dt class="col-5 fw-normal text-secondary">Descripción</dt><dd class="col-7 mb-0">{{ c.descripcion || '—' }}</dd>
                <dt class="col-5 fw-normal text-secondary">Responsable</dt><dd class="col-7 mb-0">{{ c.responsable || '—' }}</dd>
                <dt class="col-5 fw-normal text-secondary">Entregas</dt><dd class="col-7 mb-0">{{ c.entregas_realizadas }} realizadas · {{ c.entregas_programadas }} programadas</dd>
                <dt class="col-5 fw-normal text-secondary">Voluntarios</dt><dd class="col-7 mb-0">{{ c.voluntarios_participantes }} participaron</dd>
                @if (c.cerrada_en) { <dt class="col-5 fw-normal text-secondary">Cierre</dt><dd class="col-7 mb-0">{{ c.cerrada_en | fechaHora }}@if (c.motivo_cierre) { <div class="text-secondary">{{ c.motivo_cierre }}</div> }</dd> }
              </dl>
            </div></div></div>
          </div>
        }
        @case ('donaciones') {
          <div class="card">@if (!donaciones()) { <rs-carga /> } @else if (!donaciones()!.length) { <rs-vacio icono="cash-coin" titulo="Aún no hay donaciones" /> } @else {
            <div class="table-responsive"><table class="table rs-table"><thead><tr><th>Fecha</th><th>Donante</th><th>Método</th><th class="text-end">Monto</th><th>Estado</th></tr></thead><tbody>
              @for (d of donaciones(); track d.id_donacion) { <tr><td>{{ d.fecha | fecha }}</td><td>{{ d.donante }}</td><td>{{ d.metodo_pago }}</td><td class="text-end tabular">{{ d.monto | moneda: d.moneda }}</td><td><rs-estado [valor]="d.estado" /></td></tr> }
            </tbody></table></div>
            <div class="p-2 border-top text-end"><a class="btn btn-sm btn-link" routerLink="/donaciones" [queryParams]="{ id_campana: c.id_campana }">Ver todas con filtros</a></div> }</div>
        }
        @case ('gastos') {
          <div class="card">@if (!gastos()) { <rs-carga /> } @else if (!gastos()!.length) { <rs-vacio icono="receipt" titulo="Aún no hay gastos registrados" /> } @else {
            <div class="table-responsive"><table class="table rs-table"><thead><tr><th>Fecha</th><th>Concepto</th><th>Proveedor</th><th class="text-end">Monto</th><th>Estado</th></tr></thead><tbody>
              @for (g of gastos(); track g.id_gasto) { <tr><td>{{ g.fecha | fecha }}</td><td>{{ g.concepto }}<div class="small text-secondary">{{ g.comprobante }}</div></td><td>{{ g.proveedor || '—' }}</td><td class="text-end tabular">{{ g.monto | moneda: g.moneda }}</td><td><rs-estado [valor]="g.estado" /></td></tr> }
            </tbody></table></div>
            <div class="p-2 border-top text-end"><a class="btn btn-sm btn-link" routerLink="/gastos" [queryParams]="{ id_campana: c.id_campana }">Gestionar gastos</a></div> }</div>
        }
        @case ('entregas') {
          <div class="card">@if (!entregas()) { <rs-carga /> } @else if (!entregas()!.length) { <rs-vacio icono="box-seam" titulo="Aún no hay entregas" /> } @else {
            <div class="table-responsive"><table class="table rs-table"><thead><tr><th>Fecha</th><th>Hogar</th><th>Sector</th><th>Voluntario</th><th class="text-end">Cant.</th><th>Estado</th></tr></thead><tbody>
              @for (e of entregas(); track e.id_entrega) { <tr><td>{{ e.fecha | fecha }}</td><td>{{ e.hogar }}</td><td>{{ e.sector }}</td><td>{{ e.voluntario }}</td><td class="text-end tabular">{{ e.cantidad }}</td><td><rs-estado [valor]="e.estado" /></td></tr> }
            </tbody></table></div>
            <div class="p-2 border-top text-end"><a class="btn btn-sm btn-link" routerLink="/entregas" [queryParams]="{ id_campana: c.id_campana }">Ver todas con filtros</a></div> }</div>
        }
        @case ('cierre') {
          @if (!cierre()) { <div class="card"><rs-carga /></div> } @else {
            @let r = cierre()!;
            <div class="d-flex justify-content-between align-items-center mb-3"><p class="text-secondary mb-0">Rendición de cuentas de la campaña: de dónde vino el dinero, en qué se usó y a quién llegó.</p><button class="btn btn-outline-secondary" type="button" (click)="imprimir()"><i class="bi bi-printer me-1"></i>Imprimir</button></div>
            <div class="row g-3">
              <div class="col-lg-6"><div class="card h-100"><div class="card-header">Dinero recibido, por método de pago</div><div class="card-body">
                @if (r.donaciones_por_metodo.length) { <rs-barras [datos]="barrasMetodo()" color="var(--rs-dar)" /> } @else { <span class="text-secondary small">Sin donaciones confirmadas.</span> }</div></div></div>
              <div class="col-lg-6"><div class="card h-100"><div class="card-header">Gasto aprobado, por tipo</div><div class="card-body">
                @if (r.gastos_por_tipo.length) { <rs-barras [datos]="barrasGasto()" color="var(--rs-campana)" /> } @else { <span class="text-secondary small">Sin gastos aprobados.</span> }</div></div></div>
              <div class="col-lg-7"><div class="card h-100"><div class="card-header">Alcance por sector</div>
                @if (r.entregas_por_sector.length) { <div class="table-responsive"><table class="table rs-table"><thead><tr><th>Sector</th><th class="text-end">Hogares</th><th class="text-end">Entregas</th><th class="text-end">Unidades</th></tr></thead><tbody>
                  @for (s of r.entregas_por_sector; track s.sector) { <tr><td>{{ s.sector }}</td><td class="text-end tabular">{{ s.hogares }}</td><td class="text-end tabular">{{ s.entregas }}</td><td class="text-end tabular">{{ s.unidades | num }}</td></tr> }</tbody></table></div> }
                @else { <rs-vacio icono="geo-alt" titulo="Sin entregas realizadas" /> }</div></div>
              <div class="col-lg-5"><div class="card h-100"><div class="card-header">Voz de los hogares</div><div class="card-body">
                <dl class="row mb-0 gy-2"><dt class="col-7 fw-normal text-secondary">Mensajes recibidos</dt><dd class="col-5 text-end mb-0">{{ r.retroalimentacion.total }}</dd>
                  <dt class="col-7 fw-normal text-secondary">Satisfacción promedio</dt><dd class="col-5 text-end mb-0">{{ r.retroalimentacion.satisfaccion_promedio === null ? '—' : r.retroalimentacion.satisfaccion_promedio + ' / 5' }}</dd>
                  <dt class="col-7 fw-normal text-secondary">Quejas (abiertas)</dt><dd class="col-5 text-end mb-0">{{ r.retroalimentacion.quejas }} ({{ r.retroalimentacion.quejas_abiertas }})</dd></dl></div></div></div>
            </div>
          }
        }
      }
    } @else if (!error()) { <rs-carga [n]="8" /> }

    @if (formulario() && c()) { <rs-campana-form [campana]="c()" [categorias]="categorias()" (cerrar)="formulario.set(false)" (guardado)="actualizada($event)" /> }`,
})
export class CampanaDetallePage {
  readonly id = input.required<string>();
  protected readonly auth = inject(AuthService);
  private readonly api = inject(CampanaService);
  private readonly donacionApi = inject(DonacionService);
  private readonly gastoApi = inject(GastoService);
  private readonly entregaApi = inject(EntregaService);
  private readonly toast = inject(ToastService);
  private readonly confirm = inject(ConfirmService);

  protected readonly c = signal<Campana | null>(null);
  protected readonly error = signal<string | null>(null);
  protected readonly pestana = signal<Pestana>('resumen');
  protected readonly donaciones = signal<Donacion[] | null>(null);
  protected readonly gastos = signal<Gasto[] | null>(null);
  protected readonly entregas = signal<Entrega[] | null>(null);
  protected readonly cierre = signal<CierreCampana | null>(null);
  protected readonly categorias = signal<Categoria[]>([]);
  protected readonly formulario = signal(false);
  protected readonly cambiando = signal(false);

  protected readonly transiciones = computed(() => TRANSICIONES[this.c()?.estado ?? ''] ?? []);
  protected readonly editable = computed(() => ['Borrador', 'Activa', 'Pausada'].includes(this.c()?.estado ?? ''));
  protected readonly pestanas = computed(() => [
    { id: 'resumen' as Pestana, texto: 'Resumen', ok: true },
    { id: 'donaciones' as Pestana, texto: 'Donaciones', ok: this.auth.tiene('donaciones:leer') },
    { id: 'gastos' as Pestana, texto: 'Gastos', ok: this.auth.tiene('gastos:leer') },
    { id: 'entregas' as Pestana, texto: 'Entregas', ok: this.auth.tiene('entregas:leer') },
    { id: 'cierre' as Pestana, texto: 'Informe de cierre', ok: true },
  ].filter((p) => p.ok));
  protected readonly barrasMetodo = computed<DatoBarra[]>(() => (this.cierre()?.donaciones_por_metodo ?? []).map((m) => ({ etiqueta: `${m.metodo} (${m.cantidad})`, valor: m.total, texto: fmtMoneda(m.total, this.c()?.moneda) })));
  protected readonly barrasGasto = computed<DatoBarra[]>(() => (this.cierre()?.gastos_por_tipo ?? []).map((g) => ({ etiqueta: `${g.tipo} (${g.cantidad})`, valor: g.total, texto: fmtMoneda(g.total, this.c()?.moneda) })));

  constructor() {
    inject(CatalogoService).categorias().subscribe({ next: (c) => this.categorias.set(c.filter((x) => x.activo)), error: () => undefined });
    effect(() => { this.id(); this.cargar(); });
  }

  private cargar(): void {
    const id = Number(this.id());
    this.error.set(null);
    this.api.obtener(id).subscribe({ next: (c) => this.c.set(c), error: (e) => this.error.set(toApiError(e).message) });
  }

  protected ir(p: Pestana): void {
    this.pestana.set(p);
    const id = Number(this.id());
    const fallo = (e: unknown) => this.toast.error(toApiError(e).message);
    if (p === 'donaciones' && !this.donaciones()) this.donacionApi.listar({ id_campana: id, tamano: 10 }).subscribe({ next: (r) => this.donaciones.set(r.items), error: fallo });
    if (p === 'gastos' && !this.gastos()) this.gastoApi.listar({ id_campana: id, tamano: 10 }).subscribe({ next: (r) => this.gastos.set(r.items), error: fallo });
    if (p === 'entregas' && !this.entregas()) this.entregaApi.listar({ id_campana: id, tamano: 10 }).subscribe({ next: (r) => this.entregas.set(r.items), error: fallo });
    if (p === 'cierre' && !this.cierre()) this.api.cierre(id).subscribe({ next: (r) => this.cierre.set(r), error: fallo });
  }

  protected async cambiar(t: Transicion): Promise<void> {
    const c = this.c();
    if (!c) return;
    const r = await this.confirm.preguntar({
      titulo: `${t.texto} la campaña «${c.nombre}»`, mensaje: t.mensaje ?? '', confirmar: t.texto, peligro: t.a === 'Cancelada',
      pedirMotivo: t.motivo, motivoEtiqueta: 'Motivo de la cancelación',
    });
    if (!r.ok) return;
    this.cambiando.set(true);
    this.api.cambiarEstado(c.id_campana, t.a, r.motivo).subscribe({
      next: (n) => { this.c.set(n); this.cambiando.set(false); this.cierre.set(null); this.toast.ok(`Campaña ${n.estado.toLowerCase()}.`); },
      error: (e) => { this.cambiando.set(false); this.toast.error(toApiError(e).message); },
    });
  }

  protected actualizada(c: Campana): void { this.c.set(c); this.formulario.set(false); }
  protected imprimir(): void { window.print(); }
}
