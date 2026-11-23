import { HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { AuthService } from '../services/auth.service';

const PUBLICAS = ['/api/v1/auth/login', '/api/v1/public/'];

/** Añade `Authorization: Bearer <token>` a las peticiones de la API (salvo login y portal público). */
export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const token = inject(AuthService).token();
  if (!token || !req.url.startsWith('/api/') || PUBLICAS.some((p) => req.url.startsWith(p))) return next(req);
  return next(req.clone({ setHeaders: { Authorization: `Bearer ${token}` } }));
};
