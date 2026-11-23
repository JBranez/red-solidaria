/* =====================================================================
   01_create_database.sql
   Crea la base de datos de Red Solidaria. Idempotente: no destruye nada.
   Ejecutar con una cuenta administrativa (sa) conectada a master.
   Variables (las sustituye scripts/init_db.py):  $(DB_NAME)
   ===================================================================== */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF DB_ID(N'$(DB_NAME)') IS NULL
BEGIN
    -- Latin1_General_100_CI_AI: sin distinguir mayúsculas ni tildes.
    -- Permite que buscar "Hector" encuentre "Héctor" (nombres en español).
    CREATE DATABASE [$(DB_NAME)] COLLATE Latin1_General_100_CI_AI;
END
GO

-- Los lectores no bloquean a los escritores (dashboard vs. registro de donaciones)
ALTER DATABASE [$(DB_NAME)] SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
GO
ALTER DATABASE [$(DB_NAME)] SET ALLOW_SNAPSHOT_ISOLATION ON;
GO
