# Créditos y licencias

## Diseño de la interfaz (plantillas de autoría humana)
| Origen | Autoría | Licencia | Uso |
|---|---|---|---|
| **Bootstrap 5.3.8** y sus ejemplos oficiales *Dashboard* y *Sign-in* | The Bootstrap Authors | MIT | Estructura del shell (barra superior + navegación lateral con *offcanvas*) y de la pantalla de acceso |
| **Bootswatch «Zephyr»** | Thomas Park | MIT | Piel visual (CSS de Bootstrap 5.3.8 precompilado) |
| **Bootstrap Icons** | The Bootstrap Authors | MIT | Iconografía |
| **Inter** (`@fontsource-variable/inter`) | Rasmus Andersson | SIL OFL 1.1 | Tipografía, autoalojada |

Se eligieron por su larga trayectoria de autoría humana verificable y por cumplir el stack solicitado («solo CSS de Bootstrap»). La personalización (paleta de tres colores tomada del diagrama del proyecto, componentes, gráficos, pantallas) es propia. *No se pudo navegar por catálogos de plantillas en línea desde este entorno: la selección se limitó a lo obtenible por npm y GitHub.*

## Software
Angular (MIT) · FastAPI, Pydantic, Starlette, Uvicorn (MIT/BSD) · PyJWT (MIT) · pwdlib + argon2-cffi (MIT) · pyodbc (MIT) · pytest, httpx (MIT/BSD) · sqlfluff (MIT) · Vitest (MIT). Versiones exactas: `backend/constraints.txt`, `frontend/package-lock.json`.

## Datos
Los 7 CSV y el diagrama lógico provienen del proyecto original entregado (`database/legacy/`, `database/datos/`). Los datos de demostración son sintéticos.
