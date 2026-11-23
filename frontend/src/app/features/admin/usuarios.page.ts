import { ChangeDetectionStrategy, Component, computed, inject, input, OnInit, output, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { form, FormField, maxLength, minLength, required, validate } from '@angular/forms/signals';
import { firstValueFrom, Observable } from 'rxjs';
import { toApiError } from '../../core/models/api-error';
import { Donante, MatrizRoles, Pagina, Rol, UsuarioAdmin, Voluntario } from '../../core/models/api.models';
import { DonanteService, UsuarioService, VoluntarioService } from '../../core/services/api.services';
import { AuthService } from '../../core/services/auth.service';
import { ConfirmService } from '../../core/services/confirm.service';
import { ToastService } from '../../core/services/toast.service';
import { FORMATOS } from '../../core/util/format';
import { aNumero, enviar } from '../../core/util/form-utils';
import { ListaBase } from '../../core/util/lista-base';
import { Campo, Carga, Encabezado, Modal, Paginacion, Vacio } from '../../shared/ui';

const fuerte = (v: string): boolean => v.length >= 10 && /[A-Za-zÁÉÍÓÚáéíóúÑñ]/.test(v) && /\d/.test(v);

@Component({
  selector: 'rs-usuario-form',
  imports: [FormField, Campo, Modal],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <rs-modal [titulo]="usuario() ? 'Editar usuario' : 'Nuevo usuario'" (cerrar)="cerrar.emit()">
      @if (error(); as e) { <div class="alert alert-danger py-2 small" role="alert">{{ e }}</div> }
      <form id="f-usr" (submit)="guardar($event)" novalidate>
        @if (!usuario()) { <rs-campo etiqueta="Usuario" requerido [campo]="f.username" ayuda="Minúsculas, números, punto, guion o guion bajo."><input class="form-control" autocomplete="off" autocapitalize="none" [formField]="f.username" /></rs-campo> }
        @else { <p class="mb-3"><span class="text-secondary">Usuario:</span> <strong>{{ usuario()!.username }}</strong></p> }
        <rs-campo etiqueta="Nombre completo" requerido [campo]="f.nombre_completo"><input class="form-control" [formField]="f.nombre_completo" /></rs-campo>
        <rs-campo etiqueta="Correo" requerido [campo]="f.correo"><input class="form-control" type="email" autocomplete="off" [formField]="f.correo" /></rs-campo>
        <rs-campo etiqueta="Rol" requerido [campo]="f.id_rol" [ayuda]="descripcionRol()"><select class="form-select" [formField]="f.id_rol"><option value="">Seleccione…</option>@for (r of roles(); track r.id_rol) { <option [value]="r.id_rol">{{ r.nombre }}</option> }</select></rs-campo>
        @if (codigoRol() === 'DONANTE') { <rs-campo etiqueta="Donante vinculado" requerido [campo]="f.id_donante" ayuda="La cuenta solo verá las donaciones de este donante."><select class="form-select" [formField]="f.id_donante"><option value="">Seleccione…</option>@for (d of donantes(); track d.id_donante) { <option [value]="d.id_donante">{{ d.nombre }}</option> }</select></rs-campo> }
        @if (codigoRol() === 'VOLUNTARIO') { <rs-campo etiqueta="Voluntario vinculado" requerido [campo]="f.id_voluntario" ayuda="La cuenta solo verá y confirmará las entregas asignadas a esta persona."><select class="form-select" [formField]="f.id_voluntario"><option value="">Seleccione…</option>@for (v of voluntarios(); track v.id_voluntario) { <option [value]="v.id_voluntario">{{ v.nombre_completo }}</option> }</select></rs-campo> }
        @if (!usuario()) {
          <rs-campo etiqueta="Contraseña inicial" requerido [campo]="f.password" ayuda="Mínimo 10 caracteres, con letras y números."><input class="form-control" type="password" autocomplete="new-password" [formField]="f.password" /></rs-campo>
          <div class="form-check"><input class="form-check-input" type="checkbox" id="cambiar" [formField]="f.debe_cambiar_password" /><label class="form-check-label small" for="cambiar">Debe cambiarla al ingresar por primera vez (recomendado)</label></div>
        }
      </form>
      <div pie class="modal-footer border-0"><button type="button" class="btn btn-light" (click)="cerrar.emit()">Cancelar</button><button type="submit" form="f-usr" class="btn btn-primary" [disabled]="enviando()">{{ enviando() ? 'Guardando…' : 'Guardar' }}</button></div>
    </rs-modal>`,
})
export class UsuarioForm implements OnInit {
  readonly usuario = input<UsuarioAdmin | null>(null);
  readonly roles = input.required<Rol[]>();
  readonly guardado = output<void>();
  readonly cerrar = output<void>();
  private readonly api = inject(UsuarioService);
  private readonly donanteApi = inject(DonanteService);
  private readonly voluntarioApi = inject(VoluntarioService);
  private readonly toast = inject(ToastService);
  protected readonly donantes = signal<Donante[]>([]); protected readonly voluntarios = signal<Voluntario[]>([]);
  protected readonly modelo = signal({ username: '', nombre_completo: '', correo: '', id_rol: '', id_donante: '', id_voluntario: '', password: '', debe_cambiar_password: true });
  protected readonly codigoRol = computed(() => this.roles().find((r) => String(r.id_rol) === this.modelo().id_rol)?.codigo ?? '');
  protected readonly descripcionRol = computed(() => this.roles().find((r) => String(r.id_rol) === this.modelo().id_rol)?.descripcion ?? '');
  protected readonly f = form(this.modelo, (p) => {
    maxLength(p.username, 50, { message: 'Máximo 50 caracteres.' });
    maxLength(p.nombre_completo, 120, { message: 'Máximo 120 caracteres.' });
    maxLength(p.correo, 100, { message: 'Máximo 100 caracteres.' });
    validate(p.username, ({ value }) => (this.usuario() || /^[a-z0-9._-]{3,50}$/.test(value()) ? undefined : { kind: 'usuario', message: 'Use 3-50 caracteres: minúsculas, números, punto, guion o guion bajo.' }));
    required(p.nombre_completo, { message: 'Escriba el nombre completo.' }); minLength(p.nombre_completo, 3, { message: 'Use al menos 3 caracteres.' });
    required(p.correo, { message: 'Escriba el correo.' });
    validate(p.correo, ({ value }) => (!value() || /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(value()) ? undefined : { kind: 'correo', message: 'Ingrese un correo válido.' }));
    required(p.id_rol, { message: 'Seleccione el rol.' });
    validate(p.id_donante, ({ value }) => (this.codigoRol() === 'DONANTE' && !value() ? { kind: 'req', message: 'Seleccione el donante.' } : undefined));
    validate(p.id_voluntario, ({ value }) => (this.codigoRol() === 'VOLUNTARIO' && !value() ? { kind: 'req', message: 'Seleccione el voluntario.' } : undefined));
    validate(p.password, ({ value }) => (this.usuario() || fuerte(value()) ? undefined : { kind: 'pw', message: 'Mínimo 10 caracteres, con letras y números.' }));
  });
  protected readonly enviando = signal(false);
  protected readonly error = signal<string | null>(null);
  ngOnInit(): void {
    const u = this.usuario();
    if (u) this.modelo.set({ username: u.username, nombre_completo: u.nombre_completo, correo: u.correo, id_rol: String(u.id_rol), id_donante: u.id_donante ? String(u.id_donante) : '', id_voluntario: u.id_voluntario ? String(u.id_voluntario) : '', password: '', debe_cambiar_password: u.debe_cambiar_password });
    this.donanteApi.listar({ tamano: 100 }).subscribe({ next: (r) => this.donantes.set(r.items), error: () => undefined });
    this.voluntarioApi.listar({ tamano: 100 }).subscribe({ next: (r) => this.voluntarios.set(r.items), error: () => undefined });
  }
  protected async guardar(ev: Event): Promise<void> {
    ev.preventDefault();
    await enviar(this.f, { enviando: this.enviando, error: this.error }, async () => {
      const m = this.modelo(); const u = this.usuario();
      const base = { nombre_completo: m.nombre_completo, correo: m.correo, id_rol: Number(m.id_rol), id_donante: this.codigoRol() === 'DONANTE' ? aNumero(m.id_donante) : null, id_voluntario: this.codigoRol() === 'VOLUNTARIO' ? aNumero(m.id_voluntario) : null };
      await firstValueFrom(this.api.guardar(u?.id_usuario ?? null, u ? base : { ...base, username: m.username, password: m.password, debe_cambiar_password: m.debe_cambiar_password }));
      this.toast.ok(u ? 'Usuario actualizado. Si cambió el rol, sus sesiones se cerraron.' : 'Usuario creado.');
      this.guardado.emit();
    });
  }
}

@Component({
  selector: 'rs-restablecer',
  imports: [FormField, Campo, Modal],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <rs-modal [titulo]="'Restablecer contraseña · ' + usuario().username" tamano="sm" (cerrar)="cerrar.emit()">
      <p class="small text-secondary">Se cerrarán todas sus sesiones abiertas. Entregue la contraseña por un canal seguro.</p>
      @if (error(); as e) { <div class="alert alert-danger py-2 small" role="alert">{{ e }}</div> }
      <form id="f-reset" (submit)="guardar($event)" novalidate>
        <rs-campo etiqueta="Contraseña nueva" requerido [campo]="f.password"><input class="form-control" type="password" autocomplete="new-password" [formField]="f.password" /></rs-campo>
        <div class="form-check"><input class="form-check-input" type="checkbox" id="rc" [formField]="f.debe_cambiar" /><label class="form-check-label small" for="rc">Debe cambiarla al ingresar</label></div>
      </form>
      <div pie class="modal-footer border-0"><button type="button" class="btn btn-light" (click)="cerrar.emit()">Cancelar</button><button type="submit" form="f-reset" class="btn btn-primary" [disabled]="enviando()">Restablecer</button></div>
    </rs-modal>`,
})
export class Restablecer {
  readonly usuario = input.required<UsuarioAdmin>();
  readonly guardado = output<void>();
  readonly cerrar = output<void>();
  private readonly api = inject(UsuarioService);
  private readonly toast = inject(ToastService);
  protected readonly modelo = signal({ password: '', debe_cambiar: true });
  protected readonly f = form(this.modelo, (p) => { validate(p.password, ({ value }) => (fuerte(value()) ? undefined : { kind: 'pw', message: 'Mínimo 10 caracteres, con letras y números.' })); });
  protected readonly enviando = signal(false);
  protected readonly error = signal<string | null>(null);
  protected async guardar(ev: Event): Promise<void> {
    ev.preventDefault();
    await enviar(this.f, { enviando: this.enviando, error: this.error }, async () => {
      await firstValueFrom(this.api.restablecer(this.usuario().id_usuario, this.modelo().password, this.modelo().debe_cambiar));
      this.toast.ok('Contraseña restablecida.');
      this.guardado.emit();
    });
  }
}

@Component({
  selector: 'rs-usuarios',
  imports: [FormsModule, Encabezado, Carga, Vacio, Paginacion, UsuarioForm, Restablecer, ...FORMATOS],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <rs-encabezado titulo="Usuarios y roles" subtitulo="Quién puede entrar y qué puede hacer. Cada rol tiene permisos concretos; cualquier cambio queda en la auditoría.">
      @if (auth.tiene('usuarios:escribir') && pestana() === 'usuarios') { <button class="btn btn-primary" type="button" (click)="editando.set(null); formulario.set(true)"><i class="bi bi-plus-lg me-1"></i>Nuevo usuario</button> }
    </rs-encabezado>
    <ul class="nav nav-tabs mb-3" role="tablist">
      <li class="nav-item"><button class="nav-link" [class.active]="pestana() === 'usuarios'" type="button" (click)="pestana.set('usuarios')">Usuarios</button></li>
      <li class="nav-item"><button class="nav-link" [class.active]="pestana() === 'roles'" type="button" (click)="verRoles()">Roles y permisos</button></li>
    </ul>

    @if (pestana() === 'usuarios') {
      <div class="card">
        <div class="card-body border-bottom"><div class="row g-2">
          <div class="col-md-6"><div class="input-group"><span class="input-group-text bg-white"><i class="bi bi-search"></i></span><input class="form-control" type="search" placeholder="Usuario, nombre o correo" aria-label="Buscar usuarios" [ngModel]="q()" (ngModelChange)="q.set($event); buscarConRetardo()" /></div></div>
          <div class="col-6 col-md-3"><select class="form-select" aria-label="Rol" [ngModel]="rol()" (ngModelChange)="rol.set($event); refiltrar()"><option value="">Todos los roles</option>@for (r of roles(); track r.id_rol) { <option [value]="r.id_rol">{{ r.nombre }}</option> }</select></div>
          <div class="col-6 col-md-3"><select class="form-select" aria-label="Estado" [ngModel]="activo()" (ngModelChange)="activo.set($event); refiltrar()"><option value="">Activos e inactivos</option><option value="true">Solo activos</option><option value="false">Solo inactivos</option></select></div>
        </div></div>
        @if (cargando() && !items().length) { <rs-carga [n]="5" /> }
        @else if (error(); as e) { <div class="alert alert-danger m-3" role="alert">{{ e }}</div> }
        @else if (!items().length) { <rs-vacio icono="shield-lock" titulo="No se encontraron usuarios" /> }
        @else {
          <div class="table-responsive"><table class="table rs-table">
            <thead><tr><th>Usuario</th><th>Rol</th><th>Vinculado a</th><th>Último acceso</th><th>Estado</th><th></th></tr></thead>
            <tbody>@for (u of items(); track u.id_usuario) {
              <tr [class.text-secondary]="!u.activo">
                <td><div class="fw-semibold">{{ u.nombre_completo }}</div><div class="small text-secondary">{{ u.username }} · {{ u.correo }}</div></td>
                <td><span class="badge bg-primary-subtle text-primary-emphasis border border-primary-subtle">{{ u.rol_nombre }}</span></td>
                <td class="small">{{ u.donante || u.voluntario || '—' }}</td>
                <td class="small text-nowrap">{{ u.ultimo_acceso ? (u.ultimo_acceso | fechaHora) : 'Nunca' }}</td>
                <td>@if (!u.activo) { <span class="badge text-bg-secondary">Inactivo</span> } @else if (u.bloqueado_hasta) { <span class="badge text-bg-danger" title="Bloqueado por intentos fallidos">Bloqueado</span> } @else { <span class="badge bg-success-subtle text-success-emphasis border border-success-subtle">Activo</span> }@if (u.debe_cambiar_password) { <div class="small text-warning-emphasis">Clave temporal</div> }</td>
                <td class="text-end text-nowrap">@if (auth.tiene('usuarios:escribir')) {
                  <button class="btn btn-sm btn-outline-secondary me-1" type="button" (click)="editando.set(u); formulario.set(true)" title="Editar"><i class="bi bi-pencil"></i></button>
                  <button class="btn btn-sm btn-outline-secondary me-1" type="button" (click)="reset.set(u)" title="Restablecer contraseña"><i class="bi bi-key"></i></button>
                  @if (u.id_usuario !== auth.usuario()?.id_usuario) { <button class="btn btn-sm" [class]="u.activo ? 'btn-outline-danger' : 'btn-outline-success'" type="button" (click)="alternar(u)" [title]="u.activo ? 'Desactivar' : 'Reactivar'"><i class="bi" [class]="u.activo ? 'bi-person-dash' : 'bi-person-check'"></i></button> } }</td></tr> }</tbody></table></div>
          <rs-paginacion [pagina]="pagina()" [paginas]="paginas()" [total]="total()" [tamano]="tamano" (cambia)="irA($event)" />
        }
      </div>
    } @else {
      <div class="card">
        @if (!matriz()) { <rs-carga [n]="8" /> } @else {
          <div class="table-responsive"><table class="table rs-table">
            <thead><tr><th style="min-width:18rem">Permiso</th>@for (r of matriz()!.roles; track r.codigo) { <th class="text-center" [title]="r.descripcion">{{ r.nombre }}<div class="fw-normal text-secondary">{{ r.usuarios_activos }} usr.</div></th> }</tr></thead>
            <tbody>@for (m of modulos(); track m.modulo) {
              <tr class="table-light"><td colspan="8" class="fw-semibold text-capitalize small">{{ m.modulo }}</td></tr>
              @for (p of m.permisos; track p.codigo) {
                <tr><td><span class="small">{{ p.descripcion }}</span><div class="text-secondary" style="font-size:.7rem"><code>{{ p.codigo }}</code></div></td>
                  @for (r of matriz()!.roles; track r.codigo) { <td class="text-center">@if (tiene(r.codigo, p.codigo)) { <i class="bi bi-check-circle-fill text-dar" aria-label="Sí"></i> } @else { <i class="bi bi-dash text-secondary opacity-50" aria-label="No"></i> }</td> }</tr> } }</tbody></table></div>
        }
      </div>
      <p class="small text-secondary mt-2"><i class="bi bi-info-circle me-1"></i>La matriz se define en el código y en <code>database/10_reference_data.sql</code> (una prueba automática verifica que coincidan). Separación de funciones: quien registra gastos no los aprueba.</p>
    }
    @if (formulario()) { <rs-usuario-form [usuario]="editando()" [roles]="roles()" (cerrar)="formulario.set(false)" (guardado)="formulario.set(false); cargar()" /> }
    @if (reset(); as u) { <rs-restablecer [usuario]="u" (cerrar)="reset.set(null)" (guardado)="reset.set(null); cargar()" /> }`,
})
export class UsuariosPage extends ListaBase<UsuarioAdmin> {
  protected readonly auth = inject(AuthService);
  private readonly api = inject(UsuarioService);
  private readonly confirm = inject(ConfirmService);
  private readonly toast = inject(ToastService);
  protected readonly pestana = signal<'usuarios' | 'roles'>('usuarios');
  protected readonly q = signal(''); protected readonly rol = signal(''); protected readonly activo = signal('');
  protected readonly roles = signal<Rol[]>([]); protected readonly matriz = signal<MatrizRoles | null>(null);
  protected readonly formulario = signal(false); protected readonly editando = signal<UsuarioAdmin | null>(null); protected readonly reset = signal<UsuarioAdmin | null>(null);
  protected readonly modulos = computed(() => {
    const m = this.matriz();
    if (!m) return [];
    const por: Record<string, typeof m.permisos> = {};
    for (const p of m.permisos) (por[p.modulo] ??= []).push(p);
    return Object.entries(por).map(([modulo, permisos]) => ({ modulo, permisos }));
  });
  constructor() {
    super();
    this.api.roles().subscribe({ next: (r) => this.roles.set(r), error: () => undefined });
    this.cargar();
  }
  protected override consultar(): Observable<Pagina<UsuarioAdmin>> { return this.api.listar({ q: this.q(), id_rol: this.rol(), activo: this.activo(), pagina: this.pagina(), tamano: this.tamano }); }
  protected verRoles(): void { this.pestana.set('roles'); if (!this.matriz()) this.api.matriz().subscribe({ next: (m) => this.matriz.set(m), error: (e) => this.toast.error(toApiError(e).message) }); }
  protected tiene(rol: string, permiso: string): boolean { return this.matriz()?.asignaciones[rol]?.includes(permiso) ?? false; }
  protected async alternar(u: UsuarioAdmin): Promise<void> {
    const r = await this.confirm.preguntar({ titulo: u.activo ? 'Desactivar usuario' : 'Reactivar usuario', mensaje: u.activo ? `«${u.username}» no podrá ingresar y su sesión actual se cerrará al instante.` : `«${u.username}» podrá volver a ingresar.`, confirmar: u.activo ? 'Desactivar' : 'Reactivar', peligro: u.activo });
    if (!r.ok) return;
    this.api.cambiarEstado(u.id_usuario, !u.activo).subscribe({ next: () => { this.toast.ok('Estado actualizado.'); this.cargar(); }, error: (e) => this.toast.error(toApiError(e).message) });
  }
}
