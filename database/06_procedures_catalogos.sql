/* =====================================================================
   06_procedures_catalogos.sql  |  Categorías de ayuda, sectores y métodos de pago
   ===================================================================== */
USE [$(DB_NAME)];
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/* ---------------- Categorías de ayuda ---------------- */
CREATE OR ALTER PROCEDURE dbo.usp_categoria_listar
    @id           INT = NULL,
    @solo_activas BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SELECT c.id_categoria, c.nombre, c.descripcion, c.activo, c.creado_en,
           (SELECT COUNT(*) FROM dbo.campana x WHERE x.id_categoria = c.id_categoria) AS campanas,
           (SELECT COUNT(*) FROM dbo.campana x WHERE x.id_categoria = c.id_categoria
                AND x.estado IN ('Borrador', 'Activa', 'Pausada'))                    AS campanas_vigentes
    FROM dbo.categoria_ayuda c
    WHERE (@id IS NULL OR c.id_categoria = @id)
      AND (@solo_activas = 0 OR c.activo = 1)
    ORDER BY c.nombre;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_categoria_guardar
    @id_categoria INT = NULL,
    @nombre       NVARCHAR(50),
    @descripcion  NVARCHAR(150),
    @id_actor     INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;
        IF EXISTS (SELECT 1 FROM dbo.categoria_ayuda WHERE nombre = @nombre AND (@id_categoria IS NULL OR id_categoria <> @id_categoria))
            THROW 50409, N'Ya existe una categoría con ese nombre.', 1;
        IF @id_categoria IS NULL
        BEGIN
            INSERT dbo.categoria_ayuda (nombre, descripcion) VALUES (@nombre, @descripcion);
            SET @id_categoria = SCOPE_IDENTITY();
            EXEC dbo.usp_auditoria_registrar @id_actor, 'CREAR', 'categoria_ayuda', @id_categoria, @nombre;
        END
        ELSE
        BEGIN
            UPDATE dbo.categoria_ayuda SET nombre = @nombre, descripcion = @descripcion, actualizado_en = SYSUTCDATETIME()
             WHERE id_categoria = @id_categoria;
            IF @@ROWCOUNT = 0 THROW 50404, N'La categoría no existe.', 1;
            EXEC dbo.usp_auditoria_registrar @id_actor, 'EDITAR', 'categoria_ayuda', @id_categoria, @nombre;
        END
        COMMIT;
        SELECT @id_categoria AS id_categoria;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_categoria_estado
    @id_categoria INT,
    @activo       BIT,
    @id_actor     INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;
        IF NOT EXISTS (SELECT 1 FROM dbo.categoria_ayuda WHERE id_categoria = @id_categoria)
            THROW 50404, N'La categoría no existe.', 1;
        IF @activo = 0 AND EXISTS (SELECT 1 FROM dbo.campana WHERE id_categoria = @id_categoria AND estado IN ('Borrador', 'Activa', 'Pausada'))
            THROW 50422, N'No se puede desactivar: tiene campañas vigentes asociadas.', 1;
        UPDATE dbo.categoria_ayuda SET activo = @activo, actualizado_en = SYSUTCDATETIME() WHERE id_categoria = @id_categoria;
        DECLARE @det NVARCHAR(40) = CASE WHEN @activo = 1 THEN N'Reactivada' ELSE N'Desactivada' END;
        EXEC dbo.usp_auditoria_registrar @id_actor, 'CAMBIAR_ESTADO', 'categoria_ayuda', @id_categoria, @det;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

/* ---------------- Sectores ---------------- */
CREATE OR ALTER PROCEDURE dbo.usp_sector_listar
    @id           INT = NULL,
    @solo_activos BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.id_sector, s.nombre, s.activo, s.creado_en,
           (SELECT COUNT(*) FROM dbo.beneficiario b WHERE b.id_sector = s.id_sector AND b.activo = 1) AS hogares
    FROM dbo.sector s
    WHERE (@id IS NULL OR s.id_sector = @id)
      AND (@solo_activos = 0 OR s.activo = 1)
    ORDER BY s.nombre;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_sector_guardar
    @id_sector INT = NULL,
    @nombre    NVARCHAR(60),
    @id_actor  INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;
        IF EXISTS (SELECT 1 FROM dbo.sector WHERE nombre = @nombre AND (@id_sector IS NULL OR id_sector <> @id_sector))
            THROW 50409, N'Ya existe un sector con ese nombre.', 1;
        IF @id_sector IS NULL
        BEGIN
            INSERT dbo.sector (nombre) VALUES (@nombre);
            SET @id_sector = SCOPE_IDENTITY();
            EXEC dbo.usp_auditoria_registrar @id_actor, 'CREAR', 'sector', @id_sector, @nombre;
        END
        ELSE
        BEGIN
            UPDATE dbo.sector SET nombre = @nombre WHERE id_sector = @id_sector;
            IF @@ROWCOUNT = 0 THROW 50404, N'El sector no existe.', 1;
            EXEC dbo.usp_auditoria_registrar @id_actor, 'EDITAR', 'sector', @id_sector, @nombre;
        END
        COMMIT;
        SELECT @id_sector AS id_sector;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_sector_estado
    @id_sector INT,
    @activo    BIT,
    @id_actor  INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;
        UPDATE dbo.sector SET activo = @activo WHERE id_sector = @id_sector;
        IF @@ROWCOUNT = 0 THROW 50404, N'El sector no existe.', 1;
        DECLARE @det NVARCHAR(40) = CASE WHEN @activo = 1 THEN N'Reactivado' ELSE N'Desactivado' END;
        EXEC dbo.usp_auditoria_registrar @id_actor, 'CAMBIAR_ESTADO', 'sector', @id_sector, @det;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

/* ---------------- Métodos de pago ---------------- */
CREATE OR ALTER PROCEDURE dbo.usp_metodo_pago_listar
    @solo_activos BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SELECT id_metodo_pago, nombre, requiere_referencia, activo
    FROM dbo.metodo_pago
    WHERE @solo_activos = 0 OR activo = 1
    ORDER BY nombre;
END
GO
