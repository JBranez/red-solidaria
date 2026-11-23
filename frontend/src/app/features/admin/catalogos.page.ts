import { ChangeDetectionStrategy, Component, inject, input, OnInit, output, signal } from '@angular/core';
import { form, FormField, maxLength, minLength, required } from '@angular/forms/signals';
import { firstValueFrom } from 'rxjs';
import { toApiError } from '../../core/models/api-error';
import { Categoria, Sector } from '../../core/models/api.models';
import { CatalogoService } from '../../core/services/api.services';
import { ConfirmService } from '../../core/services/confirm.service';
import { ToastService } from '../../core/services/toast.service';
import { FORMATOS } from '../../core/util/format';
import { enviar } from '../../core/util/form-utils';
import { Campo, Carga, Encabezado, Modal } from '../../shared/ui';

type Tipo = 'categoria' | 'sector';

@Component({
  selector: 'rs-catalogo-form',
  imports: [FormField, Campo, Modal],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <rs-modal [titulo]="(editando() ? 'Editar ' : 'Nueva ') + (tipo() === 'categoria' ? 'categoría de ayuda' : 'sector')" tamano="sm" (cerrar)="cerrar.emit()">
      @if (error(); as e) { <div class="alert alert-danger py-2 small" role="alert">{{ e }}</div> }
      <form id="f-cat" (submit)="guardar($event)" novalidate>
        <rs-campo etiqueta="Nombre" requerido [campo]="f.nombre"><input class="form-control" [formField]="f.nombre" /></rs-campo>
        @if (tipo() === 'categoria') { <rs-campo etiqueta="Descripción" requerido [campo]="f.descripcion"><input class="form-control" [formField]="f.descripcion" /></rs-campo> }
      </form>
      <div pie class="modal-footer border-0"><button type="button" class="btn btn-light" (click)="cerrar.emit()">Cancelar</button><button type="submit" form="f-cat" class="btn btn-primary" [disabled]="enviando()">Guardar</button></div>
    </rs-modal>`,
})
export class CatalogoForm implements OnInit {
  readonly tipo = input.required<Tipo>();
  readonly editando = input<{ id: number; nombre: string; descripcion?: string } | null>(null);
  readonly guardado = output<void>();
  readonly cerrar = output<void>();
  private readonly api = inject(CatalogoService);
  private readonly toast = inject(ToastService);
  protected readonly modelo = signal({ nombre: '', descripcion: '' });
  protected readonly f = form(this.modelo, (p) => {
    maxLength(p.nombre, 50, { message: 'Máximo 50 caracteres.' });
    maxLength(p.descripcion, 150, { message: 'Máximo 150 caracteres.' });
    required(p.nombre, { message: 'Escriba el nombre.' }); minLength(p.nombre, 2, { message: 'Use al menos 2 caracteres.' });
    required(p.descripcion, { when: () => this.tipo() === 'categoria', message: 'Escriba una descripción breve.' });
  });
  protected readonly enviando = signal(false);
  protected readonly error = signal<string | null>(null);
  ngOnInit(): void { const e = this.editando(); if (e) this.modelo.set({ nombre: e.nombre, descripcion: e.descripcion ?? '' }); }
  protected async guardar(ev: Event): Promise<void> {
    ev.preventDefault();
    await enviar(this.f, { enviando: this.enviando, error: this.error }, async () => {
      const id = this.editando()?.id ?? null; const m = this.modelo();
      await firstValueFrom<unknown>(this.tipo() === 'categoria' ? this.api.guardarCategoria(id, { nombre: m.nombre, descripcion: m.descripcion }) : this.api.guardarSector(id, { nombre: m.nombre }));
      this.toast.ok('Catálogo actualizado.');
      this.guardado.emit();
    });
  }
}

@Component({
  selector: 'rs-catalogos',
  imports: [Encabezado, Carga, CatalogoForm],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <rs-encabezado titulo="Catálogos" subtitulo="Listas que usan los formularios. Se desactivan, no se borran: el historial conserva su significado." />
    <ul class="nav nav-tabs mb-3" role="tablist">
      <li class="nav-item"><button class="nav-link" [class.active]="pestana() === 'categoria'" type="button" (click)="pestana.set('categoria')">Tipos de ayuda <span class="badge text-bg-light">{{ categorias().length }}</span></button></li>
      <li class="nav-item"><button class="nav-link" [class.active]="pestana() === 'sector'" type="button" (click)="pestana.set('sector')">Sectores <span class="badge text-bg-light">{{ sectores().length }}</span></button></li>
    </ul>
    <div class="card">
      <div class="card-header d-flex justify-content-between align-items-center">{{ pestana() === 'categoria' ? 'Tipos de ayuda' : 'Sectores' }}<button class="btn btn-sm btn-primary" type="button" (click)="editando.set(null); formulario.set(true)"><i class="bi bi-plus-lg me-1"></i>Agregar</button></div>
      @if (cargando()) { <rs-carga /> } @else if (pestana() === 'categoria') {
        <div class="table-responsive"><table class="table rs-table"><thead><tr><th>Nombre</th><th>Descripción</th><th class="text-end">Campañas</th><th></th></tr></thead><tbody>
          @for (c of categorias(); track c.id_categoria) {
            <tr [class.text-secondary]="!c.activo"><td class="fw-semibold">{{ c.nombre }}@if (!c.activo) { <span class="badge text-bg-secondary ms-2">Inactiva</span> }</td><td>{{ c.descripcion }}</td><td class="text-end tabular">{{ c.campanas }} <span class="text-secondary">({{ c.campanas_vigentes }} vigentes)</span></td>
              <td class="text-end text-nowrap"><button class="btn btn-sm btn-outline-secondary me-1" type="button" (click)="editarCategoria(c)"><i class="bi bi-pencil"></i></button>
                <button class="btn btn-sm" [class]="c.activo ? 'btn-outline-danger' : 'btn-outline-success'" type="button" (click)="alternarCategoria(c)">{{ c.activo ? 'Desactivar' : 'Reactivar' }}</button></td></tr> }</tbody></table></div>
      } @else {
        <div class="table-responsive"><table class="table rs-table"><thead><tr><th>Sector</th><th class="text-end">Hogares activos</th><th></th></tr></thead><tbody>
          @for (s of sectores(); track s.id_sector) {
            <tr [class.text-secondary]="!s.activo"><td class="fw-semibold">{{ s.nombre }}@if (!s.activo) { <span class="badge text-bg-secondary ms-2">Inactivo</span> }</td><td class="text-end tabular">{{ s.hogares }}</td>
              <td class="text-end text-nowrap"><button class="btn btn-sm btn-outline-secondary me-1" type="button" (click)="editarSector(s)"><i class="bi bi-pencil"></i></button>
                <button class="btn btn-sm" [class]="s.activo ? 'btn-outline-danger' : 'btn-outline-success'" type="button" (click)="alternarSector(s)">{{ s.activo ? 'Desactivar' : 'Reactivar' }}</button></td></tr> }</tbody></table></div>
      }
    </div>
    @if (formulario()) { <rs-catalogo-form [tipo]="pestana()" [editando]="editando()" (cerrar)="formulario.set(false)" (guardado)="formulario.set(false); cargar()" /> }`,
})
export class CatalogosPage {
  private readonly api = inject(CatalogoService);
  private readonly confirm = inject(ConfirmService);
  private readonly toast = inject(ToastService);
  protected readonly pestana = signal<Tipo>('categoria');
  protected readonly categorias = signal<Categoria[]>([]); protected readonly sectores = signal<Sector[]>([]);
  protected readonly cargando = signal(true);
  protected readonly formulario = signal(false); protected readonly editando = signal<{ id: number; nombre: string; descripcion?: string } | null>(null);
  constructor() { this.cargar(); }
  protected cargar(): void {
    this.cargando.set(true);
    this.api.categorias().subscribe({ next: (c) => this.categorias.set(c), error: (e) => this.toast.error(toApiError(e).message) });
    this.api.sectores().subscribe({ next: (s) => { this.sectores.set(s); this.cargando.set(false); }, error: (e) => { this.cargando.set(false); this.toast.error(toApiError(e).message); } });
  }
  protected editarCategoria(c: Categoria): void { this.editando.set({ id: c.id_categoria, nombre: c.nombre, descripcion: c.descripcion }); this.formulario.set(true); }
  protected editarSector(s: Sector): void { this.editando.set({ id: s.id_sector, nombre: s.nombre }); this.formulario.set(true); }
  protected async alternarCategoria(c: Categoria): Promise<void> {
    if (!(await this.confirm.preguntar({ titulo: c.activo ? 'Desactivar tipo de ayuda' : 'Reactivar tipo de ayuda', mensaje: c.activo ? 'No se podrán crear campañas nuevas con este tipo. No se puede desactivar si tiene campañas vigentes.' : '', confirmar: c.activo ? 'Desactivar' : 'Reactivar', peligro: c.activo })).ok) return;
    this.api.estadoCategoria(c.id_categoria, !c.activo).subscribe({ next: () => { this.toast.ok('Estado actualizado.'); this.cargar(); }, error: (e) => this.toast.error(toApiError(e).message) });
  }
  protected async alternarSector(s: Sector): Promise<void> {
    if (!(await this.confirm.preguntar({ titulo: s.activo ? 'Desactivar sector' : 'Reactivar sector', mensaje: s.activo ? 'No aparecerá al registrar hogares nuevos. Los hogares existentes se conservan.' : '', confirmar: s.activo ? 'Desactivar' : 'Reactivar', peligro: s.activo })).ok) return;
    this.api.estadoSector(s.id_sector, !s.activo).subscribe({ next: () => { this.toast.ok('Estado actualizado.'); this.cargar(); }, error: (e) => this.toast.error(toApiError(e).message) });
  }
}
