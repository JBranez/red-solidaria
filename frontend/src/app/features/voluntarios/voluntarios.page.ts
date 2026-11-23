import { ChangeDetectionStrategy, Component, inject, input, OnInit, output, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { form, FormField, maxLength, minLength, required, validate } from '@angular/forms/signals';
import { firstValueFrom, Observable } from 'rxjs';
import { toApiError } from '../../core/models/api-error';
import { Pagina, Voluntario } from '../../core/models/api.models';
import { VoluntarioService } from '../../core/services/api.services';
import { AuthService } from '../../core/services/auth.service';
import { ConfirmService } from '../../core/services/confirm.service';
import { ToastService } from '../../core/services/toast.service';
import { FORMATOS, hoyISO } from '../../core/util/format';
import { enviar } from '../../core/util/form-utils';
import { ListaBase } from '../../core/util/lista-base';
import { Campo, Carga, Encabezado, Modal, Paginacion, Vacio } from '../../shared/ui';

@Component({
  selector: 'rs-voluntario-form',
  imports: [FormField, Campo, Modal],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <rs-modal [titulo]="voluntario() ? 'Editar voluntario' : 'Nuevo voluntario'" (cerrar)="cerrar.emit()">
      @if (error(); as e) { <div class="alert alert-danger py-2 small" role="alert">{{ e }}</div> }
      <form id="f-vol" (submit)="guardar($event)" novalidate>
        <div class="row">
          <div class="col-6"><rs-campo etiqueta="Nombres" requerido [campo]="f.nombres"><input class="form-control" [formField]="f.nombres" /></rs-campo></div>
          <div class="col-6"><rs-campo etiqueta="Apellidos" requerido [campo]="f.apellidos"><input class="form-control" [formField]="f.apellidos" /></rs-campo></div>
        </div>
        <rs-campo etiqueta="Correo electrónico" requerido [campo]="f.correo"><input class="form-control" type="email" autocomplete="off" [formField]="f.correo" /></rs-campo>
        <rs-campo etiqueta="Fecha de ingreso" requerido [campo]="f.fecha_ingreso"><input class="form-control" type="date" [formField]="f.fecha_ingreso" /></rs-campo>
      </form>
      <div pie class="modal-footer border-0"><button type="button" class="btn btn-light" (click)="cerrar.emit()">Cancelar</button><button type="submit" form="f-vol" class="btn btn-primary" [disabled]="enviando()">{{ enviando() ? 'Guardando…' : 'Guardar' }}</button></div>
    </rs-modal>`,
})
export class VoluntarioForm implements OnInit {
  readonly voluntario = input<Voluntario | null>(null);
  readonly guardado = output<Voluntario>();
  readonly cerrar = output<void>();
  private readonly api = inject(VoluntarioService);
  private readonly toast = inject(ToastService);
  protected readonly modelo = signal({ nombres: '', apellidos: '', correo: '', fecha_ingreso: hoyISO() });
  protected readonly f = form(this.modelo, (p) => {
    maxLength(p.nombres, 60, { message: 'Máximo 60 caracteres.' });
    maxLength(p.apellidos, 60, { message: 'Máximo 60 caracteres.' });
    maxLength(p.correo, 100, { message: 'Máximo 100 caracteres.' });
    required(p.nombres, { message: 'Escriba los nombres.' }); minLength(p.nombres, 2, { message: 'Use al menos 2 caracteres.' });
    required(p.apellidos, { message: 'Escriba los apellidos.' }); minLength(p.apellidos, 2, { message: 'Use al menos 2 caracteres.' });
    required(p.correo, { message: 'Escriba el correo.' });
    validate(p.correo, ({ value }) => (!value() || /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(value()) ? undefined : { kind: 'correo', message: 'Ingrese un correo válido.' }));
    required(p.fecha_ingreso, { message: 'Indique la fecha de ingreso.' });
    validate(p.fecha_ingreso, ({ value }) => (value() > hoyISO() ? { kind: 'futura', message: 'No puede ser una fecha futura.' } : undefined));
  });
  protected readonly enviando = signal(false);
  protected readonly error = signal<string | null>(null);
  ngOnInit(): void { const v = this.voluntario(); if (v) this.modelo.set({ nombres: v.nombres, apellidos: v.apellidos, correo: v.correo, fecha_ingreso: v.fecha_ingreso }); }
  protected async guardar(ev: Event): Promise<void> {
    ev.preventDefault();
    await enviar(this.f, { enviando: this.enviando, error: this.error }, async () => {
      const v = this.voluntario();
      const r = await firstValueFrom(this.api.guardar(v?.id_voluntario ?? null, this.modelo()));
      this.toast.ok(v ? 'Voluntario actualizado.' : 'Voluntario registrado.');
      this.guardado.emit(r);
    });
  }
}

@Component({
  selector: 'rs-voluntarios',
  imports: [FormsModule, Encabezado, Carga, Vacio, Paginacion, VoluntarioForm, ...FORMATOS],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <rs-encabezado titulo="Voluntarios" subtitulo="Quienes llevan la ayuda hasta los hogares.">
      @if (auth.tiene('voluntarios:escribir')) { <button class="btn btn-primary" type="button" (click)="editando.set(null); formulario.set(true)"><i class="bi bi-plus-lg me-1"></i>Nuevo voluntario</button> }
    </rs-encabezado>
    <div class="card">
      <div class="card-body border-bottom"><div class="row g-2">
        <div class="col-md-7"><div class="input-group"><span class="input-group-text bg-white"><i class="bi bi-search"></i></span><input class="form-control" type="search" placeholder="Buscar por nombre o correo" aria-label="Buscar voluntarios" [ngModel]="q()" (ngModelChange)="q.set($event); buscarConRetardo()" /></div></div>
        <div class="col-md-5"><select class="form-select" aria-label="Estado" [ngModel]="activo()" (ngModelChange)="activo.set($event); refiltrar()"><option value="true">Voluntarios activos</option><option value="false">Voluntarios inactivos</option><option value="">Todos</option></select></div>
      </div></div>
      @if (cargando() && !items().length) { <rs-carga [n]="6" /> }
      @else if (error(); as e) { <div class="alert alert-danger m-3" role="alert">{{ e }}</div> }
      @else if (!items().length) { <rs-vacio icono="person-badge" titulo="No se encontraron voluntarios" /> }
      @else {
        <div class="table-responsive"><table class="table rs-table">
          <thead><tr><th>Voluntario</th><th>Ingreso</th><th class="text-end">Entregas</th><th class="text-end">Unidades</th><th class="text-end">Campañas</th><th class="text-end">Programadas</th><th>Última</th><th></th></tr></thead>
          <tbody>@for (v of items(); track v.id_voluntario) {
            <tr [class.text-secondary]="!v.activo">
              <td><div class="fw-semibold">{{ v.nombre_completo }}@if (!v.activo) { <span class="badge text-bg-secondary ms-2">Inactivo</span> }</div><div class="small text-secondary">{{ v.correo }}</div></td>
              <td class="small text-nowrap">{{ v.fecha_ingreso | fecha }}</td>
              <td class="text-end tabular fw-semibold">{{ v.entregas_realizadas }}</td><td class="text-end tabular">{{ v.unidades_entregadas | num }}</td>
              <td class="text-end tabular">{{ v.campanas_participadas }}</td><td class="text-end tabular">{{ v.entregas_programadas }}</td><td class="small text-nowrap">{{ v.ultima_entrega | fecha }}</td>
              <td class="text-end text-nowrap">@if (auth.tiene('voluntarios:escribir')) {
                <button class="btn btn-sm btn-outline-secondary me-1" type="button" (click)="editando.set(v); formulario.set(true)" title="Editar"><i class="bi bi-pencil"></i></button>
                <button class="btn btn-sm" [class]="v.activo ? 'btn-outline-danger' : 'btn-outline-success'" type="button" (click)="alternar(v)" [title]="v.activo ? 'Desactivar' : 'Reactivar'"><i class="bi" [class]="v.activo ? 'bi-person-dash' : 'bi-person-check'"></i></button> }</td></tr> }</tbody></table></div>
        <rs-paginacion [pagina]="pagina()" [paginas]="paginas()" [total]="total()" [tamano]="tamano" (cambia)="irA($event)" />
      }
    </div>
    @if (formulario()) { <rs-voluntario-form [voluntario]="editando()" (cerrar)="formulario.set(false)" (guardado)="formulario.set(false); cargar()" /> }`,
})
export class VoluntariosPage extends ListaBase<Voluntario> {
  protected readonly auth = inject(AuthService);
  private readonly api = inject(VoluntarioService);
  private readonly confirm = inject(ConfirmService);
  private readonly toast = inject(ToastService);
  protected readonly q = signal(''); protected readonly activo = signal('true');
  protected readonly formulario = signal(false); protected readonly editando = signal<Voluntario | null>(null);
  constructor() { super(); this.cargar(); }
  protected override consultar(): Observable<Pagina<Voluntario>> { return this.api.listar({ q: this.q(), activo: this.activo(), pagina: this.pagina(), tamano: this.tamano }); }
  protected async alternar(v: Voluntario): Promise<void> {
    const r = await this.confirm.preguntar({ titulo: v.activo ? 'Desactivar voluntario' : 'Reactivar voluntario', mensaje: v.activo ? 'No podrá asignársele nuevas entregas. Si tiene entregas programadas, hay que resolverlas antes.' : 'Podrá volver a recibir entregas.', confirmar: v.activo ? 'Desactivar' : 'Reactivar', peligro: v.activo });
    if (!r.ok) return;
    this.api.cambiarEstado(v.id_voluntario, !v.activo).subscribe({ next: () => { this.toast.ok('Estado actualizado.'); this.cargar(); }, error: (e) => this.toast.error(toApiError(e).message) });
  }
}
