import { ChangeDetectionStrategy, Component, inject, input, output, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute } from '@angular/router';
import { Observable } from 'rxjs';
import { toApiError } from '../../core/models/api-error';
import { Campana, Entrega, Pagina, Sector } from '../../core/models/api.models';
import { CampanaService, CatalogoService, EntregaService } from '../../core/services/api.services';
import { AuthService } from '../../core/services/auth.service';
import { ConfirmService } from '../../core/services/confirm.service';
import { ToastService } from '../../core/services/toast.service';
import { descargar } from '../../core/util/download';
import { FORMATOS, hoyISO } from '../../core/util/format';
import { ListaBase } from '../../core/util/lista-base';
import { Carga, Encabezado, Estado, Modal, Paginacion, Vacio } from '../../shared/ui';
import { EntregaForm } from './entrega-form';

/** Constancia de entrega imprimible: respaldo para el hogar y para la organización. */
@Component({
  selector: 'rs-constancia',
  imports: [Modal, ...FORMATOS],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <rs-modal titulo="Constancia de entrega" (cerrar)="cerrar.emit()">
      <div class="rs-constancia">
        <div class="d-flex justify-content-between align-items-start mb-3 pb-3 border-bottom">
          <div><div class="fw-bold fs-5">Red Solidaria</div><div class="small text-secondary">Constancia de entrega de ayuda</div></div>
          <div class="text-end small"><div class="text-secondary">N.º</div><div class="fw-bold fs-5 tabular">{{ entrega().id_entrega | num }}</div></div>
        </div>
        <dl class="row mb-4 gy-2">
          <dt class="col-4 fw-normal text-secondary">Campaña</dt><dd class="col-8 mb-0 fw-semibold">{{ entrega().campana }} <span class="fw-normal text-secondary">({{ entrega().categoria }})</span></dd>
          <dt class="col-4 fw-normal text-secondary">Hogar receptor</dt><dd class="col-8 mb-0">{{ entrega().hogar }} · {{ entrega().sector }}</dd>
          <dt class="col-4 fw-normal text-secondary">Fecha</dt><dd class="col-8 mb-0">{{ entrega().fecha | fecha }}</dd>
          <dt class="col-4 fw-normal text-secondary">Entregado</dt><dd class="col-8 mb-0">{{ entrega().cantidad }} {{ entrega().cantidad === 1 ? 'unidad' : 'unidades' }}@if (entrega().detalle) { · {{ entrega().detalle }} }</dd>
          <dt class="col-4 fw-normal text-secondary">Entregó</dt><dd class="col-8 mb-0">{{ entrega().voluntario }}</dd>
        </dl>
        <div class="row text-center small pt-4"><div class="col-6"><div class="border-top pt-2 mx-3">Firma de quien recibe</div></div><div class="col-6"><div class="border-top pt-2 mx-3">Firma del voluntario</div></div></div>
      </div>
      <div pie class="modal-footer border-0"><button type="button" class="btn btn-light" (click)="cerrar.emit()">Cerrar</button><button type="button" class="btn btn-primary" (click)="imprimir()"><i class="bi bi-printer me-1"></i>Imprimir</button></div>
    </rs-modal>`,
})
export class Constancia {
  readonly entrega = input.required<Entrega>();
  readonly cerrar = output<void>();
  protected imprimir(): void {
    document.body.classList.add('rs-imprimiendo');
    window.addEventListener('afterprint', () => document.body.classList.remove('rs-imprimiendo'), { once: true });
    window.print();
  }
}

@Component({
  selector: 'rs-entregas',
  imports: [FormsModule, Encabezado, Estado, Carga, Vacio, Paginacion, EntregaForm, Constancia, ...FORMATOS],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <rs-encabezado titulo="Entregas" subtitulo="Una entrega nunca se borra: se anula con motivo y queda en la auditoría.">
      @if (auth.tiene('reportes:exportar')) { <button class="btn btn-outline-secondary" type="button" [disabled]="exportando()" (click)="exportar()"><i class="bi bi-download me-1"></i>Exportar CSV</button> }
      @if (auth.tiene('entregas:registrar')) { <button class="btn btn-primary" type="button" (click)="formulario.set(true)"><i class="bi bi-plus-lg me-1"></i>Registrar entrega</button> }
    </rs-encabezado>
    <div class="card">
      <div class="card-body border-bottom"><div class="row g-2">
        <div class="col-md-4"><div class="input-group"><span class="input-group-text bg-white"><i class="bi bi-search"></i></span><input class="form-control" type="search" placeholder="Hogar o voluntario" aria-label="Buscar" [ngModel]="q()" (ngModelChange)="q.set($event); buscarConRetardo()" /></div></div>
        <div class="col-6 col-md-3"><select class="form-select" aria-label="Estado" [ngModel]="estado()" (ngModelChange)="estado.set($event); refiltrar()"><option value="">Todos los estados</option><option>Programada</option><option>Entregada</option><option>No realizada</option><option>Anulada</option></select></div>
        <div class="col-6 col-md-3"><select class="form-select" aria-label="Campaña" [ngModel]="campana()" (ngModelChange)="campana.set($event); refiltrar()"><option value="">Todas las campañas</option>@for (c of campanas(); track c.id_campana) { <option [value]="c.id_campana">{{ c.nombre }}</option> }</select></div>
        <div class="col-6 col-md-2"><select class="form-select" aria-label="Sector" [ngModel]="sector()" (ngModelChange)="sector.set($event); refiltrar()"><option value="">Todo sector</option>@for (s of sectores(); track s.id_sector) { <option [value]="s.id_sector">{{ s.nombre }}</option> }</select></div>
        <div class="col-6 col-md-3"><input class="form-control" type="date" aria-label="Desde" title="Desde" [ngModel]="desde()" (ngModelChange)="desde.set($event); refiltrar()" /></div>
        <div class="col-6 col-md-3"><input class="form-control" type="date" aria-label="Hasta" title="Hasta" [ngModel]="hasta()" (ngModelChange)="hasta.set($event); refiltrar()" /></div>
      </div></div>
      @if (cargando() && !items().length) { <rs-carga [n]="7" /> }
      @else if (error(); as e) { <div class="alert alert-danger m-3" role="alert">{{ e }}</div> }
      @else if (!items().length) { <rs-vacio icono="box-seam" titulo="No hay entregas con esos filtros" /> }
      @else {
        <div class="table-responsive"><table class="table rs-table">
          <thead><tr><th>Fecha</th><th>Hogar</th><th>Campaña</th><th>Voluntario</th><th class="text-end">Cant.</th><th>Estado</th><th></th></tr></thead>
          <tbody>@for (e of items(); track e.id_entrega) {
            <tr>
              <td class="text-nowrap">{{ e.fecha | fecha }}</td>
              <td><div class="fw-semibold">{{ e.hogar }}</div><div class="small text-secondary">{{ e.sector }}</div></td>
              <td>{{ e.campana }}@if (e.detalle) { <div class="small text-secondary">{{ e.detalle }}</div> }</td>
              <td>{{ e.voluntario }}</td><td class="text-end tabular">{{ e.cantidad }}</td>
              <td><rs-estado [valor]="e.estado" />@if (e.motivo_estado) { <div class="small text-secondary" style="max-width:15rem">{{ e.motivo_estado }}</div> }</td>
              <td class="text-end text-nowrap">
                @if (e.estado === 'Entregada') { <button class="btn btn-sm btn-outline-secondary me-1" type="button" (click)="constancia.set(e)" title="Constancia"><i class="bi bi-file-earmark-text"></i></button> }
                @if (auth.tiene('entregas:gestionar')) {
                  @if (e.estado === 'Programada') {
                    <button class="btn btn-sm btn-success me-1" type="button" (click)="entregada(e)"><i class="bi bi-check-lg me-1"></i>Entregada</button>
                    <button class="btn btn-sm btn-outline-warning me-1" type="button" (click)="cambiar(e, 'No realizada')">No se realizó</button>
                  }
                  @if (e.estado === 'Programada' || e.estado === 'Entregada') { <button class="btn btn-sm btn-outline-danger" type="button" (click)="cambiar(e, 'Anulada')">Anular</button> }
                }
              </td></tr> }</tbody></table></div>
        <rs-paginacion [pagina]="pagina()" [paginas]="paginas()" [total]="total()" [tamano]="tamano" (cambia)="irA($event)" />
      }
    </div>
    @if (formulario()) { <rs-entrega-form (cerrar)="formulario.set(false)" (guardado)="formulario.set(false); cargar()" /> }
    @if (constancia(); as c) { <rs-constancia [entrega]="c" (cerrar)="constancia.set(null)" /> }`,
})
export class EntregasPage extends ListaBase<Entrega> {
  protected readonly auth = inject(AuthService);
  private readonly api = inject(EntregaService);
  private readonly confirm = inject(ConfirmService);
  private readonly toast = inject(ToastService);
  protected readonly q = signal(''); protected readonly estado = signal(''); protected readonly sector = signal(''); protected readonly desde = signal(''); protected readonly hasta = signal('');
  protected readonly campana = signal(inject(ActivatedRoute).snapshot.queryParamMap.get('id_campana') ?? '');
  protected readonly campanas = signal<Campana[]>([]); protected readonly sectores = signal<Sector[]>([]);
  protected readonly formulario = signal(false); protected readonly constancia = signal<Entrega | null>(null); protected readonly exportando = signal(false);
  constructor() {
    super();
    inject(CampanaService).listar({ tamano: 100 }).subscribe({ next: (r) => this.campanas.set(r.items), error: () => undefined });
    inject(CatalogoService).sectores().subscribe({ next: (s) => this.sectores.set(s), error: () => undefined });
    this.cargar();
  }
  private filtros() { return { q: this.q(), estado: this.estado(), id_campana: this.campana(), id_sector: this.sector(), desde: this.desde(), hasta: this.hasta() }; }
  protected override consultar(): Observable<Pagina<Entrega>> { return this.api.listar({ ...this.filtros(), pagina: this.pagina(), tamano: this.tamano }); }

  protected async entregada(e: Entrega): Promise<void> {
    const r = await this.confirm.preguntar({ titulo: 'Confirmar entrega', mensaje: `¿Se entregó la ayuda a ${e.hogar}?`, confirmar: 'Sí, se entregó' });
    if (r.ok) this.aplicar(e, 'Entregada', '');
  }
  protected async cambiar(e: Entrega, estado: 'No realizada' | 'Anulada'): Promise<void> {
    const r = await this.confirm.preguntar({ titulo: estado === 'Anulada' ? 'Anular entrega' : 'Entrega no realizada', mensaje: estado === 'Anulada' ? 'Quedará en el historial con el motivo. Si cubría una necesidad, ésta volverá a la cola de atención.' : 'Indique por qué no se pudo realizar.', confirmar: estado === 'Anulada' ? 'Anular' : 'Registrar', peligro: true, pedirMotivo: true });
    if (r.ok) this.aplicar(e, estado, r.motivo);
  }
  private aplicar(e: Entrega, estado: string, motivo: string): void {
    this.api.cambiarEstado(e.id_entrega, estado, motivo).subscribe({ next: () => { this.toast.ok('Entrega actualizada.'); this.cargar(); }, error: (er) => this.toast.error(toApiError(er).message) });
  }
  protected exportar(): void {
    this.exportando.set(true);
    this.api.exportar(this.filtros()).subscribe({
      next: (b) => { descargar(b, `entregas_${hoyISO()}.csv`); this.exportando.set(false); this.toast.ok('Exportación generada. Quedó registrada en la auditoría.'); },
      error: (er) => { this.exportando.set(false); this.toast.error(toApiError(er).message); },
    });
  }
}
