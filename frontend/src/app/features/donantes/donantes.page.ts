import { ChangeDetectionStrategy, Component, inject, OnInit, signal, input, output } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { form, FormField, maxLength, minLength, required, validate } from '@angular/forms/signals';
import { Observable, firstValueFrom } from 'rxjs';
import { toApiError } from '../../core/models/api-error';
import { Donacion, Donante, Pagina } from '../../core/models/api.models';
import { DonacionService, DonanteService } from '../../core/services/api.services';
import { AuthService } from '../../core/services/auth.service';
import { ConfirmService } from '../../core/services/confirm.service';
import { ToastService } from '../../core/services/toast.service';
import { FORMATOS } from '../../core/util/format';
import { enviar } from '../../core/util/form-utils';
import { ListaBase } from '../../core/util/lista-base';
import { Campo, Carga, Encabezado, Estado, Modal, Paginacion, Vacio } from '../../shared/ui';

@Component({
  selector: 'rs-donante-form',
  imports: [FormField, Campo, Modal],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <rs-modal [titulo]="donante() ? 'Editar donante' : 'Nuevo donante'" (cerrar)="cerrar.emit()">
      @if (error(); as e) { <div class="alert alert-danger py-2 small" role="alert">{{ e }}</div> }
      <form id="f-donante" (submit)="guardar($event)" novalidate>
        <rs-campo etiqueta="Nombre o razón social" requerido [campo]="f.nombre"><input class="form-control" [formField]="f.nombre" /></rs-campo>
        <rs-campo etiqueta="Tipo" requerido [campo]="f.tipo"><select class="form-select" [formField]="f.tipo"><option value="Persona">Persona</option><option value="Empresa">Empresa</option></select></rs-campo>
        <rs-campo etiqueta="Correo electrónico" requerido [campo]="f.correo" ayuda="Se usa para enviar la constancia de donación."><input class="form-control" type="email" autocomplete="off" [formField]="f.correo" /></rs-campo>
      </form>
      <div pie class="modal-footer border-0"><button type="button" class="btn btn-light" (click)="cerrar.emit()">Cancelar</button>
        <button type="submit" form="f-donante" class="btn btn-primary" [disabled]="enviando()">{{ enviando() ? 'Guardando…' : 'Guardar' }}</button></div>
    </rs-modal>`,
})
export class DonanteForm implements OnInit {
  readonly donante = input<Donante | null>(null);
  readonly guardado = output<Donante>();
  readonly cerrar = output<void>();
  private readonly api = inject(DonanteService);
  private readonly toast = inject(ToastService);
  private readonly confirm = inject(ConfirmService);
  protected readonly modelo = signal({ nombre: '', tipo: 'Persona', correo: '' });
  protected readonly f = form(this.modelo, (p) => {
    maxLength(p.nombre, 100, { message: 'Máximo 100 caracteres.' });
    maxLength(p.correo, 100, { message: 'Máximo 100 caracteres.' });
    required(p.nombre, { message: 'Escriba el nombre.' });
    minLength(p.nombre, 2, { message: 'Use al menos 2 caracteres.' });
    required(p.correo, { message: 'Escriba el correo.' });
    validate(p.correo, ({ value }) => (!value() || /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(value()) ? undefined : { kind: 'correo', message: 'Ingrese un correo válido (nombre@dominio.pe).' }));
  });
  protected readonly enviando = signal(false);
  protected readonly error = signal<string | null>(null);
  ngOnInit(): void { const d = this.donante(); if (d) this.modelo.set({ nombre: d.nombre, tipo: d.tipo, correo: d.correo }); }
  protected async guardar(ev: Event): Promise<void> {
    ev.preventDefault();
    await enviar(this.f, { enviando: this.enviando, error: this.error }, async (confirmado) => {
      const d = this.donante();
      const r = await firstValueFrom(this.api.guardar(d?.id_donante ?? null, { ...this.modelo(), confirmar_duplicado: confirmado }));
      this.toast.ok(d ? 'Donante actualizado.' : 'Donante registrado.');
      this.guardado.emit(r);
    }, this.confirm);
  }
}

@Component({
  selector: 'rs-donante-historial',
  imports: [Modal, Estado, Carga, Vacio, ...FORMATOS],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <rs-modal [titulo]="'Historial · ' + donante().nombre" tamano="lg" (cerrar)="cerrar.emit()">
      <div class="row g-3 mb-3 text-center">
        <div class="col-4"><div class="fs-4 fw-bold tabular text-dar">{{ donante().total_donado | moneda }}</div><div class="small text-secondary">total verificado</div></div>
        <div class="col-4"><div class="fs-4 fw-bold tabular">{{ donante().donaciones_confirmadas }}</div><div class="small text-secondary">donaciones</div></div>
        <div class="col-4"><div class="fs-4 fw-bold tabular">{{ donante().campanas_apoyadas }}</div><div class="small text-secondary">campañas apoyadas</div></div>
      </div>
      @if (!items()) { <rs-carga [n]="4" /> } @else if (!items()!.length) { <rs-vacio icono="cash-coin" titulo="Sin donaciones registradas" /> } @else {
        <div class="table-responsive"><table class="table rs-table"><thead><tr><th>Fecha</th><th>Campaña</th><th>Método</th><th class="text-end">Monto</th><th>Estado</th></tr></thead><tbody>
          @for (d of items(); track d.id_donacion) { <tr><td>{{ d.fecha | fecha }}</td><td>{{ d.campana }}</td><td>{{ d.metodo_pago }}</td><td class="text-end tabular">{{ d.monto | moneda: d.moneda }}</td><td><rs-estado [valor]="d.estado" /></td></tr> }
        </tbody></table></div>
      }
    </rs-modal>`,
})
export class DonanteHistorial implements OnInit {
  readonly donante = input.required<Donante>();
  readonly cerrar = output<void>();
  private readonly api = inject(DonacionService);
  private readonly toast = inject(ToastService);
  protected readonly items = signal<Donacion[] | null>(null);
  ngOnInit(): void {
    this.api.listar({ id_donante: this.donante().id_donante, tamano: 50 }).subscribe({ next: (r) => this.items.set(r.items), error: (e) => { this.items.set([]); this.toast.error(toApiError(e).message); } });
  }
}

@Component({
  selector: 'rs-donantes',
  imports: [FormsModule, Encabezado, Estado, Carga, Vacio, Paginacion, DonanteForm, DonanteHistorial, ...FORMATOS],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <rs-encabezado titulo="Donantes" subtitulo="Personas y empresas que aportan a las campañas.">
      @if (auth.tiene('donantes:escribir')) { <button class="btn btn-primary" type="button" (click)="editando.set(null); formulario.set(true)"><i class="bi bi-plus-lg me-1"></i>Nuevo donante</button> }
    </rs-encabezado>
    <div class="card">
      <div class="card-body border-bottom"><div class="row g-2">
        <div class="col-md-6"><div class="input-group"><span class="input-group-text bg-white"><i class="bi bi-search"></i></span><input class="form-control" type="search" placeholder="Buscar por nombre o correo" aria-label="Buscar donantes" [ngModel]="q()" (ngModelChange)="q.set($event); buscarConRetardo()" /></div></div>
        <div class="col-6 col-md-3"><select class="form-select" aria-label="Tipo" [ngModel]="tipo()" (ngModelChange)="tipo.set($event); refiltrar()"><option value="">Personas y empresas</option><option value="Persona">Personas</option><option value="Empresa">Empresas</option></select></div>
        <div class="col-6 col-md-3"><select class="form-select" aria-label="Estado" [ngModel]="activo()" (ngModelChange)="activo.set($event); refiltrar()"><option value="">Activos e inactivos</option><option value="true">Solo activos</option><option value="false">Solo inactivos</option></select></div>
      </div></div>
      @if (cargando() && !items().length) { <rs-carga [n]="6" /> }
      @else if (error(); as e) { <div class="alert alert-danger m-3" role="alert">{{ e }}</div> }
      @else if (!items().length) { <rs-vacio icono="people" titulo="No se encontraron donantes" /> }
      @else {
        <div class="table-responsive"><table class="table rs-table">
          <thead><tr><th>Donante</th><th>Tipo</th><th class="text-end">Total verificado</th><th class="text-end">Donaciones</th><th class="text-end">Campañas</th><th>Última</th><th></th></tr></thead>
          <tbody>@for (d of items(); track d.id_donante) {
            <tr [class.text-secondary]="!d.activo">
              <td><div class="fw-semibold">{{ d.nombre }}@if (!d.activo) { <span class="badge text-bg-secondary ms-2">Inactivo</span> }</div><div class="small text-secondary">{{ d.correo }}</div></td>
              <td><rs-estado [valor]="d.tipo" /></td>
              <td class="text-end tabular fw-semibold">{{ d.total_donado | moneda }}@if (d.donaciones_pendientes) { <div class="small text-warning-emphasis fw-normal">{{ d.donaciones_pendientes }} por verificar</div> }</td>
              <td class="text-end tabular">{{ d.donaciones_confirmadas }}</td><td class="text-end tabular">{{ d.campanas_apoyadas }}</td><td class="small text-nowrap">{{ d.ultima_donacion | fecha }}</td>
              <td class="text-end text-nowrap">
                @if (auth.tiene('donaciones:leer')) { <button class="btn btn-sm btn-outline-secondary me-1" type="button" (click)="historial.set(d)" title="Ver historial"><i class="bi bi-clock-history"></i></button> }
                @if (auth.tiene('donantes:escribir')) {
                  <button class="btn btn-sm btn-outline-secondary me-1" type="button" (click)="editando.set(d); formulario.set(true)" title="Editar"><i class="bi bi-pencil"></i></button>
                  <button class="btn btn-sm" [class]="d.activo ? 'btn-outline-danger' : 'btn-outline-success'" type="button" (click)="alternar(d)" [title]="d.activo ? 'Desactivar' : 'Reactivar'"><i class="bi" [class]="d.activo ? 'bi-person-dash' : 'bi-person-check'"></i></button>
                }
              </td></tr> }</tbody></table></div>
        <rs-paginacion [pagina]="pagina()" [paginas]="paginas()" [total]="total()" [tamano]="tamano" (cambia)="irA($event)" />
      }
    </div>
    @if (formulario()) { <rs-donante-form [donante]="editando()" (cerrar)="formulario.set(false)" (guardado)="formulario.set(false); cargar()" /> }
    @if (historial(); as h) { <rs-donante-historial [donante]="h" (cerrar)="historial.set(null)" /> }`,
})
export class DonantesPage extends ListaBase<Donante> {
  protected readonly auth = inject(AuthService);
  private readonly api = inject(DonanteService);
  private readonly confirm = inject(ConfirmService);
  private readonly toast = inject(ToastService);
  protected readonly q = signal(''); protected readonly tipo = signal(''); protected readonly activo = signal('');
  protected readonly formulario = signal(false); protected readonly editando = signal<Donante | null>(null); protected readonly historial = signal<Donante | null>(null);
  constructor() { super(); this.cargar(); }
  protected override consultar(): Observable<Pagina<Donante>> { return this.api.listar({ q: this.q(), tipo: this.tipo(), activo: this.activo(), pagina: this.pagina(), tamano: this.tamano }); }
  protected async alternar(d: Donante): Promise<void> {
    const r = await this.confirm.preguntar({ titulo: d.activo ? 'Desactivar donante' : 'Reactivar donante', mensaje: d.activo ? `«${d.nombre}» dejará de aparecer al registrar donaciones. Su historial se conserva.` : `«${d.nombre}» podrá volver a registrar donaciones.`, confirmar: d.activo ? 'Desactivar' : 'Reactivar', peligro: d.activo });
    if (!r.ok) return;
    this.api.cambiarEstado(d.id_donante, !d.activo).subscribe({ next: () => { this.toast.ok('Estado actualizado.'); this.cargar(); }, error: (e) => this.toast.error(toApiError(e).message) });
  }
}
