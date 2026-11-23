import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { forkJoin } from 'rxjs';
import { toApiError } from '../../core/models/api-error';
import { PublicoCampana, PublicoResumen } from '../../core/models/api.models';
import { PublicoService } from '../../core/services/api.services';
import { AuthService } from '../../core/services/auth.service';
import { FORMATOS } from '../../core/util/format';
import { Barras, DatoBarra, Progreso } from '../../shared/charts';
import { Estado } from '../../shared/ui';

/** Portal público: SOLO cifras agregadas. Sin nombres de donantes ni de hogares; sectores pequeños se ocultan. */
@Component({
  selector: 'rs-transparencia',
  imports: [RouterLink, Estado, Barras, Progreso, ...FORMATOS],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <header class="rs-hero">
      <nav class="container py-3 d-flex align-items-center justify-content-between position-relative" style="z-index:1" aria-label="Portal público">
        <a routerLink="/transparencia" class="d-flex align-items-center text-white fw-semibold text-decoration-none"><span class="rs-brand-mark" aria-hidden="true"><i class="bi bi-diagram-3-fill"></i></span>Red Solidaria</a>
        <a class="btn btn-sm btn-outline-light" [routerLink]="auth.autenticado() ? auth.rutaInicial() : '/acceso'">{{ auth.autenticado() ? 'Ir a la aplicación' : 'Ingresar' }}</a>
      </nav>
      <div class="container pt-4 pb-5 position-relative" style="z-index:1">
        <h1 class="display-5 fw-bold mb-2" style="letter-spacing:-.04em">Transparencia</h1>
        <p class="fs-6 mb-5" style="max-width:56ch;color:#cbd5e1">Cuánto se recaudó, en qué se usó y a cuántos hogares llegó la ayuda. Cifras verificadas, actualizadas al cierre de cada operación.</p>
        @if (resumen(); as r) {
          <div class="row g-4">
            <div class="col-6 col-md-3"><div class="rs-cifra">{{ r.totales.recaudado_confirmado | moneda: r.totales.moneda }}</div><div class="rs-cifra-label">donaciones verificadas</div></div>
            <div class="col-6 col-md-3"><div class="rs-cifra">{{ r.totales.gastado_aprobado | moneda: r.totales.moneda }}</div><div class="rs-cifra-label">gasto aprobado y documentado</div></div>
            <div class="col-6 col-md-3"><div class="rs-cifra">{{ r.totales.hogares_atendidos | num }}</div><div class="rs-cifra-label">hogares atendidos</div></div>
            <div class="col-6 col-md-3"><div class="rs-cifra">{{ r.totales.entregas_realizadas | num }}</div><div class="rs-cifra-label">entregas realizadas por {{ r.totales.voluntarios_participantes }} voluntarios</div></div>
          </div>
        } @else if (!error()) { <div class="rs-skeleton" style="height:4rem;max-width:40rem;opacity:.25"></div> }
      </div>
    </header>

    <main class="container py-5">
      @if (error(); as e) { <div class="alert alert-danger" role="alert">{{ e }}</div> }

      <section aria-labelledby="t-campanas">
        <h2 id="t-campanas" class="h4 mb-1">Campañas</h2>
        <p class="text-secondary mb-4">Cada campaña rinde cuentas por separado: lo recaudado, lo gastado y lo que aún queda disponible.</p>
        <div class="row g-4">
          @for (c of campanas(); track c.id_campana) {
            <div class="col-md-6 col-xl-4">
              <article class="card h-100"><div class="card-body d-flex flex-column">
                <div class="d-flex justify-content-between align-items-start gap-2 mb-2">
                  <span class="small text-secondary">{{ c.categoria }}</span><rs-estado [valor]="c.estado" />
                </div>
                <h3 class="h5">{{ c.nombre }}</h3>
                <p class="small text-secondary flex-grow-1">{{ c.objetivo_social || c.descripcion }}</p>
                <rs-progreso class="d-block mb-3" etiqueta="Recaudado de la meta" [valor]="c.pct_meta_recaudacion" [texto]="(c.recaudado_confirmado | moneda: c.moneda) + ' · ' + (c.pct_meta_recaudacion | pct)" color="var(--rs-dar)" />
                @if (c.meta_hogares) { <rs-progreso class="d-block mb-3" etiqueta="Hogares atendidos" [valor]="c.pct_meta_hogares" [texto]="c.hogares_atendidos + ' de ' + c.meta_hogares" color="var(--rs-recibe)" /> }
                <dl class="row small mb-0 g-1">
                  <dt class="col-7 fw-normal text-secondary">Gasto aprobado</dt><dd class="col-5 text-end mb-0 tabular">{{ c.gastado_aprobado | moneda: c.moneda }}</dd>
                  <dt class="col-7 fw-normal text-secondary">Saldo disponible</dt><dd class="col-5 text-end mb-0 tabular fw-semibold">{{ c.saldo_disponible | moneda: c.moneda }}</dd>
                  <dt class="col-7 fw-normal text-secondary">Hogares / unidades entregadas</dt><dd class="col-5 text-end mb-0 tabular">{{ c.hogares_atendidos }} / {{ c.unidades_entregadas | num }}</dd>
                  <dt class="col-7 fw-normal text-secondary">Periodo</dt><dd class="col-5 text-end mb-0">{{ c.fecha_inicio | fecha }} – {{ c.fecha_fin | fecha }}</dd>
                </dl>
              </div></article>
            </div>
          } @empty { @if (!error() && !cargando()) { <p class="text-secondary">Aún no hay campañas publicadas.</p> } }
        </div>
      </section>

      @if (resumen(); as r) {
        <div class="row g-4 mt-2">
          <section class="col-lg-6" aria-labelledby="t-cat"><div class="card h-100"><div class="card-body">
            <h2 id="t-cat" class="h5">Recaudación por tipo de ayuda</h2>
            <p class="small text-secondary">Donaciones verificadas por categoría de campaña.</p>
            <rs-barras [datos]="barrasCategoria()" color="var(--rs-dar)" />
          </div></div></section>
          <section class="col-lg-6" aria-labelledby="t-sec"><div class="card h-100"><div class="card-body">
            <h2 id="t-sec" class="h5">Hogares atendidos por sector</h2>
            <p class="small text-secondary">Los sectores con menos de 3 hogares se muestran como «menos de 3» para proteger su identidad.</p>
            <rs-barras [datos]="barrasSector()" color="var(--rs-recibe)" />
          </div></div></section>
        </div>
      }
    </main>

    <footer class="border-top bg-white py-4 mt-4"><div class="container small text-secondary">
      <p class="mb-1"><i class="bi bi-shield-check me-1"></i>Este portal publica únicamente cifras agregadas. No incluye nombres de donantes, hogares ni voluntarios.</p>
      <p class="mb-0">Red Solidaria · Datos de la base de gestión interna, sin intermediarios.</p>
    </div></footer>`,
})
export class TransparenciaPage {
  protected readonly auth = inject(AuthService);
  protected readonly resumen = signal<PublicoResumen | null>(null);
  protected readonly campanas = signal<PublicoCampana[]>([]);
  protected readonly error = signal<string | null>(null);
  protected readonly cargando = signal(true);

  protected readonly barrasCategoria = computed<DatoBarra[]>(() =>
    (this.resumen()?.por_categoria ?? []).map((c) => ({ etiqueta: c.categoria, valor: c.recaudado, texto: new Intl.NumberFormat('es-PE', { style: 'currency', currency: this.resumen()?.totales.moneda ?? 'PEN', maximumFractionDigits: 0 }).format(c.recaudado) })),
  );
  protected readonly barrasSector = computed<DatoBarra[]>(() =>
    (this.resumen()?.por_sector ?? []).map((s) => ({ etiqueta: s.sector, valor: s.publicable ? (s.hogares_atendidos ?? 0) : 1, texto: s.publicable ? String(s.hogares_atendidos) : '< 3' })),
  );

  constructor() {
    const api = inject(PublicoService);
    forkJoin([api.resumen(), api.campanas()]).subscribe({
      next: ([r, c]) => { this.resumen.set(r); this.campanas.set(c); this.cargando.set(false); },
      error: (e) => { this.error.set(toApiError(e).message); this.cargando.set(false); },
    });
  }
}
