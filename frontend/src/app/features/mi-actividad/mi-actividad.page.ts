import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { toApiError } from '../../core/models/api-error';
import { Donacion, Entrega } from '../../core/models/api.models';
import { EntregaService, MiPortalService } from '../../core/services/api.services';
import { AuthService } from '../../core/services/auth.service';
import { ConfirmService } from '../../core/services/confirm.service';
import { ToastService } from '../../core/services/toast.service';
import { FORMATOS } from '../../core/util/format';
import { Carga, Encabezado, Estado, Kpi, Vacio } from '../../shared/ui';

/** Portal personal: el donante ve SUS donaciones; el voluntario ve y confirma SUS entregas. La API filtra desde la sesión. */
@Component({
  selector: 'rs-mi-actividad',
  imports: [Encabezado, Estado, Kpi, Carga, Vacio, ...FORMATOS],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <rs-encabezado [titulo]="'Hola, ' + primerNombre()" [subtitulo]="esDonante ? 'Su aporte, en transparencia: cada donación y su estado.' : 'Sus entregas asignadas. Confírmelas apenas las realice.'" />

    @if (esDonante) {
      <div class="row g-3 mb-4">
        <div class="col-6 col-md-4"><rs-kpi etiqueta="Total verificado" [valor]="totalConfirmado() | moneda" acento="dar" icono="cash-coin" /></div>
        <div class="col-6 col-md-4"><rs-kpi etiqueta="Donaciones confirmadas" [valor]="confirmadas() | num" acento="dar" icono="check-circle" /></div>
        <div class="col-12 col-md-4"><rs-kpi etiqueta="Pendientes de verificar" [valor]="pendientes() | num" [acento]="pendientes() ? 'alerta' : 'neutro'" icono="hourglass-split" /></div>
      </div>
      <div class="card">
        <div class="card-header">Mis donaciones</div>
        @if (!donaciones()) { <rs-carga /> } @else if (!donaciones()!.length) { <rs-vacio icono="cash-coin" titulo="Aún no hay donaciones a su nombre" /> } @else {
          <div class="table-responsive"><table class="table rs-table"><thead><tr><th>Fecha</th><th>Campaña</th><th>Método</th><th class="text-end">Monto</th><th>Estado</th></tr></thead><tbody>
            @for (d of donaciones(); track d.id_donacion) { <tr><td>{{ d.fecha | fecha }}</td><td>{{ d.campana }}</td><td>{{ d.metodo_pago }}</td><td class="text-end tabular fw-semibold">{{ d.monto | moneda: d.moneda }}</td><td><rs-estado [valor]="d.estado" /></td></tr> }</tbody></table></div>
        }
      </div>
      <p class="small text-secondary mt-3"><i class="bi bi-eye me-1"></i>Para ver cómo se usan los fondos de cada campaña, visite el portal público de transparencia.</p>
    }

    @if (esVoluntario) {
      <div class="card mb-4">
        <div class="card-header d-flex justify-content-between">Por entregar <span class="badge text-bg-info">{{ programadas().length }}</span></div>
        @if (!entregas()) { <rs-carga /> } @else if (!programadas().length) { <rs-vacio icono="check2-all" titulo="No tiene entregas pendientes" texto="Cuando coordinación le asigne una, aparecerá aquí." /> } @else {
          <ul class="list-group list-group-flush">
            @for (e of programadas(); track e.id_entrega) {
              <li class="list-group-item py-3"><div class="d-flex flex-wrap justify-content-between align-items-center gap-2">
                <div><div class="fw-semibold">{{ e.hogar }} <span class="text-secondary fw-normal">· {{ e.sector }}</span></div>
                  <div class="small text-secondary">{{ e.campana }} · {{ e.fecha | fecha }} · {{ e.cantidad }} {{ e.cantidad === 1 ? 'unidad' : 'unidades' }}@if (e.detalle) { · {{ e.detalle }} }</div></div>
                <div class="d-flex gap-2"><button class="btn btn-success" type="button" (click)="entregada(e)"><i class="bi bi-check-lg me-1"></i>Entregada</button><button class="btn btn-outline-warning" type="button" (click)="noRealizada(e)">No se pudo</button></div>
              </div></li> }
          </ul>
        }
      </div>
      <div class="card">
        <div class="card-header">Mi historial</div>
        @if (entregas() && !historial().length) { <rs-vacio icono="box-seam" titulo="Aún no tiene entregas realizadas" /> } @else if (entregas()) {
          <div class="table-responsive"><table class="table rs-table"><thead><tr><th>Fecha</th><th>Hogar</th><th>Campaña</th><th class="text-end">Cant.</th><th>Estado</th></tr></thead><tbody>
            @for (e of historial(); track e.id_entrega) { <tr><td>{{ e.fecha | fecha }}</td><td>{{ e.hogar }}</td><td>{{ e.campana }}</td><td class="text-end tabular">{{ e.cantidad }}</td><td><rs-estado [valor]="e.estado" /></td></tr> }</tbody></table></div>
        }
      </div>
    }`,
})
export class MiActividadPage {
  private readonly auth = inject(AuthService);
  private readonly portal = inject(MiPortalService);
  private readonly entregaApi = inject(EntregaService);
  private readonly confirm = inject(ConfirmService);
  private readonly toast = inject(ToastService);
  protected readonly esDonante = this.auth.tiene('portal:donante');
  protected readonly esVoluntario = this.auth.tiene('portal:voluntario');
  protected readonly primerNombre = computed(() => this.auth.usuario()?.nombre_completo.split(' ')[0] ?? '');
  protected readonly donaciones = signal<Donacion[] | null>(null);
  protected readonly entregas = signal<Entrega[] | null>(null);
  protected readonly totalConfirmado = computed(() => (this.donaciones() ?? []).filter((d) => d.estado === 'Confirmada').reduce((s, d) => s + d.monto, 0));
  protected readonly confirmadas = computed(() => (this.donaciones() ?? []).filter((d) => d.estado === 'Confirmada').length);
  protected readonly pendientes = computed(() => (this.donaciones() ?? []).filter((d) => d.estado === 'Pendiente').length);
  protected readonly programadas = computed(() => (this.entregas() ?? []).filter((e) => e.estado === 'Programada').sort((a, b) => a.fecha.localeCompare(b.fecha)));
  protected readonly historial = computed(() => (this.entregas() ?? []).filter((e) => e.estado !== 'Programada').slice(0, 30));

  constructor() { this.cargar(); }
  private cargar(): void {
    const fallo = (e: unknown) => this.toast.error(toApiError(e).message);
    if (this.esDonante) this.portal.donaciones({ tamano: 100 }).subscribe({ next: (r) => this.donaciones.set(r.items), error: (e) => { this.donaciones.set([]); fallo(e); } });
    if (this.esVoluntario) this.portal.entregas({ tamano: 100 }).subscribe({ next: (r) => this.entregas.set(r.items), error: (e) => { this.entregas.set([]); fallo(e); } });
  }
  protected async entregada(e: Entrega): Promise<void> {
    if ((await this.confirm.preguntar({ titulo: 'Confirmar entrega', mensaje: `¿Entregó la ayuda a ${e.hogar}?`, confirmar: 'Sí, la entregué' })).ok) this.cambiar(e, 'Entregada', '');
  }
  protected async noRealizada(e: Entrega): Promise<void> {
    const r = await this.confirm.preguntar({ titulo: 'No se pudo entregar', mensaje: 'Cuéntenos qué pasó (nadie en casa, dirección incorrecta…). Coordinación la reprogramará.', confirmar: 'Registrar', pedirMotivo: true });
    if (r.ok) this.cambiar(e, 'No realizada', r.motivo);
  }
  private cambiar(e: Entrega, estado: string, motivo: string): void {
    this.entregaApi.cambiarEstado(e.id_entrega, estado, motivo).subscribe({ next: () => { this.toast.ok('Entrega actualizada. ¡Gracias!'); this.cargar(); }, error: (er) => this.toast.error(toApiError(er).message) });
  }
}
