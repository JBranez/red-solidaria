import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import { AuthService } from '../../core/services/auth.service';

@Component({
  selector: 'rs-acceso-denegado',
  imports: [RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="rs-empty py-5"><i class="bi bi-shield-lock"></i>
      <h1 class="h4">No tiene acceso a esta sección</h1>
      <p class="mb-3">Su rol no incluye este permiso. Si cree que es un error, pídaselo a un administrador.</p>
      <a class="btn btn-primary" [routerLink]="inicio">Ir al inicio</a>
    </div>`,
})
export class AccesoDenegadoPage { protected readonly inicio = inject(AuthService).rutaInicial(); }

@Component({
  selector: 'rs-no-encontrada',
  imports: [RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="min-vh-100 d-grid place-items-center" style="display:grid;place-items:center">
      <div class="rs-empty"><i class="bi bi-compass"></i>
        <h1 class="h4">Página no encontrada</h1>
        <p class="mb-3">La dirección no existe o fue movida.</p>
        <a class="btn btn-primary" routerLink="/">Volver al inicio</a>
      </div>
    </div>`,
})
export class NoEncontradaPage {}
