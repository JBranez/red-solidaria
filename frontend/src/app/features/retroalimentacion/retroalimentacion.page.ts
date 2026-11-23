import { ChangeDetectionStrategy, Component, inject, input, OnInit, output, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { form, FormField, maxLength, minLength, required, validate } from '@angular/forms/signals';
import { firstValueFrom, Observable } from 'rxjs';
import { Beneficiario, Campana, Feedback, Pagina } from '../../core/models/api.models';
import { BeneficiarioService, CampanaService, FeedbackService } from '../../core/services/api.services';
import { AuthService } from '../../core/services/auth.service';
import { ToastService } from '../../core/services/toast.service';
import { FORMATOS } from '../../core/util/format';
import { aNumero, enviar } from '../../core/util/form-utils';
import { TIPOS_FEEDBACK } from '../../core/util/labels';
import { ListaBase } from '../../core/util/lista-base';
import { Campo, Carga, Encabezado, Estado, Modal, Paginacion, Vacio } from '../../shared/ui';

@Component({
  selector: 'rs-feedback-form',
  imports: [FormField, Campo, Modal],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <rs-modal titulo="Registrar mensaje" (cerrar)="cerrar.emit()">
      <div class="alert alert-warning py-2 small" role="note"><i class="bi bi-shield-exclamation me-1"></i>Si el mensaje describe <strong>abuso, explotación o riesgo para la integridad de una persona</strong>, no espere a resolverlo aquí: escale de inmediato según el protocolo de salvaguarda de la organización.</div>
      @if (error(); as e) { <div class="alert alert-danger py-2 small" role="alert">{{ e }}</div> }
      <form id="f-fb" (submit)="guardar($event)" novalidate>
        <div class="row">
          <div class="col-6"><rs-campo etiqueta="Tipo" requerido [campo]="f.tipo"><select class="form-select" [formField]="f.tipo">@for (t of tipos; track t.v) { <option [value]="t.v">{{ t.t }}</option> }</select></rs-campo></div>
          <div class="col-6"><rs-campo etiqueta="Calificación (opcional)" [campo]="f.calificacion"><select class="form-select" [formField]="f.calificacion"><option value="">Sin calificar</option><option value="5">5 · Muy satisfecho/a</option><option value="4">4</option><option value="3">3</option><option value="2">2</option><option value="1">1 · Muy insatisfecho/a</option></select></rs-campo></div>
        </div>
        <rs-campo etiqueta="Mensaje" requerido [campo]="f.mensaje"><textarea class="form-control" rows="4" [formField]="f.mensaje"></textarea></rs-campo>
        <div class="row">
          <div class="col-6"><rs-campo etiqueta="Campaña relacionada" [campo]="f.id_campana"><select class="form-select" [formField]="f.id_campana"><option value="">Ninguna</option>@for (c of campanas(); track c.id_campana) { <option [value]="c.id_campana">{{ c.nombre }}</option> }</select></rs-campo></div>
          @if (hogares().length) { <div class="col-6"><rs-campo etiqueta="Hogar (opcional)" ayuda="Déjelo vacío si es anónimo." [campo]="f.id_beneficiario"><select class="form-select" [formField]="f.id_beneficiario"><option value="">Anónimo</option>@for (h of hogares(); track h.id_beneficiario) { <option [value]="h.id_beneficiario">{{ h.nombre_completo }}</option> }</select></rs-campo></div> }
        </div>
        <div class="form-check"><input class="form-check-input" type="checkbox" id="conf" [formField]="f.confidencial" /><label class="form-check-label small" for="conf"><strong>Confidencial</strong>: solo lo verá personal autorizado a gestionar casos sensibles.</label></div>
      </form>
      <div pie class="modal-footer border-0"><button type="button" class="btn btn-light" (click)="cerrar.emit()">Cancelar</button><button type="submit" form="f-fb" class="btn btn-primary" [disabled]="enviando()">{{ enviando() ? 'Guardando…' : 'Registrar' }}</button></div>
    </rs-modal>`,
})
export class FeedbackForm implements OnInit {
  readonly guardado = output<void>();
  readonly cerrar = output<void>();
  private readonly api = inject(FeedbackService);
  private readonly auth = inject(AuthService);
  private readonly campanaApi = inject(CampanaService);
  private readonly hogarApi = inject(BeneficiarioService);
  private readonly toast = inject(ToastService);
  protected readonly tipos = TIPOS_FEEDBACK;
  protected readonly campanas = signal<Campana[]>([]); protected readonly hogares = signal<Beneficiario[]>([]);
  protected readonly modelo = signal({ tipo: 'Consulta', mensaje: '', calificacion: '', id_campana: '', id_beneficiario: '', confidencial: false });
  protected readonly f = form(this.modelo, (p) => {
    maxLength(p.mensaje, 1000, { message: 'Máximo 1000 caracteres.' });
    required(p.tipo, { message: 'Seleccione el tipo.' });
    required(p.mensaje, { message: 'Escriba el mensaje.' }); minLength(p.mensaje, 3, { message: 'Use al menos 3 caracteres.' });
    validate(p.calificacion, ({ value }) => (value() === '' || (Number(value()) >= 1 && Number(value()) <= 5) ? undefined : { kind: 'rango', message: 'Entre 1 y 5.' }));
  });
  protected readonly enviando = signal(false);
  protected readonly error = signal<string | null>(null);
  ngOnInit(): void {
    if (this.auth.tiene('campanas:leer')) this.campanaApi.listar({ tamano: 100 }).subscribe({ next: (r) => this.campanas.set(r.items), error: () => undefined });
    if (this.auth.tiene('beneficiarios:leer')) this.hogarApi.listar({ activo: true, tamano: 100 }).subscribe({ next: (r) => this.hogares.set(r.items), error: () => undefined });
  }
  protected async guardar(ev: Event): Promise<void> {
    ev.preventDefault();
    await enviar(this.f, { enviando: this.enviando, error: this.error }, async () => {
      const m = this.modelo();
      await firstValueFrom(this.api.registrar({ tipo: m.tipo, mensaje: m.mensaje, calificacion: aNumero(m.calificacion), id_campana: aNumero(m.id_campana), id_beneficiario: aNumero(m.id_beneficiario), confidencial: m.confidencial }));
      this.toast.ok('Mensaje registrado. Tiene un plazo de atención de 7 días.');
      this.guardado.emit();
    });
  }
}

@Component({
  selector: 'rs-feedback-gestion',
  imports: [FormField, Campo, Modal, Estado, ...FORMATOS],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <rs-modal titulo="Atender mensaje" tamano="lg" (cerrar)="cerrar.emit()">
      <div class="p-3 bg-light rounded mb-3">
        <div class="d-flex flex-wrap gap-2 align-items-center mb-2"><rs-estado [valor]="item().tipo" /><rs-estado [valor]="item().estado" />@if (item().confidencial) { <span class="badge text-bg-dark"><i class="bi bi-lock me-1"></i>Confidencial</span> }
          @if (item().calificacion) { <span class="small text-secondary">{{ item().calificacion }}/5</span> }<span class="small text-secondary ms-auto">{{ item().creado_en | fechaHora }}</span></div>
        <p class="mb-1">{{ item().mensaje }}</p>
        <div class="small text-secondary">{{ item().hogar || 'Anónimo' }}@if (item().campana) { · {{ item().campana }} } · plazo {{ item().fecha_limite | fecha }}</div>
      </div>
      @if (error(); as e) { <div class="alert alert-danger py-2 small" role="alert">{{ e }}</div> }
      <form id="f-gest" (submit)="guardar($event)" novalidate>
        <rs-campo etiqueta="Nuevo estado" requerido [campo]="f.estado"><select class="form-select" [formField]="f.estado"><option value="Abierta">Abierta</option><option value="En revision">En revisión</option><option value="Resuelta">Resuelta</option><option value="Cerrada">Cerrada</option></select></rs-campo>
        <rs-campo etiqueta="Respuesta a la persona" ayuda="Obligatoria para marcar como resuelta." [campo]="f.respuesta"><textarea class="form-control" rows="3" [formField]="f.respuesta"></textarea></rs-campo>
      </form>
      <div pie class="modal-footer border-0"><button type="button" class="btn btn-light" (click)="cerrar.emit()">Cancelar</button><button type="submit" form="f-gest" class="btn btn-primary" [disabled]="enviando()">{{ enviando() ? 'Guardando…' : 'Guardar' }}</button></div>
    </rs-modal>`,
})
export class FeedbackGestion implements OnInit {
  readonly item = input.required<Feedback>();
  readonly guardado = output<void>();
  readonly cerrar = output<void>();
  private readonly api = inject(FeedbackService);
  private readonly toast = inject(ToastService);
  protected readonly modelo = signal({ estado: 'En revision', respuesta: '' });
  protected readonly f = form(this.modelo, (p) => {
    maxLength(p.respuesta, 1000, { message: 'Máximo 1000 caracteres.' });
    required(p.estado, { message: 'Seleccione el estado.' });
    validate(p.respuesta, ({ value, valueOf }) => (valueOf(p.estado) === 'Resuelta' && !value().trim() ? { kind: 'resp', message: 'Registre la respuesta dada para marcarla como resuelta.' } : undefined));
  });
  protected readonly enviando = signal(false);
  protected readonly error = signal<string | null>(null);
  ngOnInit(): void { const i = this.item(); this.modelo.set({ estado: i.estado === 'Abierta' ? 'En revision' : i.estado, respuesta: i.respuesta ?? '' }); }
  protected async guardar(ev: Event): Promise<void> {
    ev.preventDefault();
    await enviar(this.f, { enviando: this.enviando, error: this.error }, async () => {
      await firstValueFrom(this.api.gestionar(this.item().id_retroalimentacion, { estado: this.modelo().estado, respuesta: this.modelo().respuesta.trim() || null }));
      this.toast.ok('Mensaje actualizado.');
      this.guardado.emit();
    });
  }
}

@Component({
  selector: 'rs-retroalimentacion',
  imports: [FormsModule, Encabezado, Estado, Carga, Vacio, Paginacion, FeedbackForm, FeedbackGestion, ...FORMATOS],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <rs-encabezado titulo="Retroalimentación y quejas" subtitulo="La voz de los hogares: cada mensaje tiene un plazo de atención y una respuesta.">
      @if (auth.tiene('feedback:registrar')) { <button class="btn btn-primary" type="button" (click)="formulario.set(true)"><i class="bi bi-plus-lg me-1"></i>Registrar mensaje</button> }
    </rs-encabezado>
    <div class="card">
      <div class="card-body border-bottom"><div class="row g-2 align-items-center">
        <div class="col-md-4"><div class="input-group"><span class="input-group-text bg-white"><i class="bi bi-search"></i></span><input class="form-control" type="search" placeholder="Buscar en los mensajes" aria-label="Buscar" [ngModel]="q()" (ngModelChange)="q.set($event); buscarConRetardo()" /></div></div>
        <div class="col-6 col-md-2"><select class="form-select" aria-label="Tipo" [ngModel]="tipo()" (ngModelChange)="tipo.set($event); refiltrar()"><option value="">Todo tipo</option><option>Consulta</option><option>Sugerencia</option><option>Queja</option><option value="Felicitacion">Felicitación</option></select></div>
        <div class="col-6 col-md-3"><select class="form-select" aria-label="Estado" [ngModel]="estado()" (ngModelChange)="estado.set($event); refiltrar()"><option value="">Todos los estados</option><option>Abierta</option><option value="En revision">En revisión</option><option>Resuelta</option><option>Cerrada</option></select></div>
        <div class="col-md-3"><div class="form-check"><input class="form-check-input" type="checkbox" id="venc" [ngModel]="vencidas()" (ngModelChange)="vencidas.set($event); refiltrar()" /><label class="form-check-label" for="venc">Solo con plazo vencido</label></div></div>
      </div></div>
      @if (cargando() && !items().length) { <rs-carga [n]="5" /> }
      @else if (error(); as e) { <div class="alert alert-danger m-3" role="alert">{{ e }}</div> }
      @else if (!items().length) { <rs-vacio icono="chat-heart" titulo="No hay mensajes con esos filtros" /> }
      @else {
        <div class="table-responsive"><table class="table rs-table">
          <thead><tr><th>Tipo</th><th>Mensaje</th><th>Origen</th><th>Plazo</th><th>Estado</th><th></th></tr></thead>
          <tbody>@for (m of items(); track m.id_retroalimentacion) {
            <tr>
              <td class="text-nowrap"><rs-estado [valor]="m.tipo" />@if (m.calificacion) { <div class="small text-warning-emphasis mt-1">{{ '★'.repeat(m.calificacion) }}<span class="text-secondary">{{ '★'.repeat(5 - m.calificacion) }}</span></div> }</td>
              <td style="max-width:26rem">@if (m.confidencial) { <span class="badge text-bg-dark me-1"><i class="bi bi-lock"></i></span> }{{ m.mensaje }}@if (m.respuesta) { <div class="small text-secondary mt-1"><i class="bi bi-reply me-1"></i>{{ m.respuesta }}</div> }</td>
              <td class="small">{{ m.hogar || 'Anónimo' }}@if (m.campana) { <div class="text-secondary">{{ m.campana }}</div> }</td>
              <td class="small text-nowrap">{{ m.fecha_limite | fecha }}
                @if (m.estado === 'Abierta' || m.estado === 'En revision') { <div [class]="m.vencida ? 'text-danger fw-semibold' : 'text-secondary'">{{ m.vencida ? 'Vencido hace ' + (-m.dias_para_vencer) + ' d' : 'Vence en ' + m.dias_para_vencer + ' d' }}</div> }</td>
              <td><rs-estado [valor]="m.estado" /></td>
              <td class="text-end">@if (auth.tiene('feedback:gestionar')) { <button class="btn btn-sm btn-outline-primary" type="button" (click)="gestion.set(m)">Atender</button> }</td></tr> }</tbody></table></div>
        <rs-paginacion [pagina]="pagina()" [paginas]="paginas()" [total]="total()" [tamano]="tamano" (cambia)="irA($event)" />
      }
    </div>
    @if (formulario()) { <rs-feedback-form (cerrar)="formulario.set(false)" (guardado)="formulario.set(false); cargar()" /> }
    @if (gestion(); as g) { <rs-feedback-gestion [item]="g" (cerrar)="gestion.set(null)" (guardado)="gestion.set(null); cargar()" /> }`,
})
export class RetroalimentacionPage extends ListaBase<Feedback> {
  protected readonly auth = inject(AuthService);
  private readonly api = inject(FeedbackService);
  protected readonly q = signal(''); protected readonly tipo = signal(''); protected readonly estado = signal(''); protected readonly vencidas = signal(false);
  protected readonly formulario = signal(false); protected readonly gestion = signal<Feedback | null>(null);
  constructor() { super(); this.cargar(); }
  protected override consultar(): Observable<Pagina<Feedback>> { return this.api.listar({ q: this.q(), tipo: this.tipo(), estado: this.estado(), vencidas: this.vencidas(), pagina: this.pagina(), tamano: this.tamano }); }
}
