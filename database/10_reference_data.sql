/* =====================================================================
   10_reference_data.sql  |  Datos de referencia: roles, permisos y métodos de pago
   Idempotente. La matriz rol-permiso se versiona en código: cada ejecución la
   deja exactamente como está definida aquí (y en backend/app/core/permissions.py;
   una prueba automática verifica que ambas coinciden).
   ===================================================================== */
USE [$(DB_NAME)];
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- Métodos de pago (requiere_referencia: exige n.º de operación al registrar la donación)
MERGE dbo.metodo_pago AS t
USING (VALUES (N'Efectivo', 0), (N'Transferencia', 1), (N'Tarjeta', 1)) AS s (nombre, requiere_referencia)
   ON t.nombre = s.nombre
WHEN NOT MATCHED THEN INSERT (nombre, requiere_referencia) VALUES (s.nombre, s.requiere_referencia);
GO

-- Roles
MERGE dbo.rol AS t
USING (VALUES
    (1, 'ADMIN', N'Administrador', N'Gestiona usuarios, catálogos y toda la operación'),
    (2, 'COORDINADOR', N'Coordinador de programas', N'Planifica campañas, aprueba gastos y coordina entregas y voluntarios'),
    (3, 'FINANZAS', N'Responsable de donaciones y finanzas', N'Registra y verifica donaciones y registra gastos'),
    (4, 'TRABAJO_SOCIAL', N'Trabajo social y evaluación', N'Gestiona hogares, necesidades y retroalimentación'),
    (5, 'VOLUNTARIO', N'Voluntario operativo', N'Consulta y confirma únicamente sus entregas asignadas'),
    (6, 'AUDITOR', N'Auditor (solo lectura)', N'Consulta y audita sin modificar ni exportar datos personales'),
    (7, 'DONANTE', N'Donante (portal)', N'Consulta únicamente sus propias donaciones')
) AS s (id_rol, codigo, nombre, descripcion)
   ON t.id_rol = s.id_rol
WHEN MATCHED THEN UPDATE SET codigo = s.codigo, nombre = s.nombre, descripcion = s.descripcion
WHEN NOT MATCHED THEN INSERT (id_rol, codigo, nombre, descripcion) VALUES (s.id_rol, s.codigo, s.nombre, s.descripcion);
GO

-- Permisos (modulo:accion)
MERGE dbo.permiso AS t
USING (VALUES
    ('campanas:leer', 'campanas', N'Ver campañas y su avance'),
    ('campanas:escribir', 'campanas', N'Crear y editar campañas'),
    ('campanas:estado', 'campanas', N'Activar, pausar, finalizar o cancelar campañas'),
    ('catalogos:leer', 'catalogos', N'Ver catálogos (categorías, sectores, métodos de pago)'),
    ('catalogos:escribir', 'catalogos', N'Administrar catálogos'),
    ('donantes:leer', 'donantes', N'Ver donantes y su historial'),
    ('donantes:escribir', 'donantes', N'Registrar y editar donantes'),
    ('donaciones:leer', 'donaciones', N'Ver donaciones'),
    ('donaciones:registrar', 'donaciones', N'Registrar donaciones'),
    ('donaciones:verificar', 'donaciones', N'Confirmar, rechazar o anular donaciones'),
    ('donaciones:exportar', 'donaciones', N'Exportar donaciones a CSV'),
    ('gastos:leer', 'gastos', N'Ver gastos de campaña'),
    ('gastos:registrar', 'gastos', N'Registrar gastos'),
    ('gastos:aprobar', 'gastos', N'Aprobar o anular gastos'),
    ('beneficiarios:leer', 'beneficiarios', N'Ver hogares beneficiarios (datos personales)'),
    ('beneficiarios:escribir', 'beneficiarios', N'Registrar y editar hogares'),
    ('necesidades:leer', 'necesidades', N'Ver necesidades y cola de atención'),
    ('necesidades:escribir', 'necesidades', N'Registrar y gestionar necesidades'),
    ('voluntarios:leer', 'voluntarios', N'Ver voluntarios'),
    ('voluntarios:escribir', 'voluntarios', N'Registrar y editar voluntarios'),
    ('entregas:leer', 'entregas', N'Ver todas las entregas'),
    ('entregas:registrar', 'entregas', N'Registrar y programar entregas'),
    ('entregas:gestionar', 'entregas', N'Cambiar el estado de cualquier entrega'),
    ('entregas:propias', 'entregas', N'Ver y confirmar solo las entregas asignadas a uno mismo'),
    ('feedback:leer', 'feedback', N'Ver retroalimentación y quejas'),
    ('feedback:registrar', 'feedback', N'Registrar retroalimentación'),
    ('feedback:gestionar', 'feedback', N'Atender y responder retroalimentación'),
    ('feedback:confidencial', 'feedback', N'Ver y gestionar casos confidenciales'),
    ('dashboard:leer', 'dashboard', N'Ver el panel de indicadores'),
    ('reportes:leer', 'reportes', N'Ver reportes internos (incluye nombres de donantes)'),
    ('reportes:exportar', 'reportes', N'Exportar reportes y listados con datos personales'),
    ('usuarios:leer', 'usuarios', N'Ver usuarios y roles'),
    ('usuarios:escribir', 'usuarios', N'Crear y administrar usuarios'),
    ('auditoria:leer', 'auditoria', N'Consultar la bitácora de auditoría'),
    ('portal:donante', 'portal', N'Portal del donante (solo sus propias donaciones)'),
    ('portal:voluntario', 'portal', N'Portal del voluntario (solo sus propias entregas)')
) AS s (codigo, modulo, descripcion)
   ON t.codigo = s.codigo
WHEN MATCHED THEN UPDATE SET modulo = s.modulo, descripcion = s.descripcion
WHEN NOT MATCHED THEN INSERT (codigo, modulo, descripcion) VALUES (s.codigo, s.modulo, s.descripcion);
GO

-- Matriz rol → permiso (ADMIN recibe todos; el resto se enumera)
BEGIN TRY
    BEGIN TRAN;
    DELETE FROM dbo.rol_permiso;
    INSERT dbo.rol_permiso (id_rol, id_permiso)
    SELECT r.id_rol, p.id_permiso FROM dbo.rol r CROSS JOIN dbo.permiso p WHERE r.codigo = 'ADMIN';

    INSERT dbo.rol_permiso (id_rol, id_permiso)
    SELECT r.id_rol, p.id_permiso
    FROM (VALUES
        ('COORDINADOR', 'campanas:leer'),
        ('COORDINADOR', 'campanas:escribir'),
        ('COORDINADOR', 'campanas:estado'),
        ('COORDINADOR', 'catalogos:leer'),
        ('COORDINADOR', 'catalogos:escribir'),
        ('COORDINADOR', 'donantes:leer'),
        ('COORDINADOR', 'donaciones:leer'),
        ('COORDINADOR', 'gastos:leer'),
        ('COORDINADOR', 'gastos:aprobar'),
        ('COORDINADOR', 'beneficiarios:leer'),
        ('COORDINADOR', 'necesidades:leer'),
        ('COORDINADOR', 'necesidades:escribir'),
        ('COORDINADOR', 'voluntarios:leer'),
        ('COORDINADOR', 'voluntarios:escribir'),
        ('COORDINADOR', 'entregas:leer'),
        ('COORDINADOR', 'entregas:registrar'),
        ('COORDINADOR', 'entregas:gestionar'),
        ('COORDINADOR', 'feedback:leer'),
        ('COORDINADOR', 'feedback:registrar'),
        ('COORDINADOR', 'feedback:gestionar'),
        ('COORDINADOR', 'dashboard:leer'),
        ('COORDINADOR', 'reportes:leer'),
        ('FINANZAS', 'campanas:leer'),
        ('FINANZAS', 'catalogos:leer'),
        ('FINANZAS', 'donantes:leer'),
        ('FINANZAS', 'donantes:escribir'),
        ('FINANZAS', 'donaciones:leer'),
        ('FINANZAS', 'donaciones:registrar'),
        ('FINANZAS', 'donaciones:verificar'),
        ('FINANZAS', 'donaciones:exportar'),
        ('FINANZAS', 'gastos:leer'),
        ('FINANZAS', 'gastos:registrar'),
        ('FINANZAS', 'dashboard:leer'),
        ('FINANZAS', 'reportes:leer'),
        ('FINANZAS', 'reportes:exportar'),
        ('TRABAJO_SOCIAL', 'campanas:leer'),
        ('TRABAJO_SOCIAL', 'catalogos:leer'),
        ('TRABAJO_SOCIAL', 'beneficiarios:leer'),
        ('TRABAJO_SOCIAL', 'beneficiarios:escribir'),
        ('TRABAJO_SOCIAL', 'necesidades:leer'),
        ('TRABAJO_SOCIAL', 'necesidades:escribir'),
        ('TRABAJO_SOCIAL', 'voluntarios:leer'),
        ('TRABAJO_SOCIAL', 'entregas:leer'),
        ('TRABAJO_SOCIAL', 'entregas:registrar'),
        ('TRABAJO_SOCIAL', 'feedback:leer'),
        ('TRABAJO_SOCIAL', 'feedback:registrar'),
        ('TRABAJO_SOCIAL', 'feedback:gestionar'),
        ('TRABAJO_SOCIAL', 'feedback:confidencial'),
        ('TRABAJO_SOCIAL', 'dashboard:leer'),
        ('VOLUNTARIO', 'campanas:leer'),
        ('VOLUNTARIO', 'catalogos:leer'),
        ('VOLUNTARIO', 'entregas:propias'),
        ('VOLUNTARIO', 'feedback:registrar'),
        ('VOLUNTARIO', 'portal:voluntario'),
        ('AUDITOR', 'campanas:leer'),
        ('AUDITOR', 'catalogos:leer'),
        ('AUDITOR', 'donantes:leer'),
        ('AUDITOR', 'donaciones:leer'),
        ('AUDITOR', 'gastos:leer'),
        ('AUDITOR', 'beneficiarios:leer'),
        ('AUDITOR', 'necesidades:leer'),
        ('AUDITOR', 'voluntarios:leer'),
        ('AUDITOR', 'entregas:leer'),
        ('AUDITOR', 'feedback:leer'),
        ('AUDITOR', 'dashboard:leer'),
        ('AUDITOR', 'reportes:leer'),
        ('AUDITOR', 'usuarios:leer'),
        ('AUDITOR', 'auditoria:leer'),
        ('DONANTE', 'portal:donante')
    ) AS m (rol, permiso)
    JOIN dbo.rol r     ON r.codigo = m.rol
    JOIN dbo.permiso p ON p.codigo = m.permiso;
    COMMIT;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    THROW;
END CATCH
GO

IF NOT EXISTS (SELECT 1 FROM dbo.schema_migracion WHERE version = N'2.0.1')
    INSERT dbo.schema_migracion (version, descripcion) VALUES (N'2.0.1', N'Datos de referencia: roles, permisos y métodos de pago');
GO
