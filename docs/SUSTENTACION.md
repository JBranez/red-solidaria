# Guía de sustentación — Red Solidaria

## Explicación de la arquitectura en 30 segundos

“Red Solidaria es una aplicación web para administrar campañas de ayuda, donaciones, hogares beneficiarios, voluntarios y entregas. El navegador ejecuta Angular; Angular llama a una API REST de FastAPI; FastAPI valida identidad, permisos y reglas de negocio y consulta SQL Server mediante procedimientos almacenados. El frontend no accede a la base de datos directamente. La API usa una cuenta SQL de mínimo privilegio, autorizada para ejecutar procedimientos, no para lanzar consultas arbitrarias sobre las tablas”.

## Recorrido visual de una petición

```text
Usuario / navegador
  │
  ▼
Angular 22: página + formulario + servicio HTTP + interceptor Bearer
  │  HTTP /api/v1/...
  ▼
FastAPI: router → Pydantic schema → Depends (sesión/permiso/servicio)
  │
  ▼
Service: reglas de negocio y autorización por dato
  │
  ▼
Repository: método tipado por operación
  │
  ▼
Executor: EXEC dbo.usp_* con parámetros enlazados
  │
  ▼
SQL Server: transacción, restricciones, índices y bitácora
```

## Preguntas probables del docente

### 1. ¿Cuál es la función del backend en el repositorio?

El backend es la parte del servidor. Expone la API REST que consume Angular y concentra la lógica que no debe confiarse al navegador: autenticación, autorización, validaciones de negocio, acceso a datos, control de errores y auditoría. En este proyecto está desarrollado con FastAPI. Los routers reciben HTTP; los servicios aplican reglas; los repositorios invocan procedimientos almacenados; `db/executor.py` es el único ejecutor SQL.

**Ejemplo:** al registrar una campaña, el router recibe el POST, Pydantic valida la estructura, `CampanaService.crear()` procesa la operación, `CampanaRepository.guardar()` llama `usp_campana_guardar` y SQL Server registra el cambio.

### 2. ¿Qué es CORS?

CORS (*Cross-Origin Resource Sharing*) es una política del navegador que controla si una página de un origen puede leer respuestas de otro origen. Un origen combina protocolo, host y puerto. Por ejemplo, `http://localhost:4200` y `http://localhost:8000` son orígenes distintos aunque estén en el mismo equipo.

FastAPI configura `CORSMiddleware` con una lista explícita en `CORS_ORIGINS`, métodos HTTP y cabeceras permitidas. El proyecto no permite `*` y usa el token Bearer en `Authorization`, no cookies, por eso `allow_credentials=False`. En producción, si los dominios son distintos, se agrega el origen HTTPS exacto del frontend. Si Nginx publica Angular y enruta `/api` al backend bajo el mismo dominio, no hay cruce de orígenes para esa llamada.

**No confundir:** CORS no autentica ni autoriza al usuario; esa tarea corresponde al JWT y a los permisos del backend.

### 3. ¿Cómo se hacen SELECT, INSERT, UPDATE y DELETE en la base de datos?

Conceptualmente:

```sql
-- SELECT: consultar
SELECT id_campana, nombre, estado
FROM dbo.campana
ORDER BY id_campana;

-- INSERT: crear
INSERT INTO dbo.campana (nombre, id_categoria, fecha_inicio, fecha_fin, meta_recaudacion)
VALUES (N'Campaña demostrativa', 1, '2026-12-01', '2026-12-31', 1500.00);

-- UPDATE: modificar
UPDATE dbo.campana
SET nombre = N'Campaña actualizada'
WHERE id_campana = 1;

-- DELETE: eliminar físicamente (NO es el patrón normal de este sistema)
DELETE FROM dbo.campana WHERE id_campana = 1;
```

**En Red Solidaria, la aplicación no ejecuta esas sentencias directamente.** El usuario SQL de la API tiene `GRANT EXECUTE` y `DENY SELECT, INSERT, UPDATE, DELETE` sobre el esquema. El acceso se realiza por procedimientos almacenados:

- **SELECT:** `GET /api/v1/campanas` → `CampanaService.listar()` → `CampanaRepository.listar()` → `usp_campana_listar`.
- **INSERT:** `POST /api/v1/campanas` → `CampanaService.crear()` → `CampanaRepository.guardar(id_campana=None, ...)` → `usp_campana_guardar`, que ejecuta `INSERT` cuando el ID es `NULL`.
- **UPDATE:** `PUT /api/v1/campanas/{id}` → `CampanaService.actualizar()` → el mismo `usp_campana_guardar` con `id_campana` informado, que ejecuta `UPDATE`.
- **DELETE:** se evita el borrado físico para no romper el historial y las relaciones. Se usa un cambio de estado o desactivación. Por ejemplo, `usp_campana_estado` cancela/cierra una campaña y `usp_donante_estado` activa o desactiva un donante. La bitácora es de solo inserción.

Si el docente pide “hacer un DELETE”, explicar primero la diferencia entre DELETE físico y baja lógica. No ejecutar el ejemplo destructivo anterior sobre la base del proyecto: sirve para explicar SQL, no para el flujo normal de la aplicación.

### 4. ¿Qué algoritmo se usa para codificar la autenticación del login?

No se “codifica” la contraseña con un cifrado reversible. El proyecto usa **Argon2id** para generar un hash de contraseña con sal y coste de cálculo. El hash se guarda; durante el login se verifica la contraseña ingresada contra ese hash. No se puede recuperar la contraseña original desde el hash.

Después de autenticar, la API crea un **JWT firmado con HS256** (HMAC-SHA-256). El token incluye `sub` (ID de usuario), `tv` (versión de token), `iat` (emisión) y `exp` (expiración). Angular lo envía como `Authorization: Bearer ...`. HS256 firma el token para verificar integridad y autenticidad, pero **no cifra** el contenido del JWT. La lista de algoritmos aceptados es cerrada y el backend exige `exp`, `sub` y `tv`.

**Respuesta de una frase:** “Argon2id protege las contraseñas almacenadas; JWT con HS256 firma el token de sesión. Son mecanismos diferentes y ninguno guarda la contraseña en texto plano dentro del token”.

### 5. ¿Qué es un servicio en el backend y en el frontend?

- **Servicio backend:** clase de Python que concentra reglas de negocio y coordina repositorios. Ejemplo `CampanaService`: valida reglas de transición, prepara la operación y devuelve modelos de respuesta. No debería construir SQL ni conocer detalles HTTP.
- **Servicio frontend:** clase Angular reutilizable que encapsula llamadas HTTP y estado/operaciones de una funcionalidad. Ejemplo `CampanaService` dentro de `core/services/api.services.ts`: usa `HttpClient` para `GET`, `POST` y `PUT` a `/api/v1/campanas`. No debe conectarse a SQL ni reemplazar las reglas de seguridad del backend.

Tienen el mismo nombre conceptual, pero responsabilidades distintas: el del frontend comunica; el del backend aplica la lógica de negocio.

### 6. ¿Qué es la inyección de dependencias?

Es un patrón donde una clase recibe las dependencias que necesita desde fuera, en lugar de crearlas todas internamente. Reduce acoplamiento y facilita pruebas con dobles (*mocks/fakes*).

- En FastAPI, `Depends(get_db)` entrega el ejecutor de BD de la petición y `Depends(_campana_service)` construye el servicio con sus repositorios.
- En Angular, `@Injectable({ providedIn: 'root' })` registra servicios en el inyector y `inject(HttpClient)` obtiene el cliente HTTP.

En las pruebas backend, `get_db` se reemplaza por `FakeExecutor`, de modo que las pruebas de rutas y reglas no necesitan conectarse a SQL Server.

### 7. ¿Qué es un decorador?

Es una función o mecanismo de lenguaje que envuelve, registra o modifica el comportamiento de una función o clase sin tener que reescribir su cuerpo.

Ejemplos concretos del repositorio:

- `@campanas.get("", ...)` registra una función Python como endpoint GET en FastAPI.
- `@campanas.post("", ...)` registra el endpoint para crear una campaña.
- `@Injectable({ providedIn: 'root' })` indica a Angular que una clase puede ser gestionada por inyección de dependencias.
- `@Component(...)` define un componente de interfaz Angular.
- `@pytest.fixture` declara datos/recursos reutilizables para pruebas.
- `@lru_cache` memoriza resultados de una función.

No todos los decoradores hacen lo mismo; el concepto común es que añaden metadatos o comportamiento alrededor de una declaración.

## Otras preguntas que pueden aparecer

**¿Qué es una API REST?** Una interfaz HTTP basada en recursos y métodos como GET, POST, PUT y PATCH, que recibe y devuelve datos (en este proyecto, JSON).

**¿Qué hace Pydantic?** Valida y transforma datos de entrada/salida. Los esquemas están configurados para rechazar campos extra (`extra="forbid"`).

**¿Qué es una transacción?** Un conjunto de cambios que se confirma completo (`COMMIT`) o se revierte (`ROLLBACK`) si falla. Los procedimientos agrupan operaciones relacionadas y la auditoría dentro de la misma transacción.

**¿Qué es un procedimiento almacenado?** Código SQL guardado en el motor de base de datos, invocable por nombre y parámetros. En este proyecto, los repositorios llaman `dbo.usp_*` a través de un único ejecutor.

**¿Cómo justificas la 3FN?** Las entidades tienen tablas propias; los datos de categoría, sector y método de pago no se repiten en cada operación; las relaciones N:M usan tablas puente (por ejemplo `rol_permiso`). Los atributos descriptivos dependen de la clave de su entidad y no de otros atributos no clave. Complementar con el diagrama de `MODELO_DATOS.md`.

**¿Por qué no hay DELETE físico?** Donaciones, entregas, gastos y campañas forman evidencia histórica. Se prefiere anular/cambiar estado con motivo y registrar auditoría; así no se pierde trazabilidad.

**¿Cómo evitas inyección SQL?** No se concatena entrada del usuario en SQL. El ejecutor solo acepta nombres `usp_*` validados y argumentos enlazados con parámetros `?`.

## Guion corto de demostración

1. Abrir el portal público y explicar que muestra datos agregados.
2. Iniciar sesión como usuario demo y mostrar cómo cambia el menú por permisos.
3. Listar campañas (SELECT) y abrir el detalle.
4. Crear una campaña de prueba (INSERT) y editarla (UPDATE).
5. Cambiar su estado o desactivarla en vez de borrarla (baja lógica).
6. Abrir GitHub Actions y mostrar el workflow de CI verde.
7. Mostrar el host público, HTTPS y `/health`; explicar que la BD no está expuesta a Internet.

No improvisar datos personales reales durante la sustentación: usar únicamente las cuentas y fixtures sintéticos preparados para la demo.
