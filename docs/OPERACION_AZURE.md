# Operación Azure — Red Solidaria

| Acción | Comando PowerShell |
|---|---|
| Ver suscripción | `az account show -o table` |
| Ver VM | `az vm show -g rg-redsolidaria -n vm-redsolidaria -d -o table` |
| Iniciar | `scripts/Start-RedSolidaria-Azure.ps1` |
| Desasignar | `scripts/Stop-RedSolidaria-Azure.ps1` |
| Actualizar IP SSH tras cambiar de red | `scripts/Update-RedSolidaria-AzureSSH.ps1` |
| Ver IP/FQDN | `az vm list-ip-addresses -g rg-redsolidaria -n vm-redsolidaria -o table` |
| Ver estado | `az vm get-instance-view -g rg-redsolidaria -n vm-redsolidaria -o table` |
| Eliminar todos los recursos | `scripts/Remove-RedSolidaria-Azure.ps1` |

No se publica SQL Server TCP/1433. Para acceder a SQL Server usa un túnel SSH:

```powershell
ssh -i $InitialKeyPath -L 1433:127.0.0.1:1433 "$SshUser@$ServerIp"
```

Conecta SSMS a `localhost,1433`. Para no consumir crédito cuando no uses la demo, ejecuta `Stop-RedSolidaria-Azure.ps1`, que utiliza `az vm deallocate`. El disco y la IP estática siguen asociados y pueden generar consumo.
