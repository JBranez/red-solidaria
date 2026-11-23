/* =====================================================================
   08_procedures_operacion.sql  |  Hogares, necesidades, voluntarios,
                                   entregas y retroalimentación
   ===================================================================== */
USE [$(DB_NAME)];
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/* =====================================================================
   HOGARES BENEFICIARIOS
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.usp_beneficiario_listar
    @id                  INT = NULL,
    @q                   NVARCHAR(120) = NULL,
    @id_sector           INT = NULL,
    @activo              BIT = NULL,
    @sin_consentimiento  BIT = 0,
    @sin_entregas        BIT = 0,
    @con_necesidades     BIT = 0,
    @orden               VARCHAR(20) = NULL,
    @desc                BIT = 0,
    @pagina              INT = 1,
    @tamano              INT = 25
AS
BEGIN
    SET NOCOUNT ON;
    SELECT v.*, COUNT(*) OVER() AS total_filas
    FROM dbo.vw_beneficiario_resumen v
    WHERE (@id IS NULL OR v.id_beneficiario = @id)
      AND (@q IS NULL OR v.nombres LIKE @q ESCAPE '\' OR v.apellidos LIKE @q ESCAPE '\' OR v.nombre_completo LIKE @q ESCAPE '\')
      AND (@id_sector IS NULL OR v.id_sector = @id_sector)
      AND (@activo IS NULL OR v.activo = @activo)
      AND (@sin_consentimiento = 0 OR v.consentimiento_datos = 0)
      AND (@sin_entregas = 0 OR v.entregas_recibidas = 0)
      AND (@con_necesidades = 0 OR v.necesidades_abiertas > 0)
    ORDER BY
        CASE WHEN @orden = 'nombre'         AND @desc = 0 THEN v.nombre_completo END ASC,
        CASE WHEN @orden = 'nombre'         AND @desc = 1 THEN v.nombre_completo END DESC,
        CASE WHEN @orden = 'integrantes'    AND @desc = 0 THEN v.integrantes_hogar END ASC,
        CASE WHEN @orden = 'integrantes'    AND @desc = 1 THEN v.integrantes_hogar END DESC,
        CASE WHEN @orden = 'ultima_entrega' AND @desc = 0 THEN v.ultima_entrega END ASC,
        CASE WHEN @orden = 'ultima_entrega' AND @desc = 1 THEN v.ultima_entrega END DESC,
        v.apellidos ASC, v.nombres ASC
    OFFSET (@pagina - 1) * @tamano ROWS FETCH NEXT @tamano ROWS ONLY;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_beneficiario_guardar
    @id_beneficiario     INT = NULL,
    @nombres             NVARCHAR(60),
    @apellidos           NVARCHAR(60),
    @id_sector           INT,
    @integrantes_hogar   INT,
    @consentimiento_datos BIT = 0,
    @confirmar_duplicado BIT = 0,
    @id_actor            INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;
        DECLARE @hoy DATE = CONVERT(DATE, SYSDATETIME());
        DECLARE @sector_actual INT = (SELECT id_sector FROM dbo.beneficiario WHERE id_beneficiario = @id_beneficiario);
        IF NOT EXISTS (SELECT 1 FROM dbo.sector WHERE id_sector = @id_sector AND (activo = 1 OR id_sector = @sector_actual))
            THROW 50422, N'El sector no existe o está desactivado.', 1;
        IF @confirmar_duplicado = 0
        BEGIN
            DECLARE @dup INT = (SELECT TOP (1) id_beneficiario FROM dbo.beneficiario
                                WHERE nombres = @nombres AND apellidos = @apellidos AND id_sector = @id_sector
                                  AND (@id_beneficiario IS NULL OR id_beneficiario <> @id_beneficiario));
            IF @dup IS NOT NULL
            BEGIN
                DECLARE @msg NVARCHAR(300) = N'Ya hay un hogar registrado con el mismo nombre en ese sector (n.º ' + CONVERT(NVARCHAR(10), @dup)
                                           + N'). Confirme solo si se trata de otro hogar.';
                THROW 50410, @msg, 1;
            END
        END
        IF @id_beneficiario IS NULL
        BEGIN
            INSERT dbo.beneficiario (nombres, apellidos, id_sector, integrantes_hogar, consentimiento_datos, fecha_consentimiento)
            VALUES (@nombres, @apellidos, @id_sector, @integrantes_hogar, @consentimiento_datos,
                    CASE WHEN @consentimiento_datos = 1 THEN @hoy END);
            SET @id_beneficiario = SCOPE_IDENTITY();
            EXEC dbo.usp_auditoria_registrar @id_actor, 'CREAR', 'beneficiario', @id_beneficiario, N'Hogar registrado';
        END
        ELSE
        BEGIN
            UPDATE dbo.beneficiario
               SET nombres = @nombres, apellidos = @apellidos, id_sector = @id_sector, integrantes_hogar = @integrantes_hogar,
                   consentimiento_datos = @consentimiento_datos,
                   fecha_consentimiento = CASE WHEN @consentimiento_datos = 0 THEN NULL
                                               ELSE ISNULL(fecha_consentimiento, @hoy) END,
                   actualizado_en = SYSUTCDATETIME()
             WHERE id_beneficiario = @id_beneficiario;
            IF @@ROWCOUNT = 0 THROW 50404, N'El hogar no existe.', 1;
            EXEC dbo.usp_auditoria_registrar @id_actor, 'EDITAR', 'beneficiario', @id_beneficiario, N'Datos del hogar actualizados';
        END
        COMMIT;
        SELECT @id_beneficiario AS id_beneficiario;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_beneficiario_estado
    @id_beneficiario INT,
    @activo          BIT,
    @id_actor        INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;
        IF NOT EXISTS (SELECT 1 FROM dbo.beneficiario WHERE id_beneficiario = @id_beneficiario)
            THROW 50404, N'El hogar no existe.', 1;
        IF @activo = 0 AND EXISTS (SELECT 1 FROM dbo.entrega WHERE id_beneficiario = @id_beneficiario AND estado = 'Programada')
            THROW 50422, N'El hogar tiene entregas programadas. Resuélvalas antes de desactivarlo.', 1;
        UPDATE dbo.beneficiario SET activo = @activo, actualizado_en = SYSUTCDATETIME() WHERE id_beneficiario = @id_beneficiario;
        DECLARE @det NVARCHAR(40) = CASE WHEN @activo = 1 THEN N'Reactivado' ELSE N'Desactivado' END;
        EXEC dbo.usp_auditoria_registrar @id_actor, 'CAMBIAR_ESTADO', 'beneficiario', @id_beneficiario, @det;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

/* =====================================================================
   NECESIDADES  — cola de atención con criterio explicable
   Orden: urgencia (Crítica > Alta > Media > Baja) y, a igual urgencia, la más antigua primero.
   No hay puntaje opaco: una persona revisa y decide (CHS / transparencia).
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.usp_necesidad_listar
    @id              INT = NULL,
    @id_beneficiario INT = NULL,
    @id_categoria    INT = NULL,
    @id_sector       INT = NULL,
    @estado          VARCHAR(11) = NULL,
    @urgencia        VARCHAR(7)  = NULL,
    @solo_abiertas   BIT = 0,
    @pagina          INT = 1,
    @tamano          INT = 25
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @hoy DATE = CONVERT(DATE, SYSDATETIME());
    SELECT n.id_necesidad, n.id_beneficiario, b.apellidos + N', ' + b.nombres AS hogar,
           b.id_sector, s.nombre AS sector, b.integrantes_hogar,
           n.id_categoria, cat.nombre AS categoria, n.urgencia, n.estado, n.descripcion,
           n.fecha_registro, n.fecha_cobertura, n.motivo_estado,
           CASE n.urgencia WHEN 'Critica' THEN 1 WHEN 'Alta' THEN 2 WHEN 'Media' THEN 3 ELSE 4 END AS prioridad,
           DATEDIFF(DAY, n.fecha_registro,
                    CASE WHEN n.estado IN ('Pendiente', 'En atencion') THEN @hoy
                         ELSE ISNULL(n.fecha_cobertura, CONVERT(DATE, n.actualizado_en)) END) AS dias_espera,
           u.nombre_completo AS registrado_por, n.creado_en,
           COUNT(*) OVER() AS total_filas
    FROM dbo.necesidad n
    JOIN dbo.beneficiario b      ON b.id_beneficiario = n.id_beneficiario
    JOIN dbo.sector s            ON s.id_sector = b.id_sector
    JOIN dbo.categoria_ayuda cat ON cat.id_categoria = n.id_categoria
    LEFT JOIN dbo.usuario u      ON u.id_usuario = n.id_usuario_registra
    WHERE (@id IS NULL OR n.id_necesidad = @id)
      AND (@id_beneficiario IS NULL OR n.id_beneficiario = @id_beneficiario)
      AND (@id_categoria IS NULL OR n.id_categoria = @id_categoria)
      AND (@id_sector IS NULL OR b.id_sector = @id_sector)
      AND (@estado IS NULL OR n.estado = @estado)
      AND (@urgencia IS NULL OR n.urgencia = @urgencia)
      AND (@solo_abiertas = 0 OR n.estado IN ('Pendiente', 'En atencion'))
    ORDER BY CASE WHEN n.estado IN ('Pendiente', 'En atencion') THEN 0 ELSE 1 END,
             CASE n.urgencia WHEN 'Critica' THEN 1 WHEN 'Alta' THEN 2 WHEN 'Media' THEN 3 ELSE 4 END,
             n.fecha_registro ASC, n.id_necesidad ASC
    OFFSET (@pagina - 1) * @tamano ROWS FETCH NEXT @tamano ROWS ONLY;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_necesidad_guardar
    @id_necesidad    INT = NULL,
    @id_beneficiario INT,
    @id_categoria    INT,
    @urgencia        VARCHAR(7),
    @descripcion     NVARCHAR(300) = NULL,
    @id_actor        INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;
        IF NOT EXISTS (SELECT 1 FROM dbo.beneficiario WHERE id_beneficiario = @id_beneficiario AND activo = 1)
            THROW 50422, N'El hogar no existe o está inactivo.', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.categoria_ayuda WHERE id_categoria = @id_categoria AND activo = 1)
            THROW 50422, N'La categoría no existe o está desactivada.', 1;
        IF EXISTS (SELECT 1 FROM dbo.necesidad WHERE id_beneficiario = @id_beneficiario AND id_categoria = @id_categoria
                   AND estado IN ('Pendiente', 'En atencion') AND (@id_necesidad IS NULL OR id_necesidad <> @id_necesidad))
            THROW 50409, N'El hogar ya tiene una necesidad abierta en esa categoría.', 1;
        IF @id_necesidad IS NULL
        BEGIN
            INSERT dbo.necesidad (id_beneficiario, id_categoria, urgencia, descripcion, id_usuario_registra)
            VALUES (@id_beneficiario, @id_categoria, @urgencia, @descripcion, @id_actor);
            SET @id_necesidad = SCOPE_IDENTITY();
            DECLARE @det NVARCHAR(100) = N'Urgencia ' + @urgencia;
            EXEC dbo.usp_auditoria_registrar @id_actor, 'CREAR', 'necesidad', @id_necesidad, @det;
        END
        ELSE
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM dbo.necesidad WHERE id_necesidad = @id_necesidad)
                THROW 50404, N'La necesidad no existe.', 1;
            IF NOT EXISTS (SELECT 1 FROM dbo.necesidad WHERE id_necesidad = @id_necesidad AND estado IN ('Pendiente', 'En atencion'))
                THROW 50422, N'Solo se pueden editar necesidades abiertas.', 1;
            UPDATE dbo.necesidad
               SET id_categoria = @id_categoria, urgencia = @urgencia, descripcion = @descripcion, actualizado_en = SYSUTCDATETIME()
             WHERE id_necesidad = @id_necesidad;
            EXEC dbo.usp_auditoria_registrar @id_actor, 'EDITAR', 'necesidad', @id_necesidad, N'Necesidad actualizada';
        END
        COMMIT;
        SELECT @id_necesidad AS id_necesidad;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_necesidad_estado
    @id_necesidad INT,
    @nuevo_estado VARCHAR(11),
    @motivo       NVARCHAR(200) = NULL,
    @id_actor     INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;
        DECLARE @actual VARCHAR(11) = (SELECT estado FROM dbo.necesidad WITH (UPDLOCK) WHERE id_necesidad = @id_necesidad);
        IF @actual IS NULL
            THROW 50404, N'La necesidad no existe.', 1;
        IF NOT EXISTS (SELECT 1 FROM (VALUES ('Pendiente','En atencion'), ('Pendiente','Cubierta'), ('Pendiente','Descartada'),
                                             ('En atencion','Pendiente'), ('En atencion','Cubierta'), ('En atencion','Descartada')) t (de, a)
                       WHERE t.de = @actual AND t.a = @nuevo_estado)
            THROW 50422, N'Esa transición de estado no está permitida para la necesidad.', 1;
        IF @nuevo_estado = 'Descartada' AND (@motivo IS NULL OR LEN(LTRIM(RTRIM(@motivo))) = 0)
            THROW 50422, N'Indique el motivo por el que se descarta la necesidad.', 1;
        UPDATE dbo.necesidad
           SET estado = @nuevo_estado,
               fecha_cobertura = CASE WHEN @nuevo_estado = 'Cubierta' THEN CONVERT(DATE, SYSDATETIME()) ELSE NULL END,
               motivo_estado   = CASE WHEN @nuevo_estado = 'Descartada' THEN @motivo ELSE NULL END,
               actualizado_en  = SYSUTCDATETIME()
         WHERE id_necesidad = @id_necesidad;
        DECLARE @det NVARCHAR(100) = @actual + N' → ' + @nuevo_estado;
        EXEC dbo.usp_auditoria_registrar @id_actor, 'CAMBIAR_ESTADO', 'necesidad', @id_necesidad, @det;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

/* =====================================================================
   VOLUNTARIOS
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.usp_voluntario_listar
    @id     INT = NULL,
    @q      NVARCHAR(120) = NULL,
    @activo BIT = NULL,
    @orden  VARCHAR(20) = NULL,
    @desc   BIT = 0,
    @pagina INT = 1,
    @tamano INT = 25
AS
BEGIN
    SET NOCOUNT ON;
    SELECT v.*, COUNT(*) OVER() AS total_filas
    FROM dbo.vw_voluntario_resumen v
    WHERE (@id IS NULL OR v.id_voluntario = @id)
      AND (@q IS NULL OR v.nombre_completo LIKE @q ESCAPE '\' OR v.correo LIKE @q ESCAPE '\')
      AND (@activo IS NULL OR v.activo = @activo)
    ORDER BY
        CASE WHEN @orden = 'entregas' AND @desc = 0 THEN v.entregas_realizadas END ASC,
        CASE WHEN @orden = 'entregas' AND @desc = 1 THEN v.entregas_realizadas END DESC,
        CASE WHEN @orden = 'ingreso'  AND @desc = 0 THEN v.fecha_ingreso END ASC,
        CASE WHEN @orden = 'ingreso'  AND @desc = 1 THEN v.fecha_ingreso END DESC,
        v.apellidos ASC, v.nombres ASC
    OFFSET (@pagina - 1) * @tamano ROWS FETCH NEXT @tamano ROWS ONLY;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_voluntario_guardar
    @id_voluntario INT = NULL,
    @nombres       NVARCHAR(60),
    @apellidos     NVARCHAR(60),
    @correo        NVARCHAR(100),
    @fecha_ingreso DATE = NULL,
    @id_actor      INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;
        IF @fecha_ingreso > CONVERT(DATE, SYSDATETIME())
            THROW 50422, N'La fecha de ingreso no puede ser futura.', 1;
        IF EXISTS (SELECT 1 FROM dbo.voluntario WHERE correo = @correo AND (@id_voluntario IS NULL OR id_voluntario <> @id_voluntario))
            THROW 50409, N'Ya existe un voluntario con ese correo.', 1;
        IF @id_voluntario IS NULL
        BEGIN
            INSERT dbo.voluntario (nombres, apellidos, correo, fecha_ingreso)
            VALUES (@nombres, @apellidos, @correo, ISNULL(@fecha_ingreso, CONVERT(DATE, SYSDATETIME())));
            SET @id_voluntario = SCOPE_IDENTITY();
            DECLARE @det NVARCHAR(130) = @nombres + N' ' + @apellidos;
            EXEC dbo.usp_auditoria_registrar @id_actor, 'CREAR', 'voluntario', @id_voluntario, @det;
        END
        ELSE
        BEGIN
            UPDATE dbo.voluntario
               SET nombres = @nombres, apellidos = @apellidos, correo = @correo,
                   fecha_ingreso = ISNULL(@fecha_ingreso, fecha_ingreso), actualizado_en = SYSUTCDATETIME()
             WHERE id_voluntario = @id_voluntario;
            IF @@ROWCOUNT = 0 THROW 50404, N'El voluntario no existe.', 1;
            EXEC dbo.usp_auditoria_registrar @id_actor, 'EDITAR', 'voluntario', @id_voluntario, N'Datos actualizados';
        END
        COMMIT;
        SELECT @id_voluntario AS id_voluntario;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_voluntario_estado
    @id_voluntario INT,
    @activo        BIT,
    @id_actor      INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;
        IF NOT EXISTS (SELECT 1 FROM dbo.voluntario WHERE id_voluntario = @id_voluntario)
            THROW 50404, N'El voluntario no existe.', 1;
        IF @activo = 0 AND EXISTS (SELECT 1 FROM dbo.entrega WHERE id_voluntario = @id_voluntario AND estado = 'Programada')
            THROW 50422, N'Tiene entregas programadas. Resuélvalas o reasígnelas antes de desactivarlo.', 1;
        UPDATE dbo.voluntario SET activo = @activo, actualizado_en = SYSUTCDATETIME() WHERE id_voluntario = @id_voluntario;
        DECLARE @det NVARCHAR(40) = CASE WHEN @activo = 1 THEN N'Reactivado' ELSE N'Desactivado' END;
        EXEC dbo.usp_auditoria_registrar @id_actor, 'CAMBIAR_ESTADO', 'voluntario', @id_voluntario, @det;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

/* =====================================================================
   ENTREGAS  (Programada → Entregada | No realizada | Anulada ; Entregada → Anulada)
   Nunca se borra una entrega: se anula con motivo y queda en la bitácora.
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.usp_entrega_listar
    @id              INT = NULL,
    @q               NVARCHAR(120) = NULL,   -- hogar o voluntario
    @id_campana      INT = NULL,
    @id_beneficiario INT = NULL,
    @id_voluntario   INT = NULL,
    @id_sector       INT = NULL,
    @estado          VARCHAR(12) = NULL,
    @desde           DATE = NULL,
    @hasta           DATE = NULL,
    @orden           VARCHAR(20) = NULL,
    @desc            BIT = 1,
    @pagina          INT = 1,
    @tamano          INT = 25
AS
BEGIN
    SET NOCOUNT ON;
    SELECT e.id_entrega, e.fecha, e.cantidad, e.detalle, e.estado, e.motivo_estado,
           e.id_campana, c.nombre AS campana, cat.nombre AS categoria,
           e.id_beneficiario, b.apellidos + N', ' + b.nombres AS hogar,
           b.id_sector, s.nombre AS sector, b.integrantes_hogar,
           e.id_voluntario, v.nombres + N' ' + v.apellidos AS voluntario,
           e.id_necesidad, e.creado_en,
           COUNT(*) OVER() AS total_filas
    FROM dbo.entrega e
    JOIN dbo.campana c           ON c.id_campana = e.id_campana
    JOIN dbo.categoria_ayuda cat ON cat.id_categoria = c.id_categoria
    JOIN dbo.beneficiario b      ON b.id_beneficiario = e.id_beneficiario
    JOIN dbo.sector s            ON s.id_sector = b.id_sector
    JOIN dbo.voluntario v        ON v.id_voluntario = e.id_voluntario
    WHERE (@id IS NULL OR e.id_entrega = @id)
      AND (@q IS NULL OR b.nombres LIKE @q ESCAPE '\' OR b.apellidos LIKE @q ESCAPE '\'
                      OR v.nombres LIKE @q ESCAPE '\' OR v.apellidos LIKE @q ESCAPE '\')
      AND (@id_campana IS NULL OR e.id_campana = @id_campana)
      AND (@id_beneficiario IS NULL OR e.id_beneficiario = @id_beneficiario)
      AND (@id_voluntario IS NULL OR e.id_voluntario = @id_voluntario)
      AND (@id_sector IS NULL OR b.id_sector = @id_sector)
      AND (@estado IS NULL OR e.estado = @estado)
      AND (@desde IS NULL OR e.fecha >= @desde)
      AND (@hasta IS NULL OR e.fecha <= @hasta)
    ORDER BY
        CASE WHEN @orden = 'cantidad' AND @desc = 0 THEN e.cantidad END ASC,
        CASE WHEN @orden = 'cantidad' AND @desc = 1 THEN e.cantidad END DESC,
        CASE WHEN @orden = 'hogar'    AND @desc = 0 THEN b.apellidos END ASC,
        CASE WHEN @orden = 'hogar'    AND @desc = 1 THEN b.apellidos END DESC,
        CASE WHEN @orden = 'fecha'    AND @desc = 0 THEN e.fecha END ASC,
        e.fecha DESC, e.id_entrega DESC
    OFFSET (@pagina - 1) * @tamano ROWS FETCH NEXT @tamano ROWS ONLY;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_entrega_crear
    @id_campana         INT,
    @id_beneficiario    INT,
    @id_voluntario      INT,
    @fecha              DATE,
    @cantidad           INT,
    @detalle            NVARCHAR(200) = NULL,
    @estado             VARCHAR(12) = 'Entregada',   -- 'Entregada' (ya ocurrió) o 'Programada' (planificada)
    @id_necesidad       INT = NULL,
    @confirmar_repetida BIT = 0,
    @id_actor           INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;
        DECLARE @hoy DATE = CONVERT(DATE, SYSDATETIME());
        IF @estado NOT IN ('Entregada', 'Programada')
            THROW 50422, N'Una entrega nueva solo puede registrarse como Entregada o Programada.', 1;

        DECLARE @estado_c VARCHAR(10), @ini DATE, @fin DATE, @cat INT;
        SELECT @estado_c = estado, @ini = fecha_inicio, @fin = fecha_fin, @cat = id_categoria
          FROM dbo.campana WHERE id_campana = @id_campana;
        IF @estado_c IS NULL
            THROW 50404, N'La campaña no existe.', 1;
        IF @estado_c <> 'Activa'
            THROW 50422, N'Solo se pueden registrar entregas en campañas activas.', 1;
        IF @fecha < @ini OR @fecha > @fin
            THROW 50422, N'La fecha de la entrega debe estar dentro del periodo de la campaña.', 1;
        IF @estado = 'Entregada' AND @fecha > @hoy
            THROW 50422, N'Una entrega ya realizada no puede tener fecha futura. Use "Programada".', 1;
        IF @estado = 'Programada' AND @fecha < @hoy
            THROW 50422, N'Una entrega programada debe tener fecha de hoy o posterior.', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.beneficiario WHERE id_beneficiario = @id_beneficiario AND activo = 1)
            THROW 50422, N'El hogar no existe o está inactivo.', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.voluntario WHERE id_voluntario = @id_voluntario AND activo = 1)
            THROW 50422, N'El voluntario no existe o está inactivo.', 1;
        IF @fecha < (SELECT fecha_ingreso FROM dbo.voluntario WHERE id_voluntario = @id_voluntario)
            THROW 50422, N'La entrega no puede ser anterior al ingreso del voluntario.', 1;

        IF @id_necesidad IS NOT NULL
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM dbo.necesidad WHERE id_necesidad = @id_necesidad AND id_beneficiario = @id_beneficiario
                           AND estado IN ('Pendiente', 'En atencion'))
                THROW 50422, N'La necesidad indicada no está abierta o no pertenece a ese hogar.', 1;
            IF NOT EXISTS (SELECT 1 FROM dbo.necesidad WHERE id_necesidad = @id_necesidad AND id_categoria = @cat)
                THROW 50422, N'La necesidad es de una categoría distinta a la de la campaña.', 1;
        END

        IF EXISTS (SELECT 1 FROM dbo.entrega WHERE id_campana = @id_campana AND id_beneficiario = @id_beneficiario
                   AND fecha = @fecha AND estado IN ('Programada', 'Entregada'))
            THROW 50409, N'Ese hogar ya tiene una entrega registrada en esa campaña para esa fecha.', 1;
        IF @confirmar_repetida = 0
        BEGIN
            DECLARE @previa DATE = (SELECT TOP (1) fecha FROM dbo.entrega
                                    WHERE id_campana = @id_campana AND id_beneficiario = @id_beneficiario
                                      AND estado IN ('Programada', 'Entregada') ORDER BY fecha DESC);
            IF @previa IS NOT NULL
            BEGIN
                DECLARE @msg NVARCHAR(300) = N'Este hogar ya recibe o recibió apoyo en esta campaña (' + CONVERT(NVARCHAR(10), @previa, 23)
                                           + N'). Confirme si corresponde un apoyo adicional.';
                THROW 50410, @msg, 1;
            END
        END

        INSERT dbo.entrega (id_campana, id_beneficiario, id_voluntario, id_necesidad, fecha, cantidad, detalle, estado)
        VALUES (@id_campana, @id_beneficiario, @id_voluntario, @id_necesidad, @fecha, @cantidad, @detalle, @estado);
        DECLARE @id INT = SCOPE_IDENTITY();

        IF @id_necesidad IS NOT NULL
            UPDATE dbo.necesidad
               SET estado = CASE WHEN @estado = 'Entregada' THEN 'Cubierta' ELSE 'En atencion' END,
                   fecha_cobertura = CASE WHEN @estado = 'Entregada' THEN @fecha ELSE NULL END,
                   actualizado_en = SYSUTCDATETIME()
             WHERE id_necesidad = @id_necesidad;

        DECLARE @det NVARCHAR(200) = @estado + N' · ' + CONVERT(NVARCHAR(10), @cantidad) + N' u. · campaña n.º ' + CONVERT(NVARCHAR(10), @id_campana);
        EXEC dbo.usp_auditoria_registrar @id_actor, 'CREAR', 'entrega', @id, @det;
        COMMIT;
        SELECT @id AS id_entrega;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_entrega_estado
    @id_entrega   INT,
    @nuevo_estado VARCHAR(12),
    @motivo       NVARCHAR(200) = NULL,
    @fecha        DATE = NULL,              -- fecha real al marcar como Entregada
    @id_actor     INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;
        DECLARE @hoy DATE = CONVERT(DATE, SYSDATETIME());
        DECLARE @actual VARCHAR(12), @fecha_prog DATE, @id_campana INT, @id_necesidad INT;
        SELECT @actual = estado, @fecha_prog = fecha, @id_campana = id_campana, @id_necesidad = id_necesidad
          FROM dbo.entrega WITH (UPDLOCK) WHERE id_entrega = @id_entrega;
        IF @actual IS NULL
            THROW 50404, N'La entrega no existe.', 1;
        IF NOT EXISTS (SELECT 1 FROM (VALUES ('Programada','Entregada'), ('Programada','No realizada'),
                                             ('Programada','Anulada'), ('Entregada','Anulada')) t (de, a)
                       WHERE t.de = @actual AND t.a = @nuevo_estado)
            THROW 50422, N'Esa transición de estado no está permitida para la entrega.', 1;
        IF @nuevo_estado IN ('No realizada', 'Anulada') AND (@motivo IS NULL OR LEN(LTRIM(RTRIM(@motivo))) = 0)
            THROW 50422, N'Indique el motivo.', 1;

        DECLARE @fecha_real DATE = @fecha_prog;
        IF @nuevo_estado = 'Entregada'
        BEGIN
            SET @fecha_real = COALESCE(@fecha, CASE WHEN @fecha_prog <= @hoy THEN @fecha_prog ELSE @hoy END);
            IF @fecha_real > @hoy
                THROW 50422, N'La fecha real de entrega no puede ser futura.', 1;
            IF @fecha_real < (SELECT fecha_inicio FROM dbo.campana WHERE id_campana = @id_campana)
               OR @fecha_real > (SELECT fecha_fin FROM dbo.campana WHERE id_campana = @id_campana)
                THROW 50422, N'La fecha real debe estar dentro del periodo de la campaña.', 1;
        END

        UPDATE dbo.entrega
           SET estado = @nuevo_estado, fecha = @fecha_real,
               motivo_estado = CASE WHEN @nuevo_estado IN ('No realizada', 'Anulada') THEN @motivo ELSE motivo_estado END,
               actualizado_en = SYSUTCDATETIME()
         WHERE id_entrega = @id_entrega;

        IF @id_necesidad IS NOT NULL
        BEGIN
            IF @nuevo_estado = 'Entregada'
                UPDATE dbo.necesidad SET estado = 'Cubierta', fecha_cobertura = @fecha_real, actualizado_en = SYSUTCDATETIME()
                 WHERE id_necesidad = @id_necesidad AND estado IN ('Pendiente', 'En atencion');
            ELSE
                -- la entrega no se concretó: la necesidad vuelve a la cola (si no hay otra abierta equivalente)
                UPDATE n SET estado = 'Pendiente', fecha_cobertura = NULL, actualizado_en = SYSUTCDATETIME()
                  FROM dbo.necesidad n
                 WHERE n.id_necesidad = @id_necesidad AND n.estado IN ('En atencion', 'Cubierta')
                   AND NOT EXISTS (SELECT 1 FROM dbo.necesidad n2
                                   WHERE n2.id_beneficiario = n.id_beneficiario AND n2.id_categoria = n.id_categoria
                                     AND n2.estado IN ('Pendiente', 'En atencion') AND n2.id_necesidad <> n.id_necesidad);
        END

        DECLARE @det NVARCHAR(200) = @actual + N' → ' + @nuevo_estado;
        EXEC dbo.usp_auditoria_registrar @id_actor, 'CAMBIAR_ESTADO', 'entrega', @id_entrega, @det;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

/* =====================================================================
   RETROALIMENTACIÓN, CONSULTAS Y QUEJAS
   Los casos "confidenciales" solo los ve quien tenga el permiso específico.
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.usp_feedback_listar
    @id                    INT = NULL,
    @q                     NVARCHAR(120) = NULL,
    @tipo                  VARCHAR(12) = NULL,
    @estado                VARCHAR(11) = NULL,
    @id_campana            INT = NULL,
    @id_beneficiario       INT = NULL,
    @vencidas              BIT = 0,
    @incluir_confidenciales BIT = 0,
    @pagina                INT = 1,
    @tamano                INT = 25
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @hoy DATE = CONVERT(DATE, SYSDATETIME());
    SELECT r.id_retroalimentacion, r.tipo, r.mensaje, r.calificacion, r.estado, r.confidencial,
           r.id_beneficiario, b.apellidos + N', ' + b.nombres AS hogar,
           r.id_entrega, r.id_campana, c.nombre AS campana,
           r.id_responsable, u.nombre_completo AS responsable, r.respuesta,
           r.fecha_limite,
           CAST(CASE WHEN r.estado IN ('Abierta', 'En revision') AND r.fecha_limite < @hoy THEN 1 ELSE 0 END AS BIT) AS vencida,
           DATEDIFF(DAY, @hoy, r.fecha_limite) AS dias_para_vencer,
           r.resuelta_en, r.creado_en,
           COUNT(*) OVER() AS total_filas
    FROM dbo.retroalimentacion r
    LEFT JOIN dbo.beneficiario b ON b.id_beneficiario = r.id_beneficiario
    LEFT JOIN dbo.campana c      ON c.id_campana = r.id_campana
    LEFT JOIN dbo.usuario u      ON u.id_usuario = r.id_responsable
    WHERE (@id IS NULL OR r.id_retroalimentacion = @id)
      AND (@q IS NULL OR r.mensaje LIKE @q ESCAPE '\')
      AND (@tipo IS NULL OR r.tipo = @tipo)
      AND (@estado IS NULL OR r.estado = @estado)
      AND (@id_campana IS NULL OR r.id_campana = @id_campana)
      AND (@id_beneficiario IS NULL OR r.id_beneficiario = @id_beneficiario)
      AND (@vencidas = 0 OR (r.estado IN ('Abierta', 'En revision') AND r.fecha_limite < @hoy))
      AND (@incluir_confidenciales = 1 OR r.confidencial = 0)
    ORDER BY CASE WHEN r.estado IN ('Abierta', 'En revision') THEN 0 ELSE 1 END,
             r.fecha_limite ASC, r.id_retroalimentacion DESC
    OFFSET (@pagina - 1) * @tamano ROWS FETCH NEXT @tamano ROWS ONLY;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_feedback_crear
    @tipo            VARCHAR(12),
    @mensaje         NVARCHAR(1000),
    @calificacion    TINYINT = NULL,
    @id_beneficiario INT = NULL,
    @id_entrega      INT = NULL,
    @id_campana      INT = NULL,
    @confidencial    BIT = 0,
    @dias_plazo      INT = 7,
    @id_actor        INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;
        IF @id_entrega IS NOT NULL
        BEGIN
            DECLARE @e_campana INT, @e_benef INT;
            SELECT @e_campana = id_campana, @e_benef = id_beneficiario FROM dbo.entrega WHERE id_entrega = @id_entrega;
            IF @e_campana IS NULL
                THROW 50404, N'La entrega indicada no existe.', 1;
            SET @id_campana      = ISNULL(@id_campana, @e_campana);
            SET @id_beneficiario = ISNULL(@id_beneficiario, @e_benef);
        END
        IF @id_beneficiario IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.beneficiario WHERE id_beneficiario = @id_beneficiario)
            THROW 50404, N'El hogar indicado no existe.', 1;
        IF @id_campana IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.campana WHERE id_campana = @id_campana)
            THROW 50404, N'La campaña indicada no existe.', 1;

        INSERT dbo.retroalimentacion (tipo, mensaje, calificacion, id_beneficiario, id_entrega, id_campana, confidencial, fecha_limite)
        VALUES (@tipo, @mensaje, @calificacion, @id_beneficiario, @id_entrega, @id_campana, @confidencial,
                DATEADD(DAY, @dias_plazo, CONVERT(DATE, SYSDATETIME())));
        DECLARE @id INT = SCOPE_IDENTITY();
        -- el contenido NO se copia a la bitácora (puede ser sensible)
        EXEC dbo.usp_auditoria_registrar @id_actor, 'CREAR', 'retroalimentacion', @id, @tipo;
        COMMIT;
        SELECT @id AS id_retroalimentacion;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_feedback_gestionar
    @id_retroalimentacion   INT,
    @nuevo_estado           VARCHAR(11),
    @respuesta              NVARCHAR(1000) = NULL,
    @id_responsable         INT = NULL,
    @incluir_confidenciales BIT = 0,
    @id_actor               INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;
        DECLARE @actual VARCHAR(11), @conf BIT, @resp_actual NVARCHAR(1000), @asignado INT;
        SELECT @actual = estado, @conf = confidencial, @resp_actual = respuesta, @asignado = id_responsable
          FROM dbo.retroalimentacion WITH (UPDLOCK) WHERE id_retroalimentacion = @id_retroalimentacion;
        IF @actual IS NULL OR (@conf = 1 AND @incluir_confidenciales = 0)
            THROW 50404, N'El registro no existe.', 1;
        IF NOT EXISTS (SELECT 1 FROM (VALUES ('Abierta','En revision'), ('Abierta','Resuelta'), ('Abierta','Cerrada'),
                                             ('En revision','Abierta'), ('En revision','Resuelta'), ('En revision','Cerrada'),
                                             ('Resuelta','En revision'), ('Resuelta','Cerrada')) t (de, a)
                       WHERE t.de = @actual AND t.a = @nuevo_estado)
            THROW 50422, N'Esa transición de estado no está permitida.', 1;
        IF @id_responsable IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.usuario WHERE id_usuario = @id_responsable AND activo = 1)
            THROW 50422, N'El responsable indicado no existe o está inactivo.', 1;
        DECLARE @respuesta_final NVARCHAR(1000) = ISNULL(NULLIF(LTRIM(RTRIM(@respuesta)), N''), @resp_actual);
        IF @nuevo_estado = 'Resuelta' AND @respuesta_final IS NULL
            THROW 50422, N'Para marcar como resuelta registre la respuesta dada.', 1;

        UPDATE dbo.retroalimentacion
           SET estado = @nuevo_estado,
               respuesta = @respuesta_final,
               id_responsable = COALESCE(@id_responsable, @asignado, CASE WHEN @nuevo_estado <> 'Abierta' THEN @id_actor END),
               resuelta_en = CASE WHEN @nuevo_estado IN ('Resuelta', 'Cerrada') THEN ISNULL(resuelta_en, SYSUTCDATETIME()) ELSE NULL END,
               actualizado_en = SYSUTCDATETIME()
         WHERE id_retroalimentacion = @id_retroalimentacion;
        DECLARE @det NVARCHAR(100) = @actual + N' → ' + @nuevo_estado;
        EXEC dbo.usp_auditoria_registrar @id_actor, 'CAMBIAR_ESTADO', 'retroalimentacion', @id_retroalimentacion, @det;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO
