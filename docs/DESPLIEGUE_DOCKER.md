# Despliegue de Red Solidaria con Docker, GitHub y PowerShell

## Arquitectura publicada

```text
Internet
   |
   | HTTPS :443 / HTTP :80
   v
Caddy (certificado TLS automático)
   |------------------------------|
   v                              v
Angular 22 + Nginx             FastAPI + Uvicorn
                                  |
                                  | ODBC Driver 18 / TLS verificado
                                  v
                          SQL Server 2022 Express
                          (volumen persistente, red privada)
```

Solo Caddy publica los puertos 80 y 443. SQL Server se vincula a `127.0.0.1:1433` del VPS para administración mediante túnel SSH; no se expone a Internet. Además, SQL Server y el inicializador están en una red Docker privada separada: únicamente FastAPI se conecta tanto a esa red como a la red de borde. La API usa `redsolidaria_app`, que solo tiene permiso `EXECUTE` sobre procedimientos almacenados.

## Requisitos del VPS

- Ubuntu 24.04 LTS, arquitectura x86_64/amd64.
- Recomendado: 2 vCPU, 4 GB RAM y 40 GB SSD. Microsoft indica 2 GB de RAM y 2 GB de disco como mínimos para SQL Server Linux en contenedor.
- Dirección IPv4 pública y puertos TCP 22, 80 y 443 habilitados.
- Repositorio GitHub público para que el VPS pueda hacer `git pull` sin un token almacenado allí.
- Un hostname que resuelva a la IP del VPS. El script usa por defecto `red-solidaria.IP.nip.io`; se puede pasar un dominio propio mediante `-Domain`.

## 1. Preparar Windows y publicar el código

En Windows 11, instala Git y GitHub CLI si todavía no están disponibles. Docker no se instala en el PC: el bootstrap lo instalará en el VPS.

```powershell
winget install --id Git.Git -e
winget install --id GitHub.cli -e

# En PowerShell como administrador, solo si OpenSSH Client no está instalado:
$sshCapability = Get-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
if ($sshCapability.State -ne 'Installed') {
    Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
}
```

Abre una nueva ventana de PowerShell, entra a la carpeta del proyecto y publica:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
git config --global user.name "Tu nombre real"
git config --global user.email "correo-verificado@example.com"
gh auth login
gh auth refresh -h github.com -s repo,workflow
.\scripts\Publish-RedSolidaria.ps1 -Phase Day1 -Owner TU_USUARIO -Repository red-solidaria -Visibility public

# Fusiona las PR de Day1 (el script pide confirmación por cada PR)
.\scripts\Merge-RedSolidariaPhase.ps1 -Owner TU_USUARIO -Repository red-solidaria

# Lunes 23: después de fusionar las dos PR del domingo
.\scripts\Publish-RedSolidaria.ps1 -Phase Day2
.\scripts\Merge-RedSolidariaPhase.ps1 -Owner TU_USUARIO -Repository red-solidaria

# Martes 24 antes de las 18:00: después de fusionar las tres PR del lunes
.\scripts\Publish-RedSolidaria.ps1 -Phase Day3
.\scripts\Merge-RedSolidariaPhase.ps1 -Owner TU_USUARIO -Repository red-solidaria
```

El ayudante `Merge-RedSolidariaPhase.ps1` muestra cada Pull Request y solo la fusiona tras tu confirmación explícita; usa `--merge` para conservar los commits funcionales en el historial de `main`. El publicador se ejecuta por fases `Day1`, `Day2` y `Day3` en fechas reales diferentes. Para observar la validación automatizada en GitHub, usa `gh run list --repo TU_USUARIO/red-solidaria --limit 10` y luego `gh run watch ID --repo TU_USUARIO/red-solidaria`. Crea varias ramas funcionales, varios commits descriptivos por rama y Pull Requests reales. Los commits conservan la fecha y autor reales; no retrodata el historial ni fabrica actividad. Day2 y Day3 exigen que las PR de la fase previa estén fusionadas, y Day3 valida el límite del martes 24-11-2026 a las 18:00 en hora de Lima.
Plan previsto para esta entrega: domingo 22 de noviembre (base + base de datos + backend; 2 PR), lunes 23 (frontend + Docker + aprovisionamiento VPS; 3 PR) y martes 24 antes de las 18:00 (CI/CD + documentación y capturas; 2 PR). En total: 7 PR y 19 commits entre baseline y cambios funcionales (18 commits funcionales), más los commits de merge; se conservan los commits individuales en `main`. Fusiona y comprueba las PR de cada día antes de iniciar la fase siguiente.

## 2. Crear el VPS

Crea un VPS Ubuntu 24.04 x86_64 con 4 GB RAM. Usa un usuario normal con `sudo` (por ejemplo `ubuntu`), no uses `root` para trabajar habitualmente. Asegúrate de que el proveedor permita TCP 22, 80 y 443.

El hostname por defecto será `red-solidaria.IP.nip.io`; por ejemplo, `red-solidaria.198.51.100.20.nip.io` (IP reservada para documentación, no la uses). También puedes usar un dominio propio apuntando a la IPv4 pública.

## 3. Desplegar desde Windows PowerShell

Tras ejecutar las fases Day1, Day2 y Day3, revisar CI y fusionar todas las PR en `main`:

```powershell
.\scripts\Deploy-RedSolidaria.ps1 `
  -Owner TU_USUARIO `
  -Repository red-solidaria `
  -ServerIp IP_PUBLICA_REAL_DEL_VPS `
  -SshUser ubuntu `
  -ConfigureGitHubActions
```

Si tu clave SSH inicial del proveedor no está en el agente ni en `~/.ssh`, añade `-InitialKeyPath "C:\ruta\a\tu-clave.pem"`. Si ya tienes dominio propio, añade `-Domain app.tudominio.com`; sin ese parámetro se usará el hostname nip.io automático.

El script instala Docker Engine y Compose desde el repositorio oficial, configura UFW, añade una clave SSH de despliegue, genera secretos criptográficamente aleatorios, crea una CA y certificado interno para TLS entre FastAPI y SQL Server, transfiere `.env` sin incorporarlo a Git y ejecuta Compose.

El script muestra las huellas del servidor y exige que las compares con la consola del proveedor antes de enviar credenciales.

## 4. Validaciones automáticas

El despliegue falla si no se cumplen los siguientes controles:

- Compose valida su configuración.
- El contenedor SQL Server inicia.
- `db-init` espera al motor, ejecuta los scripts SQL y carga fixtures/usuario administrador.
- El backend y frontend pasan sus healthchecks.
- Caddy obtiene el certificado HTTPS para el hostname público.
- `GET /health` confirma que FastAPI responde.
- `GET /health/db` ejecuta un procedimiento almacenado con el usuario de aplicación.
- `POST /api/v1/auth/login` devuelve HTTP 200 y un JWT para el administrador creado.

## 5. Despliegue continuo (CD)

Con `-ConfigureGitHubActions`, el script crea los secretos `VPS_HOST`, `VPS_USER`, `VPS_PORT`, `VPS_KNOWN_HOSTS` y `VPS_SSH_PRIVATE_KEY`, y habilita la variable `DEPLOY_ENABLED` solo después de que la primera publicación manual quedó validada. El primer workflow CD no intenta conectarse antes de configurar los secretos. Después, al fusionar código en `main`, CD se ejecuta solo si CI termina correctamente. El script inicial de despliegue también exige CI exitoso para el SHA exacto de `main`.

## 6. Comandos de administración (PowerShell)

```powershell
# Estado de servicios
ssh ubuntu@IP "cd /opt/red-solidaria && docker compose ps"

# Últimos registros
ssh ubuntu@IP "cd /opt/red-solidaria && docker compose logs --tail=100 api db-init caddy sqlserver"

# Reiniciar API y frontend
ssh ubuntu@IP "cd /opt/red-solidaria && docker compose restart api frontend caddy"

# Actualizar desde GitHub (CI/CD recomendado)
ssh ubuntu@IP "cd /opt/red-solidaria && bash deploy/deploy-on-server.sh"

# Abrir un túnel local de administración SQL Server (SQL no se publica a Internet)
ssh -L 1433:127.0.0.1:1433 ubuntu@IP
```

Con el túnel abierto, conecta SSMS o Azure Data Studio a `localhost,1433` como `sa` usando la contraseña de despliegue local guardada. Para esa conexión administrativa, marca `Trust server certificate` porque la CA de SQL es privada y no está instalada automáticamente en Windows. No publiques esa contraseña.

## 7. Credenciales y SQL Server

`MSSQL_PID=Express` selecciona SQL Server Express, que Microsoft ofrece con una licencia gratuita que permite producción. Para SQL Server 2022 Express, el límite de una base de datos relacional es 10 GB y el motor utiliza como máximo 4 núcleos y 1.410 MB de buffer pool; es suficiente para esta demostración escolar, pero no para cargas grandes. La base persiste en el volumen Docker `sqlserver_data`; no ejecutes `docker compose down -v` salvo que quieras eliminar los datos.

El inicializador (`db-init`) se ejecuta con modo de carga demostrativa para crear registros sintéticos y cuentas de los roles; la API se ejecuta separadamente con `APP_ENV=production`. La API permanece en modo `production` (documentación OpenAPI deshabilitada). El usuario `admin` y las cuentas demo usan las contraseñas aleatorias que el script muestra al terminar el primer despliegue (se conservan en el archivo local protegido para futuras actualizaciones): `admin`, `coordinacion`, `finanzas`, `trabajo.social`, `auditoria`, `voluntario` y `donante. El usuario `sa` se usa solamente por el servicio one-shot de inicialización y no se entrega a FastAPI. La edición Developer es gratuita para desarrollo, pruebas y demostraciones escolares no productivas; no debe emplearse para ofrecer un servicio comercial o de producción.
