import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { toSignal } from '@angular/core/rxjs-interop';
import { form, FormField, required, submit } from '@angular/forms/signals';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { catchError, firstValueFrom, of } from 'rxjs';
import { toApiError } from '../../core/models/api-error';
import { PublicoService } from '../../core/services/api.services';
import { AuthService } from '../../core/services/auth.service';
import { fmtMoneda, fmtNum } from '../../core/util/format';
import { Campo } from '../../shared/ui';

/** Estructura: ejemplo "Sign-in" de Bootstrap, con un panel lateral que muestra el impacto real (datos públicos agregados). */
@Component({
  selector: 'rs-acceso',
  imports: [FormField, RouterLink, Campo],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="row g-0 min-vh-100">
      <section class="col-lg-6 rs-hero d-none d-lg-flex flex-column justify-content-between p-5" aria-label="Impacto de la red">
        <div class="d-flex align-items-center text-white fw-semibold fs-5"><span class="rs-brand-mark" aria-hidden="true"><i class="bi bi-diagram-3-fill"></i></span>Red Solidaria</div>
        <div class="position-relative" style="z-index:1">
          <h1 class="display-5 fw-bold mb-3" style="max-width:15ch;letter-spacing:-.04em">Cada donación y cada entrega, a la vista.</h1>
          <p class="fs-6 mb-5" style="max-width:42ch;color:#cbd5e1">Gestión transparente de campañas, donantes, hogares y voluntarios: de quien dona a quien recibe.</p>
          @if (resumen(); as r) {
            <div class="row g-4">
              <div class="col-4"><div class="rs-cifra">{{ num(r.totales.hogares_atendidos) }}</div><div class="rs-cifra-label">hogares atendidos</div></div>
              <div class="col-4"><div class="rs-cifra">{{ num(r.totales.entregas_realizadas) }}</div><div class="rs-cifra-label">entregas realizadas</div></div>
              <div class="col-4"><div class="rs-cifra">{{ moneda(r.totales.recaudado_confirmado, r.totales.moneda) }}</div><div class="rs-cifra-label">recaudados y verificados</div></div>
            </div>
          }
        </div>
        <a routerLink="/transparencia" class="link-light small position-relative" style="z-index:1"><i class="bi bi-globe2 me-1"></i>Ver el portal público de transparencia <i class="bi bi-arrow-right"></i></a>
      </section>

      <section class="col-lg-6 d-flex align-items-center justify-content-center bg-white">
        <main class="form-signin">
          <div class="d-lg-none d-flex align-items-center fw-semibold fs-5 mb-4"><span class="rs-brand-mark bg-dark text-white" aria-hidden="true"><i class="bi bi-diagram-3-fill"></i></span>Red Solidaria</div>
          <h2 class="h3 mb-1">Ingresar</h2>
          <p class="text-secondary mb-4">Use la cuenta que le entregó la organización.</p>

          @if (expirada) { <div class="alert alert-warning py-2 small" role="status"><i class="bi bi-clock-history me-1"></i>Su sesión expiró. Ingrese nuevamente.</div> }
          @if (error(); as e) { <div class="alert alert-danger py-2 small" role="alert"><i class="bi bi-exclamation-octagon me-1"></i>{{ e }}</div> }

          <form (submit)="entrar($event)" novalidate>
            <rs-campo etiqueta="Usuario" [campo]="f.username">
              <input class="form-control form-control-lg" type="text" autocomplete="username" autocapitalize="none" spellcheck="false" [formField]="f.username" />
            </rs-campo>
            <rs-campo etiqueta="Contraseña" [campo]="f.password">
              <div class="input-group input-group-lg">
                <input class="form-control" [type]="verClave() ? 'text' : 'password'" autocomplete="current-password" [formField]="f.password" />
                <button class="btn btn-outline-secondary" type="button" (click)="verClave.set(!verClave())" [attr.aria-label]="verClave() ? 'Ocultar contraseña' : 'Mostrar contraseña'"><i class="bi" [class]="verClave() ? 'bi-eye-slash' : 'bi-eye'"></i></button>
              </div>
            </rs-campo>
            <button class="btn btn-dark btn-lg w-100 mt-2" type="submit" [disabled]="enviando()">
              @if (enviando()) { <span class="spinner-border spinner-border-sm me-2" aria-hidden="true"></span>Verificando… } @else { Ingresar }
            </button>
          </form>
          <p class="text-secondary small mt-4 mb-0"><i class="bi bi-shield-check me-1"></i>Tras varios intentos fallidos la cuenta se bloquea unos minutos. Si olvidó su contraseña, solicite un restablecimiento al administrador.</p>
        </main>
      </section>
    </div>`,
})
export class AccesoPage {
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);

  protected readonly modelo = signal({ username: '', password: '' });
  protected readonly f = form(this.modelo, (p) => {
    required(p.username, { message: 'Ingrese su usuario.' });
    required(p.password, { message: 'Ingrese su contraseña.' });
  });
  protected readonly error = signal<string | null>(null);
  protected readonly enviando = signal(false);
  protected readonly verClave = signal(false);
  protected readonly expirada = this.route.snapshot.queryParamMap.get('sesion') === 'expirada';
  protected readonly resumen = toSignal(inject(PublicoService).resumen().pipe(catchError(() => of(null))), { initialValue: null });
  protected readonly num = fmtNum;
  protected readonly moneda = fmtMoneda;

  protected async entrar(evento: Event): Promise<void> {
    evento.preventDefault();
    this.error.set(null);
    await submit(this.f, async () => {
      this.enviando.set(true);
      try {
        const { username, password } = this.modelo();
        await firstValueFrom(this.auth.login(username.trim(), password));
        const destino = this.auth.usuario()?.debe_cambiar_password ? '/cambiar-password' : (this.rutaSegura(this.route.snapshot.queryParamMap.get('volver')) ?? this.auth.rutaInicial());
        await this.router.navigateByUrl(destino);
      } catch (e) {
        this.error.set(toApiError(e).message);
        this.modelo.update((m) => ({ ...m, password: '' }));
      } finally {
        this.enviando.set(false);
      }
    });
  }

  /** Solo rutas internas: evita que ?volver=https://sitio-malicioso.com sirva de redirección abierta. */
  private rutaSegura(r: string | null): string | null { return r && r.startsWith('/') && !r.startsWith('//') && !r.startsWith('/acceso') ? r : null; }
}
