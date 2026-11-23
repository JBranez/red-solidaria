import { Component, signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { form, required } from '@angular/forms/signals';
import { Observable, of, Subject, throwError } from 'rxjs';
import { describe, expect, it, vi } from 'vitest';
import { ApiError } from '../models/api-error';
import { Pagina } from '../models/api.models';
import { aParams } from '../services/api.services';
import { ConfirmService } from '../services/confirm.service';
import { aNumero, aTexto, enviar } from './form-utils';
import { ListaBase } from './lista-base';

@Component({ selector: 'rs-prueba', template: '' })
class Lista extends ListaBase<number> {
  fuente: () => Observable<Pagina<number>> = () => of({ items: [1, 2], total: 2, pagina: 1, tamano: 15 });
  protected override consultar(): Observable<Pagina<number>> { return this.fuente(); }
}
const pag = (items: number[], total = items.length): Pagina<number> => ({ items, total, pagina: 1, tamano: 15 });

describe('aParams', () => {
  it('descarta filtros vacíos, nulos y false (la API rechaza los parámetros en blanco)', () => {
    const p = aParams({ q: 'ana', estado: '', id: null, x: undefined, activo: false, pagina: 2, ok: true });
    expect(p.keys().sort()).toEqual(['ok', 'pagina', 'q']); expect(p.get('pagina')).toBe('2');
  });
});

describe('conversores de formularios', () => {
  it('aNumero / aTexto', () => {
    expect(aNumero('')).toBeNull(); expect(aNumero('12')).toBe(12); expect(aNumero(null)).toBeNull();
    expect(aTexto('  hola ')).toBe('hola'); expect(aTexto('   ')).toBeNull();
  });
});

describe('ListaBase', () => {
  const crear = () => TestBed.runInInjectionContext(() => new Lista());
  it('carga la página y calcula el total de páginas', () => {
    const l = crear(); l.fuente = () => of(pag(Array(15).fill(1), 31)); l.cargar();
    expect(l.items()).toHaveLength(15); expect(l.paginas()).toBe(3); expect(l.cargando()).toBe(false);
  });
  it('descarta la respuesta tardía de una consulta anterior', () => {
    const l = crear(); const a = new Subject<Pagina<number>>(); const b = new Subject<Pagina<number>>();
    l.fuente = () => a; l.cargar(); l.fuente = () => b; l.cargar();
    b.next(pag([2])); a.next(pag([1]));
    expect(l.items()).toEqual([2]);
  });
  it('un error muestra el mensaje y deja de cargar', () => {
    const l = crear(); l.fuente = () => throwError(() => new ApiError(500, 'X', 'Falló la consulta.')); l.cargar();
    expect(l.error()).toBe('Falló la consulta.'); expect(l.cargando()).toBe(false);
  });
  it('si la página quedó fuera de rango vuelve a la última', () => {
    const l = crear(); let n = 0;
    l.fuente = () => (n++ === 0 ? of(pag([], 16)) : of(pag([1], 16)));
    l.pagina.set(3); l.cargar(); expect(l.pagina()).toBe(2); expect(l.items()).toEqual([1]);
  });
  it('refiltrar vuelve a la primera página', () => { const l = crear(); l.pagina.set(4); l.refiltrar(); expect(l.pagina()).toBe(1); });
});

describe('enviar (formularios con Signal Forms)', () => {
  const montar = () => TestBed.runInInjectionContext(() => {
    const modelo = signal({ nombre: '' });
    const f = form(modelo, (p) => { required(p.nombre, { message: 'Obligatorio.' }); });
    return { modelo, f, st: { enviando: signal(false), error: signal<string | null>(null) } };
  });
  it('no ejecuta la acción si el formulario no es válido, y marca los campos como tocados', async () => {
    const { f, st } = montar(); const accion = vi.fn();
    await enviar(f, st, accion);
    expect(accion).not.toHaveBeenCalled(); expect(f.nombre().touched()).toBe(true); expect(f.nombre().errors()[0].message).toBe('Obligatorio.');
  });
  it('ejecuta la acción cuando es válido y libera el estado de envío', async () => {
    const { modelo, f, st } = montar(); modelo.set({ nombre: 'Ana' }); const accion = vi.fn().mockResolvedValue(undefined);
    await enviar(f, st, accion);
    expect(accion).toHaveBeenCalledWith(false); expect(st.enviando()).toBe(false); expect(st.error()).toBeNull();
  });
  it('muestra el error de la API', async () => {
    const { modelo, f, st } = montar(); modelo.set({ nombre: 'Ana' });
    await enviar(f, st, () => Promise.reject(new ApiError(422, 'REGLA_DE_NEGOCIO', 'La campaña no está activa.')));
    expect(st.error()).toBe('La campaña no está activa.');
  });
  it('ante un posible duplicado pregunta y reenvía con confirmación', async () => {
    const { modelo, f, st } = montar(); modelo.set({ nombre: 'Ana' });
    const confirm = TestBed.inject(ConfirmService); vi.spyOn(confirm, 'preguntar').mockResolvedValue({ ok: true, motivo: '' });
    const accion = vi.fn().mockRejectedValueOnce(new ApiError(409, 'REQUIERE_CONFIRMACION', 'Ya existe uno igual.')).mockResolvedValueOnce(undefined);
    await enviar(f, st, accion, confirm);
    expect(accion.mock.calls.map((c) => c[0])).toEqual([false, true]); expect(st.error()).toBeNull();
  });
  it('si el usuario no confirma el duplicado, no se reenvía', async () => {
    const { modelo, f, st } = montar(); modelo.set({ nombre: 'Ana' });
    const confirm = TestBed.inject(ConfirmService); vi.spyOn(confirm, 'preguntar').mockResolvedValue({ ok: false, motivo: '' });
    const accion = vi.fn().mockRejectedValue(new ApiError(409, 'REQUIERE_CONFIRMACION', 'x'));
    await enviar(f, st, accion, confirm);
    expect(accion).toHaveBeenCalledTimes(1);
  });
});
