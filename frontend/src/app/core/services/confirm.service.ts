import { Injectable, signal } from '@angular/core';

export interface PedidoConfirmacion {
  titulo: string; mensaje: string; confirmar: string; peligro: boolean;
  pedirMotivo: boolean; motivoEtiqueta: string; resolver: (r: { ok: boolean; motivo: string }) => void;
}

/** Diálogo de confirmación basado en promesas (reemplaza window.confirm). Puede exigir un motivo. */
@Injectable({ providedIn: 'root' })
export class ConfirmService {
  readonly pedido = signal<PedidoConfirmacion | null>(null);

  preguntar(o: { titulo: string; mensaje?: string; confirmar?: string; peligro?: boolean; pedirMotivo?: boolean; motivoEtiqueta?: string }): Promise<{ ok: boolean; motivo: string }> {
    return new Promise((resolver) =>
      this.pedido.set({
        titulo: o.titulo, mensaje: o.mensaje ?? '', confirmar: o.confirmar ?? 'Confirmar', peligro: o.peligro ?? false,
        pedirMotivo: o.pedirMotivo ?? false, motivoEtiqueta: o.motivoEtiqueta ?? 'Motivo', resolver,
      }),
    );
  }
  resolver(ok: boolean, motivo = ''): void {
    const p = this.pedido();
    this.pedido.set(null);
    p?.resolver({ ok, motivo: motivo.trim() });
  }
}
