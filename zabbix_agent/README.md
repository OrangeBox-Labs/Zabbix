# Scripts para Instalar el Agente Zabbix

Scripts destinados a ejecutarse en los servidores que serán monitoreados por Zabbix  
(ejemplos: servidor OpenVPN, servidor web, servidores Linux, máquinas virtuales, etc.).

---

## Nota sobre VMware

La principal diferencia entre los scripts `install-zabbix-agent-vm.sh` y `install-zabbix-agent2.sh` es que el agente utilizado para VMware (`agent-vm`) **no soporta cifrado**.

¿Por qué?

Porque el template oficial de VMware incluido en Zabbix viene diseñado de esta forma: sin soporte de encriptación para la comunicación con el agente.

Sí, Zabbix nos entrega una herramienta para monitorear VMware, pero dejó esta parte con la llave puesta sobre la mesa. Gracias Zabbix!.  
Y no, el template oficial tampoco permite simplemente activar cifrado mediante una modificación rápida.

---

## Recomendación para entornos VMware

Para mantener una arquitectura segura, se recomienda:

- Ejecutar el monitoreo VMware desde un servidor Zabbix ubicado dentro de la misma red del entorno VMware.
- Si esto no es posible, desplegar un **Zabbix Proxy** dentro de la red VMware.

El Zabbix Proxy será el encargado de comunicarse con el servidor Zabbix principal utilizando cifrado, protegiendo así la comunicación entre ambos puntos.

---

## Resumen de scripts

| Script | Uso recomendado | Cifrado |
|--------|-----------------|---------|
| `install-zabbix-agent-vm.sh` | Monitoreo de máquinas virtuales VMware mediante el template oficial | ❌ No soporta cifrado |
| `install-zabbix-agent2.sh` | Servidores Linux tradicionales y equipos donde se requiere mayor flexibilidad | ✅ Soporta cifrado y más funcionalidades |

---

## ¿Conoces una PyME que necesite hardening o auditoría?

Recomiéndanos. Ayudamos a empresas a proteger su infraestructura Linux mediante buenas prácticas de seguridad, hardening y monitoreo.

## ¿Quieres más contenido?

🔹 **Blog:** https://www.orangebox.cl/blog/  
Artículos técnicos sobre seguridad, Linux e infraestructura.

🔹 **YouTube:** https://www.youtube.com/@OrangeBoxLinux  
Ataques, defensas, guías y recomendaciones en video.

🔹 **GitHub:** https://github.com/OrangeBox-Labs  
Scripts, automatización y herramientas open-source.

---

— Felipe Román  
OrangeBox
