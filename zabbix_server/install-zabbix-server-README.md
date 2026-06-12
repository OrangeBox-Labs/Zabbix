# 🚀 Zabbix Server 7.4 Installer for AlmaLinux 10

**Script de instalación automática de Zabbix Server 7.4** con hardening de MySQL, tuning para ~200 servidores, configuración de locales y optimizaciones de rendimiento.


## Autor

- **Felipe Roman**
- Web: www.orangebox.cl
- Email: froman@orangebox.cl


## 📋 Tabla de Contenidos

- [Características](#características)
- [Requisitos](#requisitos)
- [Instalación](#instalación)
- [Uso](#uso)
- [Qué Instala](#qué-instala)
- [Configuración Aplicada](#configuración-aplicada)
- [Estructura del Script](#estructura-del-script)
- [Archivos Generados](#archivos-generados)
- [Solución de Problemas](#solución-de-problemas)
- [Referencias](#referencias)

## ✨ Características

- ✅ **Instalación completa** de Zabbix Server 7.4 + Frontend + Agent
- ✅ **Hardening automático de MySQL** (elimina usuarios anónimos, DB test, acceso remoto)
- ✅ **Tuning de MySQL** optimizado para ~200 servidores monitoreados
- ✅ **skip_name_resolve activado** (mejora performance de conexiones)
- ✅ **Locales configurados** (en_US, es_ES, es_CL)
- ✅ **Generación de passwords aleatorios** con confirmación interactiva
- ✅ **Archivo de credenciales** con toda la información de acceso
- ✅ **Log completo** de toda la instalación
- ✅ **Backup automático** de configuraciones existentes
- ✅ **SELinux configurado** para Zabbix
- ✅ **Firewall configurado** (puertos 80, 10050)

## 📦 Requisitos

| Requisito | Detalle |
|-----------|---------|
| **Sistema Operativo** | AlmaLinux 10 (o Rocky/RHEL 10) |
| **Arquitectura** | x86_64 |
| **RAM Mínima** | 4 GB (8 GB recomendado) |
| **Disco Mínimo** | 20 GB (50 GB recomendado para datos) |
| **Privilegios** | Root |
| **Conexión a Internet** | Sí (para descargar paquetes) |

## 🚀 Instalación

### Instalación Rápida

# Descargar el script
```
curl -O https://raw.githubusercontent.com/tu-usuario/zabbix-installer/main/install-zabbix-server.sh
```

# Dar permisos de ejecución
```
chmod +x install-zabbix-server.sh
```

# Ejecutar (modo interactivo)
```
./install-zabbix-server.sh
```

# O modo automático
```
./install-zabbix-server.sh --auto
```
---
**🤝 ¿Conoces una PyME que necesite hardening o auditoría?**  
Recomiéndanos. Ayudamos a empresas a proteger su infraestructura Linux.

**¿Quieres más contenido?**

🔹 **Blog**: [www.orangebox.cl/blog](https://www.orangebox.cl/blog/) — Artículos técnicos de seguridad e infraestructura  
🔹 **YouTube**: [@OrangeBoxLinux](https://www.youtube.com/@OrangeBoxLinux) — Ataques, defensas, guías y recomendaciones en video  
🔹 **GitHub**: [OrangeBox-Labs](https://github.com/OrangeBox-Labs) — Más scripts, automatización y seguridad open-source

— Felipe Román, OrangeBox
