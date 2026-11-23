import { ChangeDetectionStrategy, Component, computed, inject, OnInit, output, signal } from '@angular/core';
import { form, FormField, maxLength, min, required, validate } from '@angular/forms/signals';
import { firstValueFrom, forkJoin } from 'rxjs';
import { toApiError } from '../../core/models/api-error';
import { Campana, Donacion, Donante, MetodoPago } from '../../core/models/api.models';
import { CampanaService, CatalogoService, DonacionService, DonanteService } from '../../core/services/api.services';
import { AuthService } from '../../core/services/auth.service';
import { ConfirmService } from '../../core/services/confirm.service';
import { ToastService } from '../../core/services/toast.service';
import { hoyISO } from '../../core/util/format';
import { aTexto, enviar } from '../../core/util/form-utils';
import { Campo, Modal } from '../../shared/ui';

@Component({
  selector: 'rs-donacion-form',
  imports: [FormField, Campo, Modal],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <rs-modal titulo="Registrar donación" (cerrar)="cerrar.emit()">
      @if (errorCarga(); as e) { <div class="alert alert-danger" role="alert">{{ e }}</div> }
      @if (error(); as e) { <div class="alert alert-danger py-2 small" role="alert">{{ e }}</div> }
      <form id="f-donacion" (submit)="guardar($event)" novalidate>
        <rs-campo etiqueta="Donante" requerido [campo]="f.id_donante"><select class="form-select" [formField]="f.id_donante"><option value="">Seleccione…</option>@for (d of donantes(); track d.id_donante) { <option [value]="d.id_donante">{{ d.nombre }}</option> }</select></rs-campo>
        <rs-campo etiqueta="Campaña" requerido [campo]="f.id_campana" ayuda="Solo campañas activas aceptan donaciones."><select class="form-select" [formField]="f.id_campana"><option value="">Seleccione…</option>@for (c of campanas(); track c.id_campana) { <option [value]="c.id_campana">{{ c.nombre }}</option> }</select></rs-campo>
        <div class="row">
          <div class="col-6"><rs-campo etiqueta="Fecha" requerido [campo]="f.fecha"><input class="form-control" type="date" [formField]="f.fecha" /></rs-campo></div>
          <div class="col-6"><rs-campo [etiqueta]="'Monto' + (moneda() ? ' (' + moneda() + ')' : '')" requerido [campo]="f.monto"><input class="form-control" type="number" step="0.01" inputmode="decimal" [formField]="f.monto" /></rs-campo></div>
        </div>
        <div class="row">
          <div class="col-6"><rs-campo etiqueta="Método de pago" requerido [campo]="f.id_metodo_pago"><select class="form-select" [formField]="f.id_metodo_pago"><option value="">Seleccione…</option>@for (m of metodos(); track m.id_metodo_pago) { <option [value]="m.id_metodo_pago">{{ m.nombre }}</option> }</select></rs-campo></div>
          <div class="col-6"><rs-campo [etiqueta]="'N.º de operación' + (requiereReferencia() ? '' : ' (opcional)')" [requerido]="requiereReferencia()" [campo]="f.referencia" ayuda="Evita registrar dos veces el mismo voucher."><input class="form-control" [formField]="f.referencia" /></rs-campo></div>
        </div>
        <rs-campo etiqueta="Observación" [campo]="f.observacion"><input class="form-control" [formField]="f.observacion" /></rs-campo>
        @if (auth.tiene('donaciones:verificar')) {
          <div class="form-check"><input class="form-check-input" type="checkbox" id="confirmar-ahora" [formField]="f.confirmar" /><label class="form-check-label small" for="confirmar-ahora">Ya verifiqué el pago: registrar como <strong>confirmada</strong></label></div>
        } @else { <p class="small text-secondary mb-0"><i class="bi bi-info-circle me-1"></i>Quedará <strong>pendiente</strong> hasta que alguien verifique el pago.</p> }
      </form>
      <div pie class="modal-footer border-0"><button type="button" class="btn btn-light" (click)="cerrar.emit()">Cancelar</button>
        <button type="submit" form="f-donacion" class="btn btn-primary" [disabled]="enviando()">{{ enviando() ? 'Guardando…' : 'Registrar' }}</button></div>
    </rs-modal>`,
})
export class DonacionForm implements OnInit {
  readonly guardado = output<Donacion>();
  readonly cerrar = output<void>();
  protected readonly auth = inject(AuthService);
  private readonly api = inject(DonacionService);
  private readonly donanteApi = inject(DonanteService);
  private readonly campanaApi = inject(CampanaService);
  private readonly catalogoApi = inject(CatalogoService);
  private readonly toast = inject(ToastService);
  private readonly confirm = inject(ConfirmService);

  protected readonly donantes = signal<Donante[]>([]);
  protected readonly campanas = signal<Campana[]>([]);
  protected readonly metodos = signal<MetodoPago[]>([]);
  protected readonly errorCarga = signal<string | null>(null);
  protected readonly modelo = signal({ id_donante: '', id_campana: '', fecha: hoyISO(), monto: null as number | null, id_metodo_pago: '', referencia: '', observacion: '', confirmar: false });

  private readonly campana = computed(() => this.campanas().find((c) => String(c.id_campana) === this.modelo().id_campana));
  protected readonly moneda = computed(() => this.campana()?.moneda ?? '');
  protected readonly requiereReferencia = computed(() => this.metodos().find((m) => String(m.id_metodo_pago) === this.modelo().id_metodo_pago)?.requiere_referencia ?? false);

  protected readonly f = form(this.modelo, (p) => {
    maxLength(p.referencia, 60, { message: 'Máximo 60 caracteres.' });
    maxLength(p.observacion, 200, { message: 'Máximo 200 caracteres.' });
    required(p.id_donante, { message: 'Seleccione el donante.' });
    required(p.id_campana, { message: 'Seleccione la campaña.' });
    required(p.fecha, { message: 'Indique la fecha.' });
    validate(p.fecha, ({ value }) => (value() > hoyISO() ? { kind: 'futura', message: 'La fecha no puede ser futura.' } : undefined));
    validate(p.fecha, ({ value }) => { const c = this.campana(); return c && value() && (value() < c.fecha_inicio || value() > c.fecha_fin) ? { kind: 'periodo', message: `Debe estar dentro del periodo de la campaña (${c.fecha_inicio} a ${c.fecha_fin}).` } : undefined; });
    required(p.monto, { message: 'Indique el monto.' });
    min(p.monto, 0.01, { message: 'El monto debe ser mayor que cero.' });
    required(p.id_metodo_pago, { message: 'Seleccione el método de pago.' });
    validate(p.referencia, ({ value }) => (this.requiereReferencia() && !value().trim() ? { kind: 'referencia', message: 'Este método exige el número de operación.' } : undefined));
  });
  protected readonly enviando = signal(false);
  protected readonly error = signal<string | null>(null);

  ngOnInit(): void {
    forkJoin([this.donanteApi.listar({ activo: true, tamano: 100 }), this.campanaApi.listar({ estado: 'Activa', tamano: 100 }), this.catalogoApi.metodosPago()]).subscribe({
      next: ([d, c, m]) => { this.donantes.set(d.items); this.campanas.set(c.items); this.metodos.set(m); },
      error: (e) => this.errorCarga.set(toApiError(e).message),
    });
  }

  protected async guardar(ev: Event): Promise<void> {
    ev.preventDefault();
    await enviar(this.f, { enviando: this.enviando, error: this.error }, async (confirmado) => {
      const m = this.modelo();
      const r = await firstValueFrom(this.api.registrar({
        id_donante: Number(m.id_donante), id_campana: Number(m.id_campana), fecha: m.fecha, monto: m.monto, id_metodo_pago: Number(m.id_metodo_pago),
        referencia: aTexto(m.referencia), observacion: aTexto(m.observacion), confirmar: m.confirmar && this.auth.tiene('donaciones:verificar'), confirmar_duplicado: confirmado,
      }));
      this.toast.ok(r.estado === 'Confirmada' ? 'Donación registrada y confirmada.' : 'Donación registrada. Queda pendiente de verificación.');
      this.guardado.emit(r);
    }, this.confirm);
  }
}
