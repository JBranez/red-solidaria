import { computed, DestroyRef, inject, signal } from '@angular/core';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { Observable } from 'rxjs';
import { toApiError } from '../models/api-error';
import { Pagina } from '../models/api.models';

/** Estado y lógica comunes de los listados: paginación del servidor, carga, error y búsqueda con retardo. */
export abstract class ListaBase<T> {
  private readonly destroyRef = inject(DestroyRef);
  readonly items = signal<T[]>([]);
  readonly total = signal(0);
  readonly pagina = signal(1);
  readonly cargando = signal(true);
  readonly error = signal<string | null>(null);
  readonly tamano = 15;
  readonly paginas = computed(() => Math.max(1, Math.ceil(this.total() / this.tamano)));
  private temporizador: ReturnType<typeof setTimeout> | undefined;
  private peticion = 0;

  protected abstract consultar(): Observable<Pagina<T>>;

  cargar(): void {
    const mia = ++this.peticion; // descarta respuestas tardías de consultas anteriores
    this.cargando.set(true);
    this.error.set(null);
    this.consultar().pipe(takeUntilDestroyed(this.destroyRef)).subscribe({
      next: (r) => {
        if (mia !== this.peticion) return;
        this.items.set(r.items);
        this.total.set(r.total);
        if (r.items.length === 0 && r.total > 0 && this.pagina() > 1) { this.irA(this.paginas()); return; }
        this.cargando.set(false);
      },
      error: (e) => { if (mia === this.peticion) { this.error.set(toApiError(e).message); this.cargando.set(false); } },
    });
  }
  irA(p: number): void { this.pagina.set(Math.min(Math.max(1, p), this.paginas())); this.cargar(); }
  /** Cambia un filtro: vuelve a la primera página. */
  refiltrar(): void { this.pagina.set(1); this.cargar(); }
  /** Búsqueda de texto: espera 300 ms tras la última tecla antes de consultar. */
  buscarConRetardo(): void { clearTimeout(this.temporizador); this.temporizador = setTimeout(() => this.refiltrar(), 300); }
}
