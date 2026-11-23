import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { Observable } from 'rxjs';
import { Campana, Categoria, Pagina } from '../../core/models/api.models';
import { CampanaService, CatalogoService } from '../../core/services/api.services';
import { AuthService } from '../../core/services/auth.service';
import { FORMATOS } from '../../core/util/format';
import { ListaBase } from '../../core/util/lista-base';
import { Progreso } from '../../shared/charts';
import { Carga, Encabezado, Estado, Paginacion, Vacio } from '../../shared/ui';
import { CampanaForm } from './campana-form';

@Component({
  selector: 'rs-campanas',
  imports: [FormsModule, RouterLink, Encabezado, Estado, Carga, Vacio, Paginacion, Progreso, CampanaForm, ...FORMATOS],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <rs-encabezado titulo="Campañas" subtitulo="Cada campaña tiene su propia meta, su rendición de cuentas y su estado.">
      @if (auth.tiene('campanas:escribir')) { <button class="btn btn-primary" type="button" (click)="formulario.set(true)"><i class="bi bi-plus-lg me-1"></i>Nueva campaña</button> }
    </rs-encabezado>

    <div class="card">
      <div class="card-body border-bottom"><div class="row g-2">
        <div class="col-md-5"><div class="input-group"><span class="input-group-text bg-white"><i class="bi bi-search"></i></span>
          <input class="form-control" type="search" placeholder="Buscar por nombre o tipo de ayuda" aria-label="Buscar campañas" [ngModel]="q()" (ngModelChange)="q.set($event); buscarConRetardo()" /></div></div>
        <div class="col-6 col-md-3"><select class="form-select" aria-label="Estado" [ngModel]="estado()" (ngModelChange)="estado.set($event); refiltrar()">
          <option value="">Todos los estados</option>@for (e of estados; track e) { <option [value]="e">{{ e }}</option> }</select></div>
        <div class="col-6 col-md-4"><select class="form-select" aria-label="Tipo de ayuda" [ngModel]="categoria()" (ngModelChange)="categoria.set($event); refiltrar()">
          <option value="">Todos los tipos</option>@for (c of categorias(); track c.id_categoria) { <option [value]="c.id_categoria">{{ c.nombre }}</option> }</select></div>
      </div></div>

      @if (cargando() && !items().length) { <rs-carga [n]="6" /> }
      @else if (error(); as e) { <div class="alert alert-danger m-3" role="alert">{{ e }}</div> }
      @else if (!items().length) { <rs-vacio icono="megaphone" titulo="No hay campañas con esos filtros" texto="Cambie los filtros o cree una nueva campaña." /> }
      @else {
        <div class="table-responsive"><table class="table rs-table">
          <thead><tr><th>Campaña</th><th>Periodo</th><th>Estado</th><th style="min-width:15rem">Recaudación</th><th class="text-end">Hogares</th><th></th></tr></thead>
          <tbody>
            @for (c of items(); track c.id_campana) {
              <tr class="rs-clickable" (click)="abrir(c)">
                <td><a class="fw-semibold text-decoration-none" [routerLink]="['/campanas', c.id_campana]" (click)="$event.stopPropagation()">{{ c.nombre }}</a><div class="small text-secondary">{{ c.categoria }}</div></td>
                <td class="text-nowrap small">{{ c.fecha_inicio | fecha }} – {{ c.fecha_fin | fecha }}
                  @if (c.estado === 'Activa') { <div [class]="c.dias_restantes < 0 ? 'text-danger' : c.dias_restantes <= 15 ? 'text-warning-emphasis' : 'text-secondary'">{{ c.dias_restantes < 0 ? 'Venció hace ' + (-c.dias_restantes) + ' días' : c.dias_restantes + ' días restantes' }}</div> }</td>
                <td><rs-estado [valor]="c.estado" /></td>
                <td><rs-progreso [valor]="c.pct_meta_recaudacion" [texto]="(c.recaudado_confirmado | moneda: c.moneda) + ' / ' + (c.meta_recaudacion | moneda: c.moneda)" color="var(--rs-dar)" />
                  @if (c.recaudado_pendiente > 0) { <div class="small text-warning-emphasis mt-1">+ {{ c.recaudado_pendiente | moneda: c.moneda }} por verificar</div> }</td>
                <td class="text-end tabular">{{ c.hogares_atendidos }}@if (c.meta_hogares) { <span class="text-secondary"> / {{ c.meta_hogares }}</span> }</td>
                <td class="text-end"><a class="btn btn-sm btn-outline-secondary" [routerLink]="['/campanas', c.id_campana]" (click)="$event.stopPropagation()">Ver</a></td>
              </tr>
            }
          </tbody></table></div>
        <rs-paginacion [pagina]="pagina()" [paginas]="paginas()" [total]="total()" [tamano]="tamano" (cambia)="irA($event)" />
      }
    </div>

    @if (formulario()) { <rs-campana-form [categorias]="categoriasActivas()" (cerrar)="formulario.set(false)" (guardado)="creada($event)" /> }`,
})
export class CampanasPage extends ListaBase<Campana> {
  protected readonly auth = inject(AuthService);
  private readonly api = inject(CampanaService);
  private readonly router = inject(Router);
  protected readonly estados = ['Borrador', 'Activa', 'Pausada', 'Finalizada', 'Cancelada'];
  protected readonly q = signal('');
  protected readonly estado = signal('');
  protected readonly categoria = signal('');
  protected readonly categorias = signal<Categoria[]>([]);
  protected readonly categoriasActivas = () => this.categorias().filter((c) => c.activo);
  protected readonly formulario = signal(false);

  constructor() {
    super();
    inject(CatalogoService).categorias().subscribe({ next: (c) => this.categorias.set(c), error: () => undefined });
    this.cargar();
  }
  protected override consultar(): Observable<Pagina<Campana>> {
    return this.api.listar({ q: this.q(), estado: this.estado(), id_categoria: this.categoria(), pagina: this.pagina(), tamano: this.tamano });
  }
  protected abrir(c: Campana): void { void this.router.navigate(['/campanas', c.id_campana]); }
  protected creada(c: Campana): void { this.formulario.set(false); void this.router.navigate(['/campanas', c.id_campana]); }
}
