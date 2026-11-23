# Proximos pasos

1. Rotar la contrasena inicial `admin` tras la primera sesion y guardar el acceso en un gestor de contrasenas.
2. Restringir SSH si cambia la IP publica del administrador (actualizar regla NSG a la IP actual `/32`).
3. Revisar periodicamente `docker compose ps`, logs, espacio de disco, renovacion Caddy y backup del volumen SQL.
4. Programar backup SQL fuera del volumen de la VM y probar restauracion antes de guardar datos reales.
5. Para CD automatico, definir `DEPLOY_ENABLED=true` y secretos del workflow solo despues de resolver acceso SSH desde GitHub Actions sin ampliar SSH publico. El despliegue manual seguro esta documentado.
