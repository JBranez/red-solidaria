"""Dashboard, reportes internos y datos públicos."""
from __future__ import annotations

from typing import Any

from app.db.executor import Executor

Fila = dict[str, Any]


class ReporteRepository:
    def __init__(self, db: Executor) -> None:
        self.db = db

    def kpis(self) -> list[list[Fila]]:
        return self.db.fetch_sets("usp_dashboard_kpis")

    def series(self, *, meses: int) -> list[Fila]:
        return self.db.fetch_all("usp_dashboard_series", meses=meses)

    def por_categoria(self) -> list[Fila]:
        return self.db.fetch_all("usp_dashboard_por_categoria")

    def por_sector(self) -> list[Fila]:
        return self.db.fetch_all("usp_dashboard_por_sector")

    def top_donantes(self, *, limite: int) -> list[Fila]:
        return self.db.fetch_all("usp_reporte_top_donantes", limite=limite)

    def publico_resumen(self) -> list[list[Fila]]:
        return self.db.fetch_sets("usp_publico_resumen")

    def publico_campanas(self) -> list[Fila]:
        return self.db.fetch_all("usp_publico_campanas")
