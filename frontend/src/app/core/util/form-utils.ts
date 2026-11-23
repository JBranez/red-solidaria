import { WritableSignal } from '@angular/core';
import { submit } from '@angular/forms/signals';
import type { FieldTree } from '@angular/forms/signals';
import { toApiError } from '../models/api-error';
import { ConfirmService } from '../services/confirm.service';

export interface EstadoEnvio { enviando: WritableSignal<boolean>; error: WritableSignal<string | null> }

/**
 * Envía un formulario de Signal Forms: valida (marca todos los campos), muestra errores de la API y, si el
 * servidor pide confirmación (posible duplicado), pregunta al usuario y reenvía con `confirmado = true`.
 */
export async function enviar<T>(f: FieldTree<T>, st: EstadoEnvio, accion: (confirmado: boolean) => Promise<void>, confirm?: ConfirmService): Promise<void> {
  await submit(f, async () => {
    st.enviando.set(true);
    st.error.set(null);
    try {
      await accion(false);
    } catch (e) {
      const err = toApiError(e);
      if (err.requiereConfirmacion && confirm) {
        const r = await confirm.preguntar({ titulo: 'Antes de continuar', mensaje: err.message, confirmar: 'Continuar de todos modos' });
        if (r.ok) {
          try { await accion(true); } catch (e2) { st.error.set(toApiError(e2).message); }
        }
      } else {
        st.error.set(err.message);
      }
    } finally {
      st.enviando.set(false);
    }
  });
}

export const aNumero = (v: string | number | null | undefined): number | null => (v === '' || v === null || v === undefined ? null : Number(v));
export const aTexto = (v: string | null | undefined): string | null => (v && v.trim() ? v.trim() : null);
