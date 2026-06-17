# Configuración de Apache mod_status para Zabbix

## Descripción

Este script automatiza la configuración de `mod_status` en Apache HTTP Server para habilitar el monitoreo mediante Zabbix.

`mod_status` permite obtener información interna del servidor Apache, como cantidad de conexiones activas, procesos ocupados, solicitudes atendidas y estado general del servicio.

El script realiza las siguientes tareas:

- Verifica que sea ejecutado con privilegios de root.
- Comprueba que Apache esté instalado.
- Configura el endpoint `/server-status`.
- Habilita `ExtendedStatus` para obtener métricas detalladas.
- Verifica que el módulo `mod_status` esté cargado.
- Valida la sintaxis de configuración de Apache.
- Recarga el servicio HTTPD.
- Realiza una prueba automática del endpoint.

El objetivo es dejar Apache preparado para ser monitoreado desde Zabbix sin tener que realizar la configuración manualmente.

---

# Requisitos previos

Antes de ejecutar el script se requiere:

- Sistema operativo basado en RHEL:
  - Red Hat Enterprise Linux
  - Rocky Linux
  - AlmaLinux
  - CentOS Stream

- Apache HTTP Server instalado.

- Acceso root al servidor.

- Servicio Apache funcionando.

---

# Instalación y uso

## 1. Descargar el script

```bash
git clone https://github.com/OrangeBox-Labs/Zabbix
cd Zabbix/zabbix_apache
```

---

## 2. Dar permisos de ejecución

```bash
chmod +x configure_apache_status.sh
```

---

## 3. Ejecutar el script

```bash
./configure_apache_status.sh
```

---

# Ejemplo de ejecución

```
Configurando mod_status...

Archivo creado: /etc/httpd/conf.d/status.conf

mod_status funcionando correctamente

Configuración completada

Autor: Felipe Román <froman@orangebox.cl>
```

---

# Configuración realizada

El script crea el archivo:

```
/etc/httpd/conf.d/status.conf
```

Con la siguiente configuración:

```apache
<Location /server-status>
    SetHandler server-status
    Require local
    Require ip 127.0.0.1
    Require ip ::1
</Location>

ExtendedStatus On
```

---

# Seguridad

Por defecto, el endpoint `/server-status` queda restringido únicamente al servidor local.

Esto evita exponer información interna de Apache hacia Internet.

La configuración permite acceso desde:

```
127.0.0.1
::1
```

Si Zabbix consulta el estado desde otro servidor, se debe agregar la IP del servidor Zabbix:

```apache
Require ip 192.168.1.10
```

Después aplicar:

```bash
systemctl reload httpd
```

---

# Verificación manual

Para comprobar que Apache entrega correctamente las métricas:

```bash
curl http://127.0.0.1/server-status?auto
```

Ejemplo de salida:

```
Total Accesses: 12345
Total kBytes: 456789
BusyWorkers: 2
IdleWorkers: 8
Scoreboard: _W__...
```

---

# Integración con Zabbix

Una vez habilitado `mod_status`, se puede utilizar el template oficial de Apache disponible en Zabbix.

Template:

```
Apache by agent Zabbix
```

El monitoreo permite obtener métricas como:

- Cantidad de conexiones activas.
- Requests procesadas.
- Workers ocupados.
- Workers disponibles.
- Estado general del servicio Apache.

---

# Solución de problemas

## Consideración importante: Apache utilizando HTTPS

La plantilla de Apache en Zabbix consulta la página de estado mediante HTTP/HTTPS utilizando las macros:

| Macro | Valor por defecto | Descripción |
|---|---|---|
| `{$APACHE.STATUS.PORT}` | 80 | Puerto donde está publicada la página de estado de Apache. |
| `{$APACHE.STATUS.SCHEME}` | http | Método utilizado para realizar la consulta (`http` o `https`). |

Si Apache solamente está escuchando en el puerto `443` y utiliza HTTPS, la configuración por defecto de la plantilla no funcionará.

Ejemplo:

```
https://servidor/server-status?auto
```

---

Si Apache está configurado solamente con HTTP, por ejemplo:

```
http://servidor:80/server-status?auto
```

la plantilla fallará porque intentará conectarse utilizando HTTPS.

En este caso se deben modificar las macros del host en Zabbix a los siguientes valores:

| Macro | Valor |
|---|---|
| `{$APACHE.STATUS.PORT}` | `443` |
| `{$APACHE.STATUS.SCHEME}` | `https` |


Después de cambiar las macros, validar que Zabbix pueda acceder correctamente:

```bash
curl https://127.0.0.1/server-status?auto
```

---

## mod_status no aparece cargado

Verificar módulos cargados:

```bash
httpd -M | grep status
```

La salida esperada:

```
status_module (shared)
```

---

## Error de configuración Apache

Validar manualmente:

```bash
httpd -t
```

Salida esperada:

```
Syntax OK
```

---

## El endpoint no responde

Probar:

```bash
curl https://127.0.0.1/server-status?auto
```

Revisar logs:

```bash
tail -f /var/log/httpd/error_log
```

---

# Archivos modificados

El script modifica o crea:

| Archivo | Descripción |
|---|---|
| `/etc/httpd/conf.d/status.conf` | Configuración de mod_status |
| `/etc/httpd/conf.modules.d/00-status.conf` | Carga del módulo mod_status |

---

# Notas importantes

1. El script no instala Apache ni componentes adicionales.

2. La configuración queda restringida por defecto a conexiones locales.

3. Antes de exponer `/server-status` hacia otra red, validar las reglas de acceso.

4. El script puede ejecutarse múltiples veces; valida si la configuración ya existe antes de crearla nuevamente.

5. Está pensado para servidores RHEL donde Apache utiliza el servicio `httpd`.

---

# Autor

Felipe Román

Email:

froman@orangebox.cl

Web:

https://www.orangebox.cl

---

# Licencia

GPL-3.0
