import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { Router } from '@angular/router';
import { catchError, throwError } from 'rxjs';
import { toApiError } from '../models/api-error';
import { AuthService } from '../services/auth.service';

/** Normaliza todo error HTTP a `ApiError` y aplica las reglas globales de sesión. */
export const errorInterceptor: HttpInterceptorFn = (req, next) => {
  const auth = inject(AuthService);
  const router = inject(Router);
  return next(req).pipe(
    catchError((err: unknown) => {
      const e = toApiError(err instanceof HttpErrorResponse ? err : err);
      const esLogin = req.url.endsWith('/auth/login');
      if (e.status === 401 && !esLogin && auth.autenticado()) auth.expirar();
      if (e.status === 403 && e.codigo === 'CAMBIO_PASSWORD_REQUERIDO') void router.navigate(['/cambiar-password']);
      return throwError(() => e);
    }),
  );
};
