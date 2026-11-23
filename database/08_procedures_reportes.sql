/* =====================================================================
   08_procedures_reportes.sql  |  Dashboard, reportes y datos públicos

   Los indicadores se separan por nivel de la cadena de resultados:
     1 financiero (insumos) · 2 cobertura (productos) · 3 operación · 4 resultados y calidad
   "Unidades entregadas" y "personas estimadas" son indicadores OPERATIVOS: no miden
   reducción de pobreza (ver docs/ALCANCE_FUNCIONAL.md, catálogo de indicadores).
   ===================================================================== */
USE [$(DB_NAME)];
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- 4 result sets de una fila: financiero, cobertura, operación, resultados
CREATE OR ALTER PROCEDURE dbo.usp_dashboard_kpis
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @hoy DATE = CONVERT(DATE, SYSDATETIME());

    -- 1. FINANCIERO ---------------------------------------------------
    SELECT ISNULL(SUM(v.recaudado_confirmado), 0)  AS recaudado_confirmado,
           ISNULL(SUM(v.recaudado_pendiente), 0)   AS recaudado_pendiente,
           ISNULL(SUM(v.donaciones_confirmadas), 0) AS donaciones_confirmadas,
           ISNULL(SUM(v.donaciones_pendientes), 0) AS donaciones_pendientes,
           ISNULL(SUM(v.gastado_aprobado), 0)      AS gastado_aprobado,
           ISNULL(SUM(v.saldo_disponible), 0)      AS saldo_disponible,
           ISNULL(SUM(v.meta_recaudacion), 0)      AS meta_recaudacion,
           CAST(100.0 * SUM(v.recaudado_confirmado) / NULLIF(SUM(v.meta_recaudacion), 0) AS DECIMAL(7,1)) AS pct_meta,
           CAST(SUM(v.recaudado_confirmado) / NULLIF(SUM(v.donaciones_confirmadas), 0) AS DECIMAL(12,2)) AS ticket_promedio,
           (SELECT COUNT(DISTINCT id_donante) FROM dbo.donacion WHERE estado = 'Confirmada') AS donantes_activos,
           CASE WHEN COUNT(DISTINCT v.moneda) = 1 THEN MAX(v.moneda) ELSE 'VARIAS' END AS moneda
    FROM dbo.vw_campana_resumen v;

    -- 2. COBERTURA ----------------------------------------------------
    DECLARE @registrados INT = (SELECT COUNT(*) FROM dbo.beneficiario WHERE activo = 1);
    DECLARE @atendidos   INT = (SELECT COUNT(DISTINCT id_beneficiario) FROM dbo.entrega WHERE estado = 'Entregada');
    SELECT @registrados AS hogares_registrados,
           @atendidos   AS hogares_atendidos,
           @registrados - (SELECT COUNT(DISTINCT e.id_beneficiario) FROM dbo.entrega e
                           JOIN dbo.beneficiario b ON b.id_beneficiario = e.id_beneficiario
                           WHERE e.estado = 'Entregada' AND b.activo = 1) AS hogares_sin_atender,
           CAST(100.0 * @atendidos / NULLIF(@registrados, 0) AS DECIMAL(5,1)) AS pct_cobertura,
           ISNULL((SELECT SUM(b.integrantes_hogar) FROM dbo.beneficiario b
                   WHERE EXISTS (SELECT 1 FROM dbo.entrega e WHERE e.id_beneficiario = b.id_beneficiario AND e.estado = 'Entregada')), 0) AS personas_estimadas,
           (SELECT COUNT(*) FROM dbo.entrega WHERE estado = 'Entregada')            AS entregas_realizadas,
           ISNULL((SELECT SUM(cantidad) FROM dbo.entrega WHERE estado = 'Entregada'), 0) AS unidades_entregadas,
           (SELECT COUNT(*) FROM dbo.entrega WHERE estado = 'Programada')           AS entregas_programadas,
           (SELECT COUNT(*) FROM dbo.beneficiario WHERE activo = 1 AND consentimiento_datos = 0) AS hogares_sin_consentimiento;

    -- 3. OPERACIÓN ----------------------------------------------------
    SELECT (SELECT COUNT(*) FROM dbo.campana WHERE estado = 'Activa')     AS campanas_activas,
           (SELECT COUNT(*) FROM dbo.campana WHERE estado = 'Borrador')   AS campanas_borrador,
           (SELECT COUNT(*) FROM dbo.campana WHERE estado = 'Pausada')    AS campanas_pausadas,
           (SELECT COUNT(*) FROM dbo.campana WHERE estado = 'Finalizada') AS campanas_finalizadas,
           (SELECT COUNT(*) FROM dbo.campana WHERE estado = 'Activa' AND fecha_fin BETWEEN @hoy AND DATEADD(DAY, 15, @hoy)) AS campanas_por_vencer,
           (SELECT COUNT(*) FROM dbo.campana WHERE estado IN ('Activa', 'Pausada') AND fecha_fin < @hoy) AS campanas_vencidas_sin_cerrar,
           (SELECT COUNT(*) FROM dbo.voluntario WHERE activo = 1)         AS voluntarios_activos,
           (SELECT COUNT(DISTINCT id_voluntario) FROM dbo.entrega WHERE estado = 'Entregada') AS voluntarios_participantes,
           (SELECT COUNT(*) FROM dbo.entrega WHERE estado = 'Programada' AND fecha < @hoy) AS entregas_programadas_vencidas,
           (SELECT COUNT(*) FROM dbo.donacion WHERE estado = 'Pendiente') AS donaciones_por_verificar,
           (SELECT COUNT(*) FROM dbo.gasto WHERE estado = 'Registrado')   AS gastos_por_aprobar;

    -- 4. RESULTADOS Y CALIDAD -----------------------------------------
    DECLARE @abiertas INT  = (SELECT COUNT(*) FROM dbo.necesidad WHERE estado IN ('Pendiente', 'En atencion'));
    DECLARE @cubiertas INT = (SELECT COUNT(*) FROM dbo.necesidad WHERE estado = 'Cubierta');
    SELECT @abiertas  AS necesidades_abiertas,
           @cubiertas AS necesidades_cubiertas,
           (SELECT COUNT(*) FROM dbo.necesidad WHERE estado IN ('Pendiente', 'En atencion') AND urgencia IN ('Critica', 'Alta')) AS necesidades_urgentes,
           CAST(100.0 * @cubiertas / NULLIF(@cubiertas + @abiertas, 0) AS DECIMAL(5,1)) AS pct_necesidades_cubiertas,
           (SELECT CAST(AVG(CAST(DATEDIFF(DAY, fecha_registro, fecha_cobertura) AS DECIMAL(9,2))) AS DECIMAL(7,1))
              FROM dbo.necesidad WHERE estado = 'Cubierta') AS dias_promedio_cobertura,
           (SELECT CAST(AVG(CAST(calificacion AS DECIMAL(4,2))) AS DECIMAL(3,1))
              FROM dbo.retroalimentacion WHERE calificacion IS NOT NULL AND confidencial = 0) AS satisfaccion_promedio,
           (SELECT COUNT(*) FROM dbo.retroalimentacion WHERE estado IN ('Abierta', 'En revision') AND confidencial = 0) AS feedback_abierto,
           (SELECT COUNT(*) FROM dbo.retroalimentacion WHERE estado IN ('Abierta', 'En revision') AND fecha_limite < @hoy AND confidencial = 0) AS feedback_vencido,
           CAST(100.0 * (SELECT COUNT(*) FROM dbo.retroalimentacion
                         WHERE tipo = 'Queja' AND estado IN ('Resuelta', 'Cerrada') AND CONVERT(DATE, resuelta_en) <= fecha_limite AND confidencial = 0)
                 / NULLIF((SELECT COUNT(*) FROM dbo.retroalimentacion
                           WHERE tipo = 'Queja' AND estado IN ('Resuelta', 'Cerrada') AND confidencial = 0), 0) AS DECIMAL(5,1)) AS pct_quejas_en_plazo;
END
GO

-- Serie mensual (últimos @meses meses, incluido el actual)
CREATE OR ALTER PROCEDURE dbo.usp_dashboard_series
    @meses INT = 12
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @inicio DATE = DATEFROMPARTS(YEAR(SYSDATETIME()), MONTH(SYSDATETIME()), 1);
    WITH m AS (
        SELECT @inicio AS mes, 1 AS n
        UNION ALL
        SELECT DATEADD(MONTH, -1, mes), n + 1 FROM m WHERE n < @meses
    )
    SELECT CONVERT(CHAR(7), m.mes, 126) AS mes,
           ISNULL(d.total, 0)     AS donaciones,
           ISNULL(d.n, 0)         AS n_donaciones,
           ISNULL(e.n, 0)         AS entregas,
           ISNULL(e.unidades, 0)  AS unidades
    FROM m
    OUTER APPLY (SELECT SUM(x.monto) AS total, COUNT(*) AS n FROM dbo.donacion x
                 WHERE x.estado = 'Confirmada' AND x.fecha >= m.mes AND x.fecha < DATEADD(MONTH, 1, m.mes)) d
    OUTER APPLY (SELECT COUNT(*) AS n, SUM(y.cantidad) AS unidades FROM dbo.entrega y
                 WHERE y.estado = 'Entregada' AND y.fecha >= m.mes AND y.fecha < DATEADD(MONTH, 1, m.mes)) e
    ORDER BY m.mes
    OPTION (MAXRECURSION 120);
END
GO

-- Equivale a las consultas 1 y 4 del esquema original, pero sin multiplicar filas
CREATE OR ALTER PROCEDURE dbo.usp_dashboard_por_categoria
AS
BEGIN
    SET NOCOUNT ON;
    SELECT cat.id_categoria, cat.nombre AS categoria,
           COUNT(v.id_campana)                          AS campanas,
           ISNULL(SUM(v.recaudado_confirmado), 0)       AS recaudado,
           ISNULL(SUM(v.gastado_aprobado), 0)           AS gastado,
           ISNULL(SUM(v.entregas_realizadas), 0)        AS entregas,
           ISNULL(SUM(v.unidades_entregadas), 0)        AS unidades,
           (SELECT COUNT(DISTINCT e.id_beneficiario) FROM dbo.entrega e
             JOIN dbo.campana c ON c.id_campana = e.id_campana
            WHERE c.id_categoria = cat.id_categoria AND e.estado = 'Entregada') AS hogares
    FROM dbo.categoria_ayuda cat
    LEFT JOIN dbo.vw_campana_resumen v ON v.id_categoria = cat.id_categoria
    GROUP BY cat.id_categoria, cat.nombre
    ORDER BY recaudado DESC;
END
GO

-- Equivale a la consulta 3 del esquema original, con cobertura y necesidades pendientes por sector
CREATE OR ALTER PROCEDURE dbo.usp_dashboard_por_sector
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.id_sector, s.nombre AS sector,
           (SELECT COUNT(*) FROM dbo.beneficiario b WHERE b.id_sector = s.id_sector AND b.activo = 1) AS hogares_registrados,
           ISNULL(a.hogares, 0)   AS hogares_atendidos,
           ISNULL(p.personas, 0)  AS personas_estimadas,
           ISNULL(a.entregas, 0)  AS entregas,
           ISNULL(a.unidades, 0)  AS unidades,
           CAST(100.0 * ISNULL(a.hogares, 0)
                / NULLIF((SELECT COUNT(*) FROM dbo.beneficiario b WHERE b.id_sector = s.id_sector AND b.activo = 1), 0) AS DECIMAL(5,1)) AS pct_cobertura,
           ISNULL(nn.abiertas, 0) AS necesidades_abiertas
    FROM dbo.sector s
    OUTER APPLY (SELECT COUNT(DISTINCT e.id_beneficiario) AS hogares, COUNT(*) AS entregas, SUM(e.cantidad) AS unidades
                 FROM dbo.entrega e JOIN dbo.beneficiario b ON b.id_beneficiario = e.id_beneficiario
                 WHERE b.id_sector = s.id_sector AND e.estado = 'Entregada') a
    OUTER APPLY (SELECT SUM(b.integrantes_hogar) AS personas FROM dbo.beneficiario b
                 WHERE b.id_sector = s.id_sector
                   AND EXISTS (SELECT 1 FROM dbo.entrega e WHERE e.id_beneficiario = b.id_beneficiario AND e.estado = 'Entregada')) p
    OUTER APPLY (SELECT COUNT(*) AS abiertas FROM dbo.necesidad n JOIN dbo.beneficiario b ON b.id_beneficiario = n.id_beneficiario
                 WHERE b.id_sector = s.id_sector AND n.estado IN ('Pendiente', 'En atencion')) nn
    WHERE s.activo = 1 OR a.hogares > 0
    ORDER BY ISNULL(a.hogares, 0) DESC, s.nombre;
END
GO

-- Consulta 2 del esquema original. Es un reporte INTERNO (nombres de donantes): requiere permiso reportes:leer
CREATE OR ALTER PROCEDURE dbo.usp_reporte_top_donantes
    @limite INT = 5
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (@limite) dn.id_donante, dn.nombre, dn.tipo,
           COUNT(*) AS donaciones, SUM(d.monto) AS total_donado, COUNT(DISTINCT d.id_campana) AS campanas
    FROM dbo.donacion d
    JOIN dbo.donante dn ON dn.id_donante = d.id_donante
    WHERE d.estado = 'Confirmada'
    GROUP BY dn.id_donante, dn.nombre, dn.tipo
    ORDER BY total_donado DESC, dn.nombre;
END
GO

/* ---------------- Portal público: SOLO agregados, nunca datos personales ---------------- */
-- 3 result sets: totales, cobertura por sector (con supresión de celdas pequeñas), resumen por categoría
CREATE OR ALTER PROCEDURE dbo.usp_publico_resumen
AS
BEGIN
    SET NOCOUNT ON;
    SELECT (SELECT COUNT(*) FROM dbo.campana WHERE estado = 'Activa')     AS campanas_activas,
           (SELECT COUNT(*) FROM dbo.campana WHERE estado = 'Finalizada') AS campanas_finalizadas,
           ISNULL(SUM(v.recaudado_confirmado), 0) AS recaudado_confirmado,
           ISNULL(SUM(v.gastado_aprobado), 0)     AS gastado_aprobado,
           (SELECT COUNT(DISTINCT id_beneficiario) FROM dbo.entrega WHERE estado = 'Entregada') AS hogares_atendidos,
           (SELECT COUNT(*) FROM dbo.entrega WHERE estado = 'Entregada')                         AS entregas_realizadas,
           (SELECT COUNT(DISTINCT id_voluntario) FROM dbo.entrega WHERE estado = 'Entregada')    AS voluntarios_participantes,
           (SELECT COUNT(DISTINCT id_donante) FROM dbo.donacion WHERE estado = 'Confirmada')     AS donantes,
           CASE WHEN COUNT(DISTINCT v.moneda) = 1 THEN MAX(v.moneda) ELSE 'VARIAS' END           AS moneda
    FROM dbo.vw_campana_resumen v
    WHERE v.estado IN ('Activa', 'Pausada', 'Finalizada');

    -- Un sector con menos de 3 hogares atendidos se publica como "menos de 3" (evita reidentificar hogares)
    SELECT s.nombre AS sector,
           CASE WHEN ISNULL(a.hogares, 0) >= 3 THEN a.hogares END AS hogares_atendidos,
           CAST(CASE WHEN ISNULL(a.hogares, 0) >= 3 THEN 1 ELSE 0 END AS BIT) AS publicable
    FROM dbo.sector s
    OUTER APPLY (SELECT COUNT(DISTINCT e.id_beneficiario) AS hogares
                 FROM dbo.entrega e JOIN dbo.beneficiario b ON b.id_beneficiario = e.id_beneficiario
                 WHERE b.id_sector = s.id_sector AND e.estado = 'Entregada') a
    WHERE ISNULL(a.hogares, 0) > 0
    ORDER BY s.nombre;

    SELECT cat.nombre AS categoria,
           ISNULL(SUM(v.recaudado_confirmado), 0) AS recaudado,
           ISNULL(SUM(v.entregas_realizadas), 0)  AS entregas,
           ISNULL(SUM(v.unidades_entregadas), 0)  AS unidades
    FROM dbo.categoria_ayuda cat
    JOIN dbo.vw_campana_resumen v ON v.id_categoria = cat.id_categoria AND v.estado IN ('Activa', 'Pausada', 'Finalizada')
    GROUP BY cat.nombre
    ORDER BY recaudado DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_publico_campanas
AS
BEGIN
    SET NOCOUNT ON;
    SELECT v.id_campana, v.nombre, v.categoria, v.descripcion, v.objetivo_social,
           v.fecha_inicio, v.fecha_fin, v.estado, v.moneda,
           v.meta_recaudacion, v.recaudado_confirmado, v.pct_meta_recaudacion,
           v.gastado_aprobado, v.saldo_disponible,
           v.meta_hogares, v.hogares_atendidos, v.pct_meta_hogares,
           v.unidades_entregadas, v.dias_restantes
    FROM dbo.vw_campana_resumen v
    WHERE v.estado IN ('Activa', 'Pausada', 'Finalizada')
    ORDER BY CASE v.estado WHEN 'Activa' THEN 1 WHEN 'Pausada' THEN 2 ELSE 3 END, v.fecha_inicio DESC;
END
GO
