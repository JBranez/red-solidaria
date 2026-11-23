"""Utilidades compartidas: patrones LIKE seguros y exportación CSV."""
from __future__ import annotations

import csv
import io
from datetime import date, datetime
from decimal import Decimal
from typing import Any, Iterable, Sequence


def like_pattern(texto: str | None) -> str | None:
    """Convierte lo que escribe el usuario en un patrón LIKE '%…%' con los comodines escapados.

    Los procedimientos lo usan con ESCAPE '\\', de modo que "50%" busca literalmente "50%".
    """
    if texto is None:
        return None
    limpio = texto.strip()
    if not limpio:
        return None
    for ch in ("\\", "%", "_", "["):
        limpio = limpio.replace(ch, "\\" + ch)
    return f"%{limpio}%"


_INICIOS_PELIGROSOS = ("=", "+", "-", "@", "\t", "\r")


def _celda(valor: Any) -> str:
    if valor is None:
        return ""
    if isinstance(valor, bool):
        return "Sí" if valor else "No"
    if isinstance(valor, datetime):
        return valor.strftime("%Y-%m-%d %H:%M")
    if isinstance(valor, date):
        return valor.isoformat()
    if isinstance(valor, Decimal):
        return format(valor, "f")
    texto = str(valor)
    # Inyección de fórmulas CSV: Excel ejecuta celdas que empiezan con = + - @
    if texto.startswith(_INICIOS_PELIGROSOS):
        texto = "'" + texto
    return texto


def to_csv(filas: Iterable[dict[str, Any]], columnas: Sequence[tuple[str, str]]) -> str:
    """CSV UTF-8 con BOM (Excel lo abre con tildes correctas). `columnas` = (clave, encabezado)."""
    salida = io.StringIO()
    escritor = csv.writer(salida, lineterminator="\r\n")
    escritor.writerow([titulo for _, titulo in columnas])
    for fila in filas:
        escritor.writerow([_celda(fila.get(clave)) for clave, _ in columnas])
    return "\ufeff" + salida.getvalue()
