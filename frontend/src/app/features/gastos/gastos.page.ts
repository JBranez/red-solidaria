import { ChangeDetectionStrategy, Component, inject, OnInit, output, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { form, FormField, maxLength, min, minLength, required, validate } from '@angular/forms/signals';
import { ActivatedRoute } from '@angular/router';
import { firstValueFrom, Observable } from 'rxjs';
import { toApiError } from '../../core/models/api-error';
import { Campana, Gasto, Pagina } from '../../core/models/api.models';
import { CampanaService, GastoService } from '../../core/services/api.services';
import { AuthService } from '../../core/services/auth.service';
import { ConfirmService } from '../../core/services/confirm.service';
import { ToastService } from '../../core/services/toast.service';
import { FORMATOS, hoyISO } from '../../core/util/format';
import { aTexto, enviar } from '../../core/util/form-utils';
import { ListaBase } from '../../core/util/lista-base';
import { TIPOS_GASTO } from '../../core/util/labels';
import { Campo, Carga, Encabezado, Estado, Modal, Paginacion, Vacio } from '../../shared/ui';

@Component({
  selector: 'rs-gasto-form',
  imports: [FormField, Campo, Modal],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <rs-modal titulo="Registrar gasto" (cerrar)="cerrar.emit()">
      @if (error(); as e) { <div class="alert alert-danger py-2 small" role="alert">{{ e }}</div> }
      <form id="f-gasto" (submit)="guardar($event)" novalidate>
        <rs-campo etiqueta="Campaña" requerido [campo]="f.id_campana"><select class="form-select" [formField]="f.id_campana"><option value="">Seleccione…</option>@for (c of campanas(); track c.id_campana) { <option [value]="c.id_campana">{{ c.nombre }} ({{ c.estado }})</option> }</select></rs-campo>
        <rs-campo etiqueta="Concepto" requerido [campo]="f.concepto"><input class="form-control" [formField]="f.concepto" /></rs-campo>
        <div class="row">
          <div class="col-6"><rs-campo etiqueta="Tipo" requerido [campo]="f.tipo"><select class="form-select" [formField]="f.tipo">@for (t of tipos; track t.v) { <option [value]="t.v">{{ t.t }}</option> }</select></rs-campo></div>
          <div class="col-6"><rs-campo etiqueta="Monto" requerido [campo]="f.monto"><input class="form-control" type="number" step="0.01" inputmode="decimal" [formField]="f.monto" /></rs-campo></div>
        </div>
        <div class="row">
          <div class="col-6"><rs-campo etiqueta="Fecha" requerido [campo]="f.fecha"><input class="form-control" type="date" [formField]="f.fecha" /></rs-campo></div>
          <div class="col-6"><rs-campo etiqueta="N.º de comprobante" ayuda="Boleta o factura" [campo]="f.comprobante"><input class="form-control" [formField]="f.comprobante" /></rs-campo></div>
        </div>
        <rs-campo etiqueta="Proveedor" [campo]="f.proveedor"><input class="form-control" [formField]="f.proveedor" /></rs-campo>
        <p class="small text-secondary mb-0"><i class="bi bi-info-circle me-1"></i>Un gasto no cuenta hasta que <strong>otra persona</strong> lo apruebe. Así nadie aprueba su propio gasto.</p>
      </form>
      <div pie class="modal-footer border-0"><button type="button" class="btn btn-light" (click)="cerrar.emit()">Cancelar</button><button type="submit" form="f-gasto" class="btn btn-primary" [disabled]="enviando()">{{ enviando() ? 'Guardando…' : 'Registrar' }}</button></div>
    </rs-modal>`,
})
export class GastoForm implements OnInit {
  readonly guardado = output<Gasto>();
  readonly cerrar = output<void>();
  private readonly api = inject(GastoService);
  private readonly campanaApi = inject(CampanaService);
  private readonly toast = inject(ToastService);
  protected readonly tipos = TIPOS_GASTO;
  protected readonly campanas = signal<Campana[]>([]);
  protected readonly modelo = signal({ id_campana: '', concepto: '', tipo: 'Bienes', monto: null as number | null, fecha: hoyISO(), comprobante: '', proveedor: '' });
  protected readonly f = form(this.modelo, (p) => {
    maxLength(p.concepto, 150, { message: 'Máximo 150 caracteres.' });
    maxLength(p.comprobante, 60, { message: 'Máximo 60 caracteres.' });
    maxLength(p.proveedor, 100, { message: 'Máximo 100 caracteres.' });
    required(p.id_campana, { message: 'Seleccione la campaña.' });
    required(p.concepto, { message: 'Describa el gasto.' });
    minLength(p.concepto, 3, { message: 'Use al menos 3 caracteres.' });
    required(p.monto, { message: 'Indique el monto.' });
    min(p.monto, 0.01, { message: 'El monto debe ser mayor que cero.' });
    required(p.fecha, { message: 'Indique la fecha.' });
    validate(p.fecha, ({ value }) => (value() > hoyISO() ? { kind: 'futura', message: 'La fecha no puede ser futura.' } : undefined));
  });
  protected readonly enviando = signal(false);
  protected readonly error = signal<string | null>(null);
  ngOnInit(): void { this.campanaApi.listar({ tamano: 100 }).subscribe({ next: (r) => this.campanas.set(r.items.filter((c) => ['Activa', 'Pausada', 'Finalizada'].includes(c.estado))), error: (e) => this.error.set(toApiError(e).message) }); }
  protected async guardar(ev: Event): Promise<void> {
    ev.preventDefault();
    await enviar(this.f, { enviando: this.enviando, error: this.error }, async () => {
      const m = this.modelo();
      const r = await firstValueFrom(this.api.registrar({ id_campana: Number(m.id_campana), concepto: m.concepto, tipo: m.tipo, monto: m.monto, fecha: m.fecha, comprobante: aTexto(m.comprobante), proveedor: aTexto(m.proveedor) }));
      this.toast.ok('Gasto registrado. Falta su aprobación.');
      this.guardado.emit(r);
    });
  }
}

@Component({
  selector: 'rs-gastos',
  imports: [FormsModule, Encabezado, Estado, Carga, Vacio, Paginacion, GastoForm, ...FORMATOS],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <rs-encabezado titulo="Gastos" subtitulo="Lo recaudado y lo gastado se registran por separado. Solo el gasto aprobado resta del saldo.">
      @if (auth.tiene('gastos:registrar')) { <button class="btn btn-primary" type="button" (click)="formulario.set(true)"><i class="bi bi-plus-lg me-1"></i>Registrar gasto</button> }
    </rs-encabezado>
    <div class="card">
      <div class="card-body border-bottom"><div class="row g-2">
        <div class="col-md-4"><div class="input-group"><span class="input-group-text bg-white"><i class="bi bi-search"></i></span><input class="form-control" type="search" placeholder="Concepto, proveedor o comprobante" aria-label="Buscar" [ngModel]="q()" (ngModelChange)="q.set($event); buscarConRetardo()" /></div></div>
        <div class="col-6 col-md-3"><select class="form-select" aria-label="Campaña" [ngModel]="campana()" (ngModelChange)="campana.set($event); refiltrar()"><option value="">Todas las campañas</option>@for (c of campanas(); track c.id_campana) { <option [value]="c.id_campana">{{ c.nombre }}</option> }</select></div>
        <div class="col-6 col-md-2"><select class="form-select" aria-label="Estado" [ngModel]="estado()" (ngModelChange)="estado.set($event); refiltrar()"><option value="">Todos</option><option value="Registrado">Por aprobar</option><option>Aprobado</option><option>Anulado</option></select></div>
        <div class="col-6 col-md-3"><select class="form-select" aria-label="Tipo" [ngModel]="tipo()" (ngModelChange)="tipo.set($event); refiltrar()"><option value="">Todos los tipos</option>@for (t of tipos; track t.v) { <option [value]="t.v">{{ t.t }}</option> }</select></div>
      </div></div>
      @if (cargando() && !items().length) { <rs-carga [n]="6" /> }
      @else if (error(); as e) { <div class="alert alert-danger m-3" role="alert">{{ e }}</div> }
      @else if (!items().length) { <rs-vacio icono="receipt" titulo="No hay gastos con esos filtros" /> }
      @else {
        <div class="table-responsive"><table class="table rs-table">
          <thead><tr><th>Fecha</th><th>Concepto</th><th>Campaña</th><th>Tipo</th><th class="text-end">Monto</th><th>Estado</th><th></th></tr></thead>
          <tbody>@for (g of items(); track g.id_gasto) {
            <tr>
              <td class="text-nowrap">{{ g.fecha | fecha }}</td>
              <td><div class="fw-semibold">{{ g.concepto }}</div><div class="small text-secondary">{{ g.proveedor || 'Sin proveedor' }}@if (g.comprobante) { · {{ g.comprobante }} }</div></td>
              <td>{{ g.campana }}</td><td>{{ g.tipo }}</td>
              <td class="text-end tabular fw-semibold">{{ g.monto | moneda: g.moneda }}</td>
              <td><rs-estado [valor]="g.estado" /><div class="small text-secondary mt-1">Registró: {{ g.registrado_por || '—' }}@if (g.aprobado_por) { <br>Aprobó: {{ g.aprobado_por }} }</div>@if (g.motivo_estado) { <div class="small text-secondary">{{ g.motivo_estado }}</div> }</td>
              <td class="text-end text-nowrap">
                @if (auth.tiene('gastos:aprobar')) {
                  @if (g.estado === 'Registrado') {
                    <button class="btn btn-sm btn-success me-1" type="button" [disabled]="g.id_usuario_registra === auth.usuario()?.id_usuario" [title]="g.id_usuario_registra === auth.usuario()?.id_usuario ? 'Lo registró usted: debe aprobarlo otra persona' : 'Aprobar'" (click)="aprobar(g)"><i class="bi bi-check-lg me-1"></i>Aprobar</button>
                  }
                  @if (g.estado !== 'Anulado') { <button class="btn btn-sm btn-outline-danger" type="button" (click)="anular(g)">Anular</button> }
                }
              </td></tr> }</tbody></table></div>
        <rs-paginacion [pagina]="pagina()" [paginas]="paginas()" [total]="total()" [tamano]="tamano" (cambia)="irA($event)" />
      }
    </div>
    @if (formulario()) { <rs-gasto-form (cerrar)="formulario.set(false)" (guardado)="formulario.set(false); cargar()" /> }`,
})
export class GastosPage extends ListaBase<Gasto> {
  protected readonly auth = inject(AuthService);
  private readonly api = inject(GastoService);
  private readonly confirm = inject(ConfirmService);
  private readonly toast = inject(ToastService);
  protected readonly tipos = TIPOS_GASTO;
  protected readonly q = signal(''); protected readonly estado = signal(''); protected readonly tipo = signal('');
  protected readonly campana = signal(inject(ActivatedRoute).snapshot.queryParamMap.get('id_campana') ?? '');
  protected readonly campanas = signal<Campana[]>([]);
  protected readonly formulario = signal(false);
  constructor() {
    super();
    inject(CampanaService).listar({ tamano: 100 }).subscribe({ next: (r) => this.campanas.set(r.items), error: () => undefined });
    this.cargar();
  }
  protected override consultar(): Observable<Pagina<Gasto>> { return this.api.listar({ q: this.q(), id_campana: this.campana(), estado: this.estado(), tipo: this.tipo(), pagina: this.pagina(), tamano: this.tamano }); }
  protected async aprobar(g: Gasto): Promise<void> {
    const r = await this.confirm.preguntar({ titulo: 'Aprobar gasto', mensaje: `«${g.concepto}» por ${new Intl.NumberFormat('es-PE', { style: 'currency', currency: g.moneda }).format(g.monto)}. Se descontará del saldo de «${g.campana}».`, confirmar: 'Aprobar' });
    if (r.ok) this.aplicar(g, 'Aprobado', '');
  }
  protected async anular(g: Gasto): Promise<void> {
    const r = await this.confirm.preguntar({ titulo: 'Anular gasto', mensaje: 'Quedará en el historial con el motivo.', confirmar: 'Anular', peligro: true, pedirMotivo: true });
    if (r.ok) this.aplicar(g, 'Anulado', r.motivo);
  }
  private aplicar(g: Gasto, estado: string, motivo: string): void {
    this.api.cambiarEstado(g.id_gasto, estado, motivo).subscribe({ next: () => { this.toast.ok(`Gasto ${estado.toLowerCase()}.`); this.cargar(); }, error: (e) => this.toast.error(toApiError(e).message) });
  }
}
