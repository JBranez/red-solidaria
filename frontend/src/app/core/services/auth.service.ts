import { HttpClient } from '@angular/common/http';
import { computed, inject, Injectable, signal } from '@angular/core';
import { Router } from '@angular/router';
import { firstValueFrom, Observable, tap } from 'rxjs';
import { Token, Usuario } from '../models/api.models';

const CLAVE_TOKEN = 'rs_token';

/**
 * Sesión del usuario con Signals. El token vive en sessionStorage (se pierde al cerrar la pestaña).
 * Limitación conocida: sessionStorage es legible por JavaScript (riesgo XSS); la API revalida el token contra la
 * base de datos en cada petición y permite revocarlo (ver docs/DECISIONES.md).
 */
@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly http = inject(HttpClient);
  private readonly router = inject(Router);

  private readonly _token = signal<string | null>(this.leerToken());
  readonly usuario = signal<Usuario | null>(null);
  readonly autenticado = computed(() => this._token() !== null);
  private readonly permisos = computed(() => new Set(this.usuario()?.permisos ?? []));

  token(): string | null { return this._token(); }
  tiene(permiso: string): boolean { return this.permisos().has(permiso); }
  tieneAlguno(...permisos: string[]): boolean { return permisos.length === 0 || permisos.some((p) => this.permisos().has(p)); }

  login(username: string, password: string): Observable<Token> {
    return this.http.post<Token>('/api/v1/auth/login', { username, password }).pipe(tap((t) => this.iniciar(t)));
  }

  cambiarPassword(passwordActual: string, passwordNueva: string): Observable<Token> {
    return this.http
      .post<Token>('/api/v1/auth/cambiar-password', { password_actual: passwordActual, password_nueva: passwordNueva })
      .pipe(tap((t) => this.iniciar(t)));
  }

  /** Al arrancar la aplicación: si hay token guardado, recupera el usuario; si ya no es válido, limpia la sesión. */
  async restaurar(): Promise<void> {
    if (!this._token()) return;
    try {
      this.usuario.set(await firstValueFrom(this.http.get<Usuario>('/api/v1/auth/me')));
    } catch {
      this.limpiar();
    }
  }

  cerrarSesion(redirigir = true): void {
    if (this._token()) this.http.post('/api/v1/auth/logout', {}).subscribe({ error: () => undefined });
    this.limpiar();
    if (redirigir) void this.router.navigate(['/acceso']);
  }

  /** Cierra la sesión local sin avisar al servidor (token ya inválido o expirado). */
  expirar(): void {
    this.limpiar();
    void this.router.navigate(['/acceso'], { queryParams: { sesion: 'expirada', volver: this.router.url } });
  }

  /** Ruta de inicio según los permisos del usuario. */
  rutaInicial(): string {
    if (this.tiene('dashboard:leer')) return '/panel';
    if (this.tieneAlguno('portal:donante', 'portal:voluntario')) return '/mi-actividad';
    if (this.tiene('campanas:leer')) return '/campanas';
    return '/acceso-denegado';
  }

  private iniciar(t: Token): void {
    sessionStorage.setItem(CLAVE_TOKEN, t.access_token);
    this._token.set(t.access_token);
    this.usuario.set(t.usuario);
  }
  private limpiar(): void {
    sessionStorage.removeItem(CLAVE_TOKEN);
    this._token.set(null);
    this.usuario.set(null);
  }
  private leerToken(): string | null {
    try { return sessionStorage.getItem(CLAVE_TOKEN); } catch { return null; }
  }
}
