-- =====================================================================
--  Carga de los CSV en la base de datos (ejecutar DESPUÉS de 01_esquema.sql)
--  El orden importa: primero las tablas padre, luego las hijas.
-- =====================================================================

-- ---------- OPCIÓN A: PostgreSQL (desde psql, dentro de la carpeta del proyecto) ----------
\copy categoria_ayuda FROM 'datos/categoria_ayuda.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy donante         FROM 'datos/donante.csv'         WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy voluntario      FROM 'datos/voluntario.csv'      WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy beneficiario    FROM 'datos/beneficiario.csv'    WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy campana         FROM 'datos/campana.csv'         WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy donacion        FROM 'datos/donacion.csv'        WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy entrega         FROM 'datos/entrega.csv'         WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

-- ---------- OPCIÓN B: MySQL 8 (descomentar; requiere local_infile=1) ----------
-- LOAD DATA LOCAL INFILE 'datos/categoria_ayuda.csv' INTO TABLE categoria_ayuda
--   CHARACTER SET utf8mb4 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
--   LINES TERMINATED BY '\n' IGNORE 1 LINES;
-- (repetir el mismo bloque, en este orden, para: donante, voluntario,
--  beneficiario, campana, donacion y entrega)

-- ---------- OPCIÓN C: DBeaver / pgAdmin / MySQL Workbench ----------
-- Clic derecho en la tabla > Importar datos > CSV, respetando el mismo orden.
