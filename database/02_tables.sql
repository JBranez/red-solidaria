/* =====================================================================
   02_tables.sql  |  Red Solidaria  |  Modelo relacional v2 (SQL Server)

   Idempotente: cada tabla se crea solo si no existe. NO hay DROP TABLE.
   (El 01_esquema.sql original eliminaba las tablas en cada ejecución.)

   Convenciones
     - PK: id_<tabla> INT IDENTITY (el original usaba enteros manuales).
     - Fechas de negocio: DATE.  Marcas técnicas: DATETIME2(0) en UTC.
     - Textos: NVARCHAR (tildes y ñ sin depender del code page).
     - Estados: VARCHAR con CHECK y valores ASCII (la UI los traduce).
     - Borrado lógico con "activo" en vez de DELETE (se conserva el historial).
     - Toda FK tiene su índice en 03_indexes.sql.
   Variables: $(DB_NAME)
   ===================================================================== */
USE [$(DB_NAME)];
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/* ---------------------------------------------------------------------
   0. Control de versiones del esquema
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.schema_migracion', N'U') IS NULL
CREATE TABLE dbo.schema_migracion (
    version     VARCHAR(20)   NOT NULL,
    descripcion NVARCHAR(200) NOT NULL,
    aplicada_en DATETIME2(0)  NOT NULL CONSTRAINT df_schema_migracion_fecha DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_schema_migracion PRIMARY KEY (version)
);
GO

/* ---------------------------------------------------------------------
   1. Catálogos
   --------------------------------------------------------------------- */
-- Sector: reemplaza el texto libre beneficiario.sector (evita "Villa Norte" / "villa norte ")
IF OBJECT_ID(N'dbo.sector', N'U') IS NULL
CREATE TABLE dbo.sector (
    id_sector INT          IDENTITY(1,1) NOT NULL,
    nombre    NVARCHAR(60) NOT NULL,
    activo    BIT          NOT NULL CONSTRAINT df_sector_activo DEFAULT 1,
    creado_en DATETIME2(0) NOT NULL CONSTRAINT df_sector_creado DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_sector        PRIMARY KEY (id_sector),
    CONSTRAINT uq_sector_nombre UNIQUE (nombre)
);
GO

-- Método de pago: reemplaza el CHECK con 3 literales (agregar uno nuevo ya no exige ALTER)
IF OBJECT_ID(N'dbo.metodo_pago', N'U') IS NULL
CREATE TABLE dbo.metodo_pago (
    id_metodo_pago     INT          IDENTITY(1,1) NOT NULL,
    nombre             NVARCHAR(30) NOT NULL,
    requiere_referencia BIT         NOT NULL CONSTRAINT df_metodo_pago_ref DEFAULT 0,
    activo             BIT          NOT NULL CONSTRAINT df_metodo_pago_activo DEFAULT 1,
    CONSTRAINT pk_metodo_pago        PRIMARY KEY (id_metodo_pago),
    CONSTRAINT uq_metodo_pago_nombre UNIQUE (nombre)
);
GO

IF OBJECT_ID(N'dbo.categoria_ayuda', N'U') IS NULL
CREATE TABLE dbo.categoria_ayuda (
    id_categoria   INT           IDENTITY(1,1) NOT NULL,
    nombre         NVARCHAR(50)  NOT NULL,
    descripcion    NVARCHAR(150) NOT NULL,
    activo         BIT           NOT NULL CONSTRAINT df_categoria_activo DEFAULT 1,
    creado_en      DATETIME2(0)  NOT NULL CONSTRAINT df_categoria_creado DEFAULT SYSUTCDATETIME(),
    actualizado_en DATETIME2(0)  NULL,
    CONSTRAINT pk_categoria        PRIMARY KEY (id_categoria),
    CONSTRAINT uq_categoria_nombre UNIQUE (nombre)
);
GO

/* ---------------------------------------------------------------------
   2. Personas y entidades de negocio (tablas del modelo original, mejoradas)
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.donante', N'U') IS NULL
CREATE TABLE dbo.donante (
    id_donante     INT           IDENTITY(1,1) NOT NULL,
    nombre         NVARCHAR(100) NOT NULL,
    tipo           VARCHAR(10)   NOT NULL,
    correo         NVARCHAR(100) NOT NULL,
    fecha_registro DATE          NOT NULL CONSTRAINT df_donante_fecha DEFAULT CONVERT(DATE, SYSDATETIME()),
    activo         BIT           NOT NULL CONSTRAINT df_donante_activo DEFAULT 1,
    creado_en      DATETIME2(0)  NOT NULL CONSTRAINT df_donante_creado DEFAULT SYSUTCDATETIME(),
    actualizado_en DATETIME2(0)  NULL,
    CONSTRAINT pk_donante        PRIMARY KEY (id_donante),
    CONSTRAINT uq_donante_correo UNIQUE (correo),
    CONSTRAINT ck_donante_tipo   CHECK (tipo IN ('Persona', 'Empresa')),
    CONSTRAINT ck_donante_correo CHECK (correo LIKE N'_%@_%._%' AND correo NOT LIKE N'% %')
);
GO

IF OBJECT_ID(N'dbo.voluntario', N'U') IS NULL
CREATE TABLE dbo.voluntario (
    id_voluntario  INT           IDENTITY(1,1) NOT NULL,
    nombres        NVARCHAR(60)  NOT NULL,
    apellidos      NVARCHAR(60)  NOT NULL,
    correo         NVARCHAR(100) NOT NULL,
    fecha_ingreso  DATE          NOT NULL CONSTRAINT df_voluntario_fecha DEFAULT CONVERT(DATE, SYSDATETIME()),
    activo         BIT           NOT NULL CONSTRAINT df_voluntario_activo DEFAULT 1,
    creado_en      DATETIME2(0)  NOT NULL CONSTRAINT df_voluntario_creado DEFAULT SYSUTCDATETIME(),
    actualizado_en DATETIME2(0)  NULL,
    CONSTRAINT pk_voluntario        PRIMARY KEY (id_voluntario),
    CONSTRAINT uq_voluntario_correo UNIQUE (correo),
    CONSTRAINT ck_voluntario_correo CHECK (correo LIKE N'_%@_%._%' AND correo NOT LIKE N'% %')
);
GO

-- Beneficiario = HOGAR representado por una persona responsable (no hay registro por integrante)
IF OBJECT_ID(N'dbo.beneficiario', N'U') IS NULL
CREATE TABLE dbo.beneficiario (
    id_beneficiario      INT          IDENTITY(1,1) NOT NULL,
    nombres              NVARCHAR(60) NOT NULL,
    apellidos            NVARCHAR(60) NOT NULL,
    id_sector            INT          NOT NULL,
    integrantes_hogar    INT          NOT NULL,
    fecha_registro       DATE         NOT NULL CONSTRAINT df_beneficiario_fecha DEFAULT CONVERT(DATE, SYSDATETIME()),
    -- Privacidad desde el diseño (Ley 29733): el consentimiento queda registrado, no se presume
    consentimiento_datos BIT          NOT NULL CONSTRAINT df_beneficiario_consent DEFAULT 0,
    fecha_consentimiento DATE         NULL,
    activo               BIT          NOT NULL CONSTRAINT df_beneficiario_activo DEFAULT 1,
    creado_en            DATETIME2(0) NOT NULL CONSTRAINT df_beneficiario_creado DEFAULT SYSUTCDATETIME(),
    actualizado_en       DATETIME2(0) NULL,
    CONSTRAINT pk_beneficiario        PRIMARY KEY (id_beneficiario),
    CONSTRAINT fk_beneficiario_sector FOREIGN KEY (id_sector) REFERENCES dbo.sector (id_sector),
    CONSTRAINT ck_benef_hogar         CHECK (integrantes_hogar BETWEEN 1 AND 30),
    CONSTRAINT ck_benef_consent       CHECK ((consentimiento_datos = 0 AND fecha_consentimiento IS NULL)
                                          OR (consentimiento_datos = 1 AND fecha_consentimiento IS NOT NULL))
);
GO

/* ---------------------------------------------------------------------
   3. Seguridad: usuarios, roles y permisos (RBAC)
      Un voluntario/donante NO es un usuario: se enlazan de forma opcional.
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.rol', N'U') IS NULL
CREATE TABLE dbo.rol (
    id_rol      INT           NOT NULL,           -- fijo, definido en 10_reference_data.sql
    codigo      VARCHAR(30)   NOT NULL,
    nombre      NVARCHAR(60)  NOT NULL,
    descripcion NVARCHAR(200) NOT NULL,
    CONSTRAINT pk_rol        PRIMARY KEY (id_rol),
    CONSTRAINT uq_rol_codigo UNIQUE (codigo)
);
GO

IF OBJECT_ID(N'dbo.permiso', N'U') IS NULL
CREATE TABLE dbo.permiso (
    id_permiso  INT           IDENTITY(1,1) NOT NULL,
    codigo      VARCHAR(50)   NOT NULL,           -- modulo:accion, p. ej. donaciones:verificar
    modulo      VARCHAR(30)   NOT NULL,
    descripcion NVARCHAR(150) NOT NULL,
    CONSTRAINT pk_permiso        PRIMARY KEY (id_permiso),
    CONSTRAINT uq_permiso_codigo UNIQUE (codigo)
);
GO

IF OBJECT_ID(N'dbo.rol_permiso', N'U') IS NULL
CREATE TABLE dbo.rol_permiso (
    id_rol     INT NOT NULL,
    id_permiso INT NOT NULL,
    CONSTRAINT pk_rol_permiso         PRIMARY KEY (id_rol, id_permiso),
    CONSTRAINT fk_rol_permiso_rol     FOREIGN KEY (id_rol)     REFERENCES dbo.rol (id_rol),
    CONSTRAINT fk_rol_permiso_permiso FOREIGN KEY (id_permiso) REFERENCES dbo.permiso (id_permiso)
);
GO

IF OBJECT_ID(N'dbo.usuario', N'U') IS NULL
CREATE TABLE dbo.usuario (
    id_usuario            INT           IDENTITY(1,1) NOT NULL,
    username              VARCHAR(50)   NOT NULL,
    nombre_completo       NVARCHAR(120) NOT NULL,
    correo                NVARCHAR(100) NOT NULL,
    password_hash         VARCHAR(255)  NOT NULL,        -- Argon2id; jamás texto plano
    id_rol                INT           NOT NULL,
    id_donante            INT           NULL,            -- solo rol DONANTE
    id_voluntario         INT           NULL,            -- solo rol VOLUNTARIO
    activo                BIT           NOT NULL CONSTRAINT df_usuario_activo DEFAULT 1,
    debe_cambiar_password BIT           NOT NULL CONSTRAINT df_usuario_cambiar DEFAULT 0,
    token_version         INT           NOT NULL CONSTRAINT df_usuario_tokenv DEFAULT 0,  -- sube => revoca los JWT emitidos
    intentos_fallidos     INT           NOT NULL CONSTRAINT df_usuario_intentos DEFAULT 0,
    bloqueado_hasta       DATETIME2(0)  NULL,
    ultimo_acceso         DATETIME2(0)  NULL,
    creado_en             DATETIME2(0)  NOT NULL CONSTRAINT df_usuario_creado DEFAULT SYSUTCDATETIME(),
    actualizado_en        DATETIME2(0)  NULL,
    CONSTRAINT pk_usuario            PRIMARY KEY (id_usuario),
    CONSTRAINT uq_usuario_username   UNIQUE (username),
    CONSTRAINT uq_usuario_correo     UNIQUE (correo),
    CONSTRAINT fk_usuario_rol        FOREIGN KEY (id_rol)        REFERENCES dbo.rol (id_rol),
    CONSTRAINT fk_usuario_donante    FOREIGN KEY (id_donante)    REFERENCES dbo.donante (id_donante),
    CONSTRAINT fk_usuario_voluntario FOREIGN KEY (id_voluntario) REFERENCES dbo.voluntario (id_voluntario),
    CONSTRAINT ck_usuario_username   CHECK (LEN(username) >= 3 AND username NOT LIKE '%[^a-z0-9._-]%'),
    CONSTRAINT ck_usuario_correo     CHECK (correo LIKE N'_%@_%._%' AND correo NOT LIKE N'% %'),
    CONSTRAINT ck_usuario_intentos   CHECK (intentos_fallidos >= 0)
);
GO

/* ---------------------------------------------------------------------
   4. Campañas y movimiento de recursos
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.campana', N'U') IS NULL
CREATE TABLE dbo.campana (
    id_campana       INT           IDENTITY(1,1) NOT NULL,
    nombre           NVARCHAR(100) NOT NULL,
    descripcion      NVARCHAR(500) NULL,
    objetivo_social  NVARCHAR(300) NULL,                 -- qué necesidad atiende
    id_categoria     INT           NOT NULL,
    fecha_inicio     DATE          NOT NULL,
    fecha_fin        DATE          NOT NULL,
    meta_recaudacion DECIMAL(12,2) NOT NULL,             -- meta ECONÓMICA
    meta_hogares     INT           NULL,                 -- meta SOCIAL (no se confunde con la económica)
    meta_unidades    INT           NULL,                 -- meta FÍSICA
    moneda           CHAR(3)       NOT NULL CONSTRAINT df_campana_moneda DEFAULT 'PEN',
    estado           VARCHAR(10)   NOT NULL CONSTRAINT df_campana_estado DEFAULT 'Borrador',
    id_responsable   INT           NULL,
    cerrada_en       DATETIME2(0)  NULL,
    motivo_cierre    NVARCHAR(200) NULL,
    anio             AS (YEAR(fecha_inicio)) PERSISTED,
    creado_en        DATETIME2(0)  NOT NULL CONSTRAINT df_campana_creado DEFAULT SYSUTCDATETIME(),
    actualizado_en   DATETIME2(0)  NULL,
    CONSTRAINT pk_campana           PRIMARY KEY (id_campana),
    -- único por (nombre, año): permite repetir "Canasta Solidaria" cada año
    CONSTRAINT uq_campana_nombre_anio UNIQUE (nombre, anio),
    CONSTRAINT fk_campana_categoria FOREIGN KEY (id_categoria)   REFERENCES dbo.categoria_ayuda (id_categoria),
    CONSTRAINT fk_campana_responsable FOREIGN KEY (id_responsable) REFERENCES dbo.usuario (id_usuario),
    CONSTRAINT ck_campana_fechas    CHECK (fecha_fin >= fecha_inicio),
    CONSTRAINT ck_campana_meta      CHECK (meta_recaudacion > 0),
    CONSTRAINT ck_campana_meta_hog  CHECK (meta_hogares  IS NULL OR meta_hogares  > 0),
    CONSTRAINT ck_campana_meta_uni  CHECK (meta_unidades IS NULL OR meta_unidades > 0),
    CONSTRAINT ck_campana_moneda    CHECK (moneda LIKE '[A-Z][A-Z][A-Z]'),
    CONSTRAINT ck_campana_estado    CHECK (estado IN ('Borrador','Activa','Pausada','Finalizada','Cancelada'))
);
GO

-- Donación: declarada ≠ recibida. El método de pago NO prueba el cobro: por eso existe "estado".
IF OBJECT_ID(N'dbo.donacion', N'U') IS NULL
CREATE TABLE dbo.donacion (
    id_donacion    INT           IDENTITY(1,1) NOT NULL,
    id_donante     INT           NOT NULL,
    id_campana     INT           NOT NULL,
    fecha          DATE          NOT NULL,
    monto          DECIMAL(12,2) NOT NULL,                -- la moneda es la de la campaña
    id_metodo_pago INT           NOT NULL,
    estado         VARCHAR(10)   NOT NULL CONSTRAINT df_donacion_estado DEFAULT 'Pendiente',
    referencia     NVARCHAR(60)  NULL,                    -- n.º de operación / voucher
    observacion    NVARCHAR(200) NULL,
    motivo_estado  NVARCHAR(200) NULL,
    confirmado_en  DATETIME2(0)  NULL,
    confirmado_por INT           NULL,
    creado_en      DATETIME2(0)  NOT NULL CONSTRAINT df_donacion_creado DEFAULT SYSUTCDATETIME(),
    actualizado_en DATETIME2(0)  NULL,
    CONSTRAINT pk_donacion             PRIMARY KEY (id_donacion),
    CONSTRAINT fk_donacion_donante     FOREIGN KEY (id_donante)     REFERENCES dbo.donante (id_donante),
    CONSTRAINT fk_donacion_campana     FOREIGN KEY (id_campana)     REFERENCES dbo.campana (id_campana),
    CONSTRAINT fk_donacion_metodo      FOREIGN KEY (id_metodo_pago) REFERENCES dbo.metodo_pago (id_metodo_pago),
    CONSTRAINT fk_donacion_confirmador FOREIGN KEY (confirmado_por) REFERENCES dbo.usuario (id_usuario),
    CONSTRAINT ck_donacion_monto       CHECK (monto > 0 AND monto <= 1000000),
    CONSTRAINT ck_donacion_estado      CHECK (estado IN ('Pendiente','Confirmada','Rechazada','Anulada')),
    CONSTRAINT ck_donacion_confirmada  CHECK (estado <> 'Confirmada' OR confirmado_en IS NOT NULL),
    CONSTRAINT ck_donacion_motivo      CHECK (estado NOT IN ('Rechazada','Anulada') OR motivo_estado IS NOT NULL)
);
GO

-- Gasto: separa lo RECAUDADO de lo EJECUTADO (el modelo original no tenía egresos)
IF OBJECT_ID(N'dbo.gasto', N'U') IS NULL
CREATE TABLE dbo.gasto (
    id_gasto           INT           IDENTITY(1,1) NOT NULL,
    id_campana         INT           NOT NULL,
    fecha              DATE          NOT NULL,
    concepto           NVARCHAR(150) NOT NULL,
    tipo               VARCHAR(15)   NOT NULL,
    proveedor          NVARCHAR(100) NULL,
    monto              DECIMAL(12,2) NOT NULL,
    comprobante        NVARCHAR(60)  NULL,                -- n.º de boleta / factura
    estado             VARCHAR(10)   NOT NULL CONSTRAINT df_gasto_estado DEFAULT 'Registrado',
    motivo_estado      NVARCHAR(200) NULL,
    id_usuario_registra INT          NULL,
    aprobado_por       INT           NULL,
    aprobado_en        DATETIME2(0)  NULL,
    creado_en          DATETIME2(0)  NOT NULL CONSTRAINT df_gasto_creado DEFAULT SYSUTCDATETIME(),
    actualizado_en     DATETIME2(0)  NULL,
    CONSTRAINT pk_gasto           PRIMARY KEY (id_gasto),
    CONSTRAINT fk_gasto_campana   FOREIGN KEY (id_campana)          REFERENCES dbo.campana (id_campana),
    CONSTRAINT fk_gasto_registra  FOREIGN KEY (id_usuario_registra) REFERENCES dbo.usuario (id_usuario),
    CONSTRAINT fk_gasto_aprobador FOREIGN KEY (aprobado_por)        REFERENCES dbo.usuario (id_usuario),
    CONSTRAINT ck_gasto_monto     CHECK (monto > 0),
    CONSTRAINT ck_gasto_tipo      CHECK (tipo IN ('Bienes','Transporte','Logistica','Administrativo','Otro')),
    CONSTRAINT ck_gasto_estado    CHECK (estado IN ('Registrado','Aprobado','Anulado')),
    CONSTRAINT ck_gasto_aprobado  CHECK (estado <> 'Aprobado' OR aprobado_en IS NOT NULL),
    CONSTRAINT ck_gasto_motivo    CHECK (estado <> 'Anulado' OR motivo_estado IS NOT NULL)
);
GO

/* ---------------------------------------------------------------------
   5. Necesidades, entregas y retroalimentación
   --------------------------------------------------------------------- */
-- Necesidad: conecta la ayuda con lo que el hogar necesita (sin esto solo se sabe "a quién se le dio algo")
IF OBJECT_ID(N'dbo.necesidad', N'U') IS NULL
CREATE TABLE dbo.necesidad (
    id_necesidad        INT           IDENTITY(1,1) NOT NULL,
    id_beneficiario     INT           NOT NULL,
    id_categoria        INT           NOT NULL,
    urgencia            VARCHAR(7)    NOT NULL,
    estado              VARCHAR(11)   NOT NULL CONSTRAINT df_necesidad_estado DEFAULT 'Pendiente',
    descripcion         NVARCHAR(300) NULL,
    fecha_registro      DATE          NOT NULL CONSTRAINT df_necesidad_fecha DEFAULT CONVERT(DATE, SYSDATETIME()),
    fecha_cobertura     DATE          NULL,
    motivo_estado       NVARCHAR(200) NULL,
    id_usuario_registra INT           NULL,
    creado_en           DATETIME2(0)  NOT NULL CONSTRAINT df_necesidad_creado DEFAULT SYSUTCDATETIME(),
    actualizado_en      DATETIME2(0)  NULL,
    CONSTRAINT pk_necesidad              PRIMARY KEY (id_necesidad),
    CONSTRAINT fk_necesidad_beneficiario FOREIGN KEY (id_beneficiario)     REFERENCES dbo.beneficiario (id_beneficiario),
    CONSTRAINT fk_necesidad_categoria    FOREIGN KEY (id_categoria)        REFERENCES dbo.categoria_ayuda (id_categoria),
    CONSTRAINT fk_necesidad_usuario      FOREIGN KEY (id_usuario_registra) REFERENCES dbo.usuario (id_usuario),
    CONSTRAINT ck_necesidad_urgencia     CHECK (urgencia IN ('Baja','Media','Alta','Critica')),
    CONSTRAINT ck_necesidad_estado       CHECK (estado IN ('Pendiente','En atencion','Cubierta','Descartada')),
    CONSTRAINT ck_necesidad_cobertura    CHECK (estado <> 'Cubierta' OR fecha_cobertura IS NOT NULL),
    CONSTRAINT ck_necesidad_motivo       CHECK (estado <> 'Descartada' OR motivo_estado IS NOT NULL)
);
GO

IF OBJECT_ID(N'dbo.entrega', N'U') IS NULL
CREATE TABLE dbo.entrega (
    id_entrega      INT           IDENTITY(1,1) NOT NULL,
    id_campana      INT           NOT NULL,
    id_beneficiario INT           NOT NULL,
    id_voluntario   INT           NOT NULL,
    id_necesidad    INT           NULL,                  -- necesidad que esta entrega atiende (opcional)
    fecha           DATE          NOT NULL,              -- fecha real o programada
    cantidad        INT           NOT NULL,              -- unidades GENÉRICAS (ver detalle)
    detalle         NVARCHAR(200) NULL,                  -- qué se entregó (canasta, kit, abrigo...)
    estado          VARCHAR(12)   NOT NULL CONSTRAINT df_entrega_estado DEFAULT 'Entregada',
    motivo_estado   NVARCHAR(200) NULL,
    creado_en       DATETIME2(0)  NOT NULL CONSTRAINT df_entrega_creado DEFAULT SYSUTCDATETIME(),
    actualizado_en  DATETIME2(0)  NULL,
    CONSTRAINT pk_entrega              PRIMARY KEY (id_entrega),
    CONSTRAINT fk_entrega_campana      FOREIGN KEY (id_campana)      REFERENCES dbo.campana (id_campana),
    CONSTRAINT fk_entrega_beneficiario FOREIGN KEY (id_beneficiario) REFERENCES dbo.beneficiario (id_beneficiario),
    CONSTRAINT fk_entrega_voluntario   FOREIGN KEY (id_voluntario)   REFERENCES dbo.voluntario (id_voluntario),
    CONSTRAINT fk_entrega_necesidad    FOREIGN KEY (id_necesidad)    REFERENCES dbo.necesidad (id_necesidad),
    CONSTRAINT ck_entrega_cantidad     CHECK (cantidad > 0 AND cantidad <= 1000),
    CONSTRAINT ck_entrega_estado       CHECK (estado IN ('Programada','Entregada','No realizada','Anulada')),
    CONSTRAINT ck_entrega_motivo       CHECK (estado NOT IN ('No realizada','Anulada') OR motivo_estado IS NOT NULL)
);
GO

-- Retroalimentación y quejas (Core Humanitarian Standard / IFRC CEA)
IF OBJECT_ID(N'dbo.retroalimentacion', N'U') IS NULL
CREATE TABLE dbo.retroalimentacion (
    id_retroalimentacion INT           IDENTITY(1,1) NOT NULL,
    tipo                 VARCHAR(12)   NOT NULL,
    mensaje              NVARCHAR(1000) NOT NULL,
    calificacion         TINYINT       NULL,                 -- satisfacción 1-5 (opcional)
    id_beneficiario      INT           NULL,                 -- NULL = comunicación anónima
    id_entrega           INT           NULL,
    id_campana           INT           NULL,
    confidencial         BIT           NOT NULL CONSTRAINT df_retro_conf DEFAULT 0,
    estado               VARCHAR(11)   NOT NULL CONSTRAINT df_retro_estado DEFAULT 'Abierta',
    id_responsable       INT           NULL,
    respuesta            NVARCHAR(1000) NULL,
    fecha_limite         DATE          NOT NULL,             -- plazo de atención comprometido
    resuelta_en          DATETIME2(0)  NULL,
    creado_en            DATETIME2(0)  NOT NULL CONSTRAINT df_retro_creado DEFAULT SYSUTCDATETIME(),
    actualizado_en       DATETIME2(0)  NULL,
    CONSTRAINT pk_retroalimentacion       PRIMARY KEY (id_retroalimentacion),
    CONSTRAINT fk_retro_beneficiario      FOREIGN KEY (id_beneficiario) REFERENCES dbo.beneficiario (id_beneficiario),
    CONSTRAINT fk_retro_entrega           FOREIGN KEY (id_entrega)      REFERENCES dbo.entrega (id_entrega),
    CONSTRAINT fk_retro_campana           FOREIGN KEY (id_campana)      REFERENCES dbo.campana (id_campana),
    CONSTRAINT fk_retro_responsable       FOREIGN KEY (id_responsable)  REFERENCES dbo.usuario (id_usuario),
    CONSTRAINT ck_retro_tipo              CHECK (tipo IN ('Consulta','Sugerencia','Queja','Felicitacion')),
    CONSTRAINT ck_retro_calificacion      CHECK (calificacion IS NULL OR calificacion BETWEEN 1 AND 5),
    CONSTRAINT ck_retro_estado            CHECK (estado IN ('Abierta','En revision','Resuelta','Cerrada')),
    CONSTRAINT ck_retro_resuelta          CHECK (estado NOT IN ('Resuelta','Cerrada') OR resuelta_en IS NOT NULL)
);
GO

/* ---------------------------------------------------------------------
   6. Auditoría: bitácora de negocio, de SOLO INSERCIÓN
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.auditoria_evento', N'U') IS NULL
CREATE TABLE dbo.auditoria_evento (
    id_evento  BIGINT         IDENTITY(1,1) NOT NULL,
    fecha      DATETIME2(0)   NOT NULL CONSTRAINT df_auditoria_fecha DEFAULT SYSUTCDATETIME(),
    id_usuario INT            NULL,                    -- NULL = sistema / intento sin sesión
    username   VARCHAR(50)    NULL,                    -- copia: se conserva aunque cambie el usuario
    accion     VARCHAR(30)    NOT NULL,
    entidad    VARCHAR(40)    NOT NULL,
    id_entidad INT            NULL,
    detalle    NVARCHAR(1000) NULL,
    ip         VARCHAR(45)    NULL,
    CONSTRAINT pk_auditoria_evento PRIMARY KEY (id_evento),
    CONSTRAINT fk_auditoria_usuario FOREIGN KEY (id_usuario) REFERENCES dbo.usuario (id_usuario)
);
GO

IF OBJECT_ID(N'dbo.trg_auditoria_inmutable', N'TR') IS NOT NULL
    DROP TRIGGER dbo.trg_auditoria_inmutable;
GO
-- Nadie (ni la aplicación) puede modificar o borrar la bitácora
CREATE TRIGGER dbo.trg_auditoria_inmutable ON dbo.auditoria_evento
INSTEAD OF UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    THROW 50403, N'La bitácora de auditoría es de solo inserción.', 1;
END
GO

IF NOT EXISTS (SELECT 1 FROM dbo.schema_migracion WHERE version = N'2.0.0')
    INSERT dbo.schema_migracion (version, descripcion)
    VALUES (N'2.0.0', N'Modelo v2: catálogos, estados, RBAC, auditoría, necesidades, gastos y retroalimentación');
GO
