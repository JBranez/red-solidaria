import { ChangeDetectionStrategy, Component, computed, effect, inject, OnInit, output, signal } from '@angular/core';
import { form, FormField, max, maxLength, min, required, validate } from '@angular/forms/signals';
import { firstValueFrom, forkJoin } from 'rxjs';
import { toApiError } from '../../core/models/api-error';
import { Beneficiario, Campana, Entrega, Necesidad, Voluntario } from '../../core/models/api.models';
import { BeneficiarioService, CampanaService, EntregaService, NecesidadService, VoluntarioService } from '../../core/services/api.services';
import { AuthService } from '../../core/services/auth.service';
import { ConfirmService } from '../../core/services/confirm.service';
import { ToastService } from '../../core/services/toast.service';
import { hoyISO } from '../../core/util/format';
import { aNumero, aTexto, enviar } from '../../core/util/form-utils';
import { Campo, Modal } from '../../shared/ui';

@Component({
  selector: 'rs-entrega-form',
  imports: [FormField, Campo, Modal],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <rs-modal titulo="Registrar entrega" (cerrar)="cerrar.emit()">
      @if (errorCarga(); as e) { <div class="alert alert-danger" role="alert">{{ e }}</div> }
      @if (error(); as e) { <div class="alert alert-danger py-2 small" role="alert">{{ e }}</div> }
      <form id="f-entrega" (submit)="guardar($event)" novalidate>
        <rs-campo etiqueta="Campaña" requerido [campo]="f.id_campana" ayuda="Solo campañas activas."><select class="form-select" [formField]="f.id_campana"><option value="">Seleccione…</option>@for (c of campanas(); track c.id_campana) { <option [value]="c.id_campana">{{ c.nombre }}</option> }</select></rs-campo>
        <div class="row">
          <div class="col-md-6"><rs-campo etiqueta="Hogar" requerido [campo]="f.id_beneficiario"><select class="form-select" [formField]="f.id_beneficiario"><option value="">Seleccione…</option>@for (h of hogares(); track h.id_beneficiario) { <option [value]="h.id_beneficiario">{{ h.nombre_completo }} · {{ h.sector }}</option> }</select></rs-campo></div>
          <div class="col-md-6"><rs-campo etiqueta="Voluntario que entrega" requerido [campo]="f.id_voluntario"><select class="form-select" [formField]="f.id_voluntario"><option value="">Seleccione…</option>@for (v of voluntarios(); track v.id_voluntario) { <option [value]="v.id_voluntario">{{ v.nombre_completo }}</option> }</select></rs-campo></div>
        </div>
        @if (necesidades().length) {
          <rs-campo etiqueta="¿Atiende una necesidad registrada?" ayuda="Al entregarse, la necesidad se marca como cubierta." [campo]="f.id_necesidad"><select class="form-select" [formField]="f.id_necesidad"><option value="">No / otra</option>@for (n of necesidades(); track n.id_necesidad) { <option [value]="n.id_necesidad">{{ n.categoria }} · urgencia {{ n.urgencia === 'Critica' ? 'crítica' : n.urgencia.toLowerCase() }}</option> }</select></rs-campo>
        }
        <div class="row">
          <div class="col-4"><rs-campo etiqueta="Fecha" requerido [campo]="f.fecha"><input class="form-control" type="date" [formField]="f.fecha" /></rs-campo></div>
          <div class="col-4"><rs-campo etiqueta="Cantidad" requerido [campo]="f.cantidad" ayuda="Unidades"><input class="form-control" type="number" [formField]="f.cantidad" /></rs-campo></div>
          <div class="col-4"><rs-campo etiqueta="Situación" requerido [campo]="f.estado"><select class="form-select" [formField]="f.estado"><option value="Entregada">Ya entregada</option><option value="Programada">Programar</option></select></rs-campo></div>
        </div>
        <rs-campo etiqueta="Detalle" ayuda="Qué se entregó (canasta, kit, abrigo…)." [campo]="f.detalle"><input class="form-control" [formField]="f.detalle" /></rs-campo>
      </form>
      <div pie class="modal-footer border-0"><button type="button" class="btn btn-light" (click)="cerrar.emit()">Cancelar</button><button type="submit" form="f-entrega" class="btn btn-primary" [disabled]="enviando()">{{ enviando() ? 'Guardando…' : 'Registrar' }}</button></div>
    </rs-modal>`,
})
export class EntregaForm implements OnInit {
  readonly guardado = output<Entrega>();
  readonly cerrar = output<void>();
  private readonly auth = inject(AuthService);
  private readonly api = inject(EntregaService);
  private readonly campanaApi = inject(CampanaService);
  private readonly hogarApi = inject(BeneficiarioService);
  private readonly voluntarioApi = inject(VoluntarioService);
  private readonly necesidadApi = inject(NecesidadService);
  private readonly toast = inject(ToastService);
  private readonly confirm = inject(ConfirmService);

  protected readonly campanas = signal<Campana[]>([]);
  protected readonly hogares = signal<Beneficiario[]>([]);
  protected readonly voluntarios = signal<Voluntario[]>([]);
  protected readonly necesidades = signal<Necesidad[]>([]);
  protected readonly errorCarga = signal<string | null>(null);
  protected readonly modelo = signal({ id_campana: '', id_beneficiario: '', id_voluntario: '', id_necesidad: '', fecha: hoyISO(), cantidad: null as number | null, estado: 'Entregada', detalle: '' });
  private readonly campana = computed(() => this.campanas().find((c) => String(c.id_campana) === this.modelo().id_campana));

  protected readonly f = form(this.modelo, (p) => {
    maxLength(p.detalle, 200, { message: 'Máximo 200 caracteres.' });
    required(p.id_campana, { message: 'Seleccione la campaña.' });
    required(p.id_beneficiario, { message: 'Seleccione el hogar.' });
    required(p.id_voluntario, { message: 'Seleccione el voluntario.' });
    required(p.fecha, { message: 'Indique la fecha.' });
    validate(p.fecha, ({ value, valueOf }) => {
      const hoy = hoyISO(); const estado = valueOf(p.estado);
      if (estado === 'Entregada' && value() > hoy) return { kind: 'futura', message: 'Una entrega ya realizada no puede tener fecha futura. Use «Programar».' };
      if (estado === 'Programada' && value() < hoy) return { kind: 'pasada', message: 'Una entrega programada debe ser de hoy en adelante.' };
      const c = this.campana();
      return c && value() && (value() < c.fecha_inicio || value() > c.fecha_fin) ? { kind: 'periodo', message: `Debe estar dentro del periodo de la campaña (${c.fecha_inicio} a ${c.fecha_fin}).` } : undefined;
    });
    required(p.cantidad, { message: 'Indique la cantidad.' });
    min(p.cantidad, 1, { message: 'Mínimo 1 unidad.' }); max(p.cantidad, 1000, { message: 'Máximo 1000 unidades por entrega.' });
  });
  protected readonly enviando = signal(false);
  protected readonly error = signal<string | null>(null);

  constructor() {
    // Al elegir hogar, se ofrecen sus necesidades abiertas (si el rol puede verlas) de la misma categoría que la campaña
    effect(() => {
      const hogar = this.modelo().id_beneficiario; const c = this.campana();
      if (!hogar || !c || !this.auth.tiene('necesidades:leer')) { this.necesidades.set([]); return; }
      this.necesidadApi.listar({ id_beneficiario: hogar, solo_abiertas: true, id_categoria: c.id_categoria, tamano: 20 }).subscribe({ next: (r) => this.necesidades.set(r.items), error: () => this.necesidades.set([]) });
    });
  }

  ngOnInit(): void {
    forkJoin([this.campanaApi.listar({ estado: 'Activa', tamano: 100 }), this.hogarApi.listar({ activo: true, tamano: 100 }), this.voluntarioApi.listar({ activo: true, tamano: 100 })]).subscribe({
      next: ([c, h, v]) => { this.campanas.set(c.items); this.hogares.set(h.items); this.voluntarios.set(v.items); },
      error: (e) => this.errorCarga.set(toApiError(e).message),
    });
  }

  protected async guardar(ev: Event): Promise<void> {
    ev.preventDefault();
    await enviar(this.f, { enviando: this.enviando, error: this.error }, async (confirmado) => {
      const m = this.modelo();
      const r = await firstValueFrom(this.api.registrar({
        id_campana: Number(m.id_campana), id_beneficiario: Number(m.id_beneficiario), id_voluntario: Number(m.id_voluntario), id_necesidad: aNumero(m.id_necesidad),
        fecha: m.fecha, cantidad: m.cantidad, estado: m.estado, detalle: aTexto(m.detalle), confirmar_repetida: confirmado,
      }));
      this.toast.ok(r.estado === 'Programada' ? 'Entrega programada.' : 'Entrega registrada.');
      this.guardado.emit(r);
    }, this.confirm);
  }
}
