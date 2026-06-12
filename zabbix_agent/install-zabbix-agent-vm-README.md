# 🍊 Script de Instalación de Agente Zabbix

Script para instalar y configurar el agente Zabbix en distribuciones RHEL (7,8,9,10 y derivadas como AlmaLinux, Rocky, CentOS). Especialmente útil para VMs descubiertas por Zabbix.

---

## 🚀 ¿Qué hace este script?

| Función | Descripción |
|---------|-------------|
| Instalación automática | Instala Zabbix Agent 7.4 desde repositorio oficial (fallback a binario estático) |
| Configuración de agente | Configura el agente con la IP del servidor Zabbix (resuelve hostnames) |
| Firewall | Abre puerto 10050 en firewalld o iptables (detecta política DROP/REJECT) |
| Registro en Zabbix | Actualiza host existente vía API (NO crea host nuevo) |
| Plantillas | Vincula "Linux by Zabbix agent" y "VMware Guest" al host |
| Reparación automática | Corrige error del PID file en RHEL (crea /run/zabbix y permisos) |

---

## ⚠️ Importante

- La VM debe estar descubierta primero por Zabbix (a través del vCenter) antes de ejecutar este script
- Este script no crea el host, solo actualiza sus templates y configura el agente local
- Si el host no existe en Zabbix, el script mostrará una advertencia

---

## 📋 Requisitos previos

- Acceso root a la máquina
- IP o hostname del servidor Zabbix
- Token de API de Zabbix válido (el script incluye uno, verificar vigencia)
- Conectividad a internet (para repositorios) o acceso al binario estático
- El host debe existir previamente en Zabbix

---

## 🔧 Uso

chmod +x install_zabbix_agent.sh

./install_zabbix_agent.sh 192.168.200.240

O con hostname:

./install_zabbix_agent.sh monitoreo.orangebox.cl

Sin parámetro usa la IP por defecto (192.168.200.240):

./install_zabbix_agent.sh

---

## 📂 Variables configurables

| Variable | Descripción | Valor por defecto |
|----------|-------------|-------------------|
| DEFAULT_ZABBIX_SERVER | IP del servidor Zabbix | 192.168.200.240 |
| ZABBIX_API_URL | URL de la API de Zabbix | http://monitoreo.orangebox.cl/zabbix/api_jsonrpc.php |
| API_TOKEN | Token de autenticación | a3a43004795a... |
| TEMPLATE_NAMES | Plantillas a vincular | Linux by Zabbix agent, VMware Guest |

---

## 📝 Comportamiento detallado

1. Verifica que se ejecute como root
2. Resuelve la IP del servidor Zabbix (si se pasó hostname)
3. Configura el firewall:
   - Si firewalld está activo: agrega regla rich-rule para permitir al server Zabbix en puerto 10050
   - Si iptables tiene política INPUT DROP o REJECT: agrega regla en posición 1
4. Detecta la versión de RHEL y agrega el repositorio correspondiente
5. Instala zabbix-agent (y zabbix-agent2 si está disponible)
6. Si falla la instalación por repositorio, descarga e instala el binario estático
7. Configura el agente con la IP del servidor Zabbix
8. Corrige directorios /run/zabbix y permisos del usuario zabbix
9. Busca el host en Zabbix por su nombre visible (ej: www.jhg.cl, no el UUID)
10. Si el host existe, actualiza sus templates
11. Inicia y habilita el servicio

---

## 📄 Logs

Toda la instalación se registra en: /var/log/zabbix_install.log

---

## 📌 Notas

- El script funciona en RHEL 7, 8, 9, 10 y derivados (AlmaLinux, Rocky, CentOS)
- Si firewalld está instalado pero no activo, no se configura
- La regla de iptables se agrega al inicio de la cadena INPUT (posición 1) para prioridad
- Las reglas de iptables se guardan automáticamente en /etc/sysconfig/iptables (RHEL)
- Si el token de API expiró, el agente se instala pero no se actualizan los templates

---

## 🧠 ¿Necesitas ayuda con tu infraestructura?

En OrangeBox somos especialistas en monitoreo proactivo y administración de infraestructura crítica.

🔍 ¿Quieres visibilidad real de tu operación?

➡️ Recursos gratuitos:
Scripts para Zabbix (agentes e instalación automática): https://github.com/OrangeBox-Labs/Zabbix.git

➡️ Planes y servicios profesionales:
Monitoreo y observabilidad: https://www.orangebox.cl/servicios/monitoreo-observabilidad/
Servicios administrados (planes desde 3 UF/mes): https://www.orangebox.cl/servicios/servicios-administrados/

---

📧 Contacto: info@orangebox.cl | 🌐 www.orangebox.cl

---
**¿Quieres más contenido?**

🔹 **Blog**: [www.orangebox.cl/blog](https://www.orangebox.cl/blog/) — Artículos técnicos de seguridad e infraestructura  
🔹 **YouTube**: [@OrangeBoxLinux](https://www.youtube.com/@OrangeBoxLinux) — Ataques, defensas, guías y recomendaciones en video  
🔹 **GitHub**: [OrangeBox-Labs](https://github.com/OrangeBox-Labs) — Más scripts, automatización y seguridad open-source

— Felipe Román, OrangeBox

