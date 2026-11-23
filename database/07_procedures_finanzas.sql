/* =====================================================================
   07_procedures_finanzas.sql  |  Campañas, donantes, donaciones y gastos
   Ver convenciones en 05_procedures_seguridad.sql.
   Recordatorio T-SQL: los argumentos de EXEC no admiten expresiones;
   por eso el detalle de auditoría se arma antes en una variable.
   ===================================================================== */
USE [$(DB_NAME)];
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/* =====================================================================
   CAMPAÑAS
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.usp_campana_listar
    @id           INT = NULL,
    @q            NVARCHAR(120) = NULL,
    @estado       VARCHAR(10)   = NULL,
    @id_categoria INT           = NULL,
    @desde        DATE          = NULL,   -- campañas que terminan en o después de esta fecha
    @hasta        DATE          = NULL,   -- campañas que empiezan en o antes de esta fecha
    @orden        VARCHAR(20)   = NULL,
    @desc         BIT           = 0,
    @pagina       INT = 1,
    @tamano       INT = 25
AS
BEGIN
    SET NOCOUNT ON;
    SELECT v.*, COUNT(*) OVER() AS total_filas
    FROM dbo.vw_campana_resumen v
    WHERE (@id IS NULL OR v.id_campana = @id)
      AND (@q IS NULL OR v.nombre LIKE @q ESCAPE '\' OR v.categoria LIKE @q ESCAPE '\')
      AND (@estado IS NULL OR v.estado = @estado)
      AND (@id_categoria IS NULL OR v.id_categoria = @id_categoria)
      AND (@desde IS NULL OR v.fecha_fin >= @desde)
      AND (@hasta IS NULL OR v.fecha_inicio <= @hasta)
    ORDER BY
        CASE WHEN @orden = 'nombre'       AND @desc = 0 THEN v.nombre END ASC,
        CASE WHEN @orden = 'nombre'       AND @desc = 1 THEN v.nombre END DESC,
        CASE WHEN @orden = 'fecha_inicio' AND @desc = 0 THEN v.fecha_inicio END ASC,
        CASE WHEN @orden = 'fecha_inicio' AND @desc = 1 THEN v.fecha_inicio END DESC,
        CASE WHEN @orden = 'recaudado'    AND @desc = 0 THEN v.recaudado_confirmado END ASC,
        CASE WHEN @orden = 'recaudado'    AND @desc = 1 THEN v.recaudado_confirmado END DESC,
        CASE WHEN @orden = 'avance'       AND @desc = 0 THEN v.pct_meta_recaudacion END ASC,
        CASE WHEN @orden = 'avance'       AND @desc = 1 THEN v.pct_meta_recaudacion END DESC,
        CASE WHEN @orden IS NULL THEN
             CASE v.estado WHEN 'Activa' THEN 1 WHEN 'Pausada' THEN 2 WHEN 'Borrador' THEN 3
                           WHEN 'Finalizada' THEN 4 ELSE 5 END END ASC,
        v.fecha_inicio DESC, v.id_campana DESC
    OFFSET (@pagina - 1) * @tamano ROWS FETCH NEXT @tamano ROWS ONLY;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_campana_guardar
    @id_campana       INT = NULL,
    @nombre           NVARCHAR(100),
    @descripcion      NVARCHAR(500) = NULL,
    @objetivo_social  NVARCHAR(300) = NULL,
    @id_categoria     INT,
    @fecha_inicio     DATE,
    @fecha_fin        DATE,
    @meta_recaudacion DECIMAL(12,2),
    @meta_hogares     INT = NULL,
    @meta_unidades    INT = NULL,
    @moneda           CHAR(3) = 'PEN',
    @id_responsable   INT = NULL,
    @id_actor         INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;
        IF @fecha_fin < @fecha_inicio
            THROW 50422, N'La fecha de fin no puede ser anterior a la de inicio.', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.categoria_ayuda WHERE id_categoria = @id_categoria AND activo = 1)
            THROW 50422, N'La categoría no existe o está desactivada.', 1;
        IF @id_responsable IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.usuario WHERE id_usuario = @id_responsable AND activo = 1)
            THROW 50422, N'El responsable indicado no existe o está inactivo.', 1;
        IF EXISTS (SELECT 1 FROM dbo.campana WHERE nombre = @nombre AND anio = YEAR(@fecha_inicio)
                   AND (@id_campana IS NULL OR id_campana <> @id_campana))
            THROW 50409, N'Ya existe una campaña con ese nombre en el mismo año.', 1;

        IF @id_campana IS NULL
        BEGIN
            INSERT dbo.campana (nombre, descripcion, objetivo_social, id_categoria, fecha_inicio, fecha_fin,
                                meta_recaudacion, meta_hogares, meta_unidades, moneda, id_responsable, estado)
            VALUES (@nombre, @descripcion, @objetivo_social, @id_categoria, @fecha_inicio, @fecha_fin,
                    @meta_recaudacion, @meta_hogares, @meta_unidades, @moneda, @id_responsable, 'Borrador');
            SET @id_campana = SCOPE_IDENTITY();
            EXEC dbo.usp_auditoria_registrar @id_actor, 'CREAR', 'campana', @id_campana, @nombre;
        END
        ELSE
        BEGIN
            DECLARE @estado_actual VARCHAR(10), @moneda_actual CHAR(3);
            SELECT @estado_actual = estado, @moneda_actual = moneda
              FROM dbo.campana WITH (UPDLOCK) WHERE id_campana = @id_campana;
            IF @estado_actual IS NULL
                THROW 50404, N'La campaña no existe.', 1;
            IF @estado_actual NOT IN ('Borrador', 'Activa', 'Pausada')
                THROW 50422, N'Una campaña finalizada o cancelada ya no se puede editar.', 1;
            IF @moneda <> @moneda_actual AND EXISTS (SELECT 1 FROM dbo.donacion WHERE id_campana = @id_campana AND estado IN ('Pendiente', 'Confirmada'))
                THROW 50422, N'No se puede cambiar la moneda: la campaña ya tiene donaciones.', 1;
            IF EXISTS (SELECT 1 FROM dbo.donacion WHERE id_campana = @id_campana AND estado IN ('Pendiente', 'Confirmada')
                       AND (fecha < @fecha_inicio OR fecha > @fecha_fin))
               OR EXISTS (SELECT 1 FROM dbo.entrega WHERE id_campana = @id_campana AND estado IN ('Programada', 'Entregada')
                       AND (fecha < @fecha_inicio OR fecha > @fecha_fin))
                THROW 50422, N'Las nuevas fechas dejarían donaciones o entregas fuera del periodo de la campaña.', 1;
            UPDATE dbo.campana
               SET nombre = @nombre, descripcion = @descripcion, objetivo_social = @objetivo_social,
                   id_categoria = @id_categoria, fecha_inicio = @fecha_inicio, fecha_fin = @fecha_fin,
                   meta_recaudacion = @meta_recaudacion, meta_hogares = @meta_hogares, meta_unidades = @meta_unidades,
                   moneda = @moneda, id_responsable = @id_responsable, actualizado_en = SYSUTCDATETIME()
             WHERE id_campana = @id_campana;
            EXEC dbo.usp_auditoria_registrar @id_actor, 'EDITAR', 'campana', @id_campana, @nombre;
        END
        COMMIT;
        SELECT @id_campana AS id_campana;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

-- Ciclo de vida: Borrador → Activa ⇄ Pausada → Finalizada | Cancelada
CREATE OR ALTER PROCEDURE dbo.usp_campana_estado
    @id_campana   INT,
    @nuevo_estado VARCHAR(10),
    @motivo       NVARCHAR(200) = NULL,
    @id_actor     INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;
        DECLARE @actual VARCHAR(10), @fin DATE, @cat INT, @hoy DATE = CONVERT(DATE, SYSDATETIME());
        SELECT @actual = estado, @fin = fecha_fin, @cat = id_categoria
          FROM dbo.campana WITH (UPDLOCK, HOLDLOCK) WHERE id_campana = @id_campana;
        IF @actual IS NULL
            THROW 50404, N'La campaña no existe.', 1;
        IF NOT EXISTS (SELECT 1 FROM (VALUES ('Borrador','Activa'), ('Borrador','Cancelada'),
                                             ('Activa','Pausada'), ('Activa','Finalizada'), ('Activa','Cancelada'),
                                             ('Pausada','Activa'), ('Pausada','Finalizada'), ('Pausada','Cancelada')) t (de, a)
                       WHERE t.de = @actual AND t.a = @nuevo_estado)
            THROW 50422, N'Esa transición de estado no está permitida para la campaña.', 1;
        IF @nuevo_estado = 'Activa' AND @fin < @hoy
            THROW 50422, N'No se puede activar una campaña cuya fecha de fin ya pasó. Edite las fechas primero.', 1;
        IF @nuevo_estado = 'Activa' AND NOT EXISTS (SELECT 1 FROM dbo.categoria_ayuda WHERE id_categoria = @cat AND activo = 1)
            THROW 50422, N'La categoría de la campaña está desactivada.', 1;
        IF @nuevo_estado = 'Cancelada' AND (@motivo IS NULL OR LEN(LTRIM(RTRIM(@motivo))) = 0)
            THROW 50422, N'Indique el motivo de la cancelación.', 1;
        IF @nuevo_estado IN ('Finalizada', 'Cancelada')
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.donacion WHERE id_campana = @id_campana AND estado = 'Pendiente')
                THROW 50422, N'Hay donaciones pendientes de verificación. Confírmelas o recházelas antes de cerrar.', 1;
            IF EXISTS (SELECT 1 FROM dbo.entrega WHERE id_campana = @id_campana AND estado = 'Programada')
                THROW 50422, N'Hay entregas programadas sin resolver. Márquelas como entregadas o no realizadas antes de cerrar.', 1;
        END
        UPDATE dbo.campana
           SET estado = @nuevo_estado,
               cerrada_en    = CASE WHEN @nuevo_estado IN ('Finalizada', 'Cancelada') THEN SYSUTCDATETIME() ELSE cerrada_en END,
               motivo_cierre = CASE WHEN @nuevo_estado IN ('Finalizada', 'Cancelada') THEN @motivo ELSE motivo_cierre END,
               actualizado_en = SYSUTCDATETIME()
         WHERE id_campana = @id_campana;
        DECLARE @det NVARCHAR(200) = @actual + N' → ' + @nuevo_estado;
        EXEC dbo.usp_auditoria_registrar @id_actor, 'CAMBIAR_ESTADO', 'campana', @id_campana, @det;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

-- Informe de cierre (5 result sets): resumen, donaciones por método, gastos por tipo, entregas por sector, retroalimentación
CREATE OR ALTER PROCEDURE dbo.usp_campana_cierre
    @id_campana INT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.campana WHERE id_campana = @id_campana)
        THROW 50404, N'La campaña no existe.', 1;

    SELECT v.* FROM dbo.vw_campana_resumen v WHERE v.id_campana = @id_campana;

    SELECT mp.nombre AS metodo, COUNT(*) AS cantidad, SUM(d.monto) AS total
    FROM dbo.donacion d JOIN dbo.metodo_pago mp ON mp.id_metodo_pago = d.id_metodo_pago
    WHERE d.id_campana = @id_campana AND d.estado = 'Confirmada'
    GROUP BY mp.nombre ORDER BY total DESC;

    SELECT g.tipo, COUNT(*) AS cantidad, SUM(g.monto) AS total
    FROM dbo.gasto g
    WHERE g.id_campana = @id_campana AND g.estado = 'Aprobado'
    GROUP BY g.tipo ORDER BY total DESC;

    SELECT s.nombre AS sector, COUNT(DISTINCT e.id_beneficiario) AS hogares, COUNT(*) AS entregas, SUM(e.cantidad) AS unidades
    FROM dbo.entrega e
    JOIN dbo.beneficiario b ON b.id_beneficiario = e.id_beneficiario
    JOIN dbo.sector s       ON s.id_sector = b.id_sector
    WHERE e.id_campana = @id_campana AND e.estado = 'Entregada'
    GROUP BY s.nombre ORDER BY unidades DESC;

    SELECT COUNT(*) AS total,
           CAST(AVG(CASE WHEN r.calificacion IS NOT NULL THEN CAST(r.calificacion AS DECIMAL(4,2)) END) AS DECIMAL(3,1)) AS satisfaccion_promedio,
           COUNT(CASE WHEN r.tipo = 'Queja' THEN 1 END) AS quejas,
           COUNT(CASE WHEN r.tipo = 'Queja' AND r.estado IN ('Abierta', 'En revision') THEN 1 END) AS quejas_abiertas
    FROM dbo.retroalimentacion r
    WHERE r.id_campana = @id_campana AND r.confidencial = 0;
END
GO

/* =====================================================================
   DONANTES
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.usp_donante_listar
    @id     INT = NULL,
    @q      NVARCHAR(120) = NULL,
    @tipo   VARCHAR(10)   = NULL,
    @activo BIT           = NULL,
    @orden  VARCHAR(20)   = NULL,
    @desc   BIT           = 0,
    @pagina INT = 1,
    @tamano INT = 25
AS
BEGIN
    SET NOCOUNT ON;
    SELECT v.*, COUNT(*) OVER() AS total_filas
    FROM dbo.vw_donante_resumen v
    WHERE (@id IS NULL OR v.id_donante = @id)
      AND (@q IS NULL OR v.nombre LIKE @q ESCAPE '\' OR v.correo LIKE @q ESCAPE '\')
      AND (@tipo IS NULL OR v.tipo = @tipo)
      AND (@activo IS NULL OR v.activo = @activo)
    ORDER BY
        CASE WHEN @orden = 'nombre'        AND @desc = 0 THEN v.nombre END ASC,
        CASE WHEN @orden = 'nombre'        AND @desc = 1 THEN v.nombre END DESC,
        CASE WHEN @orden = 'total_donado'  AND @desc = 0 THEN v.total_donado END ASC,
        CASE WHEN @orden = 'total_donado'  AND @desc = 1 THEN v.total_donado END DESC,
        CASE WHEN @orden = 'ultima_donacion' AND @desc = 0 THEN v.ultima_donacion END ASC,
        CASE WHEN @orden = 'ultima_donacion' AND @desc = 1 THEN v.ultima_donacion END DESC,
        v.nombre ASC
    OFFSET (@pagina - 1) * @tamano ROWS FETCH NEXT @tamano ROWS ONLY;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_donante_guardar
    @id_donante          INT = NULL,
    @nombre              NVARCHAR(100),
    @tipo                VARCHAR(10),
    @correo              NVARCHAR(100),
    @confirmar_duplicado BIT = 0,
    @id_actor            INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;
        IF EXISTS (SELECT 1 FROM dbo.donante WHERE correo = @correo AND (@id_donante IS NULL OR id_donante <> @id_donante))
            THROW 50409, N'Ya existe un donante con ese correo.', 1;
        IF @confirmar_duplicado = 0
        BEGIN
            DECLARE @dup INT = (SELECT TOP (1) id_donante FROM dbo.donante
                                WHERE nombre = @nombre AND (@id_donante IS NULL OR id_donante <> @id_donante));
            IF @dup IS NOT NULL
            BEGIN
                DECLARE @msg NVARCHAR(300) = N'Ya hay un donante con el mismo nombre (n.º ' + CONVERT(NVARCHAR(10), @dup)
                                           + N'). Si es otra persona o empresa, confirme para registrarlo de todos modos.';
                THROW 50410, @msg, 1;
            END
        END
        IF @id_donante IS NULL
        BEGIN
            INSERT dbo.donante (nombre, tipo, correo) VALUES (@nombre, @tipo, @correo);
            SET @id_donante = SCOPE_IDENTITY();
            EXEC dbo.usp_auditoria_registrar @id_actor, 'CREAR', 'donante', @id_donante, @nombre;
        END
        ELSE
        BEGIN
            UPDATE dbo.donante SET nombre = @nombre, tipo = @tipo, correo = @correo, actualizado_en = SYSUTCDATETIME()
             WHERE id_donante = @id_donante;
            IF @@ROWCOUNT = 0 THROW 50404, N'El donante no existe.', 1;
            EXEC dbo.usp_auditoria_registrar @id_actor, 'EDITAR', 'donante', @id_donante, @nombre;
        END
        COMMIT;
        SELECT @id_donante AS id_donante;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_donante_estado
    @id_donante INT,
    @activo     BIT,
    @id_actor   INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;
        UPDATE dbo.donante SET activo = @activo, actualizado_en = SYSUTCDATETIME() WHERE id_donante = @id_donante;
        IF @@ROWCOUNT = 0 THROW 50404, N'El donante no existe.', 1;
        DECLARE @det NVARCHAR(40) = CASE WHEN @activo = 1 THEN N'Reactivado' ELSE N'Desactivado' END;
        EXEC dbo.usp_auditoria_registrar @id_actor, 'CAMBIAR_ESTADO', 'donante', @id_donante, @det;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

/* =====================================================================
   DONACIONES  (Pendiente → Confirmada | Rechazada | Anulada ; Confirmada → Anulada)
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.usp_donacion_listar
    @id             INT = NULL,
    @q              NVARCHAR(120) = NULL,   -- nombre del donante o referencia
    @id_campana     INT = NULL,
    @id_donante     INT = NULL,
    @estado         VARCHAR(10) = NULL,
    @id_metodo_pago INT = NULL,
    @desde          DATE = NULL,
    @hasta          DATE = NULL,
    @orden          VARCHAR(20) = NULL,
    @desc           BIT = 1,
    @pagina         INT = 1,
    @tamano         INT = 25
AS
BEGIN
    SET NOCOUNT ON;
    SELECT d.id_donacion, d.fecha, d.monto, c.moneda, d.estado, d.referencia, d.observacion, d.motivo_estado,
           d.id_donante, dn.nombre AS donante, dn.tipo AS donante_tipo,
           d.id_campana, c.nombre AS campana,
           d.id_metodo_pago, mp.nombre AS metodo_pago,
           d.confirmado_en, uc.nombre_completo AS confirmado_por, d.creado_en,
           COUNT(*) OVER() AS total_filas
    FROM dbo.donacion d
    JOIN dbo.donante dn     ON dn.id_donante = d.id_donante
    JOIN dbo.campana c      ON c.id_campana = d.id_campana
    JOIN dbo.metodo_pago mp ON mp.id_metodo_pago = d.id_metodo_pago
    LEFT JOIN dbo.usuario uc ON uc.id_usuario = d.confirmado_por
    WHERE (@id IS NULL OR d.id_donacion = @id)
      AND (@q IS NULL OR dn.nombre LIKE @q ESCAPE '\' OR d.referencia LIKE @q ESCAPE '\')
      AND (@id_campana IS NULL OR d.id_campana = @id_campana)
      AND (@id_donante IS NULL OR d.id_donante = @id_donante)
      AND (@estado IS NULL OR d.estado = @estado)
      AND (@id_metodo_pago IS NULL OR d.id_metodo_pago = @id_metodo_pago)
      AND (@desde IS NULL OR d.fecha >= @desde)
      AND (@hasta IS NULL OR d.fecha <= @hasta)
    ORDER BY
        CASE WHEN @orden = 'monto'   AND @desc = 0 THEN d.monto END ASC,
        CASE WHEN @orden = 'monto'   AND @desc = 1 THEN d.monto END DESC,
        CASE WHEN @orden = 'donante' AND @desc = 0 THEN dn.nombre END ASC,
        CASE WHEN @orden = 'donante' AND @desc = 1 THEN dn.nombre END DESC,
        CASE WHEN @orden = 'fecha'   AND @desc = 0 THEN d.fecha END ASC,
        d.fecha DESC, d.id_donacion DESC
    OFFSET (@pagina - 1) * @tamano ROWS FETCH NEXT @tamano ROWS ONLY;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_donacion_crear
    @id_donante          INT,
    @id_campana          INT,
    @fecha               DATE,
    @monto               DECIMAL(12,2),
    @id_metodo_pago      INT,
    @referencia          NVARCHAR(60)  = NULL,
    @observacion         NVARCHAR(200) = NULL,
    @confirmar           BIT = 0,        -- 1 = nace confirmada (requiere permiso de verificación en la API)
    @confirmar_duplicado BIT = 0,
    @id_actor            INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;
        DECLARE @estado_c VARCHAR(10), @ini DATE, @fin DATE, @hoy DATE = CONVERT(DATE, SYSDATETIME());
        SELECT @estado_c = estado, @ini = fecha_inicio, @fin = fecha_fin FROM dbo.campana WHERE id_campana = @id_campana;
        IF @estado_c IS NULL
            THROW 50404, N'La campaña no existe.', 1;
        IF @estado_c <> 'Activa'
            THROW 50422, N'Solo se pueden registrar donaciones en campañas activas.', 1;
        IF @fecha < @ini OR @fecha > @fin
            THROW 50422, N'La fecha de la donación debe estar dentro del periodo de la campaña.', 1;
        IF @fecha > @hoy
            THROW 50422, N'La fecha de la donación no puede ser futura.', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.donante WHERE id_donante = @id_donante AND activo = 1)
            THROW 50422, N'El donante no existe o está inactivo.', 1;

        DECLARE @req_ref BIT, @metodo_activo BIT;
        SELECT @req_ref = requiere_referencia, @metodo_activo = activo FROM dbo.metodo_pago WHERE id_metodo_pago = @id_metodo_pago;
        IF @metodo_activo IS NULL OR @metodo_activo = 0
            THROW 50422, N'El método de pago no existe o está desactivado.', 1;
        IF @req_ref = 1 AND (@referencia IS NULL OR LEN(LTRIM(RTRIM(@referencia))) = 0)
            THROW 50422, N'Este método de pago requiere el número de operación o referencia.', 1;
        IF @referencia IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.donacion
               WHERE id_metodo_pago = @id_metodo_pago AND referencia = @referencia AND estado <> 'Anulada')
            THROW 50409, N'Esa referencia de operación ya fue registrada con el mismo método de pago.', 1;
        IF @confirmar_duplicado = 0 AND EXISTS (SELECT 1 FROM dbo.donacion
               WHERE id_donante = @id_donante AND id_campana = @id_campana AND fecha = @fecha AND monto = @monto
                 AND estado IN ('Pendiente', 'Confirmada'))
            THROW 50410, N'Ya existe una donación igual (mismo donante, campaña, fecha y monto). Confirme si es una donación distinta.', 1;

        INSERT dbo.donacion (id_donante, id_campana, fecha, monto, id_metodo_pago, estado, referencia, observacion, confirmado_en, confirmado_por)
        VALUES (@id_donante, @id_campana, @fecha, @monto, @id_metodo_pago,
                CASE WHEN @confirmar = 1 THEN 'Confirmada' ELSE 'Pendiente' END, @referencia, @observacion,
                CASE WHEN @confirmar = 1 THEN SYSUTCDATETIME() END,
                CASE WHEN @confirmar = 1 THEN @id_actor END);
        DECLARE @id INT = SCOPE_IDENTITY();
        DECLARE @det NVARCHAR(200) = N'Monto ' + CONVERT(NVARCHAR(20), @monto) + N' a campaña n.º ' + CONVERT(NVARCHAR(10), @id_campana)
                                   + CASE WHEN @confirmar = 1 THEN N' (confirmada al registrar)' ELSE N'' END;
        EXEC dbo.usp_auditoria_registrar @id_actor, 'CREAR', 'donacion', @id, @det;
        COMMIT;
        SELECT @id AS id_donacion;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_donacion_estado
    @id_donacion  INT,
    @nuevo_estado VARCHAR(10),
    @motivo       NVARCHAR(200) = NULL,
    @id_actor     INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;
        DECLARE @actual VARCHAR(10), @monto DECIMAL(12,2);
        DECLARE @id_campana INT = (SELECT id_campana FROM dbo.donacion WHERE id_donacion = @id_donacion);  -- inmutable
        IF @id_campana IS NULL
            THROW 50404, N'La donación no existe.', 1;
        -- 1.º se toma el bloqueo de la campaña (serializa operaciones financieras: donaciones vs. gastos)...
        DECLARE @estado_c VARCHAR(10) = (SELECT estado FROM dbo.campana WITH (UPDLOCK, HOLDLOCK) WHERE id_campana = @id_campana);
        -- 2.º se lee el estado ya con el bloqueo: nunca un valor desactualizado
        SELECT @actual = estado, @monto = monto FROM dbo.donacion WHERE id_donacion = @id_donacion;
        IF NOT EXISTS (SELECT 1 FROM (VALUES ('Pendiente','Confirmada'), ('Pendiente','Rechazada'),
                                             ('Pendiente','Anulada'), ('Confirmada','Anulada')) t (de, a)
                       WHERE t.de = @actual AND t.a = @nuevo_estado)
            THROW 50422, N'Esa transición de estado no está permitida para la donación.', 1;
        IF @nuevo_estado IN ('Rechazada', 'Anulada') AND (@motivo IS NULL OR LEN(LTRIM(RTRIM(@motivo))) = 0)
            THROW 50422, N'Indique el motivo.', 1;
        IF @nuevo_estado = 'Confirmada' AND @estado_c = 'Cancelada'
            THROW 50422, N'No se puede confirmar una donación de una campaña cancelada.', 1;
        IF @actual = 'Confirmada' AND @nuevo_estado = 'Anulada'
        BEGIN
            DECLARE @recaudado DECIMAL(14,2) = (SELECT ISNULL(SUM(monto), 0) FROM dbo.donacion WHERE id_campana = @id_campana AND estado = 'Confirmada');
            DECLARE @gastado   DECIMAL(14,2) = (SELECT ISNULL(SUM(monto), 0) FROM dbo.gasto    WHERE id_campana = @id_campana AND estado = 'Aprobado');
            IF @recaudado - @monto < @gastado
                THROW 50422, N'No se puede anular: los gastos aprobados de la campaña superarían lo recaudado.', 1;
        END
        UPDATE dbo.donacion
           SET estado = @nuevo_estado,
               motivo_estado  = CASE WHEN @nuevo_estado IN ('Rechazada', 'Anulada') THEN @motivo ELSE motivo_estado END,
               confirmado_en  = CASE WHEN @nuevo_estado = 'Confirmada' THEN SYSUTCDATETIME() ELSE confirmado_en END,
               confirmado_por = CASE WHEN @nuevo_estado = 'Confirmada' THEN @id_actor ELSE confirmado_por END,
               actualizado_en = SYSUTCDATETIME()
         WHERE id_donacion = @id_donacion;
        DECLARE @det NVARCHAR(200) = @actual + N' → ' + @nuevo_estado + CASE WHEN @motivo IS NOT NULL THEN N' (' + LEFT(@motivo, 120) + N')' ELSE N'' END;
        EXEC dbo.usp_auditoria_registrar @id_actor, 'CAMBIAR_ESTADO', 'donacion', @id_donacion, @det;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

/* =====================================================================
   GASTOS  (Registrado → Aprobado | Anulado ; Aprobado → Anulado)
   ===================================================================== */
CREATE OR ALTER PROCEDURE dbo.usp_gasto_listar
    @id         INT = NULL,
    @q          NVARCHAR(120) = NULL,
    @id_campana INT = NULL,
    @estado     VARCHAR(10) = NULL,
    @tipo       VARCHAR(15) = NULL,
    @desde      DATE = NULL,
    @hasta      DATE = NULL,
    @pagina     INT = 1,
    @tamano     INT = 25
AS
BEGIN
    SET NOCOUNT ON;
    SELECT g.id_gasto, g.id_campana, c.nombre AS campana, c.moneda, g.fecha, g.concepto, g.tipo, g.proveedor,
           g.monto, g.comprobante, g.estado, g.motivo_estado,
           g.id_usuario_registra, ur.nombre_completo AS registrado_por,
           g.aprobado_por AS id_aprobador, ua.nombre_completo AS aprobado_por, g.aprobado_en, g.creado_en,
           COUNT(*) OVER() AS total_filas
    FROM dbo.gasto g
    JOIN dbo.campana c ON c.id_campana = g.id_campana
    LEFT JOIN dbo.usuario ur ON ur.id_usuario = g.id_usuario_registra
    LEFT JOIN dbo.usuario ua ON ua.id_usuario = g.aprobado_por
    WHERE (@id IS NULL OR g.id_gasto = @id)
      AND (@q IS NULL OR g.concepto LIKE @q ESCAPE '\' OR g.proveedor LIKE @q ESCAPE '\' OR g.comprobante LIKE @q ESCAPE '\')
      AND (@id_campana IS NULL OR g.id_campana = @id_campana)
      AND (@estado IS NULL OR g.estado = @estado)
      AND (@tipo IS NULL OR g.tipo = @tipo)
      AND (@desde IS NULL OR g.fecha >= @desde)
      AND (@hasta IS NULL OR g.fecha <= @hasta)
    ORDER BY g.fecha DESC, g.id_gasto DESC
    OFFSET (@pagina - 1) * @tamano ROWS FETCH NEXT @tamano ROWS ONLY;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_gasto_crear
    @id_campana  INT,
    @fecha       DATE,
    @concepto    NVARCHAR(150),
    @tipo        VARCHAR(15),
    @proveedor   NVARCHAR(100) = NULL,
    @monto       DECIMAL(12,2),
    @comprobante NVARCHAR(60)  = NULL,
    @id_actor    INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;
        DECLARE @estado_c VARCHAR(10) = (SELECT estado FROM dbo.campana WHERE id_campana = @id_campana);
        IF @estado_c IS NULL
            THROW 50404, N'La campaña no existe.', 1;
        IF @estado_c IN ('Borrador', 'Cancelada')
            THROW 50422, N'No se registran gastos en campañas en borrador o canceladas.', 1;
        IF @fecha > CONVERT(DATE, SYSDATETIME())
            THROW 50422, N'La fecha del gasto no puede ser futura.', 1;
        INSERT dbo.gasto (id_campana, fecha, concepto, tipo, proveedor, monto, comprobante, id_usuario_registra)
        VALUES (@id_campana, @fecha, @concepto, @tipo, @proveedor, @monto, @comprobante, @id_actor);
        DECLARE @id INT = SCOPE_IDENTITY();
        DECLARE @det NVARCHAR(200) = LEFT(@concepto, 100) + N' — ' + CONVERT(NVARCHAR(20), @monto);
        EXEC dbo.usp_auditoria_registrar @id_actor, 'CREAR', 'gasto', @id, @det;
        COMMIT;
        SELECT @id AS id_gasto;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

-- Aprobar exige: persona distinta a quien registró (separación de funciones) y saldo suficiente
CREATE OR ALTER PROCEDURE dbo.usp_gasto_estado
    @id_gasto     INT,
    @nuevo_estado VARCHAR(10),
    @motivo       NVARCHAR(200) = NULL,
    @id_actor     INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;
        DECLARE @actual VARCHAR(10), @monto DECIMAL(12,2), @registra INT;
        DECLARE @id_campana INT = (SELECT id_campana FROM dbo.gasto WHERE id_gasto = @id_gasto);  -- inmutable
        IF @id_campana IS NULL
            THROW 50404, N'El gasto no existe.', 1;
        DECLARE @bloqueo INT = (SELECT id_campana FROM dbo.campana WITH (UPDLOCK, HOLDLOCK) WHERE id_campana = @id_campana);
        SELECT @actual = estado, @monto = monto, @registra = id_usuario_registra FROM dbo.gasto WHERE id_gasto = @id_gasto;
        IF NOT EXISTS (SELECT 1 FROM (VALUES ('Registrado','Aprobado'), ('Registrado','Anulado'), ('Aprobado','Anulado')) t (de, a)
                       WHERE t.de = @actual AND t.a = @nuevo_estado)
            THROW 50422, N'Esa transición de estado no está permitida para el gasto.', 1;
        IF @nuevo_estado = 'Anulado' AND (@motivo IS NULL OR LEN(LTRIM(RTRIM(@motivo))) = 0)
            THROW 50422, N'Indique el motivo de la anulación.', 1;
        IF @nuevo_estado = 'Aprobado'
        BEGIN
            IF @registra IS NOT NULL AND @registra = @id_actor
                THROW 50422, N'El gasto debe ser aprobado por una persona distinta de quien lo registró.', 1;
            DECLARE @recaudado DECIMAL(14,2) = (SELECT ISNULL(SUM(monto), 0) FROM dbo.donacion WHERE id_campana = @id_campana AND estado = 'Confirmada');
            DECLARE @gastado   DECIMAL(14,2) = (SELECT ISNULL(SUM(monto), 0) FROM dbo.gasto    WHERE id_campana = @id_campana AND estado = 'Aprobado');
            IF @recaudado - @gastado < @monto
                THROW 50422, N'El gasto excede el saldo disponible de la campaña (solo cuentan donaciones confirmadas).', 1;
        END
        UPDATE dbo.gasto
           SET estado = @nuevo_estado,
               motivo_estado = CASE WHEN @nuevo_estado = 'Anulado' THEN @motivo ELSE motivo_estado END,
               aprobado_por  = CASE WHEN @nuevo_estado = 'Aprobado' THEN @id_actor ELSE aprobado_por END,
               aprobado_en   = CASE WHEN @nuevo_estado = 'Aprobado' THEN SYSUTCDATETIME() ELSE aprobado_en END,
               actualizado_en = SYSUTCDATETIME()
         WHERE id_gasto = @id_gasto;
        DECLARE @det NVARCHAR(200) = @actual + N' → ' + @nuevo_estado;
        EXEC dbo.usp_auditoria_registrar @id_actor, 'CAMBIAR_ESTADO', 'gasto', @id_gasto, @det;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO
