/* =====================================================================
   05_procedures_seguridad.sql  |  Auditoría, autenticación, usuarios y roles

   Convenciones de TODOS los procedimientos:
     - Cada escritura es una unidad transaccional: SET XACT_ABORT ON + TRY/CATCH.
     - Errores de negocio con THROW y un número de la serie 50xxx:
         50404 no encontrado | 50409 conflicto | 50410 requiere confirmación
         50422 regla de negocio violada | 50403 prohibido
       La capa Python los traduce a HTTP 404/409/409/422/403.
     - @id_actor = id del usuario autenticado (para la bitácora).
     - Listados: filtros opcionales (NULL = sin filtro), @id para obtener uno,
       y paginación OFFSET/FETCH con total_filas en cada fila.
     - @q llega ya escapado como patrón LIKE (ESCAPE '\').
   ===================================================================== */
USE [$(DB_NAME)];
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/* ---------------- Bitácora ---------------- */
CREATE OR ALTER PROCEDURE dbo.usp_auditoria_registrar
    @id_usuario INT = NULL,
    @accion     VARCHAR(30),
    @entidad    VARCHAR(40),
    @id_entidad INT = NULL,
    @detalle    NVARCHAR(1000) = NULL,
    @ip         VARCHAR(45) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT dbo.auditoria_evento (id_usuario, username, accion, entidad, id_entidad, detalle, ip)
    VALUES (@id_usuario,
            (SELECT username FROM dbo.usuario WHERE id_usuario = @id_usuario),
            @accion, @entidad, @id_entidad, LEFT(@detalle, 1000), @ip);
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_auditoria_listar
    @q          NVARCHAR(120) = NULL,
    @accion     VARCHAR(30)   = NULL,
    @entidad    VARCHAR(40)   = NULL,
    @id_usuario INT           = NULL,
    @desde      DATE          = NULL,
    @hasta      DATE          = NULL,
    @pagina     INT = 1,
    @tamano     INT = 25
AS
BEGIN
    SET NOCOUNT ON;
    SELECT a.id_evento, a.fecha, a.id_usuario, a.username, a.accion, a.entidad, a.id_entidad, a.detalle, a.ip,
           COUNT(*) OVER() AS total_filas
    FROM dbo.auditoria_evento a
    WHERE (@q IS NULL OR a.detalle LIKE @q ESCAPE '\' OR a.username LIKE @q ESCAPE '\')
      AND (@accion IS NULL OR a.accion = @accion)
      AND (@entidad IS NULL OR a.entidad = @entidad)
      AND (@id_usuario IS NULL OR a.id_usuario = @id_usuario)
      AND (@desde IS NULL OR a.fecha >= @desde)
      AND (@hasta IS NULL OR a.fecha < DATEADD(DAY, 1, CAST(@hasta AS DATETIME2(0))))
    ORDER BY a.fecha DESC, a.id_evento DESC
    OFFSET (@pagina - 1) * @tamano ROWS FETCH NEXT @tamano ROWS ONLY;
END
GO

/* ---------------- Autenticación ---------------- */
CREATE OR ALTER PROCEDURE dbo.usp_auth_obtener_credenciales
    @username VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT u.id_usuario, u.username, u.password_hash, u.activo, u.intentos_fallidos, u.bloqueado_hasta,
           CAST(CASE WHEN u.bloqueado_hasta IS NOT NULL AND u.bloqueado_hasta > SYSUTCDATETIME() THEN 1 ELSE 0 END AS BIT) AS bloqueado
    FROM dbo.usuario u
    WHERE u.username = @username;
END
GO

-- Registra un intento de acceso de un usuario existente; bloquea tras @max_intentos fallos seguidos
CREATE OR ALTER PROCEDURE dbo.usp_auth_registrar_intento
    @id_usuario      INT,
    @exitoso         BIT,
    @ip              VARCHAR(45) = NULL,
    @max_intentos    INT = 5,
    @minutos_bloqueo INT = 15
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;
        IF @exitoso = 1
        BEGIN
            UPDATE dbo.usuario
               SET intentos_fallidos = 0, bloqueado_hasta = NULL, ultimo_acceso = SYSUTCDATETIME()
             WHERE id_usuario = @id_usuario;
            EXEC dbo.usp_auditoria_registrar @id_usuario, 'LOGIN', 'usuario', @id_usuario, NULL, @ip;
        END
        ELSE
        BEGIN
            DECLARE @n INT = (SELECT CASE WHEN bloqueado_hasta IS NOT NULL AND bloqueado_hasta <= SYSUTCDATETIME()
                                          THEN 1 ELSE intentos_fallidos + 1 END
                                FROM dbo.usuario WHERE id_usuario = @id_usuario);
            UPDATE dbo.usuario
               SET intentos_fallidos = @n,
                   bloqueado_hasta = CASE WHEN @n >= @max_intentos
                                          THEN DATEADD(MINUTE, @minutos_bloqueo, SYSUTCDATETIME()) ELSE NULL END
             WHERE id_usuario = @id_usuario;
            EXEC dbo.usp_auditoria_registrar @id_usuario, 'LOGIN_FALLIDO', 'usuario', @id_usuario,
                 N'Contraseña incorrecta', @ip;
        END
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

-- Usuario autenticado + sus permisos (2 result sets). Se consulta en CADA petición protegida.
CREATE OR ALTER PROCEDURE dbo.usp_auth_obtener_usuario
    @id_usuario INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT u.id_usuario, u.username, u.nombre_completo, u.correo, u.id_rol,
           r.codigo AS rol_codigo, r.nombre AS rol_nombre,
           u.id_donante, u.id_voluntario, u.activo, u.debe_cambiar_password, u.token_version
    FROM dbo.usuario u
    JOIN dbo.rol r ON r.id_rol = u.id_rol
    WHERE u.id_usuario = @id_usuario;

    SELECT p.codigo
    FROM dbo.usuario u
    JOIN dbo.rol_permiso rp ON rp.id_rol = u.id_rol
    JOIN dbo.permiso p      ON p.id_permiso = rp.id_permiso
    WHERE u.id_usuario = @id_usuario
    ORDER BY p.codigo;
END
GO

/* ---------------- Usuarios ---------------- */
CREATE OR ALTER PROCEDURE dbo.usp_usuario_listar
    @id     INT = NULL,
    @q      NVARCHAR(120) = NULL,
    @id_rol INT = NULL,
    @activo BIT = NULL,
    @pagina INT = 1,
    @tamano INT = 25
AS
BEGIN
    SET NOCOUNT ON;
    SELECT u.id_usuario, u.username, u.nombre_completo, u.correo, u.id_rol,
           r.codigo AS rol_codigo, r.nombre AS rol_nombre,
           u.id_donante, dn.nombre AS donante,
           u.id_voluntario, vo.nombres + N' ' + vo.apellidos AS voluntario,
           u.activo, u.debe_cambiar_password, u.ultimo_acceso, u.bloqueado_hasta, u.creado_en,
           COUNT(*) OVER() AS total_filas
    FROM dbo.usuario u
    JOIN dbo.rol r ON r.id_rol = u.id_rol
    LEFT JOIN dbo.donante dn   ON dn.id_donante = u.id_donante
    LEFT JOIN dbo.voluntario vo ON vo.id_voluntario = u.id_voluntario
    WHERE (@id IS NULL OR u.id_usuario = @id)
      AND (@q IS NULL OR u.username LIKE @q ESCAPE '\' OR u.nombre_completo LIKE @q ESCAPE '\' OR u.correo LIKE @q ESCAPE '\')
      AND (@id_rol IS NULL OR u.id_rol = @id_rol)
      AND (@activo IS NULL OR u.activo = @activo)
    ORDER BY u.nombre_completo
    OFFSET (@pagina - 1) * @tamano ROWS FETCH NEXT @tamano ROWS ONLY;
END
GO

-- Crea (@id_usuario NULL) o edita un usuario. La contraseña solo se escribe al crear.
CREATE OR ALTER PROCEDURE dbo.usp_usuario_guardar
    @id_usuario            INT = NULL,
    @username              VARCHAR(50),
    @nombre_completo       NVARCHAR(120),
    @correo                NVARCHAR(100),
    @password_hash         VARCHAR(255) = NULL,
    @id_rol                INT,
    @id_donante            INT = NULL,
    @id_voluntario         INT = NULL,
    @debe_cambiar_password BIT = 0,
    @id_actor              INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;
        IF NOT EXISTS (SELECT 1 FROM dbo.rol WHERE id_rol = @id_rol)
            THROW 50404, N'El rol indicado no existe.', 1;
        IF @id_donante IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.donante WHERE id_donante = @id_donante)
            THROW 50404, N'El donante vinculado no existe.', 1;
        IF @id_voluntario IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.voluntario WHERE id_voluntario = @id_voluntario)
            THROW 50404, N'El voluntario vinculado no existe.', 1;
        IF EXISTS (SELECT 1 FROM dbo.usuario WHERE username = @username AND (@id_usuario IS NULL OR id_usuario <> @id_usuario))
            THROW 50409, N'Ya existe un usuario con ese nombre de usuario.', 1;
        IF EXISTS (SELECT 1 FROM dbo.usuario WHERE correo = @correo AND (@id_usuario IS NULL OR id_usuario <> @id_usuario))
            THROW 50409, N'Ya existe un usuario con ese correo.', 1;
        IF @id_donante IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.usuario WHERE id_donante = @id_donante AND (@id_usuario IS NULL OR id_usuario <> @id_usuario))
            THROW 50409, N'Ese donante ya tiene una cuenta de acceso.', 1;
        IF @id_voluntario IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.usuario WHERE id_voluntario = @id_voluntario AND (@id_usuario IS NULL OR id_usuario <> @id_usuario))
            THROW 50409, N'Ese voluntario ya tiene una cuenta de acceso.', 1;

        IF @id_usuario IS NULL
        BEGIN
            IF @password_hash IS NULL
                THROW 50422, N'Debe indicar una contraseña inicial.', 1;
            INSERT dbo.usuario (username, nombre_completo, correo, password_hash, id_rol, id_donante, id_voluntario, debe_cambiar_password)
            VALUES (@username, @nombre_completo, @correo, @password_hash, @id_rol, @id_donante, @id_voluntario, @debe_cambiar_password);
            SET @id_usuario = SCOPE_IDENTITY();
            EXEC dbo.usp_auditoria_registrar @id_actor, 'CREAR', 'usuario', @id_usuario, @username;
        END
        ELSE
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM dbo.usuario WHERE id_usuario = @id_usuario)
                THROW 50404, N'El usuario no existe.', 1;
            -- No se puede quitar el rol ADMIN al último administrador activo
            IF EXISTS (SELECT 1 FROM dbo.usuario u JOIN dbo.rol r ON r.id_rol = u.id_rol
                       WHERE u.id_usuario = @id_usuario AND r.codigo = 'ADMIN' AND u.activo = 1)
               AND NOT EXISTS (SELECT 1 FROM dbo.rol WHERE id_rol = @id_rol AND codigo = 'ADMIN')
               AND NOT EXISTS (SELECT 1 FROM dbo.usuario u JOIN dbo.rol r ON r.id_rol = u.id_rol
                               WHERE r.codigo = 'ADMIN' AND u.activo = 1 AND u.id_usuario <> @id_usuario)
                THROW 50422, N'Debe existir al menos un administrador activo.', 1;
            UPDATE dbo.usuario
               SET nombre_completo = @nombre_completo, correo = @correo,
                   token_version   = token_version + CASE WHEN id_rol <> @id_rol THEN 1 ELSE 0 END,  -- cambia el rol: revoca sesiones
                   id_rol = @id_rol, id_donante = @id_donante, id_voluntario = @id_voluntario,
                   actualizado_en = SYSUTCDATETIME()
             WHERE id_usuario = @id_usuario;
            EXEC dbo.usp_auditoria_registrar @id_actor, 'EDITAR', 'usuario', @id_usuario, @username;
        END
        COMMIT;
        SELECT @id_usuario AS id_usuario;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

-- Cambia la contraseña y revoca todas las sesiones emitidas (token_version + 1)
CREATE OR ALTER PROCEDURE dbo.usp_usuario_password
    @id_usuario            INT,
    @password_hash         VARCHAR(255),
    @debe_cambiar_password BIT = 0,
    @id_actor              INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;
        UPDATE dbo.usuario
           SET password_hash = @password_hash, debe_cambiar_password = @debe_cambiar_password,
               token_version = token_version + 1, intentos_fallidos = 0, bloqueado_hasta = NULL,
               actualizado_en = SYSUTCDATETIME()
         WHERE id_usuario = @id_usuario;
        IF @@ROWCOUNT = 0
            THROW 50404, N'El usuario no existe.', 1;
        EXEC dbo.usp_auditoria_registrar @id_actor, 'CAMBIAR_PASSWORD', 'usuario', @id_usuario,
             N'Se renovó la contraseña y se cerraron las sesiones activas';
        COMMIT;
        SELECT token_version FROM dbo.usuario WHERE id_usuario = @id_usuario;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_usuario_estado
    @id_usuario INT,
    @activo     BIT,
    @id_actor   INT = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;
        IF NOT EXISTS (SELECT 1 FROM dbo.usuario WHERE id_usuario = @id_usuario)
            THROW 50404, N'El usuario no existe.', 1;
        IF @activo = 0
           AND EXISTS (SELECT 1 FROM dbo.usuario u JOIN dbo.rol r ON r.id_rol = u.id_rol
                       WHERE u.id_usuario = @id_usuario AND r.codigo = 'ADMIN')
           AND NOT EXISTS (SELECT 1 FROM dbo.usuario u JOIN dbo.rol r ON r.id_rol = u.id_rol
                           WHERE r.codigo = 'ADMIN' AND u.activo = 1 AND u.id_usuario <> @id_usuario)
            THROW 50422, N'Debe existir al menos un administrador activo.', 1;
        UPDATE dbo.usuario
           SET activo = @activo, actualizado_en = SYSUTCDATETIME(),
               token_version = token_version + CASE WHEN @activo = 0 THEN 1 ELSE 0 END
         WHERE id_usuario = @id_usuario;
        DECLARE @det NVARCHAR(40) = CASE WHEN @activo = 1 THEN N'Reactivado' ELSE N'Desactivado' END;
        EXEC dbo.usp_auditoria_registrar @id_actor, 'CAMBIAR_ESTADO', 'usuario', @id_usuario, @det;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

/* ---------------- Roles y permisos ---------------- */
CREATE OR ALTER PROCEDURE dbo.usp_rol_listar
AS
BEGIN
    SET NOCOUNT ON;
    SELECT r.id_rol, r.codigo, r.nombre, r.descripcion,
           (SELECT COUNT(*) FROM dbo.rol_permiso rp WHERE rp.id_rol = r.id_rol)             AS permisos,
           (SELECT COUNT(*) FROM dbo.usuario u WHERE u.id_rol = r.id_rol AND u.activo = 1)  AS usuarios_activos
    FROM dbo.rol r
    ORDER BY r.id_rol;
END
GO

-- Matriz de permisos (2 result sets): catálogo de permisos y asignaciones rol-permiso
CREATE OR ALTER PROCEDURE dbo.usp_rol_matriz
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.codigo, p.modulo, p.descripcion FROM dbo.permiso p ORDER BY p.modulo, p.codigo;
    SELECT r.codigo AS rol_codigo, p.codigo AS permiso_codigo
    FROM dbo.rol_permiso rp
    JOIN dbo.rol r     ON r.id_rol = rp.id_rol
    JOIN dbo.permiso p ON p.id_permiso = rp.id_permiso;
END
GO
