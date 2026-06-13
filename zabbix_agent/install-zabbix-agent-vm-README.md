# Script de Instalación del Agente Zabbix para RHEL/AlmaLinux/Rocky

¡Hola! Este script está diseñado para que instalar y configurar el agente de Zabbix en tus VM VMware, Es distinto del otro instalador del agente, porque Zabbix no puede agregar cifrado PSK en sus plantillas de VMware ESX, por lo que este instalador no usa cifrado, sólo para usarse con un zabbix proxy o un server zabbix en la misma red que el VMware, NO lo usen para chequeos remotos porque envía todo en claro, sin cifrar. 

## ¿Qué hace este script?

Este script todo-en-uno realiza las siguientes tareas:

- Pre-chequea el sistema: Verifica que se ejecute como root y resuelve el hostname/IP del servidor Zabbix.
- Abre el firewall: Detecta si usas firewalld o iptables y agrega la regla necesaria para que el servidor Zabbix pueda comunicarse con el agente (puerto 10050).
- Detecta tu sistema operativo: Identifica la versión de RHEL/AlmaLinux/Rocky para instalar el paquete correcto.
- Instala el agente Zabbix: Primero intenta la instalación desde el repositorio oficial. Si falla (por ejemplo, en RHEL 10), descarga e instala el binario estático de Zabbix.
- Configura el agente: Ajusta los archivos de configuración (zabbix_agentd.conf o zabbix_agent2.conf) con la IP de tu servidor Zabbix y el nombre del host.
- Repara errores comunes: Soluciona problemas típicos como archivos PidFile incorrectos o directorios con permisos inadecuados.
- Registra el host en Zabbix (vía API): Se comunica con tu instancia de Zabbix para crear el host, asignarlo al grupo "Linux Servers" y vincularle las plantillas que le indiques.

## Requisitos Previos

Antes de lanzar el script, asegúrate de tener:

- Acceso root o con sudo al servidor que quieres monitorear.
- Un Token de API de Zabbix con permisos para crear y modificar hosts.
- La URL de tu API de Zabbix (por defecto, apunta a http://monitoreo.orangebox.cl/zabbix/api_jsonrpc.php).
- (Opcional) Las plantillas que quieras asignar deben existir en Zabbix con los nombres exactos.

## Instalación y Ejecución

Sigue estos sencillos pasos:

1. Copia el script en tu servidor.
2. Dale permisos de ejecución:
   chmod +x install-zabbix-agent-vm.sh
3. Ejecútalo como root:
   sudo ./install-zabbix-agent-vm.sh

Si no le pasas la IP del servidor Zabbix, usará la que está en la variable DEFAULT_ZABBIX_SERVER. Si quieres especificarla, hazlo así:

   sudo ./install-zabbix-agent-vm.sh IP_O_HOSTNAME_DEL_SERVIDOR_ZABBIX

El script te irá informando de cada paso y, al final, verificará que el servicio del agente esté funcionando.

## Configuración Personalizable (Edita el Script)

Antes de ejecutar, puedes modificar algunas variables dentro del script para adaptarlo a tu entorno:

- DEFAULT_ZABBIX_SERVER: IP o hostname de tu servidor Zabbix (por si no se lo pasas como argumento).
- ZABBIX_API_URL: La URL completa de la API de Zabbix.
- API_TOKEN: Tu token de autenticación para la API de Zabbix.
- TEMPLATE_NAMES: Un array con los nombres exactos de las plantillas que quieres vincular al host.

## ¿Qué se Instala y Dónde?

- Ejecutables: El agente (zabbix_agentd o zabbix_agent2) se instala en /usr/sbin/.
- Configuración: Los archivos de configuración se encuentran en /etc/zabbix/.
- Logs: Los archivos de log del agente y del propio script de instalación se guardan en /var/log/zabbix/ y /var/log/zabbix_install.log.
- Usuario: Se crea el usuario zabbix si no existía.

## Funcionalidades de la API

El script utiliza la API de Zabbix para:

- Verificar la conexión y la validez del token.
- Obtener los IDs de las plantillas que especifiques (Linux by Zabbix agent, VMware Guest, etc.).
- Obtener o crear el grupo "Linux Servers".
- Crear el host si no existe, o actualizar sus plantillas si ya existe.

## Gestión del Firewall

El script es inteligente con el firewall:

- Si detecta firewalld activo, agrega una rich rule para permitir el tráfico desde el servidor Zabbix.
- Si no detecta firewalld pero ve que iptables está en uso con una política DROP o REJECT, agrega una regla para aceptar la conexión.
- Guarda las reglas para que persistan tras un reinicio.

## Manejo de Errores y Reparación

- Si el agente no logra iniciar, el script ejecuta una función de reparación que corrige problemas comunes como el directorio PidFile o permisos incorrectos.
- Intenta instalar desde el repositorio y, si falla, recurre a la descarga del binario estático.

## Verificación Final

Al terminar, el script te indicará si el servicio del agente está activo, qué versión se instaló (Agent o Agent2) y dónde puedes revisar los logs para más detalles.

## Autor

Felipe Román - froman@orangebox.cl

**OrangeBox - Área de Infraestructura**
Web: https://orangebox.cl

## Licencia

Script de uso interno. Puedes modificarlo y adaptarlo a tus necesidades.

---

** ¿Conoces una PyME que necesite hardening o auditoría?**  
Recomiéndanos. Ayudamos a empresas a proteger su infraestructura Linux.

**¿Quieres más contenido?**

🔹 **Blog**: [www.orangebox.cl/blog](https://www.orangebox.cl/blog/) — Artículos técnicos de seguridad e infraestructura  
🔹 **YouTube**: [@OrangeBoxLinux](https://www.youtube.com/@OrangeBoxLinux) — Ataques, defensas, guías y recomendaciones en video  
🔹 **GitHub**: [OrangeBox-Labs](https://github.com/OrangeBox-Labs) — Más scripts, automatización y seguridad open-source


