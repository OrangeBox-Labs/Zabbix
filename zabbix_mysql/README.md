# Script de configuración de usuario MySQL para Zabbix

## Descripción

Este script automatiza la creación del usuario `zbx_monitor` en MySQL para habilitar el monitoreo desde Zabbix.

La idea es simplificar la configuración inicial del monitoreo, evitando realizar manualmente la creación del usuario, generación de contraseñas y asignación de permisos necesarios.

El script realiza las siguientes tareas:

- Detecta automáticamente la versión de MySQL o MariaDB instalada.
- Adapta la creación del usuario según la versión detectada.
- Genera una contraseña segura de 20 caracteres alfanuméricos.
- Crea o actualiza el usuario `zbx_monitor`.
- Asigna los permisos necesarios para el monitoreo.
- Verifica la conexión del usuario creado.
- Guarda las credenciales generadas en un archivo protegido.

**Importante:** Este script solamente configura el usuario dentro de MySQL. No instala Zabbix Agent ni modifica la configuración del agente.

---

## Requisitos previos

Antes de ejecutar el script se requiere:

- Acceso root al servidor MySQL.
- MySQL o MariaDB instalado y funcionando.
- Permisos para crear usuarios y asignar privilegios.

---

# Instalación y uso

## 1. Descargar el script

```bash
git clone https://github.com/OrangeBox-Labs/Zabbix
cd Zabbix/zabbix_mysql/
```

## 2. Dar permisos de ejecución

```bash
chmod +x setup_mysql_zabbix_user.sh
```

## 3. Ejecutar el script

```bash
./setup_mysql_zabbix_user.sh
```

---

# Ejemplo de ejecución

```
================================================================================
Script de Configuración de Usuario MySQL para Zabbix
================================================================================

Versión de MySQL detectada: 5.7.33
Tipo de MySQL: modern

Probando conexión a MySQL sin contraseña...

No se pudo conectar sin contraseña.

Solicitando contraseña root de MySQL:

Conexión exitosa con contraseña.

El usuario zbx_monitor ya existe.

¿Deseas actualizar contraseña y permisos? (s/N): s

Contraseña generada: KxM9pLqR3nBvW4tZ

Creando usuario zbx_monitor...

Usuario creado correctamente.

Asignando permisos...

Permisos asignados correctamente.

Probando conexión del usuario zbx_monitor...

Conexión exitosa.

================================================================================
CONFIGURACIÓN COMPLETADA
================================================================================

Usuario:
  zbx_monitor@%

Contraseña:
  KxM9pLqR3nBvW4tZ

Archivo de credenciales:
  /root/.zbx_mysql_credentials

Log:
  /var/log/mysql_zabbix_setup.log
```

---

# Estructura del script

## Variables principales

| Variable | Descripción | Valor por defecto |
|---|---|---|
| MYSQL_USER | Usuario creado para Zabbix | zbx_monitor |
| MYSQL_HOST | Host permitido para conexión | % |
| LOG_FILE | Archivo de log | /var/log/mysql_zabbix_setup.log |

---

# Permisos asignados

El usuario creado utiliza permisos mínimos necesarios para el monitoreo mediante Zabbix.

| Permiso | Descripción |
|---|---|
| REPLICATION CLIENT | Permite consultar información de replicación. |
| PROCESS | Permite consultar procesos y estados internos de MySQL. |
| SHOW DATABASES | Permite descubrir bases de datos disponibles. |
| SHOW VIEW | Permite obtener información de vistas. |

---

# Versiones soportadas

El script detecta automáticamente la versión instalada y utiliza la sintaxis correspondiente.

| Tipo | Versiones |
|---|---|
| Modern | MySQL 5.7+, MySQL 8.x, MariaDB 10.2+ |
| Legacy | MySQL 5.1, 5.5, 5.6, MariaDB 5.5, 10.0, 10.1 |

---

# Configuración en Zabbix

## Usando Zabbix Agent 2

El método recomendado es utilizar el template:

```
MySQL by Zabbix agent 2
```

---

## 1. Verificar instalación del Agent 2

Validar que el agente esté instalado:

```bash
rpm -qa | grep zabbix-agent2
```

o:

```bash
which zabbix_agent2
```

---

## 2. Agregar template en Zabbix

Desde la interfaz web:

1. Ir a:

```
Recopilación de datos → Equipos
```

2. Seleccionar el host que ejecuta MySQL.

3. Ir a:

```
Plantillas → Agregar
```

4. Buscar:

```
MySQL by Zabbix agent 2
```

5. Guardar los cambios.

---

## 3. Configurar macros

En el host agregar las siguientes macros:

| Macro | Valor |
|---|---|
| {$MYSQL.USER} | zbx_monitor |
| {$MYSQL.PASSWORD} | contraseña_generada |
| {$MYSQL.DSN} | tcp://localhost:3306 |

---

# Verificación del monitoreo

Después de asociar el template, esperar algunos minutos y validar los datos recibidos.

Items principales:

```
mysql.status[Uptime]
mysql.status[Com_select]
mysql.status[Com_insert]
mysql.status[Com_update]
mysql.status[Com_delete]
mysql.version
```

---

# Solución de problemas

## Error: Access denied for user 'zbx_monitor'

Verificar que el usuario existe:

```sql
SELECT User, Host FROM mysql.user WHERE User='zbx_monitor';
```

Ver permisos:

```sql
SHOW GRANTS FOR 'zbx_monitor'@'%';
```

Si es necesario recrear el usuario:

```sql
DROP USER 'zbx_monitor'@'%';
```

Luego ejecutar nuevamente el script.

---

## Error: Plugin is not configured

Verificar la configuración del agente:

```bash
cat /etc/zabbix/zabbix_agent2.conf | grep -i mysql
```

---

## Probar conexión manualmente

```bash
mysql -u zbx_monitor -p'contraseña' -e "SELECT VERSION();"
```

Ver permisos:

```bash
mysql -u zbx_monitor -p'contraseña' -e "SHOW GRANTS;"
```

---

# Comandos útiles

## Ver log del script

```bash
cat /var/log/mysql_zabbix_setup.log
```

## Ver credenciales generadas

```bash
cat /root/.zbx_mysql_credentials
```

## Estado del agente Zabbix

```bash
systemctl status zabbix-agent2
```

## Logs del agente

```bash
tail -f /var/log/zabbix/zabbix_agent2.log
```

---

# Notas importantes

1. El script no modifica la configuración del agente Zabbix.

2. La contraseña generada utiliza solamente caracteres alfanuméricos para evitar problemas con caracteres especiales en Bash y MySQL.

3. Los permisos asignados corresponden al mínimo necesario para realizar monitoreo.

4. Las credenciales se almacenan en:

```bash
/root/.zbx_mysql_credentials
```

con permisos restrictivos.

5. El script soporta distintas versiones de MySQL y MariaDB adaptando la sintaxis automáticamente.

---

# Autor

Felipe Román

Email:

froman@orangebox.cl

Web:

https://www.orangebox.cl

---

# Licencia

MIT
