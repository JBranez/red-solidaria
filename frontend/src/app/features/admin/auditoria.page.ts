import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Observable } from 'rxjs';
import { Auditoria, Pagina } from '../../core/models/api.models';
import { AuditoriaService } from '../../core/services/api.services';
import { FORMATOS } from '../../core/util/format';
import { ACCIONES_AUDITORIA } from '../../core/util/labels';
import { ListaBase } from '../../core/util/lista-base';
import { Carga, Encabezado, Paginacion, Vacio } from '../../shared/ui';

@Component({
  selector: 'rs-auditoria',
  imports: [FormsModule, Encabezado, Carga, Vacio, Paginacion, ...FORMATOS],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <rs-encabezado titulo="Auditoría" subtitulo="Bitácora de solo inserción: quién hizo qué y cuándo. Nadie puede modificarla ni borrarla, ni siquiera la aplicación." />
    <div class="card">
      <div class="card-body border-bottom"><div class="row g-2">
        <div class="col-md-3"><div class="input-group"><span class="input-group-text bg-white"><i class="bi bi-search"></i></span><input class="form-control" type="search" placeholder="Usuario o detalle" aria-label="Buscar" [ngModel]="q()" (ngModelChange)="q.set($event); buscarConRetardo()" /></div></div>
        <div class="col-6 col-md-2"><select class="form-select" aria-label="Acción" [ngModel]="accion()" (ngModelChange)="accion.set($event); refiltrar()"><option value="">Toda acción</option>@for (a of acciones; track a[0]) { <option [value]="a[0]">{{ a[1] }}</option> }</select></div>
        <div class="col-6 col-md-2"><select class="form-select" aria-label="Entidad" [ngModel]="entidad()" (ngModelChange)="entidad.set($event); refiltrar()"><option value="">Toda entidad</option>@for (e of entidades; track e) { <option>{{ e }}</option> }</select></div>
        <div class="col-6 col-md-2"><input class="form-control" type="date" aria-label="Desde" title="Desde" [ngModel]="desde()" (ngModelChange)="desde.set($event); refiltrar()" /></div>
        <div class="col-6 col-md-2"><input class="form-control" type="date" aria-label="Hasta" title="Hasta" [ngModel]="hasta()" (ngModelChange)="hasta.set($event); refiltrar()" /></div>
      </div></div>
      @if (cargando() && !items().length) { <rs-carga [n]="8" /> }
      @else if (error(); as e) { <div class="alert alert-danger m-3" role="alert">{{ e }}</div> }
      @else if (!items().length) { <rs-vacio icono="journal-check" titulo="No hay eventos con esos filtros" /> }
      @else {
        <div class="table-responsive"><table class="table rs-table">
          <thead><tr><th>Fecha</th><th>Usuario</th><th>Acción</th><th>Entidad</th><th>Detalle</th><th>IP</th></tr></thead>
          <tbody>@for (a of items(); track a.id_evento) {
            <tr><td class="text-nowrap small">{{ a.fecha | fechaHora }}</td><td>{{ a.username || '—' }}</td>
              <td><span class="badge" [class]="a.accion === 'LOGIN_FALLIDO' ? 'text-bg-danger' : 'text-bg-light border'">{{ etiqueta(a.accion) }}</span></td>
              <td class="small">{{ a.entidad }}@if (a.id_entidad) { <span class="text-secondary"> #{{ a.id_entidad }}</span> }</td><td class="small" style="max-width:26rem">{{ a.detalle || '' }}</td><td class="small text-secondary">{{ a.ip || '' }}</td></tr> }</tbody></table></div>
        <rs-paginacion [pagina]="pagina()" [paginas]="paginas()" [total]="total()" [tamano]="tamano" (cambia)="irA($event)" />
      }
    </div>`,
})
export class AuditoriaPage extends ListaBase<Auditoria> {
  private readonly api = inject(AuditoriaService);
  protected readonly acciones = Object.entries(ACCIONES_AUDITORIA);
  protected readonly entidades = ['usuario', 'campana', 'donante', 'donacion', 'gasto', 'beneficiario', 'necesidad', 'voluntario', 'entrega', 'retroalimentacion', 'categoria_ayuda', 'sector'];
  protected readonly q = signal(''); protected readonly accion = signal(''); protected readonly entidad = signal(''); protected readonly desde = signal(''); protected readonly hasta = signal('');
  protected readonly etiqueta = (a: string): string => ACCIONES_AUDITORIA[a] ?? a;
  constructor() { super(); this.cargar(); }
  protected override consultar(): Observable<Pagina<Auditoria>> { return this.api.listar({ q: this.q(), accion: this.accion(), entidad: this.entidad(), desde: this.desde(), hasta: this.hasta(), pagina: this.pagina(), tamano: this.tamano }); }
}
