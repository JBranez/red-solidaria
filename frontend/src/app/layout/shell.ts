import { ChangeDetectionStrategy, Component, computed, ElementRef, HostListener, inject, signal } from '@angular/core';
import { NavigationEnd, Router, RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { filter } from 'rxjs';
import { AuthService } from '../core/services/auth.service';

interface Item { ruta: string; texto: string; icono: string; permisos: string[] }
interface Grupo { titulo: string; clase: string; items: Item[] }

/** Menú por permisos. Ocultar un enlace es solo comodidad: la API vuelve a exigir el permiso en cada petición. */
const MENU: Grupo[] = [
  { titulo: '', clase: '', items: [
    { ruta: '/panel', texto: 'Panel', icono: 'speedometer2', permisos: ['dashboard:leer'] },
    { ruta: '/mi-actividad', texto: 'Mi actividad', icono: 'person-heart', permisos: ['portal:donante', 'portal:voluntario'] },
  ] },
  { titulo: 'Campañas de ayuda', clase: 'grupo-campana', items: [
    { ruta: '/campanas', texto: 'Campañas', icono: 'megaphone', permisos: ['campanas:leer'] },
  ] },
  { titulo: 'Quienes donan', clase: 'grupo-dar', items: [
    { ruta: '/donantes', texto: 'Donantes', icono: 'people', permisos: ['donantes:leer'] },
    { ruta: '/donaciones', texto: 'Donaciones', icono: 'cash-coin', permisos: ['donaciones:leer'] },
    { ruta: '/gastos', texto: 'Gastos', icono: 'receipt', permisos: ['gastos:leer'] },
  ] },
  { titulo: 'Quienes ayudan y reciben', clase: 'grupo-recibe', items: [
    { ruta: '/hogares', texto: 'Hogares', icono: 'house-heart', permisos: ['beneficiarios:leer'] },
    { ruta: '/necesidades', texto: 'Cola de atención', icono: 'clipboard2-pulse', permisos: ['necesidades:leer'] },
    { ruta: '/entregas', texto: 'Entregas', icono: 'box-seam', permisos: ['entregas:leer'] },
    { ruta: '/voluntarios', texto: 'Voluntarios', icono: 'person-badge', permisos: ['voluntarios:leer'] },
    { ruta: '/retroalimentacion', texto: 'Retroalimentación', icono: 'chat-heart', permisos: ['feedback:leer'] },
  ] },
  { titulo: 'Administración', clase: 'grupo-admin', items: [
    { ruta: '/catalogos', texto: 'Catálogos', icono: 'tags', permisos: ['catalogos:escribir'] },
    { ruta: '/usuarios', texto: 'Usuarios y roles', icono: 'shield-lock', permisos: ['usuarios:leer'] },
    { ruta: '/auditoria', texto: 'Auditoría', icono: 'journal-check', permisos: ['auditoria:leer'] },
  ] },
];

@Component({
  selector: 'rs-shell',
  imports: [RouterOutlet, RouterLink, RouterLinkActive],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <header class="navbar sticky-top rs-topbar flex-md-nowrap p-0 shadow">
      <a class="navbar-brand col-md-3 col-lg-2 me-0 px-3 fs-6 text-white d-flex align-items-center" routerLink="/">
        <span class="rs-brand-mark" aria-hidden="true"><i class="bi bi-diagram-3-fill"></i></span>Red Solidaria
      </a>
      <button class="navbar-toggler d-md-none border-0 text-white me-2" type="button" aria-label="Abrir menú" [attr.aria-expanded]="menuAbierto()" (click)="menuAbierto.set(true)">
        <i class="bi bi-list fs-3"></i>
      </button>
      <div class="d-none d-md-flex ms-auto pe-3 align-items-center gap-3 position-relative">
        <a routerLink="/transparencia" class="link-light small text-decoration-none opacity-75"><i class="bi bi-globe2 me-1"></i>Portal público</a>
        <button type="button" class="btn btn-sm btn-outline-light border-0 d-flex align-items-center gap-2" (click)="usuarioMenu.set(!usuarioMenu()); $event.stopPropagation()" [attr.aria-expanded]="usuarioMenu()" aria-haspopup="menu">
          <span class="rounded-circle bg-light text-dark fw-semibold d-inline-grid place-items-center" style="width:1.8rem;height:1.8rem;display:inline-grid;place-items:center;font-size:.75rem">{{ iniciales() }}</span>
          <span class="text-start lh-sm d-none d-lg-block"><span class="d-block small text-white">{{ auth.usuario()?.nombre_completo }}</span><span class="d-block text-white-50" style="font-size:.7rem">{{ auth.usuario()?.rol_nombre }}</span></span>
          <i class="bi bi-chevron-down small"></i>
        </button>
        @if (usuarioMenu()) {
          <div class="dropdown-menu dropdown-menu-end show shadow position-absolute end-0 top-100 mt-1" role="menu">
            <a class="dropdown-item" routerLink="/cambiar-password" role="menuitem"><i class="bi bi-key me-2"></i>Cambiar contraseña</a>
            <div class="dropdown-divider"></div>
            <button class="dropdown-item text-danger" type="button" role="menuitem" (click)="auth.cerrarSesion()"><i class="bi bi-box-arrow-right me-2"></i>Cerrar sesión</button>
          </div>
        }
      </div>
    </header>

    @if (menuAbierto()) { <div class="rs-backdrop d-md-none" (click)="menuAbierto.set(false)"></div> }
    <div class="container-fluid">
      <div class="row">
        <nav class="col-md-3 col-lg-2 d-md-block rs-sidebar p-0" aria-label="Navegación principal">
          <div class="offcanvas-md offcanvas-end bg-white" [class.show]="menuAbierto()" tabindex="-1" style="--bs-offcanvas-width: 17rem">
            <div class="offcanvas-header d-md-none border-bottom">
              <span class="fw-semibold">Menú</span>
              <button type="button" class="btn-close" aria-label="Cerrar menú" (click)="menuAbierto.set(false)"></button>
            </div>
            <div class="offcanvas-body d-md-flex flex-column p-0 pt-2 pb-4 overflow-y-auto">
              @for (g of grupos(); track g.titulo) {
                @if (g.titulo) { <div class="rs-sidebar-heading" [class]="g.clase">{{ g.titulo }}</div> }
                <ul class="nav flex-column gap-1">
                  @for (i of g.items; track i.ruta) {
                    <li class="nav-item"><a class="nav-link d-flex align-items-center gap-2" [routerLink]="i.ruta" routerLinkActive="active"><i class="bi" [class]="'bi-' + i.icono" aria-hidden="true"></i>{{ i.texto }}</a></li>
                  }
                </ul>
              }
              <div class="d-md-none mt-3 border-top pt-3">
                <a class="nav-link d-flex align-items-center gap-2" routerLink="/cambiar-password"><i class="bi bi-key"></i>Cambiar contraseña</a>
                <button class="nav-link d-flex align-items-center gap-2 border-0 bg-transparent text-danger w-100" type="button" (click)="auth.cerrarSesion()"><i class="bi bi-box-arrow-right"></i>Cerrar sesión ({{ auth.usuario()?.username }})</button>
              </div>
            </div>
          </div>
        </nav>
        <main class="col-md-9 ms-sm-auto col-lg-10 px-md-4 rs-main" id="contenido"><div class="py-4 px-3 px-md-0"><router-outlet /></div></main>
      </div>
    </div>`,
})
export class Shell {
  protected readonly auth = inject(AuthService);
  private readonly el = inject(ElementRef);
  protected readonly menuAbierto = signal(false);
  protected readonly usuarioMenu = signal(false);
  protected readonly grupos = computed(() =>
    MENU.map((g) => ({ ...g, items: g.items.filter((i) => this.auth.tieneAlguno(...i.permisos)) })).filter((g) => g.items.length > 0),
  );
  protected readonly iniciales = computed(() =>
    (this.auth.usuario()?.nombre_completo ?? '?').split(' ').filter(Boolean).slice(0, 2).map((p) => p[0].toUpperCase()).join(''),
  );

  constructor() {
    inject(Router).events.pipe(filter((e) => e instanceof NavigationEnd)).subscribe(() => { this.menuAbierto.set(false); this.usuarioMenu.set(false); });
  }
  @HostListener('document:click', ['$event.target']) cerrarMenuUsuario(t: EventTarget | null): void {
    if (this.usuarioMenu() && !(t instanceof Node && this.el.nativeElement.querySelector('.dropdown-menu')?.contains(t))) this.usuarioMenu.set(false);
  }
}
