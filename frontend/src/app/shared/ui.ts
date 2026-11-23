import { booleanAttribute, ChangeDetectionStrategy, Component, computed, effect, ElementRef, inject, input, OnDestroy, output, signal, viewChild } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ConfirmService } from '../core/services/confirm.service';
import { ToastService } from '../core/services/toast.service';
import { etiqueta } from '../core/util/labels';

@Component({
  selector: 'rs-encabezado',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="d-flex flex-wrap align-items-end justify-content-between gap-3 mb-4">
      <div>
        <h1 class="rs-page-title">{{ titulo() }}</h1>
        @if (subtitulo()) { <p class="rs-page-sub">{{ subtitulo() }}</p> }
      </div>
      <div class="d-flex flex-wrap gap-2 align-items-center"><ng-content /></div>
    </div>`,
})
export class Encabezado { readonly titulo = input.required<string>(); readonly subtitulo = input(''); }

@Component({
  selector: 'rs-kpi',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="card rs-kpi" [class]="'acento-' + acento()">
      <div class="rs-kpi-label">@if (icono()) { <i class="bi" [class]="'bi-' + icono()"></i> }{{ etiqueta() }}</div>
      <div class="rs-kpi-value">{{ valor() }}</div>
      @if (pista()) { <div class="rs-kpi-hint">{{ pista() }}</div> }
    </div>`,
})
export class Kpi {
  readonly etiqueta = input.required<string>(); readonly valor = input.required<string>();
  readonly pista = input(''); readonly icono = input(''); readonly acento = input<'dar' | 'campana' | 'recibe' | 'alerta' | 'neutro'>('neutro');
}

@Component({
  selector: 'rs-estado',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<span class="badge fw-medium" [class]="e().clase">@if (conIcono() && e().icono) { <i class="bi me-1" [class]="'bi-' + e().icono"></i> }{{ e().texto }}</span>`,
})
export class Estado {
  readonly valor = input.required<string>(); readonly conIcono = input(true);
  protected readonly e = computed(() => etiqueta(this.valor()));
}

@Component({
  selector: 'rs-vacio',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<div class="rs-empty"><i class="bi" [class]="'bi-' + icono()"></i><div class="fw-semibold text-body">{{ titulo() }}</div>@if (texto()) { <div class="small">{{ texto() }}</div> }<ng-content /></div>`,
})
export class Vacio { readonly icono = input('inbox'); readonly titulo = input('No hay registros'); readonly texto = input(''); }

@Component({
  selector: 'rs-carga',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<div class="p-3 d-grid gap-3" aria-busy="true" aria-label="Cargando">@for (f of filas(); track f) { <div class="rs-skeleton" [style.width.%]="60 + (f * 13) % 40"></div> }</div>`,
})
export class Carga { readonly n = input(5); protected readonly filas = computed(() => Array.from({ length: this.n() }, (_, i) => i)); }

@Component({
  selector: 'rs-paginacion',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (total() > 0) {
      <div class="d-flex flex-wrap justify-content-between align-items-center gap-2 px-3 py-2 border-top small text-secondary">
        <span class="tabular">{{ desde() }}–{{ hasta() }} de {{ total() }}</span>
        <div class="btn-group btn-group-sm" role="group" aria-label="Paginación">
          <button type="button" class="btn btn-outline-secondary" [disabled]="pagina() <= 1" (click)="cambia.emit(pagina() - 1)" aria-label="Página anterior"><i class="bi bi-chevron-left"></i></button>
          <span class="btn btn-outline-secondary disabled tabular">{{ pagina() }} / {{ paginas() }}</span>
          <button type="button" class="btn btn-outline-secondary" [disabled]="pagina() >= paginas()" (click)="cambia.emit(pagina() + 1)" aria-label="Página siguiente"><i class="bi bi-chevron-right"></i></button>
        </div>
      </div>
    }`,
})
export class Paginacion {
  readonly pagina = input.required<number>(); readonly paginas = input.required<number>(); readonly total = input.required<number>(); readonly tamano = input(15);
  readonly cambia = output<number>();
  protected readonly desde = computed(() => (this.pagina() - 1) * this.tamano() + 1);
  protected readonly hasta = computed(() => Math.min(this.pagina() * this.tamano(), this.total()));
}

/** Modal propio (clases de Bootstrap, sin su JavaScript). Escape cierra; el foco pasa al primer control. */
@Component({
  selector: 'rs-modal',
  changeDetection: ChangeDetectionStrategy.OnPush,
  host: { '(document:keydown.escape)': 'cerrar.emit()' },
  template: `
    <div class="rs-modal-backdrop" (click)="$event.stopPropagation()"></div>
    <div class="modal rs-modal" tabindex="-1" role="dialog" aria-modal="true" [attr.aria-label]="titulo()">
      <div class="modal-dialog modal-dialog-centered modal-dialog-scrollable" [class]="'modal-' + tamano()" #dialogo>
        <div class="modal-content">
          <div class="modal-header border-0 pb-0">
            <h2 class="modal-title fs-5">{{ titulo() }}</h2>
            <button type="button" class="btn-close" aria-label="Cerrar" (click)="cerrar.emit()"></button>
          </div>
          <div class="modal-body"><ng-content /></div>
          <ng-content select="[pie]" />
        </div>
      </div>
    </div>`,
})
export class Modal implements OnDestroy {
  readonly titulo = input.required<string>(); readonly tamano = input<'sm' | 'md' | 'lg' | 'xl'>('md');
  readonly cerrar = output<void>();
  private readonly dialogo = viewChild<ElementRef<HTMLElement>>('dialogo');
  constructor() {
    document.body.classList.add('modal-open-rs');
    effect(() => {
      const el = this.dialogo()?.nativeElement;
      queueMicrotask(() => el?.querySelector<HTMLElement>('input:not([type=hidden]), select, textarea')?.focus());
    });
  }
  ngOnDestroy(): void { document.body.classList.remove('modal-open-rs'); }
}

/** Campo de formulario con etiqueta y mensaje de error de Signal Forms (se muestra al tocar o enviar). */
/** Lo mínimo que `rs-campo` necesita de un campo de Signal Forms (acepta cualquier FieldTree, sea cual sea su tipo de valor). */
export type CampoLike = () => { touched: () => boolean; errors: () => readonly { message?: string }[] };

@Component({
  selector: 'rs-campo',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <label class="rs-field d-block mb-3" [class.has-error]="error() !== null">
      <span class="form-label d-block">{{ etiqueta() }}@if (requerido()) { <span class="text-danger" aria-hidden="true"> *</span> }</span>
      <ng-content />
      @if (error(); as msg) { <span class="rs-field-error d-block" role="alert">{{ msg }}</span> }
      @else if (ayuda()) { <span class="rs-hint d-block">{{ ayuda() }}</span> }
    </label>`,
})
export class Campo {
  readonly etiqueta = input.required<string>();
  readonly campo = input<CampoLike | null>(null);
  readonly ayuda = input(''); readonly requerido = input(false, { transform: booleanAttribute });
  protected readonly error = computed(() => {
    const f = this.campo();
    if (!f) return null;
    const s = f();
    return s.touched() && s.errors().length > 0 ? (s.errors()[0].message ?? 'El valor no es válido.') : null;
  });
}

@Component({
  selector: 'rs-avisos',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="rs-toasts" aria-live="polite">
      @for (a of avisos.avisos(); track a.id) {
        <div class="rs-toast" [class]="a.tipo" role="status">
          <i class="bi mt-1" [class]="a.tipo === 'ok' ? 'bi-check-circle-fill text-dar' : a.tipo === 'error' ? 'bi-x-octagon-fill text-danger' : 'bi-exclamation-triangle-fill text-warning'"></i>
          <div class="flex-grow-1 small">{{ a.texto }}</div>
          <button type="button" class="btn-close btn-sm" aria-label="Cerrar aviso" (click)="avisos.cerrar(a.id)"></button>
        </div>
      }
    </div>`,
})
export class Avisos { protected readonly avisos = inject(ToastService); }

@Component({
  selector: 'rs-confirmacion',
  imports: [FormsModule, Modal],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (svc.pedido(); as p) {
      <rs-modal [titulo]="p.titulo" tamano="sm" (cerrar)="svc.resolver(false)">
        @if (p.mensaje) { <p class="mb-3">{{ p.mensaje }}</p> }
        @if (p.pedirMotivo) {
          <label class="d-block"><span class="form-label d-block">{{ p.motivoEtiqueta }} <span class="text-danger">*</span></span>
            <textarea class="form-control" rows="3" maxlength="200" [ngModel]="motivo()" (ngModelChange)="motivo.set($event)"></textarea></label>
        }
        <div pie class="modal-footer border-0 pt-0">
          <button type="button" class="btn btn-light" (click)="svc.resolver(false)">Cancelar</button>
          <button type="button" class="btn" [class]="p.peligro ? 'btn-danger' : 'btn-primary'" [disabled]="p.pedirMotivo && !motivo().trim()" (click)="aceptar()">{{ p.confirmar }}</button>
        </div>
      </rs-modal>
    }`,
})
export class Confirmacion {
  protected readonly svc = inject(ConfirmService);
  protected readonly motivo = signal('');
  protected aceptar(): void { const m = this.motivo(); this.motivo.set(''); this.svc.resolver(true, m); }
}

export const UI = [Encabezado, Kpi, Estado, Vacio, Carga, Paginacion, Modal, Campo] as const;
