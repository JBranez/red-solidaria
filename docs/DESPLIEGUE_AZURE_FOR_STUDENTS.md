# Despliegue de Red Solidaria en Azure for Students

Guía reproducible para Windows PowerShell 5.1, Azure CLI, Ubuntu 22.04 x64, Docker Compose y SQL Server 2022.

## 0. Costes y límites

Azure for Students ofrece USD 100 de crédito durante 12 meses sin tarjeta bancaria para estudiantes elegibles. El crédito se consume por la máquina virtual, el disco administrado y la dirección IP, entre otros recursos. No es una VM ilimitada ni gratuita para siempre. Consulta el saldo antes de aprovisionar: <https://www.microsoftazuresponsorships.com/Balance>. Si se agota el crédito, Microsoft puede deshabilitar la suscripción y sus recursos; no actualices a Pay-As-You-Go si no puedes asumir cargos.

El `SubscriptionId` y el `TenantId` son GUID asignados a tu cuenta. No existen códigos universales. Se obtienen mediante `az account show` y el script `Connect-RedSolidaria-Azure.ps1` los guarda en `Documents\RedSolidaria-Azure-Subscription.json`.

SQL Server 2022 en contenedor Linux requiere host Intel/AMD x86-64; por ello no se selecciona una VM ARM. Se utiliza Ubuntu 22.04 x64. El tamaño preferido es `Standard_B2ms` (2 vCPU, 8 GiB RAM). El aprovisionador comprueba SKU, restricciones y cuotas antes de crear recursos y puede probar `Standard_D2as_v5` o `Standard_D2s_v5`. Como último recurso de demostración, `-Allow4GBFallback` habilita `Standard_B2s` (4 GiB), con menor margen de memoria.

Las regiones y cuotas dependen de la suscripción. La disponibilidad de SKU no garantiza capacidad física inmediata. No fuerces una suscripción de pago para evitar restricciones.

## 1. Requisitos de Windows

- Windows 10/11 x64.
- Windows PowerShell 5.1.
- Git y GitHub CLI, autenticados como propietario del repositorio.
- OpenSSH Client (`ssh`, `scp`, `ssh-keygen`, `ssh-keyscan`).
- Azure CLI v2.

Instala Azure CLI:

```powershell
winget install --exact --id Microsoft.AzureCLI
```

Cierra PowerShell y abre una sesión nueva:

```powershell
az --version
git --version
gh --version
ssh -V
```

## 2. Iniciar sesión y obtener los identificadores personales

```powershell
az login
# Si el navegador no abre: az login --use-device-code
az account list --all --query "[?state=='Enabled'].{Name:name,SubscriptionId:id,TenantId:tenantId,State:state}" -o table
az account show --query "{Name:name,SubscriptionId:id,TenantId:tenantId,State:state}" -o json
```

Selecciona una suscripción cuyo portal muestre el producto/offer `Azure for Students`. Si tienes varias, usa el script selector:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\scripts\Connect-RedSolidaria-Azure.ps1
```

Guarda esta ruta; es un registro local de identificadores, no una clave secreta:

```text
%USERPROFILE%\Documents\RedSolidaria-Azure-Subscription.json
```

No publiques ni compartas Access Keys, tokens, contraseñas ni llaves privadas.

## 3. Integrar este paquete en el repositorio que ya existe

**No ejecutar Day1. No borrar `.git`.** Descarga el paquete Azure preparado y descomprímelo temporalmente. El ZIP lleva una carpeta raíz `red-solidaria`.

```powershell
$ProjectRoot = 'C:\Users\User\Documents\RedSolidariaDeploy\red-solidaria'
$Zip = "$HOME\Downloads\RedSolidaria_Azure_Students_PowerShell_v5.zip"
$Temp = Join-Path $env:TEMP 'RedSolidariaAzureV5'

if (!(Test-Path "$ProjectRoot\.git")) { throw 'La carpeta indicada no es el repositorio existente: falta .git.' }
if (!(Test-Path $Zip)) { throw "No se encontró $Zip" }

# Verifica que las PR iniciales estén fusionadas.
gh pr view 1 --repo JBranez/red-solidaria --json state,mergedAt
gh pr view 2 --repo JBranez/red-solidaria --json state,mergedAt

# No sobrescribir cambios locales sin respaldarlos.
$dirty = @(git -C $ProjectRoot status --porcelain)
if ($dirty.Count -gt 0) { throw 'Hay cambios locales. Respáldalos o revísalos antes de integrar el paquete.' }

git -C $ProjectRoot fetch origin
git -C $ProjectRoot switch main
git -C $ProjectRoot pull --ff-only origin main

Remove-Item $Temp -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive -LiteralPath $Zip -DestinationPath $Temp -Force
$Source = Join-Path $Temp 'red-solidaria'
if (!(Test-Path (Join-Path $Source 'scripts\Provision-RedSolidaria-Azure.ps1'))) { throw 'El ZIP no contiene el aprovisionador Azure esperado.' }

robocopy $Source $ProjectRoot /E /COPY:DAT /DCOPY:DAT /R:2 /W:2 /XD .git
if ($LASTEXITCODE -ge 8) { throw "Robocopy falló con código $LASTEXITCODE" }
Set-Location $ProjectRoot
```

El comando `robocopy` mezcla los archivos y excluye `.git`; no reemplaza tu historial ni el archivo local de estado que está dentro de `.git`.

Si no existe `.git\redsolidaria-publish-state.json`, recupera el estado local solo después de confirmar que PR #1 y #2 están fusionadas:

```powershell
if (!(Test-Path '.git\redsolidaria-publish-state.json')) {
  .\scripts\Repair-RedSolidariaPublishState.ps1 -Owner JBranez -Repository red-solidaria
}
.\scripts\Publish-RedSolidaria.ps1 -Phase Status
```

No ejecutes el reparador si el archivo ya existe; no debe sobrescribir la fase de publicación.

## 4. Seleccionar suscripción y comprobar región/cuota

```powershell
.\scripts\Connect-RedSolidaria-Azure.ps1
.\scripts\Test-RedSolidaria-Azure.ps1 -Location eastus2
```

El segundo script es solo lectura: no crea recursos ni consume crédito. Prueba otras regiones permitidas si eastus2 no admite el tamaño o no tiene cuota:

```powershell
$regions = @('eastus2','eastus','centralus','southcentralus','westus2')
foreach ($region in $regions) {
  Write-Host "`n========== $region ==========" -ForegroundColor Cyan
  try { .\scripts\Test-RedSolidaria-Azure.ps1 -Location $region }
  catch { Write-Warning $_.Exception.Message }
}
```

Comprueba el saldo manualmente en Azure Sponsorships Balance y verifica el tipo de oferta en Azure Portal > Subscriptions. El script consulta SKU/quotas, pero no puede garantizar la capacidad física de un centro de datos.

## 5. Publicar Day2 en GitHub

Day1 ya existe y PR #1/#2 ya están fusionadas. El estado local de publicación debe existir. En la fecha programada (23 de noviembre de 2026, hora de Lima):

```powershell
$ProjectRoot = 'C:\Users\User\Documents\RedSolidariaDeploy\red-solidaria'
Set-Location $ProjectRoot
git fetch origin
git switch main
git pull --ff-only origin main
.\scripts\Publish-RedSolidaria.ps1 -Phase Day2
```

Se abren PR para Angular, Docker/Compose y operaciones Azure. Revisa el contenido y fusiona una por una:

```powershell
.\scripts\Merge-RedSolidariaOpenPRs.ps1 -Owner JBranez -Repository red-solidaria -Phase Day2
```

No avances hasta que las tres estén fusionadas y `gh pr list --repo JBranez/red-solidaria --state open` no muestre PR de esa fase.

## 6. Publicar Day3 y validar CI

En la fecha programada (24 de noviembre de 2026, antes de las 18:00 hora de Lima):

```powershell
Set-Location 'C:\Users\User\Documents\RedSolidariaDeploy\red-solidaria'
git fetch origin
git switch main
git pull --ff-only origin main
.\scripts\Publish-RedSolidaria.ps1 -Phase Day3
.\scripts\Merge-RedSolidariaOpenPRs.ps1 -Owner JBranez -Repository red-solidaria -Phase Day3
```

Espera el workflow CI. Debe existir una ejecución `completed/success` para el SHA exacto de `origin/main`:

```powershell
git fetch origin
$mainSha = (git rev-parse origin/main).Trim()
$runs = gh run list --repo JBranez/red-solidaria --workflow ci.yml --branch main --limit 20 --json databaseId,headSha,status,conclusion | ConvertFrom-Json
$run = $runs | Where-Object { $_.headSha -eq $mainSha } | Select-Object -First 1
if (!$run) { throw 'No existe CI para el SHA actual de main.' }
gh run watch $run.databaseId --repo JBranez/red-solidaria
```

No despliegues si el workflow falla o no se ha ejecutado.

## 7. Crear la VM Azure

El tamaño preferido es 2 vCPU/8 GiB (`Standard_B2ms`). El aprovisionador utiliza Ubuntu 22.04 x64, un disco Standard SSD administrado de 64 GB, una IP pública estática con DNS y un NSG. El puerto 22 se restringe a la IPv4 actual del usuario; 80 y 443 quedan abiertos para HTTP/HTTPS; 1433 no se abre.

Primero lee el precio en <https://azure.microsoft.com/pricing/calculator/> y confirma el saldo en <https://www.microsoftazuresponsorships.com/Balance>. Después:

```powershell
Set-Location 'C:\Users\User\Documents\RedSolidariaDeploy\red-solidaria'
.\scripts\Provision-RedSolidaria-Azure.ps1 -Location eastus2 -VmSize Standard_B2ms -ConfigPath "$HOME\Documents\RedSolidaria-config.ps1"
```

Si eastus2 no permite el tamaño, repite la prueba con una región aprobada. **No ejecutes provisión repetida si el grupo/VM ya existe**; el aprovisionador reutiliza el grupo/recursos conocidos y revalida la VM. El script muestra recursos y requiere escribir `CREAR`.

Como último recurso de demostración, con menos margen de memoria:

```powershell
.\scripts\Provision-RedSolidaria-Azure.ps1 -Location eastus2 -Allow4GBFallback
```

No uses `-NoConfirm`.

El script guarda todos los valores propios de tu cuenta y VM en:

```text
%USERPROFILE%\Documents\RedSolidaria-config.ps1
%USERPROFILE%\Documents\RedSolidaria-Azure-VM.json
%USERPROFILE%\.ssh\redsolidaria_azure_ed25519
```

El Subscription ID/Tenant ID son identificadores; la llave privada SSH sí es secreta.

## 8. Verificar host y desplegar la aplicación

Carga la configuración generada:

```powershell
. "$HOME\Documents\RedSolidaria-config.ps1"
Set-Location $ProjectRoot
```

Antes de confiar en SSH, consulta en el lado de Azure la huella de la clave del host:

```powershell
az vm run-command invoke -g $AzureResourceGroup -n $AzureVmName --command-id RunShellScript --scripts 'sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub' --query "value[0].message" -o tsv
```

Comprueba y ajusta el acceso SSH si cambió la IP pública del cliente:

```powershell
.\scripts\Update-RedSolidaria-AzureSSH.ps1
```

Luego despliega. El script vuelve a validar PR, visibilidad pública del repositorio y CI del SHA actual de `main`:

```powershell
.\scripts\Deploy-RedSolidaria.ps1 `
  -Owner $Owner `
  -Repository $Repository `
  -ServerIp $ServerIp `
  -SshUser $SshUser `
  -SshPort $SshPort `
  -InitialKeyPath $InitialKeyPath `
  -Domain $Domain `
  -MssqlMemoryLimitMB $MssqlMemoryLimitMB `
  -MssqlContainerMemoryLimit $MssqlContainerMemoryLimit
```

El primer despliegue se hace desde PowerShell/SSH, no desde runners hospedados por GitHub. El NSG restringe SSH a tu IP, por lo que no se debe activar CD remoto desde GitHub Actions sin diseñar una conectividad segura para esos runners. CI es suficiente para la rúbrica de integración continua.

## 9. Verificar la URL pública

```powershell
$BaseUrl = "https://$Domain"
(Invoke-WebRequest $BaseUrl -UseBasicParsing -TimeoutSec 30).StatusCode
Invoke-RestMethod "$BaseUrl/health"
Invoke-RestMethod "$BaseUrl/health/db"
```

El script de despliegue también ejecuta un login real con el administrador inicial y verifica que la API devuelva un JWT. Las contraseñas se generan y quedan en `%USERPROFILE%\.redsolidaria\JBranez-red-solidaria.env`; no las subas a GitHub.

## 10. Operación y ahorro de crédito

Iniciar VM:

```powershell
.\scripts\Start-RedSolidaria-Azure.ps1
```

Desasignar VM cuando no se use (detiene el cómputo; disco e IP todavía pueden consumir crédito):

```powershell
.\scripts\Stop-RedSolidaria-Azure.ps1
```

Si cambia la IP desde la que te conectas por SSH:

```powershell
.\scripts\Update-RedSolidaria-AzureSSH.ps1
```

Eliminar toda la infraestructura y la base de datos (operación destructiva; hacer backup antes):

```powershell
.\scripts\Remove-RedSolidaria-Azure.ps1
```

El script exige escribir `ELIMINAR rg-redsolidaria`.

## Arquitectura de red

- Internet → Caddy (80/443) → Angular/Nginx o FastAPI.
- FastAPI → SQL Server por red Docker `backend`.
- SQL Server TCP/1433 está publicado solo en `127.0.0.1` para túnel SSH local, no en IP pública.
- GitHub Actions CI valida backend/frontend en cada PR y push a `main`.

## Fuentes oficiales

- Azure for Students: <https://azure.microsoft.com/free/students/> y <https://learn.microsoft.com/azure/education-hub/about-azure-for-students>
- Azure CLI: <https://learn.microsoft.com/cli/azure/account> y <https://learn.microsoft.com/cli/azure/vm>
- Cuotas de VM: <https://learn.microsoft.com/azure/virtual-machines/quotas>
- SQL Server en Linux/containers x64: <https://learn.microsoft.com/sql/linux/sql-server-linux-release-notes-2022>
