import { ChangeDetectionStrategy, Component, inject, input, OnInit, output, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { form, FormField, max, maxLength, min, minLength, required } from '@angular/forms/signals';
import { forkJoin, firstValueFrom, Observable, of } from 'rxjs';
import { toApiError } from '../../core/models/api-error';
import { Beneficiario, Entrega, Necesidad, Pagina, Sector } from '../../core/models/api.models';
import { BeneficiarioService, CatalogoService, EntregaService, NecesidadService } from '../../core/services/api.services';
import { AuthService } from '../../core/services/auth.service';
import { ConfirmService } from '../../core/services/confirm.service';
import { ToastService } from '../../core/services/toast.service';
import { FORMATOS } from '../../core/util/format';
import { enviar } from '../../core/util/form-utils';
import { ListaBase } from '../../core/util/lista-base';
import { Campo, Carga, Encabezado, Estado, Modal, Paginacion, Vacio } from '../../shared/ui';

@Component({
  selector: 'rs-hogar-form',
  imports: [FormField, Campo, Modal],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <rs-modal [titulo]="hogar() ? 'Editar hogar' : 'Registrar hogar'" (cerrar)="cerrar.emit()">
      @if (error(); as e) { <div class="alert alert-danger py-2 small" role="alert">{{ e }}</div> }
      <form id="f-hogar" (submit)="guardar($event)" novalidate>
        <div class="row">
          <div class="col-6"><rs-campo etiqueta="Nombres de la persona responsable" requerido [campo]="f.nombres"><input class="form-control" autocomplete="off" [formField]="f.nombres" /></rs-campo></div>
          <div class="col-6"><rs-campo etiqueta="Apellidos" requerido [campo]="f.apellidos"><input class="form-control" autocomplete="off" [formField]="f.apellidos" /></rs-campo></div>
        </div>
        <div class="row">
          <div class="col-7"><rs-campo etiqueta="Sector" requerido [campo]="f.id_sector"><select class="form-select" [formField]="f.id_sector"><option value="">Seleccione…</option>@for (s of sectores(); track s.id_sector) { <option [value]="s.id_sector">{{ s.nombre }}</option> }</select></rs-campo></div>
          <div class="col-5"><rs-campo etiqueta="Integrantes del hogar" requerido [campo]="f.integrantes_hogar"><input class="form-control" type="number" [formField]="f.integrantes_hogar" /></rs-campo></div>
        </div>
        <div class="form-check p-3 ps-5 bg-light rounded border">
          <input class="form-check-input" type="checkbox" id="consent" [formField]="f.consentimiento_datos" />
          <label class="form-check-label small" for="consent"><strong>La persona responsable aceptó</strong> que se registren y usen sus datos para gestionar la ayuda social.</label>
          <div class="small text-secondary mt-1">Marque solo si lo autorizó (de preferencia por escrito). No se asume: si no lo marca, el hogar queda con «consentimiento pendiente» y no se pierde la ayuda.</div>
        </div>
      </form>
      <div pie class="modal-footer border-0"><button type="button" class="btn btn-light" (click)="cerrar.emit()">Cancelar</button><button type="submit" form="f-hogar" class="btn btn-primary" [disabled]="enviando()">{{ enviando() ? 'Guardando…' : 'Guardar' }}</button></div>
    </rs-modal>`,
})
export class HogarForm implements OnInit {
  readonly hogar = input<Beneficiario | null>(null);
  readonly sectores = input.required<Sector[]>();
  readonly guardado = output<Beneficiario>();
  readonly cerrar = output<void>();
  private readonly api = inject(BeneficiarioService);
  private readonly toast = inject(ToastService);
  private readonly confirm = inject(ConfirmService);
  protected readonly modelo = signal({ nombres: '', apellidos: '', id_sector: '', integrantes_hogar: null as number | null, consentimiento_datos: false });
  protected readonly f = form(this.modelo, (p) => {
    maxLength(p.nombres, 60, { message: 'Máximo 60 caracteres.' });
    maxLength(p.apellidos, 60, { message: 'Máximo 60 caracteres.' });
    required(p.nombres, { message: 'Escriba los nombres.' }); minLength(p.nombres, 2, { message: 'Use al menos 2 caracteres.' });
    required(p.apellidos, { message: 'Escriba los apellidos.' }); minLength(p.apellidos, 2, { message: 'Use al menos 2 caracteres.' });
    required(p.id_sector, { message: 'Seleccione el sector.' });
    required(p.integrantes_hogar, { message: 'Indique cuántas personas viven en el hogar.' });
    min(p.integrantes_hogar, 1, { message: 'Mínimo 1 persona.' }); max(p.integrantes_hogar, 30, { message: 'Máximo 30 personas por hogar.' });
  });
  protected readonly enviando = signal(false);
  protected readonly error = signal<string | null>(null);
  ngOnInit(): void { const h = this.hogar(); if (h) this.modelo.set({ nombres: h.nombres, apellidos: h.apellidos, id_sector: String(h.id_sector), integrantes_hogar: h.integrantes_hogar, consentimiento_datos: h.consentimiento_datos }); }
  protected async guardar(ev: Event): Promise<void> {
    ev.preventDefault();
    await enviar(this.f, { enviando: this.enviando, error: this.error }, async (confirmado) => {
      const m = this.modelo(); const h = this.hogar();
      const r = await firstValueFrom(this.api.guardar(h?.id_beneficiario ?? null, { ...m, id_sector: Number(m.id_sector), confirmar_duplicado: confirmado }));
      this.toast.ok(h ? 'Hogar actualizado.' : 'Hogar registrado.');
      this.guardado.emit(r);
    }, this.confirm);
  }
}

@Component({
  selector: 'rs-hogar-detalle',
  imports: [Modal, Estado, Carga, Vacio, ...FORMATOS],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <rs-modal [titulo]="hogar().nombre_completo" tamano="lg" (cerrar)="cerrar.emit()">
      <div class="d-flex flex-wrap gap-3 mb-3 small">
        <span><i class="bi bi-geo-alt me-1"></i>{{ hogar().sector }}</span><span><i class="bi bi-people me-1"></i>{{ hogar().integrantes_hogar }} integrantes</span>
        <span><i class="bi bi-calendar-plus me-1"></i>Registrado el {{ hogar().fecha_registro | fecha }}</span>
        @if (hogar().consentimiento_datos) { <span class="text-dar"><i class="bi bi-shield-check me-1"></i>Consentimiento: {{ hogar().fecha_consentimiento | fecha }}</span> } @else { <span class="text-warning-emphasis"><i class="bi bi-shield-exclamation me-1"></i>Consentimiento pendiente</span> }
      </div>
      @if (!cargado()) { <rs-carga [n]="4" /> } @else {
        @if (necesidades().length) {
          <h3 class="h6">Necesidades</h3>
          <ul class="list-group mb-3">@for (n of necesidades(); track n.id_necesidad) { <li class="list-group-item d-flex justify-content-between align-items-center gap-2"><span><strong>{{ n.categoria }}</strong> <span class="text-secondary small">· {{ n.descripcion || 'sin detalle' }} · {{ n.fecha_registro | fecha }}</span></span><span class="text-nowrap"><rs-estado [valor]="n.urgencia" [conIcono]="false" /> <rs-estado [valor]="n.estado" /></span></li> }</ul>
        }
        <h3 class="h6">Entregas recibidas</h3>
        @if (!entregas().length) { <rs-vacio icono="box-seam" titulo="Este hogar aún no recibió entregas" /> } @else {
          <div class="table-responsive"><table class="table rs-table"><thead><tr><th>Fecha</th><th>Campaña</th><th>Voluntario</th><th class="text-end">Cant.</th><th>Estado</th></tr></thead><tbody>
            @for (e of entregas(); track e.id_entrega) { <tr><td>{{ e.fecha | fecha }}</td><td>{{ e.campana }}</td><td>{{ e.voluntario }}</td><td class="text-end tabular">{{ e.cantidad }}</td><td><rs-estado [valor]="e.estado" /></td></tr> }</tbody></table></div>
        }
      }
    </rs-modal>`,
})
export class HogarDetalle implements OnInit {
  readonly hogar = input.required<Beneficiario>();
  readonly cerrar = output<void>();
  private readonly auth = inject(AuthService);
  private readonly entregaApi = inject(EntregaService);
  private readonly necesidadApi = inject(NecesidadService);
  private readonly toast = inject(ToastService);
  protected readonly entregas = signal<Entrega[]>([]); protected readonly necesidades = signal<Necesidad[]>([]); protected readonly cargado = signal(false);
  ngOnInit(): void {
    const id = this.hogar().id_beneficiario;
    forkJoin([this.auth.tiene('entregas:leer') ? this.entregaApi.listar({ id_beneficiario: id, tamano: 50 }) : of(null), this.auth.tiene('necesidades:leer') ? this.necesidadApi.listar({ id_beneficiario: id, tamano: 50 }) : of(null)]).subscribe({
      next: ([e, n]) => { this.entregas.set(e?.items ?? []); this.necesidades.set(n?.items ?? []); this.cargado.set(true); },
      error: (err) => { this.cargado.set(true); this.toast.error(toApiError(err).message); },
    });
  }
}

@Component({
  selector: 'rs-hogares',
  imports: [FormsModule, Encabezado, Carga, Vacio, Paginacion, HogarForm, HogarDetalle, ...FORMATOS],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <rs-encabezado titulo="Hogares" subtitulo="Cada hogar está representado por una persona responsable. Datos personales: acceso restringido por rol.">
      @if (auth.tiene('beneficiarios:escribir')) { <button class="btn btn-primary" type="button" (click)="editando.set(null); formulario.set(true)"><i class="bi bi-plus-lg me-1"></i>Registrar hogar</button> }
    </rs-encabezado>
    <div class="card">
      <div class="card-body border-bottom">
        <div class="row g-2">
          <div class="col-md-5"><div class="input-group"><span class="input-group-text bg-white"><i class="bi bi-search"></i></span><input class="form-control" type="search" placeholder="Buscar por nombre o apellido" aria-label="Buscar hogares" [ngModel]="q()" (ngModelChange)="q.set($event); buscarConRetardo()" /></div></div>
          <div class="col-6 col-md-3"><select class="form-select" aria-label="Sector" [ngModel]="sector()" (ngModelChange)="sector.set($event); refiltrar()"><option value="">Todos los sectores</option>@for (s of sectores(); track s.id_sector) { <option [value]="s.id_sector">{{ s.nombre }}</option> }</select></div>
          <div class="col-6 col-md-4"><select class="form-select" aria-label="Estado" [ngModel]="activo()" (ngModelChange)="activo.set($event); refiltrar()"><option value="true">Hogares activos</option><option value="false">Hogares inactivos</option><option value="">Todos</option></select></div>
        </div>
        <div class="d-flex flex-wrap gap-3 mt-2 small">
          <div class="form-check"><input class="form-check-input" type="checkbox" id="h1" [ngModel]="sinEntregas()" (ngModelChange)="sinEntregas.set($event); refiltrar()" /><label class="form-check-label" for="h1">Sin ninguna entrega</label></div>
          <div class="form-check"><input class="form-check-input" type="checkbox" id="h2" [ngModel]="conNecesidades()" (ngModelChange)="conNecesidades.set($event); refiltrar()" /><label class="form-check-label" for="h2">Con necesidades abiertas</label></div>
          <div class="form-check"><input class="form-check-input" type="checkbox" id="h3" [ngModel]="sinConsent()" (ngModelChange)="sinConsent.set($event); refiltrar()" /><label class="form-check-label" for="h3">Consentimiento pendiente</label></div>
        </div>
      </div>
      @if (cargando() && !items().length) { <rs-carga [n]="7" /> }
      @else if (error(); as e) { <div class="alert alert-danger m-3" role="alert">{{ e }}</div> }
      @else if (!items().length) { <rs-vacio icono="house-heart" titulo="No se encontraron hogares" texto="Pruebe con otros filtros." /> }
      @else {
        <div class="table-responsive"><table class="table rs-table">
          <thead><tr><th>Hogar</th><th>Sector</th><th class="text-end">Integrantes</th><th>Entregas</th><th>Necesidades</th><th>Consentimiento</th><th></th></tr></thead>
          <tbody>@for (h of items(); track h.id_beneficiario) {
            <tr [class.text-secondary]="!h.activo">
              <td class="fw-semibold">{{ h.nombre_completo }}@if (!h.activo) { <span class="badge text-bg-secondary ms-2">Inactivo</span> }</td>
              <td>{{ h.sector }}</td><td class="text-end tabular">{{ h.integrantes_hogar }}</td>
              <td class="small">@if (h.entregas_recibidas) { <span class="tabular fw-semibold">{{ h.entregas_recibidas }}</span> · última {{ h.ultima_entrega | fecha }} } @else { <span class="badge text-bg-warning">Sin entregas</span> }</td>
              <td>@if (h.necesidades_abiertas) { <span class="badge bg-danger-subtle text-danger-emphasis border border-danger-subtle">{{ h.necesidades_abiertas }} abiertas</span> } @else { <span class="text-secondary">—</span> }</td>
              <td>@if (h.consentimiento_datos) { <span class="small text-dar"><i class="bi bi-shield-check me-1"></i>{{ h.fecha_consentimiento | fecha }}</span> } @else { <span class="badge bg-warning-subtle text-warning-emphasis border border-warning-subtle">Pendiente</span> }</td>
              <td class="text-end text-nowrap">
                <button class="btn btn-sm btn-outline-secondary me-1" type="button" (click)="detalle.set(h)" title="Ver historial"><i class="bi bi-clock-history"></i></button>
                @if (auth.tiene('beneficiarios:escribir')) {
                  <button class="btn btn-sm btn-outline-secondary me-1" type="button" (click)="editando.set(h); formulario.set(true)" title="Editar"><i class="bi bi-pencil"></i></button>
                  <button class="btn btn-sm" [class]="h.activo ? 'btn-outline-danger' : 'btn-outline-success'" type="button" (click)="alternar(h)" [title]="h.activo ? 'Desactivar' : 'Reactivar'"><i class="bi" [class]="h.activo ? 'bi-house-dash' : 'bi-house-check'"></i></button>
                }
              </td></tr> }</tbody></table></div>
        <rs-paginacion [pagina]="pagina()" [paginas]="paginas()" [total]="total()" [tamano]="tamano" (cambia)="irA($event)" />
      }
    </div>
    @if (formulario()) { <rs-hogar-form [hogar]="editando()" [sectores]="sectoresActivos()" (cerrar)="formulario.set(false)" (guardado)="formulario.set(false); cargar()" /> }
    @if (detalle(); as h) { <rs-hogar-detalle [hogar]="h" (cerrar)="detalle.set(null)" /> }`,
})
export class HogaresPage extends ListaBase<Beneficiario> {
  protected readonly auth = inject(AuthService);
  private readonly api = inject(BeneficiarioService);
  private readonly confirm = inject(ConfirmService);
  private readonly toast = inject(ToastService);
  protected readonly q = signal(''); protected readonly sector = signal(''); protected readonly activo = signal('true');
  protected readonly sinEntregas = signal(false); protected readonly conNecesidades = signal(false); protected readonly sinConsent = signal(false);
  protected readonly sectores = signal<Sector[]>([]);
  protected readonly sectoresActivos = () => this.sectores().filter((s) => s.activo);
  protected readonly formulario = signal(false); protected readonly editando = signal<Beneficiario | null>(null); protected readonly detalle = signal<Beneficiario | null>(null);
  constructor() {
    super();
    inject(CatalogoService).sectores().subscribe({ next: (s) => this.sectores.set(s), error: () => undefined });
    this.cargar();
  }
  protected override consultar(): Observable<Pagina<Beneficiario>> {
    return this.api.listar({ q: this.q(), id_sector: this.sector(), activo: this.activo(), sin_entregas: this.sinEntregas(), con_necesidades: this.conNecesidades(), sin_consentimiento: this.sinConsent(), pagina: this.pagina(), tamano: this.tamano });
  }
  protected async alternar(h: Beneficiario): Promise<void> {
    const r = await this.confirm.preguntar({ titulo: h.activo ? 'Desactivar hogar' : 'Reactivar hogar', mensaje: h.activo ? 'Dejará de aparecer al registrar entregas. Su historial se conserva.' : 'Podrá volver a recibir entregas.', confirmar: h.activo ? 'Desactivar' : 'Reactivar', peligro: h.activo });
    if (!r.ok) return;
    this.api.cambiarEstado(h.id_beneficiario, !h.activo).subscribe({ next: () => { this.toast.ok('Estado actualizado.'); this.cargar(); }, error: (e) => this.toast.error(toApiError(e).message) });
  }
}
