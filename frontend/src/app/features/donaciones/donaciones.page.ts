import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute } from '@angular/router';
import { Observable } from 'rxjs';
import { toApiError } from '../../core/models/api-error';
import { Campana, Donacion, MetodoPago, Pagina } from '../../core/models/api.models';
import { CampanaService, CatalogoService, DonacionService } from '../../core/services/api.services';
import { AuthService } from '../../core/services/auth.service';
import { ConfirmService } from '../../core/services/confirm.service';
import { ToastService } from '../../core/services/toast.service';
import { descargar } from '../../core/util/download';
import { FORMATOS, hoyISO } from '../../core/util/format';
import { ListaBase } from '../../core/util/lista-base';
import { Carga, Encabezado, Estado, Paginacion, Vacio } from '../../shared/ui';
import { DonacionForm } from './donacion-form';

@Component({
  selector: 'rs-donaciones',
  imports: [FormsModule, Encabezado, Estado, Carga, Vacio, Paginacion, DonacionForm, ...FORMATOS],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <rs-encabezado titulo="Donaciones" subtitulo="Una donación declarada no es una donación recibida: solo las confirmadas cuentan en los totales.">
      @if (auth.tiene('donaciones:exportar')) { <button class="btn btn-outline-secondary" type="button" [disabled]="exportando()" (click)="exportar()"><i class="bi bi-download me-1"></i>Exportar CSV</button> }
      @if (auth.tiene('donaciones:registrar')) { <button class="btn btn-primary" type="button" (click)="formulario.set(true)"><i class="bi bi-plus-lg me-1"></i>Registrar donación</button> }
    </rs-encabezado>

    <div class="card">
      <div class="card-body border-bottom"><div class="row g-2">
        <div class="col-md-4"><div class="input-group"><span class="input-group-text bg-white"><i class="bi bi-search"></i></span><input class="form-control" type="search" placeholder="Donante o n.º de operación" aria-label="Buscar" [ngModel]="q()" (ngModelChange)="q.set($event); buscarConRetardo()" /></div></div>
        <div class="col-6 col-md-2"><select class="form-select" aria-label="Estado" [ngModel]="estado()" (ngModelChange)="estado.set($event); refiltrar()"><option value="">Todos los estados</option><option>Pendiente</option><option>Confirmada</option><option>Rechazada</option><option>Anulada</option></select></div>
        <div class="col-6 col-md-3"><select class="form-select" aria-label="Campaña" [ngModel]="campana()" (ngModelChange)="campana.set($event); refiltrar()"><option value="">Todas las campañas</option>@for (c of campanas(); track c.id_campana) { <option [value]="c.id_campana">{{ c.nombre }}</option> }</select></div>
        <div class="col-6 col-md-3"><select class="form-select" aria-label="Método" [ngModel]="metodo()" (ngModelChange)="metodo.set($event); refiltrar()"><option value="">Todos los métodos</option>@for (m of metodos(); track m.id_metodo_pago) { <option [value]="m.id_metodo_pago">{{ m.nombre }}</option> }</select></div>
        <div class="col-6 col-md-3"><label class="visually-hidden" for="d-desde">Desde</label><input id="d-desde" class="form-control" type="date" [ngModel]="desde()" (ngModelChange)="desde.set($event); refiltrar()" title="Desde" /></div>
        <div class="col-6 col-md-3"><label class="visually-hidden" for="d-hasta">Hasta</label><input id="d-hasta" class="form-control" type="date" [ngModel]="hasta()" (ngModelChange)="hasta.set($event); refiltrar()" title="Hasta" /></div>
        <div class="col-12 col-md-2"><button class="btn btn-link px-0" type="button" (click)="limpiar()">Limpiar filtros</button></div>
      </div></div>

      @if (cargando() && !items().length) { <rs-carga [n]="7" /> }
      @else if (error(); as e) { <div class="alert alert-danger m-3" role="alert">{{ e }}</div> }
      @else if (!items().length) { <rs-vacio icono="cash-coin" titulo="No hay donaciones con esos filtros" /> }
      @else {
        <div class="table-responsive"><table class="table rs-table">
          <thead><tr><th>Fecha</th><th>Donante</th><th>Campaña</th><th>Método</th><th class="text-end">Monto</th><th>Estado</th><th></th></tr></thead>
          <tbody>@for (d of items(); track d.id_donacion) {
            <tr>
              <td class="text-nowrap">{{ d.fecha | fecha }}</td>
              <td><div class="fw-semibold">{{ d.donante }}</div><div class="small text-secondary">{{ d.donante_tipo }}</div></td>
              <td>{{ d.campana }}</td>
              <td>{{ d.metodo_pago }}@if (d.referencia) { <div class="small text-secondary">Op. {{ d.referencia }}</div> }</td>
              <td class="text-end tabular fw-semibold">{{ d.monto | moneda: d.moneda }}</td>
              <td><rs-estado [valor]="d.estado" />@if (d.motivo_estado) { <div class="small text-secondary mt-1" style="max-width:16rem">{{ d.motivo_estado }}</div> }@if (d.confirmado_por) { <div class="small text-secondary">por {{ d.confirmado_por }}</div> }</td>
              <td class="text-end text-nowrap">
                @if (auth.tiene('donaciones:verificar')) {
                  @if (d.estado === 'Pendiente') {
                    <button class="btn btn-sm btn-success me-1" type="button" (click)="confirmar(d)"><i class="bi bi-check-lg me-1"></i>Confirmar</button>
                    <button class="btn btn-sm btn-outline-danger me-1" type="button" (click)="cambiar(d, 'Rechazada')">Rechazar</button>
                  }
                  @if (d.estado === 'Pendiente' || d.estado === 'Confirmada') { <button class="btn btn-sm btn-outline-secondary" type="button" (click)="cambiar(d, 'Anulada')">Anular</button> }
                }
              </td></tr> }</tbody></table></div>
        <rs-paginacion [pagina]="pagina()" [paginas]="paginas()" [total]="total()" [tamano]="tamano" (cambia)="irA($event)" />
      }
    </div>
    @if (formulario()) { <rs-donacion-form (cerrar)="formulario.set(false)" (guardado)="formulario.set(false); cargar()" /> }`,
})
export class DonacionesPage extends ListaBase<Donacion> {
  protected readonly auth = inject(AuthService);
  private readonly api = inject(DonacionService);
  private readonly confirm = inject(ConfirmService);
  private readonly toast = inject(ToastService);
  protected readonly q = signal(''); protected readonly estado = signal(''); protected readonly metodo = signal('');
  protected readonly desde = signal(''); protected readonly hasta = signal('');
  protected readonly campana = signal(inject(ActivatedRoute).snapshot.queryParamMap.get('id_campana') ?? '');
  protected readonly campanas = signal<Campana[]>([]);
  protected readonly metodos = signal<MetodoPago[]>([]);
  protected readonly formulario = signal(false);
  protected readonly exportando = signal(false);

  constructor() {
    super();
    inject(CampanaService).listar({ tamano: 100 }).subscribe({ next: (r) => this.campanas.set(r.items), error: () => undefined });
    inject(CatalogoService).metodosPago().subscribe({ next: (m) => this.metodos.set(m), error: () => undefined });
    this.cargar();
  }
  private filtros() { return { q: this.q(), estado: this.estado(), id_campana: this.campana(), id_metodo_pago: this.metodo(), desde: this.desde(), hasta: this.hasta() }; }
  protected override consultar(): Observable<Pagina<Donacion>> { return this.api.listar({ ...this.filtros(), pagina: this.pagina(), tamano: this.tamano }); }
  protected limpiar(): void { this.q.set(''); this.estado.set(''); this.metodo.set(''); this.campana.set(''); this.desde.set(''); this.hasta.set(''); this.refiltrar(); }

  protected async confirmar(d: Donacion): Promise<void> {
    const r = await this.confirm.preguntar({ titulo: 'Confirmar donación', mensaje: `¿Verificó que ${d.donante} pagó realmente ${new Intl.NumberFormat('es-PE', { style: 'currency', currency: d.moneda }).format(d.monto)}? Desde ahora contará en los totales.`, confirmar: 'Sí, confirmar' });
    if (r.ok) this.aplicar(d, 'Confirmada', '');
  }
  protected async cambiar(d: Donacion, estado: 'Rechazada' | 'Anulada'): Promise<void> {
    const r = await this.confirm.preguntar({ titulo: estado === 'Rechazada' ? 'Rechazar donación' : 'Anular donación', mensaje: 'Quedará en el historial con el motivo; no se borra.', confirmar: estado === 'Rechazada' ? 'Rechazar' : 'Anular', peligro: true, pedirMotivo: true });
    if (r.ok) this.aplicar(d, estado, r.motivo);
  }
  private aplicar(d: Donacion, estado: string, motivo: string): void {
    this.api.cambiarEstado(d.id_donacion, estado, motivo).subscribe({ next: () => { this.toast.ok(`Donación ${estado.toLowerCase()}.`); this.cargar(); }, error: (e) => this.toast.error(toApiError(e).message) });
  }
  protected exportar(): void {
    this.exportando.set(true);
    this.api.exportar(this.filtros()).subscribe({
      next: (b) => { descargar(b, `donaciones_${hoyISO()}.csv`); this.exportando.set(false); this.toast.ok('Exportación generada. Quedó registrada en la auditoría.'); },
      error: (e) => { this.exportando.set(false); this.toast.error(toApiError(e).message); },
    });
  }
}
