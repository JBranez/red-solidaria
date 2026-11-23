"""Dashboard, reportes internos y datos públicos."""
from __future__ import annotations

from app.repositories.reportes import ReporteRepository
from app.schemas.reportes import (
    KpiCobertura, KpiFinanciero, KpiOperacion, KpiResultados, KpisOut, PorCategoriaOut, PorSectorOut,
    PublicoCampanaOut, PublicoCategoriaOut, PublicoResumenOut, PublicoSectorOut, PublicoTotalesOut,
    SerieMensualOut, TopDonanteOut,
)


class ReporteService:
    def __init__(self, repo: ReporteRepository) -> None:
        self.repo = repo

    def kpis(self) -> KpisOut:
        financiero, cobertura, operacion, resultados = (conjunto[0] for conjunto in self.repo.kpis())
        return KpisOut(
            financiero=KpiFinanciero.model_validate(financiero),
            cobertura=KpiCobertura.model_validate(cobertura),
            operacion=KpiOperacion.model_validate(operacion),
            resultados=KpiResultados.model_validate(resultados),
        )

    def series(self, meses: int) -> list[SerieMensualOut]:
        return [SerieMensualOut.model_validate(f) for f in self.repo.series(meses=meses)]

    def por_categoria(self) -> list[PorCategoriaOut]:
        return [PorCategoriaOut.model_validate(f) for f in self.repo.por_categoria()]

    def por_sector(self) -> list[PorSectorOut]:
        return [PorSectorOut.model_validate(f) for f in self.repo.por_sector()]

    def top_donantes(self, limite: int) -> list[TopDonanteOut]:
        return [TopDonanteOut.model_validate(f) for f in self.repo.top_donantes(limite=limite)]

    # ---- público: nunca incluye datos personales
    def publico_resumen(self) -> PublicoResumenOut:
        totales, sectores, categorias = self.repo.publico_resumen()
        return PublicoResumenOut(
            totales=PublicoTotalesOut.model_validate(totales[0]),
            por_sector=[PublicoSectorOut.model_validate(f) for f in sectores],
            por_categoria=[PublicoCategoriaOut.model_validate(f) for f in categorias],
        )

    def publico_campanas(self) -> list[PublicoCampanaOut]:
        return [PublicoCampanaOut.model_validate(f) for f in self.repo.publico_campanas()]

