# 🚀 OrangeBox Zabbix Toolkit

Colección de scripts para la instalación, configuración y automatización de Zabbix en entornos Linux empresariales.

## Autor

- **Felipe Roman**
- Web: https://www.orangebox.cl
- Email: froman@orangebox.cl



## Descripción General

Este repositorio contiene un conjunto de scripts diseñados para simplificar y automatizar la implementación de Zabbix en entornos Red Hat Enterprise Linux (RHEL) y sus derivados (AlmaLinux, Rocky Linux, CentOS).

Los scripts cubren desde la instalación completa del servidor Zabbix con optimizaciones de rendimiento, hasta la instalación de agentes en sistemas remotos y tareas automatizadas para el mantenimiento diario.

## Scripts Disponibles

| Script | Descripción | Estado |
|--------|-------------|--------|
| install-zabbix-server.sh | Instalación completa de Zabbix Server 7.4 con hardening, tuning y locales | Estable |
| install-zabbix-agent.sh | Instalación y configuración de Zabbix Agent con TLS PSK | Próximamente |


## Instalación

### Clonar el Repositorio
```
git clone https://github.com/OrangeBox-Labs/Zabbix.git
cd zabbix-toolkit
chmod +x *.sh
```

### Instalación Rápida del Servidor Zabbix

```
./install-zabbix-server.sh
```

### Instalación Automática (sin prompts)

```
./install-zabbix-server.sh --auto
```

## Uso

### Opciones Comunes

# Ver ayuda de cada script
```
./install-zabbix-server.sh --help
```

# Instalación automática (modo no interactivo)
```
./install-zabbix-server.sh --auto
```

# Instalar solo el agente (próximamente)
```
./install-zabbix-agent.sh --server 192.168.1.100
```

### Variables de Entorno

| Variable | Descripción | Ejemplo |
|----------|-------------|---------|
| ZBX_DB_PASSWORD | Password para usuario zabbix en MySQL | export ZBX_DB_PASSWORD=MiPass123 |
| ZBX_MYSQL_ROOT_PASSWORD | Password para root de MySQL | export ZBX_MYSQL_ROOT_PASSWORD=RootPass456 |
| ZBX_SERVER | IP del servidor Zabbix (para agentes) | export ZBX_SERVER=192.168.1.100 |


## Seguridad

### Prácticas Implementadas

| Práctica | Descripción |
|----------|-------------|
| Passwords aleatorios | Generación de passwords de 24 caracteres con símbolos |
| Archivo de credenciales | Permisos 600, solo legible por root |
| Hardening de MySQL | Eliminación de usuarios anónimos, DB test, acceso remoto |
| skip_name_resolve | Elimina lookup DNS en MySQL (mejora seguridad y performance) |
| SELinux | Configuración automática de políticas |
| Firewall | Solo puertos necesarios expuestos |
| Logging completo | Todos los comandos registrados para auditoría |


## Licencia

MIT License

Copyright (c) 2025-2026 Felipe Roman - OrangeBox Labs

Permiso concedido gratuitamente a cualquier persona que obtenga una copia de este software y los archivos de documentación asociados, para utilizar el Software sin restricción, incluyendo sin limitación los derechos de usar, copiar, modificar, fusionar, publicar, distribuir, sublicenciar y/o vender copias del Software.

---
**🤝 ¿Conoces una PyME que necesite hardening o auditoría?**  
Recomiéndanos. Ayudamos a empresas a proteger su infraestructura Linux.

**¿Quieres más contenido?**

🔹 **Blog**: [www.orangebox.cl/blog](https://www.orangebox.cl/blog/) — Artículos técnicos de seguridad e infraestructura  
🔹 **YouTube**: [@OrangeBoxLinux](https://www.youtube.com/@OrangeBoxLinux) — Ataques, defensas, guías y recomendaciones en video  
🔹 **GitHub**: [OrangeBox-Labs](https://github.com/OrangeBox-Labs) — Más scripts, automatización y seguridad open-source

— Felipe Román, OrangeBox
