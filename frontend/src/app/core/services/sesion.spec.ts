import { HttpClient, provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { provideRouter, Router } from '@angular/router';
import { firstValueFrom } from 'rxjs';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { authGuard, guestGuard, inicioGuard, permisoGuard } from '../guards/auth.guards';
import { authInterceptor } from '../interceptors/auth.interceptor';
import { errorInterceptor } from '../interceptors/error.interceptor';
import { ApiError } from '../models/api-error';
import { Token, Usuario } from '../models/api.models';
import { AuthService } from './auth.service';

const usuario = (permisos: string[], extra: Partial<Usuario> = {}): Usuario => ({
  id_usuario: 1, username: 'ana', nombre_completo: 'Ana', correo: 'a@x.pe', id_rol: 1, rol_codigo: 'ADMIN', rol_nombre: 'Admin',
  id_donante: null, id_voluntario: null, debe_cambiar_password: false, permisos, ...extra,
});
const token = (u: Usuario): Token => ({ access_token: 'jwt-123', token_type: 'bearer', expires_in: 3600, usuario: u });
const err = (status: number, codigo: string, mensaje = 'x') => [{ error: { codigo, mensaje } }, { status, statusText: 'x' }] as const;

describe('sesión, interceptores y guards', () => {
  let http: HttpTestingController; let auth: AuthService; let router: Router;
  beforeEach(() => {
    sessionStorage.clear();
    TestBed.configureTestingModule({
      providers: [provideRouter([{ path: 'acceso', children: [] }, { path: 'panel', children: [] }, { path: 'cambiar-password', children: [] }]),
        provideHttpClient(withInterceptors([authInterceptor, errorInterceptor])), provideHttpClientTesting()],
    });
    http = TestBed.inject(HttpTestingController); auth = TestBed.inject(AuthService); router = TestBed.inject(Router);
  });

  it('login guarda el token en sessionStorage y expone usuario y permisos', async () => {
    const p = firstValueFrom(auth.login('ana', 'x'));
    http.expectOne('/api/v1/auth/login').flush(token(usuario(['dashboard:leer'])));
    await p;
    expect(sessionStorage.getItem('rs_token')).toBe('jwt-123');
    expect(auth.autenticado()).toBe(true); expect(auth.tiene('dashboard:leer')).toBe(true); expect(auth.tiene('usuarios:escribir')).toBe(false);
    expect(auth.rutaInicial()).toBe('/panel');
  });

  it('la ruta inicial depende de los permisos', () => {
    auth.usuario.set(usuario(['portal:voluntario'])); expect(auth.rutaInicial()).toBe('/mi-actividad');
    auth.usuario.set(usuario(['campanas:leer'])); expect(auth.rutaInicial()).toBe('/campanas');
    auth.usuario.set(usuario([])); expect(auth.rutaInicial()).toBe('/acceso-denegado');
  });

  it('el interceptor añade el Bearer a la API pero no al login, al portal público ni a terceros', () => {
    sessionStorage.setItem('rs_token', 'jwt-123'); (auth as unknown as { _token: { set(v: string): void } })._token.set('jwt-123');
    const c = TestBed.inject(HttpClient);
    c.get('/api/v1/campanas').subscribe();
    expect(http.expectOne('/api/v1/campanas').request.headers.get('Authorization')).toBe('Bearer jwt-123');
    c.post('/api/v1/auth/login', {}).subscribe({ error: () => undefined });
    expect(http.expectOne('/api/v1/auth/login').request.headers.has('Authorization')).toBe(false);
    c.get('/api/v1/public/resumen').subscribe();
    expect(http.expectOne('/api/v1/public/resumen').request.headers.has('Authorization')).toBe(false);
    c.get('https://otro-sitio.example/api/x').subscribe();
    expect(http.expectOne('https://otro-sitio.example/api/x').request.headers.has('Authorization')).toBe(false);
  });

  it('un 401 con sesión activa la cierra y lleva a /acceso', async () => {
    (auth as unknown as { _token: { set(v: string): void } })._token.set('jwt-123'); auth.usuario.set(usuario([]));
    const ir = vi.spyOn(router, 'navigate').mockResolvedValue(true);
    const p = firstValueFrom(TestBed.inject(HttpClient).get('/api/v1/campanas')).catch((e) => e);
    http.expectOne('/api/v1/campanas').flush(...err(401, 'SESION_EXPIRADA', 'La sesión expiró.'));
    expect(await p).toBeInstanceOf(ApiError);
    expect(auth.autenticado()).toBe(false); expect(sessionStorage.getItem('rs_token')).toBeNull();
    expect(ir).toHaveBeenCalledWith(['/acceso'], expect.anything());
  });

  it('un 401 en el login (credenciales malas) NO redirige', async () => {
    const ir = vi.spyOn(router, 'navigate');
    const p = firstValueFrom(auth.login('ana', 'mal')).catch((e) => e);
    http.expectOne('/api/v1/auth/login').flush(...err(401, 'NO_AUTENTICADO', 'Usuario o contraseña incorrectos.'));
    expect((await p).message).toBe('Usuario o contraseña incorrectos.'); expect(ir).not.toHaveBeenCalled();
  });

  it('un 403 por contraseña temporal lleva a cambiarla', async () => {
    const ir = vi.spyOn(router, 'navigate').mockResolvedValue(true);
    const p = firstValueFrom(TestBed.inject(HttpClient).get('/api/v1/campanas')).catch(() => undefined);
    http.expectOne('/api/v1/campanas').flush(...err(403, 'CAMBIO_PASSWORD_REQUERIDO'));
    await p; expect(ir).toHaveBeenCalledWith(['/cambiar-password']);
  });

  it('restaurar() recupera al usuario con el token guardado y limpia si ya no vale', async () => {
    (auth as unknown as { _token: { set(v: string): void } })._token.set('jwt-123');
    const ok = auth.restaurar(); http.expectOne('/api/v1/auth/me').flush(usuario(['x:y'])); await ok;
    expect(auth.usuario()?.username).toBe('ana');
    const mal = auth.restaurar(); http.expectOne('/api/v1/auth/me').flush(...err(401, 'SESION_REVOCADA')); await mal;
    expect(auth.autenticado()).toBe(false);
  });

  describe('guards', () => {
    const correr = (g: ReturnType<typeof permisoGuard>, url = '/x') => TestBed.runInInjectionContext(() => g({} as never, { url } as never));
    const sesion = (u: Usuario) => { (auth as unknown as { _token: { set(v: string): void } })._token.set('t'); auth.usuario.set(u); };
    it('authGuard: sin sesión redirige a /acceso conservando la ruta pedida', () => {
      expect(router.serializeUrl(correr(authGuard, '/donaciones') as never)).toBe('/acceso?volver=%2Fdonaciones');
    });
    it('authGuard: con sesión pasa; con contraseña temporal obliga a cambiarla', () => {
      sesion(usuario([])); expect(correr(authGuard)).toBe(true);
      sesion(usuario([], { debe_cambiar_password: true }));
      expect(router.serializeUrl(correr(authGuard, '/panel') as never)).toBe('/cambiar-password');
    });
    it('guestGuard: quien ya ingresó no ve el login', () => {
      expect(correr(guestGuard)).toBe(true);
      sesion(usuario(['dashboard:leer'])); expect(router.serializeUrl(correr(guestGuard) as never)).toBe('/panel');
    });
    it('permisoGuard: exige al menos uno de los permisos', () => {
      sesion(usuario(['campanas:leer']));
      expect(correr(permisoGuard('campanas:leer', 'x:y'))).toBe(true);
      expect(router.serializeUrl(correr(permisoGuard('usuarios:leer')) as never)).toBe('/acceso-denegado');
    });
    it('inicioGuard envía a /acceso o a la ruta inicial', () => {
      expect(router.serializeUrl(correr(inicioGuard) as never)).toBe('/acceso');
      sesion(usuario(['dashboard:leer'])); expect(router.serializeUrl(correr(inicioGuard) as never)).toBe('/panel');
    });
  });
});
