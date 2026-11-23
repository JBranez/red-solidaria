import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { forkJoin, of } from 'rxjs';
import { toApiError } from '../../core/models/api-error';
import { Campana, Kpis, Pagina, PorCategoria, PorSector, SerieMensual, TopDonante } from '../../core/models/api.models';
import { CampanaService, ReporteService } from '../../core/services/api.services';
import { AuthService } from '../../core/services/auth.service';
import { FORMATOS, fmtMoneda } from '../../core/util/format';
import { Anillo, Barras, DatoBarra, Progreso, Serie } from '../../shared/charts';
import { Encabezado, Estado, Kpi } from '../../shared/ui';

const MES = new Intl.DateTimeFormat('es-PE', { month: 'short', timeZone: 'UTC' });
const etiquetaMes = (m: string): string => MES.format(new Date(`${m}-15T00:00:00Z`)).replace('.', '');

@Component({
  selector: 'rs-panel',
  imports: [RouterLink, Encabezado, Kpi, Estado, Serie, Barras, Anillo, Progreso, ...FORMATOS],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <rs-encabezado titulo="Panel" subtitulo="Cuatro niveles de lectura: recursos, cobertura, operación y resultados. No se mezclan." />
    @if (error(); as e) { <div class="alert alert-danger" role="alert">{{ e }} <button class="btn btn-sm btn-outline-danger ms-2" (click)="cargar()">Reintentar</button></div> }

    @if (k(); as k) {
      @if (alertas().length) {
        <section class="mb-4" aria-label="Pendientes">
          <div class="d-flex flex-wrap gap-2">
            @for (a of alertas(); track a.texto) {
              <a [routerLink]="a.ruta" class="badge text-bg-warning text-decoration-none fw-medium py-2 px-3 fs-6" style="font-size:.82rem!important"><i class="bi me-1" [class]="'bi-' + a.icono"></i>{{ a.texto }}</a>
            }
          </div>
        </section>
      }

      <!-- 1. Recursos -->
      <h2 class="h6 text-secondary mb-2"><span class="text-dar">●</span> Recursos · ¿cuánto entró y cuánto se usó?</h2>
      <div class="row g-3 mb-4">
        <div class="col-6 col-xl-3"><rs-kpi etiqueta="Recaudado y verificado" [valor]="k.financiero.recaudado_confirmado | moneda: k.financiero.moneda" [pista]="(k.financiero.pct_meta | pct: 0) + ' de la meta total'" acento="dar" icono="cash-coin" /></div>
        <div class="col-6 col-xl-3"><rs-kpi etiqueta="Gasto aprobado" [valor]="k.financiero.gastado_aprobado | moneda: k.financiero.moneda" [pista]="'Saldo: ' + (k.financiero.saldo_disponible | moneda: k.financiero.moneda)" acento="dar" icono="receipt" /></div>
        <div class="col-6 col-xl-3"><rs-kpi etiqueta="Pendiente de verificar" [valor]="k.financiero.recaudado_pendiente | moneda: k.financiero.moneda" [pista]="k.financiero.donaciones_pendientes + ' donaciones sin confirmar'" [acento]="k.financiero.donaciones_pendientes ? 'alerta' : 'neutro'" icono="hourglass-split" /></div>
        <div class="col-6 col-xl-3"><rs-kpi etiqueta="Donantes con aporte" [valor]="k.financiero.donantes_activos | num" [pista]="'Aporte medio: ' + (k.financiero.ticket_promedio | moneda: k.financiero.moneda)" acento="dar" icono="people" /></div>
      </div>

      <!-- 2. Cobertura -->
      <h2 class="h6 text-secondary mb-2"><span class="text-recibe">●</span> Cobertura · ¿a quiénes llegó?</h2>
      <div class="row g-3 mb-4">
        <div class="col-lg-4"><div class="card h-100"><div class="card-body d-flex align-items-center gap-3">
          <rs-anillo [valor]="k.cobertura.pct_cobertura" color="var(--rs-recibe)" etiqueta="Cobertura de hogares" />
          <div><div class="fw-semibold">{{ k.cobertura.hogares_atendidos }} de {{ k.cobertura.hogares_registrados }} hogares</div>
            <div class="small text-secondary">{{ k.cobertura.hogares_sin_atender }} aún sin ninguna entrega · ≈{{ k.cobertura.personas_estimadas | num }} personas*</div></div>
        </div></div></div>
        <div class="col-6 col-lg-4"><rs-kpi etiqueta="Entregas realizadas" [valor]="k.cobertura.entregas_realizadas | num" [pista]="(k.cobertura.unidades_entregadas | num) + ' unidades · ' + k.cobertura.entregas_programadas + ' programadas'" acento="recibe" icono="box-seam" /></div>
        <div class="col-6 col-lg-4"><rs-kpi etiqueta="Hogares sin consentimiento registrado" [valor]="k.cobertura.hogares_sin_consentimiento | num" pista="Regularizar la autorización de uso de datos" [acento]="k.cobertura.hogares_sin_consentimiento ? 'alerta' : 'neutro'" icono="shield-exclamation" /></div>
      </div>

      <div class="row g-3 mb-4">
        <div class="col-lg-6"><div class="card h-100"><div class="card-header">Donaciones verificadas por mes</div><div class="card-body">
          <rs-serie [etiquetas]="etiquetasMes()" [valores]="serieDonaciones()" color="var(--rs-dar)" [formato]="moneda" descripcion="Donaciones verificadas por mes" />
        </div></div></div>
        <div class="col-lg-6"><div class="card h-100"><div class="card-header">Entregas realizadas por mes</div><div class="card-body">
          <rs-serie [etiquetas]="etiquetasMes()" [valores]="serieEntregas()" tipo="columnas" color="var(--rs-recibe)" descripcion="Entregas realizadas por mes" />
        </div></div></div>
      </div>

      <!-- 3. Operación -->
      <h2 class="h6 text-secondary mb-2"><span class="text-campana">●</span> Operación · ¿qué hay en marcha?</h2>
      <div class="row g-3 mb-4">
        <div class="col-6 col-lg-3"><rs-kpi etiqueta="Campañas activas" [valor]="k.operacion.campanas_activas | num" [pista]="k.operacion.campanas_por_vencer + ' vencen en 15 días'" acento="campana" icono="megaphone" /></div>
        <div class="col-6 col-lg-3"><rs-kpi etiqueta="Voluntarios activos" [valor]="k.operacion.voluntarios_activos | num" [pista]="k.operacion.voluntarios_participantes + ' ya hicieron entregas'" acento="recibe" icono="person-badge" /></div>
        <div class="col-6 col-lg-3"><rs-kpi etiqueta="Por verificar / aprobar" [valor]="(k.operacion.donaciones_por_verificar + k.operacion.gastos_por_aprobar) | num" [pista]="k.operacion.donaciones_por_verificar + ' donaciones · ' + k.operacion.gastos_por_aprobar + ' gastos'" [acento]="k.operacion.donaciones_por_verificar + k.operacion.gastos_por_aprobar ? 'alerta' : 'neutro'" icono="patch-check" /></div>
        <div class="col-6 col-lg-3"><rs-kpi etiqueta="Entregas programadas vencidas" [valor]="k.operacion.entregas_programadas_vencidas | num" pista="Sin confirmar tras su fecha" [acento]="k.operacion.entregas_programadas_vencidas ? 'alerta' : 'neutro'" icono="calendar-x" /></div>
      </div>

      <!-- 4. Resultados y calidad -->
      <h2 class="h6 text-secondary mb-2"><span class="text-secondary">●</span> Resultados y calidad · ¿se cubrió lo que se necesitaba?</h2>
      <div class="row g-3 mb-4">
        <div class="col-6 col-lg-3"><rs-kpi etiqueta="Necesidades abiertas" [valor]="k.resultados.necesidades_abiertas | num" [pista]="k.resultados.necesidades_urgentes + ' urgentes (crítica o alta)'" [acento]="k.resultados.necesidades_urgentes ? 'alerta' : 'neutro'" icono="clipboard2-pulse" /></div>
        <div class="col-6 col-lg-3"><rs-kpi etiqueta="Necesidades cubiertas" [valor]="k.resultados.pct_necesidades_cubiertas === null ? '—' : (k.resultados.pct_necesidades_cubiertas | pct)" [pista]="k.resultados.necesidades_cubiertas + ' cubiertas · ' + (k.resultados.dias_promedio_cobertura === null ? 'sin tiempo medio aún' : k.resultados.dias_promedio_cobertura + ' días en promedio')" acento="neutro" icono="check2-circle" /></div>
        <div class="col-6 col-lg-3"><rs-kpi etiqueta="Satisfacción" [valor]="k.resultados.satisfaccion_promedio === null ? '—' : k.resultados.satisfaccion_promedio + ' / 5'" [pista]="k.resultados.feedback_abierto + ' mensajes abiertos'" acento="neutro" icono="emoji-smile" /></div>
        <div class="col-6 col-lg-3"><rs-kpi etiqueta="Quejas atendidas en plazo" [valor]="k.resultados.pct_quejas_en_plazo === null ? '—' : (k.resultados.pct_quejas_en_plazo | pct)" [pista]="k.resultados.feedback_vencido + ' con plazo vencido'" [acento]="k.resultados.feedback_vencido ? 'alerta' : 'neutro'" icono="stopwatch" /></div>
      </div>
      <p class="small text-secondary">* Estimación: suma de integrantes de los hogares atendidos. Unidades y entregas son indicadores operativos; no miden por sí solos mejoras en la vida de las personas.</p>

      <div class="row g-3 mb-4">
        <div class="col-lg-6"><div class="card h-100"><div class="card-header d-flex justify-content-between">Cobertura por sector <a routerLink="/hogares" class="small fw-normal">Ver hogares</a></div><div class="card-body">
          <rs-barras [datos]="barrasSector()" color="var(--rs-recibe)" />
        </div></div></div>
        <div class="col-lg-6"><div class="card h-100"><div class="card-header">Recaudado por tipo de ayuda</div><div class="card-body">
          <rs-barras [datos]="barrasCategoria()" color="var(--rs-dar)" />
        </div></div></div>
      </div>

      <div class="card mb-4"><div class="card-header d-flex justify-content-between">Campañas en curso <a routerLink="/campanas" class="small fw-normal">Ver todas</a></div>
        <div class="list-group list-group-flush">
          @for (c of enCurso(); track c.id_campana) {
            <a class="list-group-item list-group-item-action py-3" [routerLink]="['/campanas', c.id_campana]">
              <div class="d-flex justify-content-between gap-2 mb-2"><span class="fw-semibold">{{ c.nombre }}</span><rs-estado [valor]="c.estado" /></div>
              <div class="row g-3">
                <div class="col-md-6"><rs-progreso etiqueta="Recaudación" [valor]="c.pct_meta_recaudacion" [texto]="(c.recaudado_confirmado | moneda: c.moneda) + ' de ' + (c.meta_recaudacion | moneda: c.moneda)" color="var(--rs-dar)" /></div>
                <div class="col-md-6"><rs-progreso etiqueta="Hogares atendidos" [valor]="c.pct_meta_hogares" [texto]="c.meta_hogares ? c.hogares_atendidos + ' de ' + c.meta_hogares : c.hogares_atendidos + ' (sin meta)'" color="var(--rs-recibe)" /></div>
              </div>
            </a>
          } @empty { <div class="list-group-item text-secondary py-4 text-center">No hay campañas en curso.</div> }
        </div>
      </div>

      @if (top().length) {
        <div class="card mb-4"><div class="card-header">Mayores donantes <span class="badge text-bg-light fw-normal ms-1">interno</span></div><div class="card-body">
          <rs-barras [datos]="barrasTop()" color="var(--rs-dar)" />
          <p class="small text-secondary mt-3 mb-0">Reporte interno: los nombres de donantes no se publican sin su consentimiento.</p>
        </div></div>
      }
    } @else if (!error()) {
      <div class="row g-3">@for (i of [1, 2, 3, 4, 5, 6, 7, 8]; track i) { <div class="col-6 col-xl-3"><div class="card p-3"><div class="rs-skeleton mb-2" style="width:50%"></div><div class="rs-skeleton" style="height:1.8rem;width:70%"></div></div></div> }</div>
    }`,
})
export class PanelPage {
  private readonly reportes = inject(ReporteService);
  private readonly campanasApi = inject(CampanaService);
  private readonly auth = inject(AuthService);

  protected readonly k = signal<Kpis | null>(null);
  protected readonly serie = signal<SerieMensual[]>([]);
  protected readonly porCategoria = signal<PorCategoria[]>([]);
  protected readonly porSector = signal<PorSector[]>([]);
  protected readonly enCurso = signal<Campana[]>([]);
  protected readonly top = signal<TopDonante[]>([]);
  protected readonly error = signal<string | null>(null);
  protected readonly moneda = (n: number): string => fmtMoneda(n, this.k()?.financiero.moneda ?? 'PEN');

  protected readonly etiquetasMes = computed(() => this.serie().map((s) => etiquetaMes(s.mes)));
  protected readonly serieDonaciones = computed(() => this.serie().map((s) => s.donaciones));
  protected readonly serieEntregas = computed(() => this.serie().map((s) => s.entregas));
  protected readonly barrasSector = computed<DatoBarra[]>(() =>
    this.porSector().filter((s) => s.hogares_registrados > 0).map((s) => ({ etiqueta: s.sector, valor: s.pct_cobertura ?? 0, texto: `${s.hogares_atendidos}/${s.hogares_registrados}` })),
  );
  protected readonly barrasCategoria = computed<DatoBarra[]>(() =>
    this.porCategoria().filter((c) => c.campanas > 0).map((c) => ({ etiqueta: c.categoria, valor: c.recaudado, texto: fmtMoneda(c.recaudado, this.k()?.financiero.moneda ?? 'PEN') })),
  );
  protected readonly barrasTop = computed<DatoBarra[]>(() => this.top().map((d) => ({ etiqueta: d.nombre, valor: d.total_donado, texto: fmtMoneda(d.total_donado, this.k()?.financiero.moneda ?? 'PEN') })));
  protected readonly alertas = computed(() => {
    const k = this.k();
    if (!k) return [];
    const a: { texto: string; ruta: string; icono: string }[] = [];
    const o = k.operacion;
    if (o.donaciones_por_verificar) a.push({ texto: `${o.donaciones_por_verificar} donaciones por verificar`, ruta: '/donaciones', icono: 'hourglass-split' });
    if (o.gastos_por_aprobar) a.push({ texto: `${o.gastos_por_aprobar} gastos por aprobar`, ruta: '/gastos', icono: 'receipt' });
    if (o.campanas_vencidas_sin_cerrar) a.push({ texto: `${o.campanas_vencidas_sin_cerrar} campañas vencidas sin cerrar`, ruta: '/campanas', icono: 'calendar-x' });
    if (o.entregas_programadas_vencidas) a.push({ texto: `${o.entregas_programadas_vencidas} entregas programadas vencidas`, ruta: '/entregas', icono: 'calendar-x' });
    if (k.resultados.necesidades_urgentes) a.push({ texto: `${k.resultados.necesidades_urgentes} necesidades urgentes`, ruta: '/necesidades', icono: 'exclamation-triangle' });
    if (k.resultados.feedback_vencido) a.push({ texto: `${k.resultados.feedback_vencido} mensajes con plazo vencido`, ruta: '/retroalimentacion', icono: 'stopwatch' });
    return a.filter((x) => this.permiteRuta(x.ruta));
  });

  constructor() { this.cargar(); }

  protected cargar(): void {
    this.error.set(null);
    const sinCampanas: Pagina<Campana> = { items: [], total: 0, pagina: 1, tamano: 6 };
    forkJoin({
      k: this.reportes.kpis(), serie: this.reportes.series(12), cat: this.reportes.porCategoria(), sec: this.reportes.porSector(),
      camp: this.auth.tiene('campanas:leer') ? this.campanasApi.listar({ estado: 'Activa', tamano: 6 }) : of(sinCampanas),
      top: this.auth.tiene('reportes:leer') ? this.reportes.topDonantes(5) : of([] as TopDonante[]),
    }).subscribe({
      next: (r) => {
        this.k.set(r.k); this.serie.set(r.serie); this.porCategoria.set(r.cat); this.porSector.set(r.sec);
        this.enCurso.set(r.camp.items); this.top.set(r.top);
      },
      error: (e) => this.error.set(toApiError(e).message),
    });
  }

  private permiteRuta(ruta: string): boolean {
    const permiso: Record<string, string> = { '/donaciones': 'donaciones:leer', '/gastos': 'gastos:leer', '/campanas': 'campanas:leer', '/entregas': 'entregas:leer', '/necesidades': 'necesidades:leer', '/retroalimentacion': 'feedback:leer' };
    return this.auth.tiene(permiso[ruta] ?? 'dashboard:leer');
  }
}
