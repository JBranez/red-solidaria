/* =====================================================================
   03_indexes.sql  |  Índices y reglas de unicidad condicional

   En SQL Server una FOREIGN KEY NO crea índice automáticamente. Sin índice,
   cada JOIN y cada DELETE/UPDATE en la tabla padre escanea la tabla hija.
   El esquema original indexaba 5 de 6 FK: faltaba entrega.id_voluntario.

   Los índices ÚNICOS FILTRADOS ("WHERE ...") convierten reglas de negocio
   en garantías del motor, aun si alguien escribe SQL a mano.
   Requiere QUOTED_IDENTIFIER ON (el driver ODBC lo activa por defecto).
   ===================================================================== */
USE [$(DB_NAME)];
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/* ---- Búsqueda y FK de catálogos / personas ---- */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_beneficiario_sector' AND object_id = OBJECT_ID(N'dbo.beneficiario'))
    CREATE INDEX ix_beneficiario_sector ON dbo.beneficiario (id_sector) INCLUDE (activo, integrantes_hogar);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_beneficiario_nombre' AND object_id = OBJECT_ID(N'dbo.beneficiario'))
    CREATE INDEX ix_beneficiario_nombre ON dbo.beneficiario (apellidos, nombres);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_donante_nombre' AND object_id = OBJECT_ID(N'dbo.donante'))
    CREATE INDEX ix_donante_nombre ON dbo.donante (nombre);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_voluntario_nombre' AND object_id = OBJECT_ID(N'dbo.voluntario'))
    CREATE INDEX ix_voluntario_nombre ON dbo.voluntario (apellidos, nombres);
GO

/* ---- Seguridad ---- */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_usuario_rol' AND object_id = OBJECT_ID(N'dbo.usuario'))
    CREATE INDEX ix_usuario_rol ON dbo.usuario (id_rol);
GO
-- Una persona donante o voluntaria tiene como máximo UNA cuenta
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ux_usuario_donante' AND object_id = OBJECT_ID(N'dbo.usuario'))
    CREATE UNIQUE INDEX ux_usuario_donante ON dbo.usuario (id_donante) WHERE id_donante IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ux_usuario_voluntario' AND object_id = OBJECT_ID(N'dbo.usuario'))
    CREATE UNIQUE INDEX ux_usuario_voluntario ON dbo.usuario (id_voluntario) WHERE id_voluntario IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_rol_permiso_permiso' AND object_id = OBJECT_ID(N'dbo.rol_permiso'))
    CREATE INDEX ix_rol_permiso_permiso ON dbo.rol_permiso (id_permiso);
GO

/* ---- Campañas ---- */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_campana_categoria' AND object_id = OBJECT_ID(N'dbo.campana'))
    CREATE INDEX ix_campana_categoria ON dbo.campana (id_categoria);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_campana_estado_fechas' AND object_id = OBJECT_ID(N'dbo.campana'))
    CREATE INDEX ix_campana_estado_fechas ON dbo.campana (estado, fecha_inicio, fecha_fin);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_campana_responsable' AND object_id = OBJECT_ID(N'dbo.campana'))
    CREATE INDEX ix_campana_responsable ON dbo.campana (id_responsable) WHERE id_responsable IS NOT NULL;
GO

/* ---- Donaciones ---- */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_donacion_donante' AND object_id = OBJECT_ID(N'dbo.donacion'))
    CREATE INDEX ix_donacion_donante ON dbo.donacion (id_donante) INCLUDE (id_campana, monto, estado, fecha);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_donacion_campana' AND object_id = OBJECT_ID(N'dbo.donacion'))
    CREATE INDEX ix_donacion_campana ON dbo.donacion (id_campana, estado) INCLUDE (monto, fecha, id_donante);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_donacion_fecha' AND object_id = OBJECT_ID(N'dbo.donacion'))
    CREATE INDEX ix_donacion_fecha ON dbo.donacion (fecha DESC) INCLUDE (monto, estado);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_donacion_metodo' AND object_id = OBJECT_ID(N'dbo.donacion'))
    CREATE INDEX ix_donacion_metodo ON dbo.donacion (id_metodo_pago);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_donacion_confirmador' AND object_id = OBJECT_ID(N'dbo.donacion'))
    CREATE INDEX ix_donacion_confirmador ON dbo.donacion (confirmado_por) WHERE confirmado_por IS NOT NULL;
GO
-- Una misma referencia de operación no puede registrarse dos veces con el mismo método
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ux_donacion_referencia' AND object_id = OBJECT_ID(N'dbo.donacion'))
    CREATE UNIQUE INDEX ux_donacion_referencia ON dbo.donacion (id_metodo_pago, referencia)
    WHERE referencia IS NOT NULL AND estado <> 'Anulada';
GO

/* ---- Gastos ---- */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_gasto_campana' AND object_id = OBJECT_ID(N'dbo.gasto'))
    CREATE INDEX ix_gasto_campana ON dbo.gasto (id_campana, estado) INCLUDE (monto, fecha, tipo);
GO
-- Un índice compuesto (a, b) solo sirve a consultas por "a": cada FK necesita el suyo
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_gasto_registra' AND object_id = OBJECT_ID(N'dbo.gasto'))
    CREATE INDEX ix_gasto_registra ON dbo.gasto (id_usuario_registra) WHERE id_usuario_registra IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_gasto_aprobador' AND object_id = OBJECT_ID(N'dbo.gasto'))
    CREATE INDEX ix_gasto_aprobador ON dbo.gasto (aprobado_por) WHERE aprobado_por IS NOT NULL;
GO

/* ---- Necesidades ---- */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_necesidad_cola' AND object_id = OBJECT_ID(N'dbo.necesidad'))
    CREATE INDEX ix_necesidad_cola ON dbo.necesidad (estado, urgencia, fecha_registro);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_necesidad_beneficiario' AND object_id = OBJECT_ID(N'dbo.necesidad'))
    CREATE INDEX ix_necesidad_beneficiario ON dbo.necesidad (id_beneficiario);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_necesidad_categoria' AND object_id = OBJECT_ID(N'dbo.necesidad'))
    CREATE INDEX ix_necesidad_categoria ON dbo.necesidad (id_categoria);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_necesidad_usuario' AND object_id = OBJECT_ID(N'dbo.necesidad'))
    CREATE INDEX ix_necesidad_usuario ON dbo.necesidad (id_usuario_registra) WHERE id_usuario_registra IS NOT NULL;
GO
-- Un hogar no puede tener dos necesidades ABIERTAS de la misma categoría
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ux_necesidad_abierta' AND object_id = OBJECT_ID(N'dbo.necesidad'))
    CREATE UNIQUE INDEX ux_necesidad_abierta ON dbo.necesidad (id_beneficiario, id_categoria)
    WHERE estado IN ('Pendiente', 'En atencion');
GO

/* ---- Entregas ---- */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_entrega_campana' AND object_id = OBJECT_ID(N'dbo.entrega'))
    CREATE INDEX ix_entrega_campana ON dbo.entrega (id_campana, estado) INCLUDE (cantidad, id_beneficiario, id_voluntario, fecha);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_entrega_beneficiario' AND object_id = OBJECT_ID(N'dbo.entrega'))
    CREATE INDEX ix_entrega_beneficiario ON dbo.entrega (id_beneficiario) INCLUDE (estado, fecha);
GO
-- FALTABA en el esquema original: sin este índice, filtrar por voluntario escanea toda la tabla
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_entrega_voluntario' AND object_id = OBJECT_ID(N'dbo.entrega'))
    CREATE INDEX ix_entrega_voluntario ON dbo.entrega (id_voluntario) INCLUDE (estado, fecha);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_entrega_fecha' AND object_id = OBJECT_ID(N'dbo.entrega'))
    CREATE INDEX ix_entrega_fecha ON dbo.entrega (fecha DESC) INCLUDE (estado, cantidad);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_entrega_necesidad' AND object_id = OBJECT_ID(N'dbo.entrega'))
    CREATE INDEX ix_entrega_necesidad ON dbo.entrega (id_necesidad) WHERE id_necesidad IS NOT NULL;
GO
-- Evita el doble registro accidental: mismo hogar, misma campaña, mismo día
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ux_entrega_dia' AND object_id = OBJECT_ID(N'dbo.entrega'))
    CREATE UNIQUE INDEX ux_entrega_dia ON dbo.entrega (id_campana, id_beneficiario, fecha)
    WHERE estado IN ('Programada', 'Entregada');
GO

/* ---- Retroalimentación ---- */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_retro_estado' AND object_id = OBJECT_ID(N'dbo.retroalimentacion'))
    CREATE INDEX ix_retro_estado ON dbo.retroalimentacion (estado, fecha_limite);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_retro_beneficiario' AND object_id = OBJECT_ID(N'dbo.retroalimentacion'))
    CREATE INDEX ix_retro_beneficiario ON dbo.retroalimentacion (id_beneficiario) WHERE id_beneficiario IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_retro_campana' AND object_id = OBJECT_ID(N'dbo.retroalimentacion'))
    CREATE INDEX ix_retro_campana ON dbo.retroalimentacion (id_campana) WHERE id_campana IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_retro_entrega' AND object_id = OBJECT_ID(N'dbo.retroalimentacion'))
    CREATE INDEX ix_retro_entrega ON dbo.retroalimentacion (id_entrega) WHERE id_entrega IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_retro_responsable' AND object_id = OBJECT_ID(N'dbo.retroalimentacion'))
    CREATE INDEX ix_retro_responsable ON dbo.retroalimentacion (id_responsable) WHERE id_responsable IS NOT NULL;
GO

/* ---- Auditoría ---- */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_auditoria_fecha' AND object_id = OBJECT_ID(N'dbo.auditoria_evento'))
    CREATE INDEX ix_auditoria_fecha ON dbo.auditoria_evento (fecha DESC);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_auditoria_entidad' AND object_id = OBJECT_ID(N'dbo.auditoria_evento'))
    CREATE INDEX ix_auditoria_entidad ON dbo.auditoria_evento (entidad, id_entidad);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_auditoria_usuario' AND object_id = OBJECT_ID(N'dbo.auditoria_evento'))
    CREATE INDEX ix_auditoria_usuario ON dbo.auditoria_evento (id_usuario) WHERE id_usuario IS NOT NULL;
GO
