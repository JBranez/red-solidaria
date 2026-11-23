/* =====================================================================
   09_permissions.sql  |  Cuenta de aplicación con MÍNIMO privilegio

   FastAPI NUNCA se conecta como sa. La cuenta de aplicación solo puede
   ejecutar procedimientos almacenados; no puede leer ni escribir tablas
   directamente. Gracias al "encadenamiento de propietarios" (los
   procedimientos, vistas y tablas pertenecen a dbo), los procedimientos sí
   pueden tocar las tablas aunque el usuario tenga DENY directo.
   (Por eso no se usa SQL dinámico dentro de los procedimientos: rompería la cadena.)

   Variables: $(DB_NAME) $(DB_APP_USER) $(DB_APP_PASSWORD)
   ===================================================================== */
USE master;
GO
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$(DB_APP_USER)')
    CREATE LOGIN [$(DB_APP_USER)] WITH PASSWORD = N'$(DB_APP_PASSWORD)', DEFAULT_DATABASE = [$(DB_NAME)], CHECK_POLICY = ON;
ELSE
    ALTER LOGIN [$(DB_APP_USER)] WITH PASSWORD = N'$(DB_APP_PASSWORD)';   -- permite rotar la contraseña re-ejecutando
GO

USE [$(DB_NAME)];
GO
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'$(DB_APP_USER)')
    CREATE USER [$(DB_APP_USER)] FOR LOGIN [$(DB_APP_USER)] WITH DEFAULT_SCHEMA = dbo;
GO

GRANT EXECUTE ON SCHEMA::dbo TO [$(DB_APP_USER)];
DENY  SELECT, INSERT, UPDATE, DELETE ON SCHEMA::dbo TO [$(DB_APP_USER)];
-- DENY CONTROL incluye implícitamente EXECUTE y prevalecería sobre el GRANT
-- anterior. Se deniega ALTER/REFERENCES directamente, pero no CONTROL de schema.
DENY  ALTER, REFERENCES ON SCHEMA::dbo TO [$(DB_APP_USER)];
GO

IF NOT EXISTS (SELECT 1 FROM dbo.schema_migracion WHERE version = N'2.0.2')
    INSERT dbo.schema_migracion (version, descripcion) VALUES (N'2.0.2', N'Permisos de la cuenta de aplicación (solo EXECUTE)');
GO
