# Zabbix PSK Get - Consulta de Hosts con TLS/PSK

Script interactivo para consultar cualquier host con PSK automáticamente, extrayendo la configuración directamente desde la base de datos MySQL de Zabbix.

## Autor
- **Felipe Roman**
- Web: https://www.orangebox.cl
- Email: froman@orangebox.cl
 


## Características

- Consulta hosts por nombre o IP directamente desde MySQL
- Extrae automáticamente PSK Identity y PSK Key de la base de datos Zabbix
- Soporte para modo interactivo y por línea de comandos
- Colores para mejor visualización
- Limpieza automática de archivos temporales

## Requisitos

- Acceso a la base de datos MySQL de Zabbix
- Usuario de MySQL con permisos de lectura en tablas hosts e interface
- zabbix_get instalado
- Hosts deben tener TLS/PSK configurado

## Uso

### Modo interactivo

./zabbix_get_psk.sh

El script mostrará:
- Lista de hosts con PSK configurado
- Solicitará IP o hostname
- Solicitará la key a consultar
- Solicitará el puerto (default 10050)

### Modo línea de comandos

./zabbix_get_psk.sh <hostname_o_ip> [key]

Ejemplos:
./zabbix_get_psk.sh fw-vizcachas.orangebox.cl
./zabbix_get_psk.sh 186.79.131.105 agent.ping
./zabbix_get_psk.sh servidor.example.com system.hostname

## Formato de salida

El script muestra:
- Host encontrado y su IP
- PSK Identity usada
- Resultado de la consulta

Ejemplo:

 Host: fw-vizcachas.orangebox.cl (186.79.131.105)
 PSK Identity: fw-vizcachas.orangebox.cl_psk_1781126953
 Consultando: agent.ping

 Resultado: 1

## Comandos de ejemplo

Consultar el estado del agente:
./zabbix_get_psk.sh fw-vizcachas.orangebox.cl agent.ping

Consultar el hostname:
./zabbix_get_psk.sh fw-vizcachas.orangebox.cl system.hostname

Consultar version del agente:
./zabbix_get_psk.sh fw-vizcachas.orangebox.cl agent.version

Consultar por IP:
./zabbix_get_psk.sh 186.79.131.105 agent.ping

## Consultas útiles para OpenVPN

Días restantes de un certificado:
./zabbix_get_psk.sh fw-vizcachas.orangebox.cl openvpn.cert.days[froman]

Estado global de certificados:
./zabbix_get_psk.sh fw-vizcachas.orangebox.cl openvpn.certs.check

## Notas de seguridad

- El script crea archivos temporales en /tmp/psk_$$.key
- Los archivos se eliminan automáticamente al finalizar
- Permisos 600 en el archivo temporal de PSK

## Solución de problemas

Error: No se encontró el host
Verificar que el host existe en Zabbix y tiene TLS/PSK configurado

Error: MySQL connection
Verificar credenciales de MySQL en el script

Error: zabbix_get failed
Verificar conectividad de red y que el puerto 10050 esté accesible

## Estructura de la base de datos consultada

Tablas utilizadas:
- hosts: contiene hostid, host, tls_psk_identity, tls_psk
- interface: contiene hostid, ip, main, port

---

**¿Conoces una PyME que necesite hardening o auditoría?**  
Recomiéndanos. Ayudamos a empresas a proteger su infraestructura Linux.

**¿Quieres más contenido?**

🔹 **Blog**: [www.orangebox.cl/blog](https://www.orangebox.cl/blog/) — Artículos técnicos de seguridad e infraestructura  
🔹 **YouTube**: [@OrangeBoxLinux](https://www.youtube.com/@OrangeBoxLinux) — Ataques, defensas, guías y recomendaciones en video  
🔹 **GitHub**: [OrangeBox-Labs](https://github.com/OrangeBox-Labs) — Más scripts, automatización y seguridad open-source

— Felipe Román, OrangeBox Labs

