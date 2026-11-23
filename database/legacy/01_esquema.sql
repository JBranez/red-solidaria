-- =====================================================================
--  RED SOLIDARIA  |  Base de datos relacional en 3FN
--  Gestión de donaciones y ayuda social
--
--  Idea en una frase:
--    Personas y empresas DONAN a CAMPAÑAS de ayuda; luego VOLUNTARIOS
--    ENTREGAN esa ayuda a HOGARES que la necesitan.
--
--  Sirve para cualquier ONG, banco de alimentos, parroquia, colegio o
--  municipio, en cualquier país (los montos están en moneda local).
--
--  SQL estándar: funciona en PostgreSQL, MySQL 8+ y SQLite.
--  Los ids NO son autoincrementales: vienen ya definidos en los CSV.
-- =====================================================================
--  Justificación de normalización
--  1FN: todos los campos son atómicos (nombres y apellidos separados,
--       sin listas ni grupos repetidos).
--  2FN: todas las tablas tienen llave primaria de una sola columna, por
--       lo que no existen dependencias parciales.
--  3FN: cada dato vive en un solo lugar. Ejemplos:
--       - el nombre y correo del donante están en DONANTE, no repetidos
--         en cada DONACION;
--       - el nombre de la categoría está en CATEGORIA_AYUDA, no repetido
--         en cada CAMPANA;
--       - los datos del hogar están en BENEFICIARIO, no en ENTREGA.
-- =====================================================================

-- Limpieza (orden inverso a las dependencias) para poder re-ejecutar el script
DROP TABLE IF EXISTS entrega;
DROP TABLE IF EXISTS donacion;
DROP TABLE IF EXISTS campana;
DROP TABLE IF EXISTS beneficiario;
DROP TABLE IF EXISTS voluntario;
DROP TABLE IF EXISTS donante;
DROP TABLE IF EXISTS categoria_ayuda;

-- ---------------------------------------------------------------------
-- 1. CATEGORIA_AYUDA: tipo de ayuda que ofrece cada campaña
-- ---------------------------------------------------------------------
CREATE TABLE categoria_ayuda (
    id_categoria INT          NOT NULL,
    nombre       VARCHAR(50)  NOT NULL,
    descripcion  VARCHAR(150) NOT NULL,
    CONSTRAINT pk_categoria        PRIMARY KEY (id_categoria),
    CONSTRAINT uq_categoria_nombre UNIQUE (nombre)
);

-- ---------------------------------------------------------------------
-- 2. DONANTE: personas o empresas que aportan dinero
-- ---------------------------------------------------------------------
CREATE TABLE donante (
    id_donante     INT          NOT NULL,
    nombre         VARCHAR(100) NOT NULL,
    tipo           VARCHAR(10)  NOT NULL,
    correo         VARCHAR(100) NOT NULL,
    fecha_registro DATE         NOT NULL,
    CONSTRAINT pk_donante        PRIMARY KEY (id_donante),
    CONSTRAINT uq_donante_correo UNIQUE (correo),
    CONSTRAINT ck_donante_tipo   CHECK (tipo IN ('Persona', 'Empresa'))
);

-- ---------------------------------------------------------------------
-- 3. VOLUNTARIO: personas que reparten la ayuda
-- ---------------------------------------------------------------------
CREATE TABLE voluntario (
    id_voluntario INT          NOT NULL,
    nombres       VARCHAR(60)  NOT NULL,
    apellidos     VARCHAR(60)  NOT NULL,
    correo        VARCHAR(100) NOT NULL,
    fecha_ingreso DATE         NOT NULL,
    CONSTRAINT pk_voluntario        PRIMARY KEY (id_voluntario),
    CONSTRAINT uq_voluntario_correo UNIQUE (correo)
);

-- ---------------------------------------------------------------------
-- 4. BENEFICIARIO: hogares que reciben ayuda (representados por su jefe/a)
-- ---------------------------------------------------------------------
CREATE TABLE beneficiario (
    id_beneficiario   INT         NOT NULL,
    nombres           VARCHAR(60) NOT NULL,
    apellidos         VARCHAR(60) NOT NULL,
    sector            VARCHAR(60) NOT NULL,
    integrantes_hogar INT         NOT NULL,
    fecha_registro    DATE        NOT NULL,
    CONSTRAINT pk_beneficiario  PRIMARY KEY (id_beneficiario),
    CONSTRAINT ck_benef_hogar   CHECK (integrantes_hogar > 0)
);

-- ---------------------------------------------------------------------
-- 5. CAMPANA: cada iniciativa de recaudación y ayuda, con su meta en dinero
-- ---------------------------------------------------------------------
CREATE TABLE campana (
    id_campana       INT           NOT NULL,
    nombre           VARCHAR(100)  NOT NULL,
    id_categoria     INT           NOT NULL,
    fecha_inicio     DATE          NOT NULL,
    fecha_fin        DATE          NOT NULL,
    meta_recaudacion DECIMAL(10,2) NOT NULL,
    CONSTRAINT pk_campana           PRIMARY KEY (id_campana),
    CONSTRAINT uq_campana_nombre    UNIQUE (nombre),
    CONSTRAINT fk_campana_categoria FOREIGN KEY (id_categoria) REFERENCES categoria_ayuda (id_categoria),
    CONSTRAINT ck_campana_fechas    CHECK (fecha_fin >= fecha_inicio),
    CONSTRAINT ck_campana_meta      CHECK (meta_recaudacion > 0)
);

-- ---------------------------------------------------------------------
-- 6. DONACION: un aporte de un donante a una campaña
-- ---------------------------------------------------------------------
CREATE TABLE donacion (
    id_donacion INT           NOT NULL,
    id_donante  INT           NOT NULL,
    id_campana  INT           NOT NULL,
    fecha       DATE          NOT NULL,
    monto       DECIMAL(10,2) NOT NULL,
    metodo_pago VARCHAR(15)   NOT NULL,
    CONSTRAINT pk_donacion          PRIMARY KEY (id_donacion),
    CONSTRAINT fk_donacion_donante  FOREIGN KEY (id_donante) REFERENCES donante (id_donante),
    CONSTRAINT fk_donacion_campana  FOREIGN KEY (id_campana) REFERENCES campana (id_campana),
    CONSTRAINT ck_donacion_monto    CHECK (monto > 0),
    CONSTRAINT ck_donacion_metodo   CHECK (metodo_pago IN ('Efectivo', 'Transferencia', 'Tarjeta'))
);

-- ---------------------------------------------------------------------
-- 7. ENTREGA: ayuda entregada a un hogar, dentro de una campaña, por un voluntario
-- ---------------------------------------------------------------------
CREATE TABLE entrega (
    id_entrega      INT  NOT NULL,
    id_campana      INT  NOT NULL,
    id_beneficiario INT  NOT NULL,
    id_voluntario   INT  NOT NULL,
    fecha           DATE NOT NULL,
    cantidad        INT  NOT NULL,   -- unidades entregadas (canastas, kits, abrigos, raciones...)
    CONSTRAINT pk_entrega              PRIMARY KEY (id_entrega),
    CONSTRAINT fk_entrega_campana      FOREIGN KEY (id_campana)      REFERENCES campana (id_campana),
    CONSTRAINT fk_entrega_beneficiario FOREIGN KEY (id_beneficiario) REFERENCES beneficiario (id_beneficiario),
    CONSTRAINT fk_entrega_voluntario   FOREIGN KEY (id_voluntario)   REFERENCES voluntario (id_voluntario),
    CONSTRAINT ck_entrega_cantidad     CHECK (cantidad > 0)
);

-- ---------------------------------------------------------------------
-- Índices sobre llaves foráneas de uso frecuente
-- ---------------------------------------------------------------------
CREATE INDEX ix_campana_categoria   ON campana (id_categoria);
CREATE INDEX ix_donacion_donante    ON donacion (id_donante);
CREATE INDEX ix_donacion_campana    ON donacion (id_campana);
CREATE INDEX ix_entrega_campana     ON entrega (id_campana);
CREATE INDEX ix_entrega_beneficiario ON entrega (id_beneficiario);
