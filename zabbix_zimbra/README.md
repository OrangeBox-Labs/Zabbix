# Script de Monitoreo Zabbix para Zimbra

Autor: Felipe Roman
Web: https://www.orangebox.cl
Email: froman@orangebox.cl

## Descripcion

Este script instala y configura automaticamente el monitoreo completo de servidores Zimbra para Zabbix.
Incluye discovery de servicios, estado de procesos, cola de correos, estadisticas diarias y metricas adicionales.

Incluye template para Zabbix en este mismo directorio.

## Requisitos previos

- Servidor Zimbra instalado y funcionando
- Zabbix agent instalado en el servidor Zimbra
- Acceso root al servidor Zimbra

## Instalacion del agente en el servidor Zimbra

Paso 1: Descargar el script en el servidor Zimbra

Paso 2: Dar permisos de ejecucion

```
chmod +x install_zabbix_zimbra_agent.sh
```

Paso 3: Ejecutar como root

```
./install_zabbix_zimbra_agent.sh
```

## Importar la plantilla en Zabbix

El archivo zabbix_zimbra_template.yaml contiene la plantilla lista para importar.

Paso 1: En la interfaz web de Zabbix, vaya a Equipos -> Plantillas

Paso 2: Haga clic en el boton Importar (esquina superior derecha)

Paso 3: Seleccione el archivo zabbix_zimbra_template.yaml

Paso 4: En opciones de importacion, marque:
- Actualizar plantillas existentes
- Crear nuevos elementos faltantes

Paso 5: Haga clic en Importar

## Crear la plantilla manualmente (si prefiere no importar)

Si no quiere usar el archivo YAML, puede crear la plantilla manualmente siguiendo estos pasos:

Paso 1: Crear el grupo de plantillas
Ir a Equipos -> Grupos de plantillas -> Crear grupo de plantillas
Nombre: Templates/OrangeBox
Guardar

Paso 2: Crear la plantilla
Ir a Equipos -> Plantillas -> Crear plantilla
Nombre: Template App Zimbra
Nombre visible: Zimbra Mail Server by OrangeBox
Grupo: Templates/OrangeBox
Guardar

Paso 3: Crear las macros
Ir a la plantilla -> Macros -> Agregar
Macro {$ZIMBRA.LLD.FILTER} valor .*
Macro {$ZIMBRA.QUEUE.WARNING} valor 50
Macro {$ZIMBRA.QUEUE.CRITICAL} valor 100

Paso 4: Crear los items fijos
Ir a la plantilla -> Metricas -> Crear metrica

Item 1: Zimbra Cola de correos
Clave: zimbra.queue
Tipo: Agente Zabbix
Intervalo: 10m
Timeout: 15s

Item 2: Zimbra Correos enviados
Clave: zimbra.mailstats.sent
Intervalo: 1h
Timeout: 15s

Item 3: Zimbra Correos recibidos
Clave: zimbra.mailstats.received
Intervalo: 1h
Timeout: 15s

Item 4: Zimbra Spam detectado
Clave: zimbra.mailstats.spam
Intervalo: 1h
Timeout: 15s

Item 5: Zimbra Virus detectados
Clave: zimbra.mailstats.virus
Intervalo: 1h
Timeout: 15s

Item 6: Zimbra Version
Clave: zimbra.version
Tipo: Texto
Intervalo: 1d
Timeout: 15s

Paso 5: Crear los triggers de cola
Ir a la plantilla -> Iniciadores -> Crear iniciador

Trigger 1: Cola de correos Zimbra alta
Expresion: last(/Zimbra Mail Server by OrangeBox/zimbra.queue)>{$ZIMBRA.QUEUE.WARNING}
Gravedad: Advertencia

Trigger 2: Cola de correos Zimbra critica
Expresion: last(/Zimbra Mail Server by OrangeBox/zimbra.queue)>{$ZIMBRA.QUEUE.CRITICAL}
Gravedad: Critica

Paso 6: Crear la regla de descubrimiento
Ir a la plantilla -> Descubrimiento -> Crear regla de descubrimiento
Nombre: Descubrimiento de servicios Zimbra
Clave: zimbra.discovery
Intervalo: 12h

Paso 7: Agregar filtro a la regla
Macro: {#ZIMBRA_SERVICE}
Operador: Coincide con
Valor: {$ZIMBRA.LLD.FILTER}

Paso 8: Crear prototipo de metrica
Ir a Prototipos de metrica -> Crear prototipo de metrica
Nombre: Servicio Zimbra {#ZIMBRA_SERVICE} estado
Clave: zimbra.service.status[{#ZIMBRA_SERVICE}]
Tipo: Texto
Intervalo: 3m
Timeout: 15s
Preprocesamiento:
- Reemplazar 1 por Running
- Reemplazar 0 por Stopped
- Reemplazar -1 por Unknown

Paso 9: Crear prototipos de iniciador
Ir a Prototipos de iniciador -> Crear prototipo de iniciador

Trigger para servicio detenido:
Nombre: Servicio Zimbra {#ZIMBRA_SERVICE} esta detenido
Expresion: last(/Zimbra Mail Server by OrangeBox/zimbra.service.status[{#ZIMBRA_SERVICE}],#2)="Stopped" and last(/Zimbra Mail Server by OrangeBox/zimbra.service.status[{#ZIMBRA_SERVICE}],#3)="Stopped"
Gravedad: Critica

>NOTA: La expresión está formulada así para que no gatille una alerta hasta que el check retorne 3 veces seguidas "Stopped", para evitar falsos positivos. 

Trigger para servicio desconocido:
Nombre: Servicio Zimbra {#ZIMBRA_SERVICE} estado desconocido
Expresion: last(/Zimbra Mail Server by OrangeBox/zimbra.service.status[{#ZIMBRA_SERVICE}],#2)="Unknown" and last(/Zimbra Mail Server by OrangeBox/zimbra.service.status[{#ZIMBRA_SERVICE}],#3)="Unknown"
Gravedad: Advertencia

>NOTA: La expresión está formulada así para que no gatille una alerta hasta que el check retorne 3 veces seguidas "Unknown", para evitar falsos positivos. 

Paso 10: Vincular la plantilla a un host
Ir a Equipos -> Equipos
Seleccionar el servidor Zimbra
Ir a Plantillas -> Vincular
Agregar: Zimbra Mail Server by OrangeBox

## Que instala el script en el agente

Scripts de monitoreo en /usr/local/bin/

- zabbix_zimbra_discovery.sh - Descubrimiento automatico de servicios
- zabbix_zimbra_status.sh - Estado de servicio especifico
- zabbix_zimbra_queue.sh - Cantidad de correos en cola
- zabbix_zimbra_mailstats.sh - Estadisticas de correo
- zabbix_zimbra_version.sh - Version de Zimbra
- zabbix_zimbra_extra.sh - Metricas adicionales

Configuracion de Zabbix

- UserParameter en /etc/zabbix/zabbix_agent2.d/zabbix_zimbra.conf
- Permisos sudo en /etc/sudoers.d/zabbix_zimbra

## UserParameters disponibles

- zimbra.discovery - Descubre todos los servicios Zimbra
- zimbra.service.status[nombre] - Estado del servicio (Running, Stopped, Unknown)
- zimbra.queue - Cantidad de correos en cola
- zimbra.mailstats.sent - Correos enviados desde el inicio del log
- zimbra.mailstats.received - Correos recibidos desde el inicio del log
- zimbra.mailstats.spam - Spam detectado desde el inicio del log
- zimbra.mailstats.virus - Virus detectados desde el inicio del log
- zimbra.version - Version de Zimbra instalada
- zimbra.extra[mailbox_size] - Tamaño del mailbox en bytes
- zimbra.extra[index_size] - Tamaño del indice en bytes
- zimbra.extra[db_size] - Tamaño de la base de datos en MB
- zimbra.extra[accounts_count] - Cantidad de cuentas de correo
- zimbra.extra[domains_count] - Cantidad de dominios configurados

## Prueba de funcionamiento

Ejecutar como root para probar los scripts:

sudo -u zabbix /usr/local/bin/zabbix_zimbra_discovery.sh
sudo -u zabbix /usr/local/bin/zabbix_zimbra_status.sh antivirus
sudo -u zabbix /usr/local/bin/zabbix_zimbra_queue.sh

Desde el servidor Zabbix, probar:

zabbix_get -s IP_DEL_ZIMBRA -k zimbra.discovery
zabbix_get -s IP_DEL_ZIMBRA -k zimbra.service.status[antivirus]
zabbix_get -s IP_DEL_ZIMBRA -k zimbra.queue

## Desinstalacion

Para eliminar completamente el monitoreo:

rm -f /usr/local/bin/zabbix_zimbra_*.sh
rm -f /etc/zabbix/zabbix_agent2.d/zabbix_zimbra.conf
rm -f /etc/zabbix/zabbix_agentd.d/zabbix_zimbra.conf
rm -f /etc/sudoers.d/zabbix_zimbra

Luego reiniciar el agente Zabbix.

## Notas importantes

- El script debe ejecutarse como root
- El agente Zabbix debe estar preinstalado
- El usuario zabbix necesita permisos sudo configurados
- Los logs de correo deben existir para que funcionen las estadisticas
- El timeout de los items debe ser al menos 15s (configurado en la plantilla)

## Solucion de problemas

Si los scripts no funcionan, verificar:

- Que el agente Zabbix este corriendo: systemctl status zabbix-agent2
- Que el usuario zabbix tenga permisos: sudo -u zabbix /usr/local/bin/zabbix_zimbra_status.sh antivirus
- Que los comandos de Zimbra funcionen: su - zimbra -c "/opt/zimbra/bin/zmcontrol status"
- Revisar logs de Zabbix: tail -f /var/log/zabbix/zabbix_agentd.log

Si el discovery muestra No soportada o Timeout:
- Aumentar el timeout en la regla de discovery a 15s
- Aumentar el timeout en zabbix_server.conf: Timeout=10
- Reiniciar zabbix-server: systemctl restart zabbix-server

** ¿Conoces una PyME que necesite hardening o auditoria?**  
Recomiéndanos. Ayudamos a empresas a proteger su infraestructura Linux.

**¿Quieres mas contenido?**

🔹 **Blog**: [www.orangebox.cl/blog](https://www.orangebox.cl/blog/) — Articulos tecnicos de seguridad e infraestructura  
🔹 **YouTube**: [@OrangeBoxLinux](https://www.youtube.com/@OrangeBoxLinux) — Ataques, defensas, guias y recomendaciones en video  
🔹 **GitHub**: [OrangeBox-Labs](https://github.com/OrangeBox-Labs) — Mas scripts, automatizacion y seguridad open-source

— Felipe Roman, OrangeBox
