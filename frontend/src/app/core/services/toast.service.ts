import { Injectable, signal } from '@angular/core';

export interface Aviso { id: number; tipo: 'ok' | 'error' | 'aviso'; texto: string }

@Injectable({ providedIn: 'root' })
export class ToastService {
  private siguiente = 1;
  readonly avisos = signal<Aviso[]>([]);

  ok(texto: string): void { this.mostrar('ok', texto, 4000); }
  error(texto: string): void { this.mostrar('error', texto, 7000); }
  aviso(texto: string): void { this.mostrar('aviso', texto, 6000); }
  cerrar(id: number): void { this.avisos.update((a) => a.filter((x) => x.id !== id)); }

  private mostrar(tipo: Aviso['tipo'], texto: string, ms: number): void {
    const id = this.siguiente++;
    this.avisos.update((a) => [...a.slice(-3), { id, tipo, texto }]);
    setTimeout(() => this.cerrar(id), ms);
  }
}
