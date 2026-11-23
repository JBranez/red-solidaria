import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { AuthService } from '../services/auth.service';

/** Solo con sesión. Una contraseña temporal obliga a pasar por /cambiar-password. */
export const authGuard: CanActivateFn = (_route, state) => {
  const auth = inject(AuthService);
  const router = inject(Router);
  if (!auth.autenticado()) return router.createUrlTree(['/acceso'], { queryParams: { volver: state.url } });
  if (auth.usuario()?.debe_cambiar_password && !state.url.startsWith('/cambiar-password')) return router.createUrlTree(['/cambiar-password']);
  return true;
};

/** Pantallas de invitado (acceso): si ya hay sesión, se envía al inicio. */
export const guestGuard: CanActivateFn = () => {
  const auth = inject(AuthService);
  return auth.autenticado() ? inject(Router).createUrlTree([auth.rutaInicial()]) : true;
};

/** Autorización de navegación (comodidad de la interfaz). La API vuelve a exigir el permiso en cada petición. */
export const permisoGuard = (...permisos: string[]): CanActivateFn => () => {
  const auth = inject(AuthService);
  return auth.tieneAlguno(...permisos) ? true : inject(Router).createUrlTree(['/acceso-denegado']);
};

export const inicioGuard: CanActivateFn = () => {
  const auth = inject(AuthService);
  return inject(Router).createUrlTree([auth.autenticado() ? auth.rutaInicial() : '/acceso']);
};
