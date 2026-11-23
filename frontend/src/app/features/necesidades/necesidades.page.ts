import { ChangeDetectionStrategy, Component, inject, input, OnInit, output, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { form, FormField, maxLength, required } from '@angular/forms/signals';
import { forkJoin, firstValueFrom, Observable } from 'rxjs';
import { toApiError } from '../../core/models/api-error';
import { Beneficiario, Categoria, Necesidad, Pagina, Sector } from '../../core/models/api.models';
import { BeneficiarioService, CatalogoService, NecesidadService } from '../../core/services/api.services';
import { AuthService } from '../../core/services/auth.service';
import { ConfirmService } from '../../core/services/confirm.service';
import { ToastService } from '../../core/services/toast.service';
import { FORMATOS } from '../../core/util/format';
import { aTexto, enviar } from '../../core/util/form-utils';
import { URGENCIAS } from '../../core/util/labels';
import { ListaBase } from '../../core/util/lista-base';
import { Campo, Carga, Encabezado, Estado, Modal, Paginacion, Vacio } from '../../shared/ui';

@Component({
  selector: 'rs-necesidad-form',
  imports: [FormField, Campo, Modal],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <rs-modal [titulo]="necesidad() ? 'Editar necesidad' : 'Registrar necesidad'" (cerrar)="cerrar.emit()">
      @if (error(); as e) { <div class="alert alert-danger py-2 small" role="alert">{{ e }}</div> }
      <form id="f-nec" (submit)="guardar($event)" novalidate>
        @if (!necesidad()) { <rs-campo etiqueta="Hogar" requerido [campo]="f.id_beneficiario"><select class="form-select" [formField]="f.id_beneficiario"><option value="">Seleccione…</option>@for (h of hogares(); track h.id_beneficiario) { <option [value]="h.id_beneficiario">{{ h.nombre_completo }} · {{ h.sector }}</option> }</select></rs-campo> }
        @else { <p class="mb-3"><strong>{{ necesidad()!.hogar }}</strong> <span class="text-secondary">· {{ necesidad()!.sector }}</span></p> }
        <div class="row">
          <div class="col-7"><rs-campo etiqueta="Tipo de ayuda" requerido [campo]="f.id_categoria"><select class="form-select" [formField]="f.id_categoria"><option value="">Seleccione…</option>@for (c of categorias(); track c.id_categoria) { <option [value]="c.id_categoria">{{ c.nombre }}</option> }</select></rs-campo></div>
          <div class="col-5"><rs-campo etiqueta="Urgencia" requerido [campo]="f.urgencia"><select class="form-select" [formField]="f.urgencia">@for (u of urgencias; track u.v) { <option [value]="u.v">{{ u.t }}</option> }</select></rs-campo></div>
        </div>
        <rs-campo etiqueta="Descripción" ayuda="Qué se necesita y por qué. Sin datos de salud ni de otro tipo que no sean imprescindibles." [campo]="f.descripcion"><textarea class="form-control" rows="3" [formField]="f.descripcion"></textarea></rs-campo>
      </form>
      <div pie class="modal-footer border-0"><button type="button" class="btn btn-light" (click)="cerrar.emit()">Cancelar</button><button type="submit" form="f-nec" class="btn btn-primary" [disabled]="enviando()">{{ enviando() ? 'Guardando…' : 'Guardar' }}</button></div>
    </rs-modal>`,
})
export class NecesidadForm implements OnInit {
  readonly necesidad = input<Necesidad | null>(null);
  readonly categorias = input.required<Categoria[]>();
  readonly guardado = output<Necesidad>();
  readonly cerrar = output<void>();
  private readonly api = inject(NecesidadService);
  private readonly hogarApi = inject(BeneficiarioService);
  private readonly toast = inject(ToastService);
  protected readonly urgencias = URGENCIAS;
  protected readonly hogares = signal<Beneficiario[]>([]);
  protected readonly modelo = signal({ id_beneficiario: '', id_categoria: '', urgencia: 'Media', descripcion: '' });
  protected readonly f = form(this.modelo, (p) => {
    maxLength(p.descripcion, 300, { message: 'Máximo 300 caracteres.' });
    required(p.id_beneficiario, { message: 'Seleccione el hogar.' });
    required(p.id_categoria, { message: 'Seleccione el tipo de ayuda.' });
    required(p.urgencia, { message: 'Indique la urgencia.' });
  });
  protected readonly enviando = signal(false);
  protected readonly error = signal<string | null>(null);
  ngOnInit(): void {
    const n = this.necesidad();
    if (n) this.modelo.set({ id_beneficiario: String(n.id_beneficiario), id_categoria: String(n.id_categoria), urgencia: n.urgencia, descripcion: n.descripcion ?? '' });
    else this.hogarApi.listar({ activo: true, tamano: 100 }).subscribe({ next: (r) => this.hogares.set(r.items), error: (e) => this.error.set(toApiError(e).message) });
  }
  protected async guardar(ev: Event): Promise<void> {
    ev.preventDefault();
    await enviar(this.f, { enviando: this.enviando, error: this.error }, async () => {
      const m = this.modelo(); const n = this.necesidad();
      const cuerpo = { id_categoria: Number(m.id_categoria), urgencia: m.urgencia, descripcion: aTexto(m.descripcion) };
      const r = await firstValueFrom(this.api.guardar(n?.id_necesidad ?? null, n ? cuerpo : { ...cuerpo, id_beneficiario: Number(m.id_beneficiario) }));
      this.toast.ok(n ? 'Necesidad actualizada.' : 'Necesidad registrada en la cola de atención.');
      this.guardado.emit(r);
    });
  }
}

@Component({
  selector: 'rs-necesidades',
  imports: [FormsModule, Encabezado, Estado, Carga, Vacio, Paginacion, NecesidadForm, ...FORMATOS],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <rs-encabezado titulo="Cola de atención" subtitulo="Orden transparente: primero la urgencia y, a igual urgencia, quien lleva más tiempo esperando. Una persona revisa y decide.">
      @if (auth.tiene('necesidades:escribir')) { <button class="btn btn-primary" type="button" (click)="editando.set(null); formulario.set(true)"><i class="bi bi-plus-lg me-1"></i>Registrar necesidad</button> }
    </rs-encabezado>
    <div class="card">
      <div class="card-body border-bottom"><div class="row g-2">
        <div class="col-6 col-md-3"><select class="form-select" aria-label="Estado" [ngModel]="vista()" (ngModelChange)="vista.set($event); refiltrar()"><option value="abiertas">Abiertas (por atender)</option><option value="">Todas</option><option value="Cubierta">Cubiertas</option><option value="Descartada">Descartadas</option></select></div>
        <div class="col-6 col-md-3"><select class="form-select" aria-label="Urgencia" [ngModel]="urgencia()" (ngModelChange)="urgencia.set($event); refiltrar()"><option value="">Toda urgencia</option>@for (u of urgencias; track u.v) { <option [value]="u.v">{{ u.t }}</option> }</select></div>
        <div class="col-6 col-md-3"><select class="form-select" aria-label="Tipo de ayuda" [ngModel]="categoria()" (ngModelChange)="categoria.set($event); refiltrar()"><option value="">Todo tipo de ayuda</option>@for (c of categorias(); track c.id_categoria) { <option [value]="c.id_categoria">{{ c.nombre }}</option> }</select></div>
        <div class="col-6 col-md-3"><select class="form-select" aria-label="Sector" [ngModel]="sector()" (ngModelChange)="sector.set($event); refiltrar()"><option value="">Todos los sectores</option>@for (s of sectores(); track s.id_sector) { <option [value]="s.id_sector">{{ s.nombre }}</option> }</select></div>
      </div></div>
      @if (cargando() && !items().length) { <rs-carga [n]="6" /> }
      @else if (error(); as e) { <div class="alert alert-danger m-3" role="alert">{{ e }}</div> }
      @else if (!items().length) { <rs-vacio icono="clipboard2-check" titulo="No hay necesidades en esta vista" texto="Cuando se registre una necesidad aparecerá aquí, ordenada por urgencia y antigüedad." /> }
      @else {
        <div class="table-responsive"><table class="table rs-table">
          <thead><tr><th style="width:2.5rem">#</th><th>Hogar</th><th>Necesidad</th><th>¿Por qué está en este lugar?</th><th>Estado</th><th></th></tr></thead>
          <tbody>@for (n of items(); track n.id_necesidad; let i = $index) {
            <tr>
              <td class="text-secondary tabular">{{ (pagina() - 1) * tamano + i + 1 }}</td>
              <td><div class="fw-semibold">{{ n.hogar }}</div><div class="small text-secondary">{{ n.sector }} · {{ n.integrantes_hogar }} integrantes</div></td>
              <td><div><strong>{{ n.categoria }}</strong></div><div class="small text-secondary" style="max-width:22rem">{{ n.descripcion || 'Sin descripción' }}</div></td>
              <td class="small"><rs-estado [valor]="n.urgencia" [conIcono]="false" /> <span class="text-secondary ms-1">{{ n.dias_espera }} {{ n.dias_espera === 1 ? 'día' : 'días' }} {{ n.estado === 'Cubierta' || n.estado === 'Descartada' ? 'hasta resolverse' : 'esperando' }}</span></td>
              <td><rs-estado [valor]="n.estado" />@if (n.motivo_estado) { <div class="small text-secondary">{{ n.motivo_estado }}</div> }</td>
              <td class="text-end text-nowrap">
                @if (auth.tiene('necesidades:escribir') && (n.estado === 'Pendiente' || n.estado === 'En atencion')) {
                  @if (n.estado === 'Pendiente') { <button class="btn btn-sm btn-outline-primary me-1" type="button" (click)="cambiar(n, 'En atencion')">Atender</button> }
                  <button class="btn btn-sm btn-success me-1" type="button" (click)="cambiar(n, 'Cubierta')">Cubierta</button>
                  <button class="btn btn-sm btn-outline-secondary me-1" type="button" (click)="editando.set(n); formulario.set(true)" title="Editar"><i class="bi bi-pencil"></i></button>
                  <button class="btn btn-sm btn-outline-danger" type="button" (click)="descartar(n)" title="Descartar"><i class="bi bi-x-lg"></i></button>
                }
              </td></tr> }</tbody></table></div>
        <rs-paginacion [pagina]="pagina()" [paginas]="paginas()" [total]="total()" [tamano]="tamano" (cambia)="irA($event)" />
      }
    </div>
    @if (formulario()) { <rs-necesidad-form [necesidad]="editando()" [categorias]="categoriasActivas()" (cerrar)="formulario.set(false)" (guardado)="formulario.set(false); cargar()" /> }`,
})
export class NecesidadesPage extends ListaBase<Necesidad> {
  protected readonly auth = inject(AuthService);
  private readonly api = inject(NecesidadService);
  private readonly confirm = inject(ConfirmService);
  private readonly toast = inject(ToastService);
  protected readonly urgencias = URGENCIAS;
  protected readonly vista = signal('abiertas'); protected readonly urgencia = signal(''); protected readonly categoria = signal(''); protected readonly sector = signal('');
  protected readonly categorias = signal<Categoria[]>([]); protected readonly sectores = signal<Sector[]>([]);
  protected readonly categoriasActivas = () => this.categorias().filter((c) => c.activo);
  protected readonly formulario = signal(false); protected readonly editando = signal<Necesidad | null>(null);
  constructor() {
    super();
    const cat = inject(CatalogoService);
    forkJoin([cat.categorias(), cat.sectores()]).subscribe({ next: ([c, s]) => { this.categorias.set(c); this.sectores.set(s); }, error: () => undefined });
    this.cargar();
  }
  protected override consultar(): Observable<Pagina<Necesidad>> {
    const v = this.vista();
    return this.api.listar({ solo_abiertas: v === 'abiertas', estado: v === 'abiertas' ? '' : v, urgencia: this.urgencia(), id_categoria: this.categoria(), id_sector: this.sector(), pagina: this.pagina(), tamano: this.tamano });
  }
  protected cambiar(n: Necesidad, estado: string): void {
    this.api.cambiarEstado(n.id_necesidad, estado).subscribe({ next: () => { this.toast.ok(estado === 'Cubierta' ? 'Necesidad marcada como cubierta.' : 'Necesidad en atención.'); this.cargar(); }, error: (e) => this.toast.error(toApiError(e).message) });
  }
  protected async descartar(n: Necesidad): Promise<void> {
    const r = await this.confirm.preguntar({ titulo: 'Descartar necesidad', mensaje: 'Indique por qué ya no corresponde atenderla (p. ej., el hogar se mudó o ya se resolvió por otra vía).', confirmar: 'Descartar', peligro: true, pedirMotivo: true });
    if (r.ok) this.api.cambiarEstado(n.id_necesidad, 'Descartada', r.motivo).subscribe({ next: () => { this.toast.ok('Necesidad descartada.'); this.cargar(); }, error: (e) => this.toast.error(toApiError(e).message) });
  }
}
