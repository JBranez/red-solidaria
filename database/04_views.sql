/* =====================================================================
   04_views.sql  |  Vistas de agregados reutilizadas por los procedimientos

   Regla de oro: cada hecho (donaciones, gastos, entregas) se agrega en su
   propio OUTER APPLY. Si se hiciera JOIN directo de donacion con entrega,
   cada donación se multiplicaría por el número de entregas y los totales
   quedarían inflados.
   Solo cuentan donaciones 'Confirmada', gastos 'Aprobado' y entregas 'Entregada'.
   ===================================================================== */
USE [$(DB_NAME)];
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER VIEW dbo.vw_campana_resumen
AS
SELECT
    c.id_campana, c.nombre, c.descripcion, c.objetivo_social,
    c.id_categoria, cat.nombre AS categoria,
    c.fecha_inicio, c.fecha_fin, c.estado, c.moneda,
    c.meta_recaudacion, c.meta_hogares, c.meta_unidades,
    c.id_responsable, resp.nombre_completo AS responsable,
    c.cerrada_en, c.motivo_cierre, c.creado_en,
    ISNULL(d.recaudado, 0)           AS recaudado_confirmado,
    ISNULL(d.pendiente, 0)           AS recaudado_pendiente,
    ISNULL(d.n_confirmadas, 0)       AS donaciones_confirmadas,
    ISNULL(d.n_pendientes, 0)        AS donaciones_pendientes,
    ISNULL(d.n_donantes, 0)          AS donantes,
    ISNULL(g.gastado, 0)             AS gastado_aprobado,
    ISNULL(d.recaudado, 0) - ISNULL(g.gastado, 0) AS saldo_disponible,
    ISNULL(e.n_entregas, 0)          AS entregas_realizadas,
    ISNULL(e.hogares, 0)             AS hogares_atendidos,
    ISNULL(e.unidades, 0)            AS unidades_entregadas,
    ISNULL(e.voluntarios, 0)         AS voluntarios_participantes,
    ISNULL(e.programadas, 0)         AS entregas_programadas,
    CAST(100.0 * ISNULL(d.recaudado, 0) / c.meta_recaudacion AS DECIMAL(7,1)) AS pct_meta_recaudacion,
    CAST(CASE WHEN c.meta_hogares  > 0 THEN 100.0 * ISNULL(e.hogares, 0)  / c.meta_hogares  END AS DECIMAL(7,1)) AS pct_meta_hogares,
    CAST(CASE WHEN c.meta_unidades > 0 THEN 100.0 * ISNULL(e.unidades, 0) / c.meta_unidades END AS DECIMAL(7,1)) AS pct_meta_unidades,
    DATEDIFF(DAY, CONVERT(DATE, SYSDATETIME()), c.fecha_fin) AS dias_restantes
FROM dbo.campana c
JOIN dbo.categoria_ayuda cat ON cat.id_categoria = c.id_categoria
LEFT JOIN dbo.usuario resp   ON resp.id_usuario  = c.id_responsable
OUTER APPLY (
    SELECT SUM(CASE WHEN x.estado = 'Confirmada' THEN x.monto END)                  AS recaudado,
           SUM(CASE WHEN x.estado = 'Pendiente'  THEN x.monto END)                  AS pendiente,
           COUNT(CASE WHEN x.estado = 'Confirmada' THEN 1 END)                      AS n_confirmadas,
           COUNT(CASE WHEN x.estado = 'Pendiente'  THEN 1 END)                      AS n_pendientes,
           COUNT(DISTINCT CASE WHEN x.estado = 'Confirmada' THEN x.id_donante END)  AS n_donantes
    FROM dbo.donacion x WHERE x.id_campana = c.id_campana
) d
OUTER APPLY (
    SELECT SUM(y.monto) AS gastado
    FROM dbo.gasto y WHERE y.id_campana = c.id_campana AND y.estado = 'Aprobado'
) g
OUTER APPLY (
    SELECT COUNT(CASE WHEN z.estado = 'Entregada' THEN 1 END)                         AS n_entregas,
           COUNT(DISTINCT CASE WHEN z.estado = 'Entregada' THEN z.id_beneficiario END) AS hogares,
           SUM(CASE WHEN z.estado = 'Entregada' THEN z.cantidad END)                  AS unidades,
           COUNT(DISTINCT CASE WHEN z.estado = 'Entregada' THEN z.id_voluntario END)  AS voluntarios,
           COUNT(CASE WHEN z.estado = 'Programada' THEN 1 END)                        AS programadas
    FROM dbo.entrega z WHERE z.id_campana = c.id_campana
) e;
GO

CREATE OR ALTER VIEW dbo.vw_donante_resumen
AS
SELECT
    dn.id_donante, dn.nombre, dn.tipo, dn.correo, dn.fecha_registro, dn.activo, dn.creado_en,
    ISNULL(d.total, 0)         AS total_donado,
    ISNULL(d.n, 0)             AS donaciones_confirmadas,
    ISNULL(d.n_pend, 0)        AS donaciones_pendientes,
    ISNULL(d.campanas, 0)      AS campanas_apoyadas,
    d.ultima                   AS ultima_donacion
FROM dbo.donante dn
OUTER APPLY (
    SELECT SUM(CASE WHEN x.estado = 'Confirmada' THEN x.monto END)                 AS total,
           COUNT(CASE WHEN x.estado = 'Confirmada' THEN 1 END)                     AS n,
           COUNT(CASE WHEN x.estado = 'Pendiente'  THEN 1 END)                     AS n_pend,
           COUNT(DISTINCT CASE WHEN x.estado = 'Confirmada' THEN x.id_campana END) AS campanas,
           MAX(CASE WHEN x.estado = 'Confirmada' THEN x.fecha END)                 AS ultima
    FROM dbo.donacion x WHERE x.id_donante = dn.id_donante
) d;
GO

CREATE OR ALTER VIEW dbo.vw_beneficiario_resumen
AS
SELECT
    b.id_beneficiario, b.nombres, b.apellidos,
    b.apellidos + N', ' + b.nombres AS nombre_completo,
    b.id_sector, s.nombre AS sector, b.integrantes_hogar, b.fecha_registro,
    b.consentimiento_datos, b.fecha_consentimiento, b.activo, b.creado_en,
    ISNULL(e.n, 0)        AS entregas_recibidas,
    ISNULL(e.unidades, 0) AS unidades_recibidas,
    e.ultima              AS ultima_entrega,
    ISNULL(n.abiertas, 0) AS necesidades_abiertas
FROM dbo.beneficiario b
JOIN dbo.sector s ON s.id_sector = b.id_sector
OUTER APPLY (
    SELECT COUNT(*) AS n, SUM(x.cantidad) AS unidades, MAX(x.fecha) AS ultima
    FROM dbo.entrega x WHERE x.id_beneficiario = b.id_beneficiario AND x.estado = 'Entregada'
) e
OUTER APPLY (
    SELECT COUNT(*) AS abiertas
    FROM dbo.necesidad y WHERE y.id_beneficiario = b.id_beneficiario AND y.estado IN ('Pendiente', 'En atencion')
) n;
GO

CREATE OR ALTER VIEW dbo.vw_voluntario_resumen
AS
SELECT
    v.id_voluntario, v.nombres, v.apellidos,
    v.nombres + N' ' + v.apellidos AS nombre_completo,
    v.correo, v.fecha_ingreso, v.activo, v.creado_en,
    ISNULL(e.n, 0)         AS entregas_realizadas,
    ISNULL(e.unidades, 0)  AS unidades_entregadas,
    ISNULL(e.campanas, 0)  AS campanas_participadas,
    ISNULL(e.programadas, 0) AS entregas_programadas,
    e.ultima               AS ultima_entrega
FROM dbo.voluntario v
OUTER APPLY (
    SELECT COUNT(CASE WHEN x.estado = 'Entregada' THEN 1 END)                         AS n,
           SUM(CASE WHEN x.estado = 'Entregada' THEN x.cantidad END)                  AS unidades,
           COUNT(DISTINCT CASE WHEN x.estado = 'Entregada' THEN x.id_campana END)     AS campanas,
           COUNT(CASE WHEN x.estado = 'Programada' THEN 1 END)                        AS programadas,
           MAX(CASE WHEN x.estado = 'Entregada' THEN x.fecha END)                     AS ultima
    FROM dbo.entrega x WHERE x.id_voluntario = v.id_voluntario
) e;
GO
