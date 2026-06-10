
# Zabbix Agent Secure Installer

Script de instalación automática de Zabbix Agent 2 con PSK única por agente y registro automático vía API


## Autor

- **Felipe Roman**
- Web: www.orangebox.cl
- Email: froman@orangebox.cl


## Descripción

Este script instala y configura Zabbix Agent 2 en sistemas Linux de manera segura.

- PSK única y diferente para cada agente
- TLS obligatorio para todas las comunicaciones
- Registro automático en Zabbix Server vía API
- Sin intervención manual en la interfaz web
- Soporte multi-distribución (RHEL, AlmaLinux, Rocky, Ubuntu)

## Características

| Característica | Descripción |
|----------------|-------------|
| PSK única por agente | Cada instalación genera su propia clave, aislando el compromiso |
| TLS obligatorio | Toda la comunicación está encriptada |
| Registro automático | El host se añade a Zabbix automáticamente sin intervención web |
| Multi-distribución | Soporta RHEL 7/8/9/10, AlmaLinux, Rocky, Ubuntu 22.04/24.04 |
| Logging completo | Registro detallado de toda la instalación |
| Backup de credenciales | Guarda PSK y configuración en archivo seguro |

## Modo Interactivo vs Automático

El script soporta dos modos de ejecución:

| Modo | Característica | Uso |
|------|----------------|-----|
| Interactivo | Pregunta los datos necesarios durante la ejecución | Ejecutar sin variables predefinidas |
| Automático | Usa valores predefinidos sin preguntar | Definir variables al inicio del script |

## Variables Configurables

| Variable | Descripción | Ejemplo |
|----------|-------------|---------|
| ZABBIX_SERVER | Servidor Zabbix (FQDN o IP) | monitoreo.orangebox.cl |
| ZABBIX_SERVER_PORT | Puerto del servidor Zabbix | 10051 |
| ZABBIX_API_URL | URL de la API de Zabbix | https://monitoreo.orangebox.cl/api_jsonrpc.php |
| API_TOKEN  | token que debes generar en la web de tu Zabbix |

## Comportamiento

Si una variable está predefinida en el script, se usa automáticamente. Si está vacía, el script solicita el valor durante la ejecución.

La URL de la API se genera automáticamente a partir de ZABBIX_SERVER si no se define manualmente.


## Requisito Previo: Crear API Token en Zabbix

Antes de ejecutar el script, debes crear un API Token en la interfaz web de Zabbix.

### Pasos para crear el API Token:

1. Inicia sesión en Zabbix como usuario **Admin**
2. Haz clic en tu avatar (esquina superior derecha)
3. Selecciona **User settings** → **API tokens**
4. Haz clic en **Create API token**
5. Asigna un nombre (ej: `agent_installer`)
6. Haz clic en **Add**
7. **COPIA EL TOKEN** (se muestra solo una vez)

### Configurar el script:

Edita el script y modifica las siguientes variables:

```
ZABBIX_SERVER="monitoreo.orangebox.cl"
API_TOKEN="aea418dfd357074b808e151b5d23a47d14f8290642f0984101a75e3654355408"
TEMPLATE_ID="10343"  # Linux by Zabbix agent active
GROUP_ID="2"         # Linux servers
```


# Obtener template ID para "Linux by Zabbix agent active"
mysql -uzabbix -p zabbix -e "SELECT hostid, host FROM hosts WHERE host='Linux by Zabbix agent active' AND status=3;"

# Obtener group ID para "Linux servers"
mysql -uzabbix -p zabbix -e "SELECT groupid, name FROM groups WHERE name='Linux servers';"

| Requisito | Detalle |
|-----------|---------|
| Sistema Operativo | RHEL 7/8/9/10, AlmaLinux 8/9/10, Rocky 8/9/10, Ubuntu 22.04/24.04 |
| Arquitectura | x86_64, ARM64 |
| Privilegios | Root |
| Conexión a Internet | Sí (para descargar paquetes) |
| Acceso a Zabbix Server | Puerto 10051/TCP abierto hacia monitoreo.orangebox.cl |
| Zabbix Server | Versión 7.4 con API accesible |

## Instalación
```
git clone https://github.com/OrangeBox-Labs/Zabbix.git
cd Zabbix
chmod +x install-zabbix-agent-secure.sh
```

## Que hace el script

| Paso | Acción |
|------|--------|
| 1 | Detecta el sistema operativo y versión |
| 2 | Solicita configuración si no está predefinida |
| 3 | Genera una PSK única de 32 bytes hex para el agente |
| 4 | Instala el repositorio de Zabbix |
| 5 | Instala Zabbix Agent 2 |
| 6 | Configura el agente con TLS PSK obligatorio |
| 7 | Inicia y habilita el servicio |
| 8 | Se autentica en la API de Zabbix |
| 9 | Crea el host con la configuración PSK |
| 10 | Guarda las credenciales en un archivo seguro |

## Archivos Generados

| Archivo | Contenido | Permisos |
|---------|-----------|----------|
| /etc/zabbix/zabbix_agent2.conf | Configuración del agente | 644 |
| /etc/zabbix/zabbix_agentd.psk | Clave PSK del agente | 400 |
| /root/zabbix_agent_NOMBRE_credentials.txt | Credenciales completas | 600 |
| /root/zabbix-agent-install.log | Log de instalación | 600 |

## Verificación

Comprobar que el agente está corriendo:

```
systemctl status zabbix-agent2
```

Ver logs:

```
tail -f /var/log/zabbix/zabbix_agent2.log
```

Probar conexión desde otro servidor:

```
zabbix_get -s IP_DEL_AGENTE -p 10050 -k "agent.ping" --tls-connect psk --tls-psk-identity "PSK_IDENTITY" --tls-psk-file /etc/zabbix/zabbix_agentd.psk
```

## Solución de Problemas

Error: No se puede conectar al servidor

Verificar que el puerto 10051 está abierto en el servidor Zabbix:
```
nc -zv monitoreo.orangebox.cl 10051
```

Error: No se pudo autenticar en Zabbix API

Verificar que el usuario y password de Admin son correctos:
```
curl -k https://monitoreo.orangebox.cl/api_jsonrpc.php
```

Error: El agente no inicia

Revisar configuración:
```
zabbix_agent2 -T
journalctl -u zabbix-agent2 -n 50
```

## Seguridad

Este script implementa las siguientes medidas de seguridad:

| Medida | Implementación |
|--------|----------------|
| Cifrado de comunicaciones | TLS obligatorio con PSK |
| Aislamiento de claves | PSK única por agente |
| Protección de credenciales | Archivos con permisos 600 y 400 |
| Autenticación | Sin contraseñas en texto plano en el agente |
| DNS | Uso de FQDN unificado para evitar resolución mixta |

## Licencia

MIT License

Copyright (c) 2026 Felipe Roman - OrangeBox Labs

---
**🤝 ¿Conoces una PyME que necesite hardening o auditoría?**  
Recomiéndanos. Ayudamos a empresas a proteger su infraestructura Linux.

**¿Quieres más contenido?**

🔹 **Blog**: [www.orangebox.cl/blog](https://www.orangebox.cl/blog/) — Artículos técnicos de seguridad e infraestructura  
🔹 **YouTube**: [@OrangeBoxLinux](https://www.youtube.com/@OrangeBoxLinux) — Ataques, defensas, guías y recomendaciones en video  
🔹 **GitHub**: [OrangeBox-Labs](https://github.com/OrangeBox-Labs) — Más scripts, automatización y seguridad open-source

— Felipe Román, OrangeBox
