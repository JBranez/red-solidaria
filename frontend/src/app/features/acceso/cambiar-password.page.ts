import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { form, FormField, minLength, required, submit, validate } from '@angular/forms/signals';
import { Router, RouterLink } from '@angular/router';
import { firstValueFrom } from 'rxjs';
import { toApiError } from '../../core/models/api-error';
import { AuthService } from '../../core/services/auth.service';
import { ToastService } from '../../core/services/toast.service';
import { Campo } from '../../shared/ui';

@Component({
  selector: 'rs-cambiar-password',
  imports: [FormField, RouterLink, Campo],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="min-vh-100 d-flex align-items-center justify-content-center p-3">
      <main class="card shadow-sm w-100" style="max-width:30rem"><div class="card-body p-4 p-md-5">
        <h1 class="h4 mb-1"><i class="bi bi-key me-2 text-campana"></i>Cambiar contraseña</h1>
        @if (obligatorio()) { <div class="alert alert-info py-2 small mt-3" role="status">Su contraseña es temporal. Elija una nueva para continuar.</div> }
        @else { <p class="text-secondary small">Al cambiarla se cerrarán las demás sesiones abiertas con esta cuenta.</p> }
        @if (error(); as e) { <div class="alert alert-danger py-2 small" role="alert">{{ e }}</div> }
        <form (submit)="guardar($event)" novalidate class="mt-3">
          <rs-campo etiqueta="Contraseña actual" [campo]="f.actual"><input class="form-control" type="password" autocomplete="current-password" [formField]="f.actual" /></rs-campo>
          <rs-campo etiqueta="Contraseña nueva" [campo]="f.nueva" ayuda="Mínimo 10 caracteres, con letras y números. Una frase larga es mejor que una palabra rara.">
            <input class="form-control" type="password" autocomplete="new-password" [formField]="f.nueva" />
          </rs-campo>
          <div class="progress mb-3" style="height:.3rem" aria-hidden="true"><div class="progress-bar" [class]="fuerza().clase" [style.width.%]="fuerza().pct"></div></div>
          <rs-campo etiqueta="Repita la contraseña nueva" [campo]="f.confirmar"><input class="form-control" type="password" autocomplete="new-password" [formField]="f.confirmar" /></rs-campo>
          <div class="d-flex gap-2 justify-content-end mt-2">
            @if (!obligatorio()) { <a class="btn btn-light" [routerLink]="auth.rutaInicial()">Cancelar</a> }
            @else { <button class="btn btn-light" type="button" (click)="auth.cerrarSesion()">Salir</button> }
            <button class="btn btn-primary" type="submit" [disabled]="enviando()">Guardar contraseña</button>
          </div>
        </form>
      </div></main>
    </div>`,
})
export class CambiarPasswordPage {
  protected readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  private readonly toast = inject(ToastService);
  protected readonly obligatorio = computed(() => this.auth.usuario()?.debe_cambiar_password === true);

  protected readonly modelo = signal({ actual: '', nueva: '', confirmar: '' });
  protected readonly f = form(this.modelo, (p) => {
    required(p.actual, { message: 'Ingrese su contraseña actual.' });
    required(p.nueva, { message: 'Ingrese la nueva contraseña.' });
    minLength(p.nueva, 10, { message: 'Use al menos 10 caracteres.' });
    validate(p.nueva, ({ value }) => (/[A-Za-zÁÉÍÓÚáéíóúÑñ]/.test(value()) && /\d/.test(value()) ? undefined : { kind: 'composicion', message: 'Combine letras y números.' }));
    required(p.confirmar, { message: 'Repita la nueva contraseña.' });
    validate(p.confirmar, ({ value, valueOf }) => (value() === valueOf(p.nueva) ? undefined : { kind: 'distinta', message: 'Las contraseñas no coinciden.' }));
  });
  protected readonly error = signal<string | null>(null);
  protected readonly enviando = signal(false);
  protected readonly fuerza = computed(() => {
    const v = this.modelo().nueva;
    const puntos = (v.length >= 10 ? 1 : 0) + (v.length >= 14 ? 1 : 0) + (/[a-z]/.test(v) && /[A-Z]/.test(v) ? 1 : 0) + (/\d/.test(v) ? 1 : 0) + (/[^A-Za-z0-9]/.test(v) ? 1 : 0);
    return puntos <= 2 ? { pct: Math.max(8, puntos * 20), clase: 'bg-danger' } : puntos <= 3 ? { pct: 60, clase: 'bg-warning' } : { pct: 100, clase: 'bg-success' };
  });

  protected async guardar(evento: Event): Promise<void> {
    evento.preventDefault();
    this.error.set(null);
    await submit(this.f, async () => {
      this.enviando.set(true);
      try {
        await firstValueFrom(this.auth.cambiarPassword(this.modelo().actual, this.modelo().nueva));
        this.toast.ok('Contraseña actualizada.');
        await this.router.navigateByUrl(this.auth.rutaInicial());
      } catch (e) { this.error.set(toApiError(e).message); } finally { this.enviando.set(false); }
    });
  }
}
