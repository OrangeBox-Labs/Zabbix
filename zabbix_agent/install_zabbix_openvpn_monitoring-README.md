# Monitoreo de Certificados OpenVPN para Zabbix

Instalador automático de monitoreo de certificados OpenVPN para Zabbix! Este script te ayudará a mantener un ojo en tus certificados para que nunca caduquen sin que te des cuenta.

## ¿Qué hace este script?

Funciones:

- Ver cuántos días le quedan a cada certificado.
- Recibir alertas cuando un certificado esté por vencer.
- Visualizar la evolución de cada certificado en el tiempo.

Lo hace mediante Low Level Discovery (LLD), así que cuando agregues un nuevo cliente, ¡Zabbix lo detectará automáticamente!

## Requisitos Previos

Antes de comenzar, asegúrate de tener:

- Zabbix Agent 2 instalado y funcionando en el servidor OpenVPN.
- Acceso root o con sudo al servidor OpenVPN.
- Los certificados de tus clientes en la ruta estándar de Easy-RSA (/etc/openvpn/server/easy-rsa/pki/issued).

##  Instalación

```
git clone https://github.com/OrangeBox-Labs/Zabbix.git
cd zabbix_agent
./install_zabbix_openvpn_monitoring.sh
```

El script hará todo el trabajo sucio por ti: detectará la ruta de tus certificados, creará los scripts necesarios, configurará los parámetros de usuario (UserParameters) y ajustará los permisos para el usuario zabbix.

## ¿Qué se Instala?

El script desplegará tres scripts clave en /usr/local/bin/:

- openvpn_cert_discovery.sh: Se encarga del descubrimiento automático de los certificados.
- openvpn_cert_days.sh: Calcula los días restantes para un certificado específico.
- check_openvpn_certs_zabbix.sh: Genera un resumen del estado global de todos los certificados.

Además, creará el archivo de configuración openvpn_certs.conf en el directorio de configuración de Zabbix Agent 2.

## 📊 Configuración en Zabbix WEB

Una vez que el script haya terminado, tendrás que hacer algunos pasos en la interfaz web de Zabbix:

### 1. Crear la Plantilla

Ve a Recopilación de datos → Plantillas y crea una nueva plantilla llamada Openvpn certs by OrangeBox.

### 2. Crear la Regla de Descubrimiento (LLD)

Dentro de la plantilla, ve a Reglas de descubrimiento y crea una nueva regla:

- Nombre: OpenVPN Certificates Discovery
- Clave: openvpn.certs.discovery
- Tipo: Agente Zabbix
- Intervalo de actualización: 1h

### 3. Crear el Prototipo de Métrica

Dentro de la regla LLD, ve a Prototipos de métrica y crea uno nuevo:

- Nombre: Certificate {#CERTNAME} days remaining
- Clave: openvpn.cert.days[{#CERTNAME}]
- Tipo: Agente Zabbix
- Tipo de información: Numérico (entero 64 bits)
- Unidades: días
- Intervalo de actualización: 6h
- Historial: 90d
- Tendencias: 365d

### 4. Crear los Prototipos de Iniciador (Triggers)

Dentro del prototipo de métrica, ve a Prototipos de iniciador y crea dos:

**Trigger WARNING:**
- Nombre: OpenVPN: Certificate {#CERTNAME} expires soon (WARNING)
- Expresión: last(/Openvpn certs by OrangeBox/openvpn.cert.days[{#CERTNAME}])<30 and last(/Openvpn certs by OrangeBox/openvpn.cert.days[{#CERTNAME}])>=15
- Severidad: Advertencia

**Trigger CRITICAL:**
- Nombre: OpenVPN: Certificate {#CERTNAME} expires soon (CRITICAL)
- Expresión: last(/Openvpn certs by OrangeBox/openvpn.cert.days[{#CERTNAME}])<15
- Severidad: Alta

### 5. Crear el Item Global (Opcional pero recomendado)

Para tener un resumen en texto de todos los certificados, crea este item en la plantilla:

- Nombre: OpenVPN: Certificates Status
- Clave: openvpn.certs.check
- Tipo: Agente Zabbix
- Tipo de información: Texto
- Intervalo de actualización: 6h

### 6. Aplicar la Plantilla al Host

Finalmente, ve a Recopilación de datos → Hosts, selecciona tu servidor OpenVPN, ve a la pestaña Plantillas y añade la plantilla Openvpn certs by OrangeBox.

> También puedes importar la plantilla que dejé en el directorio **zabbix_server** de este mismo repo!. (agrega todo, incluido el dashboard)

##  Dashboard Recomendado

Para visualizar todo de forma amigable, crea un dashboard con estos widgets:

**Widget 1 - Resumen en texto:**
- Tipo: Valor de la métrica
- Métrica: openvpn.certs.check
- Host: Tu servidor OpenVPN

**Widget 2 - Tabla de días restantes:**
- Tipo: Navegador de métricas
- Patrón de métrica: openvpn.cert.days[*]

**Widget 3 - Evolución en el tiempo:**
- Tipo: Gráficas
- Patrón de métrica: openvpn.cert.days[*]

**Widget 4 - Problemas activos:**
- Tipo: Problemas
- Etiqueta: application = openvpn

##  Comandos Útiles

Probar el descubrimiento manualmente:
```
zabbix_get -s IP_DEL_AGENTE -k openvpn.certs.discovery
```

Probar los días restantes de un certificado:
```
zabbix_get -s IP_DEL_AGENTE -k openvpn.cert.days[froman]
```

Probar el estado global:
```
zabbix_get -s IP_DEL_AGENTE -k openvpn.certs.check
```

##  Notas Importantes

- Los certificados con más de 30 días se consideran OK.
- Los certificados entre 15 y 30 días generan una alerta WARNING.
- Los certificados con menos de 15 días generan una alerta CRITICAL.
- El intervalo de actualización recomendado es 6h, ya que los certificados no cambian rápidamente.
- Si agregas un nuevo certificado, la regla LLD lo descubrirá automáticamente en la próxima ejecución (cada 1 hora).

## Autor

**OrangeBox - Área de Infraestructura**
Web: https://www.orangebox.cl
Versión: 3.0 - LLD

##  Licencia

Script de uso interno. Puedes modificarlo y adaptarlo a tus necesidades.

---

**🤝 ¿Conoces una PyME que necesite hardening o auditoría?**  
Recomiéndanos. Ayudamos a empresas a proteger su infraestructura Linux.

**¿Quieres más contenido?**

🔹 **Blog**: [www.orangebox.cl/blog](https://www.orangebox.cl/blog/) — Artículos técnicos de seguridad e infraestructura  
🔹 **YouTube**: [@OrangeBoxLinux](https://www.youtube.com/@OrangeBoxLinux) — Ataques, defensas, guías y recomendaciones en video  
🔹 **GitHub**: [OrangeBox-Labs](https://github.com/OrangeBox-Labs) — Más scripts, automatización y seguridad open-source

— Felipe Román, OrangeBox 

