-- =====================================================================
--  Consultas de ejemplo: ¿qué impacto está logrando la red solidaria?
-- =====================================================================

-- 1) ¿Cuánto se recaudó en cada campaña y qué porcentaje de la meta representa?
SELECT c.nombre                       AS campana,
       cat.nombre                     AS categoria,
       c.meta_recaudacion             AS meta,
       COALESCE(SUM(d.monto), 0)      AS recaudado,
       ROUND(100.0 * COALESCE(SUM(d.monto), 0) / c.meta_recaudacion, 1) AS pct_meta
FROM campana c
JOIN categoria_ayuda cat ON cat.id_categoria = c.id_categoria
LEFT JOIN donacion d     ON d.id_campana     = c.id_campana
GROUP BY c.id_campana, c.nombre, cat.nombre, c.meta_recaudacion
ORDER BY pct_meta DESC;

-- 2) Los 5 donantes que más han aportado
SELECT dn.nombre,
       dn.tipo,
       COUNT(*)      AS donaciones,
       SUM(d.monto)  AS total_donado
FROM donacion d
JOIN donante dn ON dn.id_donante = d.id_donante
GROUP BY dn.id_donante, dn.nombre, dn.tipo
ORDER BY total_donado DESC
LIMIT 5;

-- 3) Alcance por sector: hogares atendidos y personas beneficiadas
SELECT sector,
       COUNT(*)               AS hogares_atendidos,
       SUM(integrantes_hogar) AS personas_alcanzadas
FROM beneficiario
WHERE id_beneficiario IN (SELECT id_beneficiario FROM entrega)
GROUP BY sector
ORDER BY personas_alcanzadas DESC;

-- 4) Ayuda entregada por categoría y voluntarios que participaron
SELECT cat.nombre                       AS categoria,
       COUNT(*)                         AS entregas,
       SUM(e.cantidad)                  AS unidades_entregadas,
       COUNT(DISTINCT e.id_voluntario)  AS voluntarios
FROM entrega e
JOIN campana c           ON c.id_campana    = e.id_campana
JOIN categoria_ayuda cat ON cat.id_categoria = c.id_categoria
GROUP BY cat.nombre
ORDER BY unidades_entregadas DESC;
