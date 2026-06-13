# Zabbix Host Manager - Gestión de Hosts via API

Script interactivo para gestionar hosts en Zabbix utilizando la API. Permite buscar, eliminar, agregar y modificar la configuración TLS/PSK de los hosts.

## Autor

- **Felipe Roman**
- Web: https://www.orangebox.cl
- Email: froman@orangebox.cl


## Características

- Buscar host por nombre
- Buscar host por IP (muestra todos los hosts asociados)
- Agregar nuevo host con configuración TLS/PSK opcional
- Eliminar host por nombre
- Eliminar host por IP (elimina todos los hosts con esa IP)
- Cambiar datos de encriptacion PSK
- Listar todos los hosts
- Ver detalles completos de un host

## Requisitos

- Conexión al servidor Zabbix
- Token de API de Zabbix con permisos de Super Admin
- jq instalado
- openssl instalado (para generación de PSK)

## Instalación de dependencias

En RHEL/CentOS/AlmaLinux/Rocky:
```
yum install -y jq openssl
```


## Configuración

Edita las siguientes variables dentro del script:

API_TOKEN="tu_token_api_aqui"
ZABBIX_API_URL="http://tu_servidor_zabbix/zabbix/api_jsonrpc.php"

## Uso

Ejecutar el script:
```
./zabbix-host-manager.sh
```

## Menú Principal

============================================
     ZABBIX HOST MANAGER - API v1.0
     OrangeBox - Infraestructura
============================================

MENU PRINCIPAL:

1. Buscar host por nombre
2. Buscar host por IP
3. Agregar nuevo host
4. Eliminar host por nombre
5. Eliminar host por IP (elimina todos los hosts con esa IP)
6. Cambiar datos de encriptacion PSK
7. Listar todos los hosts
8. Ver detalles completos de un host
0. Salir

Seleccione una opcion:

## Opción 3: Agregar nuevo host

El script preguntará por:

- Nombre del host (ej: servidor.example.com)
- Nombre visible (opcional, usa el mismo si se deja vacío)
- IP del host
- Puerto (default 10050)
- ID del grupo (default 2 - Linux Servers)
- ID de la plantilla (default 10001 - Template OS Linux by Zabbix agent)
- Habilitar TLS/PSK (s/N)
  - Si se habilita, permite ingresar PSK Identity y Key o los genera automáticamente

## Opción 6: Cambiar PSK

Permite actualizar la configuración TLS/PSK de un host existente:
- Muestra el PSK actual
- Permite ingresar nueva PSK Identity
- Permite ingresar nueva PSK Key
- Mantiene valores anteriores si se deja vacío

## Formato de salida

Las búsquedas muestran los resultados en formato tabla:

Host ID: 10835 | Nombre: servidor.example.com | IP: 192.168.1.100 | Puerto: 10050

## Archivos generados

Cuando se crea un host con TLS/PSK habilitado y se generan automáticamente las credenciales, se guarda un archivo en:

/root/zabbix_psk_nombre_host_fecha.txt

## Modo Debug

Para activar el modo debug y ver el JSON enviado a la API, cambiar en el script:

DEBUG_MODE=true

## Ejemplos de uso

Buscar un host por nombre
Seleccionar opción 1, ingresar "servidor.ejemplo.cl"

Buscar todos los hosts con una IP
Seleccionar opción 2, ingresar "192.168.1.100"

Agregar un host sin TLS
Seleccionar opción 3, ingresar los datos y responder "n" a "Habilitar TLS/PSK"

Agregar un host con TLS/PSK automático
Seleccionar opción 3, ingresar los datos y responder "s" a "Habilitar TLS/PSK", dejar vacíos los campos de PSK

Eliminar todos los hosts con una IP
Seleccionar opción 5, ingresar la IP, confirmar eliminación

## Notas de seguridad

- El token de API debe tener permisos de Super Admin
- Los archivos de credenciales PSK se guardan con permisos 600
- No compartir los archivos de credenciales PSK

## Solución de problemas

Error "jq no esta instalado"
Instalar jq según tu distribución

Error "openssl no esta instalado"
Instalar openssl según tu distribución

Error "Parse error" al crear host
Verificar que el token tenga permisos suficientes y que los datos ingresados sean correctos

Error "No permissions to referred object"
El token no tiene permisos suficientes. Usar un token de Super Admin

## Autor

OrangeBox - Area de Infraestructura
Web: https://orangebox.cl

---

**¿Conoces una PyME que necesite hardening o auditoría?**  
Recomiéndanos. Ayudamos a empresas a proteger su infraestructura Linux.

**¿Quieres más contenido?**

🔹 **Blog**: [www.orangebox.cl/blog](https://www.orangebox.cl/blog/) — Artículos técnicos de seguridad e infraestructura  
🔹 **YouTube**: [@OrangeBoxLinux](https://www.youtube.com/@OrangeBoxLinux) — Ataques, defensas, guías y recomendaciones en video  
🔹 **GitHub**: [OrangeBox-Labs](https://github.com/OrangeBox-Labs) — Más scripts, automatización y seguridad open-source

— Felipe Román, OrangeBox Labs

