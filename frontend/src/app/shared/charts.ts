import { ChangeDetectionStrategy, Component, computed, input } from '@angular/core';

export interface DatoBarra { etiqueta: string; valor: number; texto?: string; color?: string }

/** Lista de barras horizontales (HTML/CSS: accesible y se adapta al ancho). */
@Component({
  selector: 'rs-barras',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="rs-barlist" role="list">
      @for (d of datos(); track d.etiqueta) {
        <div class="rs-bar-row" role="listitem">
          <span class="text-truncate" [title]="d.etiqueta">{{ d.etiqueta }}</span>
          <div class="rs-bar-track" role="img" [attr.aria-label]="d.etiqueta + ': ' + (d.texto ?? d.valor)"><div class="rs-bar-fill" [style.width.%]="ancho(d.valor)" [style.background]="d.color ?? color()"></div></div>
          <span class="tabular fw-semibold text-end">{{ d.texto ?? d.valor }}</span>
        </div>
      }
    </div>`,
})
export class Barras {
  readonly datos = input.required<DatoBarra[]>(); readonly color = input('var(--rs-campana)');
  private readonly maximo = computed(() => Math.max(1, ...this.datos().map((d) => d.valor)));
  protected ancho(v: number): number { return Math.max(2, (v / this.maximo()) * 100); }
}

/** Serie temporal en SVG: área o columnas. Sin librerías: se calcula a mano. */
@Component({
  selector: 'rs-serie',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <svg class="rs-chart-svg" viewBox="0 0 600 190" role="img" [attr.aria-label]="descripcion()">
      @for (g of rejilla(); track g.y) {
        <line [attr.x1]="30" [attr.x2]="596" [attr.y1]="g.y" [attr.y2]="g.y" stroke="#e4e7ec" stroke-dasharray="3 4" />
        <text [attr.x]="24" [attr.y]="g.y + 3" text-anchor="end">{{ g.t }}</text>
      }
      @if (tipo() === 'area') {
        <path [attr.d]="area()" [attr.fill]="color()" fill-opacity="0.14" />
        <path [attr.d]="linea()" fill="none" [attr.stroke]="color()" stroke-width="2.2" stroke-linejoin="round" stroke-linecap="round" />
        @for (p of puntos(); track p.x) { <circle [attr.cx]="p.x" [attr.cy]="p.y" r="3" [attr.fill]="color()" stroke="#fff" stroke-width="1.5"><title>{{ p.tip }}</title></circle> }
      } @else {
        @for (p of puntos(); track p.x) { <rect [attr.x]="p.x - ancho() / 2" [attr.y]="p.y" [attr.width]="ancho()" [attr.height]="160 - p.y" rx="3" [attr.fill]="color()"><title>{{ p.tip }}</title></rect> }
      }
      @for (p of puntos(); track p.x) { <text [attr.x]="p.x" y="180" text-anchor="middle">{{ p.etiqueta }}</text> }
    </svg>`,
})
export class Serie {
  readonly etiquetas = input.required<string[]>(); readonly valores = input.required<number[]>();
  readonly tipo = input<'area' | 'columnas'>('area'); readonly color = input('var(--rs-dar)');
  readonly formato = input<(n: number) => string>((n) => String(n)); readonly descripcion = input('Serie mensual');
  private readonly max = computed(() => { const m = Math.max(...this.valores(), 0); return m <= 0 ? 1 : m; });
  protected readonly ancho = computed(() => Math.min(28, 520 / Math.max(1, this.valores().length) - 10));
  protected readonly puntos = computed(() => {
    const n = this.valores().length;
    const paso = n > 1 ? 540 / (n - 1) : 0;
    return this.valores().map((v, i) => ({
      x: n > 1 ? 40 + i * paso : 320, y: 160 - (v / this.max()) * 140, etiqueta: this.etiquetas()[i] ?? '', tip: `${this.etiquetas()[i]}: ${this.formato()(v)}`,
    }));
  });
  protected readonly linea = computed(() => this.puntos().map((p, i) => `${i ? 'L' : 'M'}${p.x.toFixed(1)} ${p.y.toFixed(1)}`).join(' '));
  protected readonly area = computed(() => {
    const p = this.puntos();
    return p.length ? `${this.linea()} L${p[p.length - 1].x.toFixed(1)} 160 L${p[0].x.toFixed(1)} 160 Z` : '';
  });
  protected readonly rejilla = computed(() => [0, 0.5, 1].map((f) => ({ y: 160 - f * 140, t: f === 0 ? '0' : this.compacto(this.max() * f) })));
  private compacto(n: number): string { return new Intl.NumberFormat('es-PE', { notation: 'compact', maximumFractionDigits: 1 }).format(n); }
}

/** Anillo de progreso (0-100). */
@Component({
  selector: 'rs-anillo',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <svg [attr.width]="tam()" [attr.height]="tam()" viewBox="0 0 100 100" role="img" [attr.aria-label]="etiqueta() + ': ' + (valor() ?? 0) + ' %'">
      <circle cx="50" cy="50" r="42" fill="none" stroke="#eef0f3" stroke-width="10" />
      <circle cx="50" cy="50" r="42" fill="none" [attr.stroke]="color()" stroke-width="10" stroke-linecap="round"
              [attr.stroke-dasharray]="trazo()" transform="rotate(-90 50 50)" style="transition: stroke-dasharray .6s ease" />
      <text x="50" y="55" text-anchor="middle" font-size="19" font-weight="700" fill="var(--rs-ink)">{{ texto() }}</text>
    </svg>`,
})
export class Anillo {
  readonly valor = input.required<number | null>(); readonly color = input('var(--rs-recibe)'); readonly tam = input(96); readonly etiqueta = input('Avance');
  protected readonly texto = computed(() => (this.valor() === null ? '—' : `${Math.round(this.valor() ?? 0)}%`));
  protected readonly trazo = computed(() => { const c = 2 * Math.PI * 42; const f = Math.min(100, Math.max(0, this.valor() ?? 0)) / 100; return `${(c * f).toFixed(1)} ${c.toFixed(1)}`; });
}

/** Barra de progreso con etiqueta. Un valor sobre 100 se rellena completo (sobrefinanciada). */
@Component({
  selector: 'rs-progreso',
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="d-flex justify-content-between small mb-1"><span class="text-secondary">{{ etiqueta() }}</span><span class="fw-semibold tabular">{{ texto() }}</span></div>
    <div class="progress" style="height:.5rem" role="progressbar" [attr.aria-valuenow]="valor()" aria-valuemin="0" aria-valuemax="100" [attr.aria-label]="etiqueta()">
      <div class="progress-bar" [style.width.%]="ancho()" [style.background]="color()"></div>
    </div>`,
})
export class Progreso {
  readonly valor = input.required<number | null>(); readonly etiqueta = input(''); readonly texto = input(''); readonly color = input('var(--rs-campana)');
  protected readonly ancho = computed(() => Math.min(100, Math.max(0, this.valor() ?? 0)));
}

export const GRAFICOS = [Barras, Serie, Anillo, Progreso] as const;
