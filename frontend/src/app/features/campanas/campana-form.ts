import { ChangeDetectionStrategy, Component, inject, input, OnInit, output, signal } from '@angular/core';
import { form, FormField, maxLength, min, minLength, required, validate } from '@angular/forms/signals';
import { firstValueFrom } from 'rxjs';
import { Campana, Categoria } from '../../core/models/api.models';
import { CampanaService } from '../../core/services/api.services';
import { AuthService } from '../../core/services/auth.service';
import { ConfirmService } from '../../core/services/confirm.service';
import { ToastService } from '../../core/services/toast.service';
import { aNumero, aTexto, enviar } from '../../core/util/form-utils';
import { Campo, Modal } from '../../shared/ui';

@Component({
  selector: 'rs-campana-form',
  imports: [FormField, Campo, Modal],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <rs-modal [titulo]="campana() ? 'Editar campaña' : 'Nueva campaña'" tamano="lg" (cerrar)="cerrar.emit()">
      @if (error(); as e) { <div class="alert alert-danger py-2 small" role="alert">{{ e }}</div> }
      <form id="f-campana" (submit)="guardar($event)" novalidate>
        <div class="row">
          <div class="col-md-8"><rs-campo etiqueta="Nombre" requerido [campo]="f.nombre"><input class="form-control" [formField]="f.nombre" /></rs-campo></div>
          <div class="col-md-4"><rs-campo etiqueta="Tipo de ayuda" requerido [campo]="f.id_categoria">
            <select class="form-select" [formField]="f.id_categoria"><option value="">Seleccione…</option>@for (c of categorias(); track c.id_categoria) { <option [value]="c.id_categoria">{{ c.nombre }}</option> }</select>
          </rs-campo></div>
        </div>
        <rs-campo etiqueta="Objetivo social" ayuda="¿Qué necesidad atiende? Se muestra en el portal público." [campo]="f.objetivo_social"><input class="form-control" [formField]="f.objetivo_social" /></rs-campo>
        <rs-campo etiqueta="Descripción" [campo]="f.descripcion"><textarea class="form-control" rows="2" [formField]="f.descripcion"></textarea></rs-campo>
        <div class="row">
          <div class="col-md-6"><rs-campo etiqueta="Inicio" requerido [campo]="f.fecha_inicio"><input class="form-control" type="date" [formField]="f.fecha_inicio" /></rs-campo></div>
          <div class="col-md-6"><rs-campo etiqueta="Fin" requerido [campo]="f.fecha_fin"><input class="form-control" type="date" [formField]="f.fecha_fin" /></rs-campo></div>
        </div>
        <div class="row">
          <div class="col-md-4"><rs-campo etiqueta="Meta de recaudación" requerido [campo]="f.meta_recaudacion"><input class="form-control" type="number" step="0.01" [formField]="f.meta_recaudacion" /></rs-campo></div>
          <div class="col-md-4"><rs-campo etiqueta="Meta de hogares" ayuda="Meta social (opcional)" [campo]="f.meta_hogares"><input class="form-control" type="number" [formField]="f.meta_hogares" /></rs-campo></div>
          <div class="col-md-4"><rs-campo etiqueta="Meta de unidades" ayuda="Meta física (opcional)" [campo]="f.meta_unidades"><input class="form-control" type="number" [formField]="f.meta_unidades" /></rs-campo></div>
        </div>
        <rs-campo etiqueta="Moneda" ayuda="No se mezclan monedas dentro de una campaña. No puede cambiarse si ya hay donaciones.">
          <select class="form-select" style="max-width:12rem" [formField]="f.moneda"><option value="PEN">PEN · Sol peruano</option><option value="USD">USD · Dólar</option></select>
        </rs-campo>
      </form>
      <div pie class="modal-footer border-0"><button type="button" class="btn btn-light" (click)="cerrar.emit()">Cancelar</button>
        <button type="submit" form="f-campana" class="btn btn-primary" [disabled]="enviando()">{{ enviando() ? 'Guardando…' : 'Guardar' }}</button></div>
    </rs-modal>`,
})
export class CampanaForm implements OnInit {
  readonly campana = input<Campana | null>(null);
  readonly categorias = input.required<Categoria[]>();
  readonly guardado = output<Campana>();
  readonly cerrar = output<void>();
  private readonly api = inject(CampanaService);
  private readonly toast = inject(ToastService);
  private readonly auth = inject(AuthService);
  private readonly confirm = inject(ConfirmService);

  protected readonly modelo = signal({
    nombre: '', descripcion: '', objetivo_social: '', id_categoria: '', fecha_inicio: '', fecha_fin: '', moneda: 'PEN',
    meta_recaudacion: null as number | null, meta_hogares: null as number | null, meta_unidades: null as number | null,
  });
  protected readonly f = form(this.modelo, (p) => {
    maxLength(p.nombre, 100, { message: 'Máximo 100 caracteres.' });
    maxLength(p.objetivo_social, 300, { message: 'Máximo 300 caracteres.' });
    maxLength(p.descripcion, 500, { message: 'Máximo 500 caracteres.' });
    required(p.nombre, { message: 'Escriba el nombre de la campaña.' });
    minLength(p.nombre, 3, { message: 'Use al menos 3 caracteres.' });
    required(p.id_categoria, { message: 'Seleccione el tipo de ayuda.' });
    required(p.fecha_inicio, { message: 'Indique la fecha de inicio.' });
    required(p.fecha_fin, { message: 'Indique la fecha de fin.' });
    validate(p.fecha_fin, ({ value, valueOf }) => (!value() || !valueOf(p.fecha_inicio) || value() >= valueOf(p.fecha_inicio) ? undefined : { kind: 'rango', message: 'La fecha de fin no puede ser anterior al inicio.' }));
    required(p.meta_recaudacion, { message: 'Indique la meta de recaudación.' });
    min(p.meta_recaudacion, 1, { message: 'La meta debe ser mayor que cero.' });
    min(p.meta_hogares, 1, { message: 'Debe ser mayor que cero.' });
    min(p.meta_unidades, 1, { message: 'Debe ser mayor que cero.' });
  });
  protected readonly enviando = signal(false);
  protected readonly error = signal<string | null>(null);

  ngOnInit(): void {
    const c = this.campana();
    if (c) {
      this.modelo.set({
        nombre: c.nombre, descripcion: c.descripcion ?? '', objetivo_social: c.objetivo_social ?? '', id_categoria: String(c.id_categoria),
        fecha_inicio: c.fecha_inicio, fecha_fin: c.fecha_fin, moneda: c.moneda, meta_recaudacion: c.meta_recaudacion, meta_hogares: c.meta_hogares, meta_unidades: c.meta_unidades,
      });
    }
  }

  protected async guardar(ev: Event): Promise<void> {
    ev.preventDefault();
    await enviar(this.f, { enviando: this.enviando, error: this.error }, async () => {
      const m = this.modelo();
      const c = this.campana();
      const r = await firstValueFrom(this.api.guardar(c?.id_campana ?? null, {
        nombre: m.nombre, descripcion: aTexto(m.descripcion), objetivo_social: aTexto(m.objetivo_social), id_categoria: Number(m.id_categoria),
        fecha_inicio: m.fecha_inicio, fecha_fin: m.fecha_fin, meta_recaudacion: m.meta_recaudacion, meta_hogares: aNumero(m.meta_hogares),
        meta_unidades: aNumero(m.meta_unidades), moneda: m.moneda, id_responsable: c ? c.id_responsable : this.auth.usuario()?.id_usuario ?? null,
      }));
      this.toast.ok(c ? 'Campaña actualizada.' : 'Campaña creada como borrador. Actívela cuando esté lista.');
      this.guardado.emit(r);
    }, this.confirm);
  }
}
