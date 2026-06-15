# Scripts para Instalar el Agente Zabbix

Scripts que deben ejecutarse en el servidor que monitorearas (servidor OpenVPN, servidor web, etc.)

> NOTA: La diferencia más importante entre los scripts `install-zabbix-agent-vm.sh` y `install-zabbix-agent2.sh` es que el agente para VMware (`agent-vm`) no soporta cifrado.

> ¿Por qué? Porque el template oficial de VMware que trae Zabbix viene así de fábrica: sin soporte de encriptación. Sí, Zabbix nos da una herramienta para monitorear VMware, pero dejó esa puerta con la llave puesta encima de la mesa (gracias, Zabbix, y no, el template tampoco soporta modificaciones.).

> Por este motivo, lo recomendado es que las máquinas virtuales VMware sean monitoreadas por un servidor Zabbix ubicado dentro de la misma red del entorno VMware. Si eso no es posible, la alternativa correcta es desplegar un Zabbix Proxy dentro de la red VMware.

> En este último caso, el Proxy sí debe comunicarse con el servidor Zabbix utilizando cifrado, dejando protegido el canal entre ambos puntos. (en el zabbix-proxy si deben usar el script install-zabbix-agent2.sh para que todo quede cifrado.

> En resumen:
>
> - `install-zabbix-agent-vm.sh` → pensado para VMware, pero sin cifrado (por limitación del template oficial).
> - `install-zabbix-agent2.sh` → agente tradicional con soporte de cifrado y más funcionalidades.
> - Si VMware está en una red separada → mejor usar un Zabbix Proxy y que él haga de "mensajero blindado" entre VMware y el servidor Zabbix.

---
** ¿Conoces una PyME que necesite hardening o auditoría?**  
Recomiéndanos. Ayudamos a empresas a proteger su infraestructura Linux.

**¿Quieres más contenido?**

🔹 **Blog**: [www.orangebox.cl/blog](https://www.orangebox.cl/blog/) — Artículos técnicos de seguridad e infraestructura  
🔹 **YouTube**: [@OrangeBoxLinux](https://www.youtube.com/@OrangeBoxLinux) — Ataques, defensas, guías y recomendaciones en video  
🔹 **GitHub**: [OrangeBox-Labs](https://github.com/OrangeBox-Labs) — Más scripts, automatización y seguridad open-source

— Felipe Román, OrangeBox 

