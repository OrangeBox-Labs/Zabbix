# Templates HTML para Alertas de Correo Zabbix 7.4

Templates HTML personalizados para las notificaciones por correo electrónico de Zabbix 7.4.

Estos templates reemplazan los mensajes de correo por defecto de Zabbix, entregando alertas con un formato más limpio, profesional y fácil de interpretar, manteniendo la información relevante del evento directamente en el correo.

---
## Autor

- **Felipe Roman**
- Web: https://www.orangebox.cl
- Email: froman@orangebox.cl

---

## Características

- Diseño HTML compatible con clientes de correo modernos.
- Adaptado para Zabbix 7.4.
- Formato visual basado en la identidad de OrangeBox.
- Alertas diferenciadas según el estado del evento.
- Información relevante del problema directamente en el correo.
- Enlace directo hacia Zabbix para revisar el evento.
- Diseño pensado para facilitar la lectura desde computadores y dispositivos móviles.

---

## Archivos incluidos

### alerta-problem.html

Template utilizado cuando un trigger cambia al estado **PROBLEM**.

Incluye:

- Host afectado.
- Dirección IP.
- Severidad del trigger.
- Nombre del problema.
- Estado del evento.
- Fecha y hora de inicio.
- Duración del incidente.
- Descripción del trigger.
- Enlace directo al problema en Zabbix.

El diseño utiliza color rojo para identificar rápidamente una alerta activa.

---

### alerta-recuperacion.html

Template utilizado cuando un trigger vuelve al estado **OK**.

Incluye:

- Host recuperado.
- Estado actual.
- Fecha y hora del evento.
- Duración del incidente.
- Descripción del problema original.
- Enlace directo hacia Zabbix.

El diseño utiliza color verde para indicar que el servicio fue restaurado correctamente.

---

### alerta-actualizacion.html

Template utilizado para eventos actualizados o reconocidos por un operador.

Incluye información adicional:

- Usuario que realizó el reconocimiento.
- Fecha y hora del reconocimiento.
- Comentario ingresado por el operador.
- Estado actual del evento.
- Fecha de inicio.
- Duración del evento.
- Descripción del trigger.

Este formato permite mantener trazabilidad de las acciones realizadas sobre las alertas.

---

# Macros Zabbix utilizadas

Los templates utilizan macros estándar proporcionadas por Zabbix:

| Macro | Descripción |
|---|---|
| `{HOST.NAME}` | Nombre del host afectado |
| `{HOST.IP}` | Dirección IP del host |
| `{HOST.ID}` | ID interno del host en Zabbix |
| `{TRIGGER.NAME}` | Nombre del trigger |
| `{TRIGGER.SEVERITY}` | Nivel de severidad del evento |
| `{TRIGGER.STATUS}` | Estado actual del trigger |
| `{TRIGGER.DESCRIPTION}` | Descripción configurada del trigger |
| `{EVENT.DATE}` | Fecha del evento |
| `{EVENT.TIME}` | Hora del evento |
| `{EVENT.DURATION}` | Duración del evento |
| `{USER.FULLNAME}` | Usuario que realizó el reconocimiento |
| `{ACK.DATE}` | Fecha del reconocimiento |
| `{ACK.TIME}` | Hora del reconocimiento |
| `{ACK.MESSAGE}` | Comentario agregado durante el reconocimiento |

---

# Instalación

1. Copiar los archivos HTML al servidor o repositorio donde se administren los templates de correo.

2. En Zabbix ingresar a:

Administración  
→ Tipos de medio  
→ Email

3. Configurar el tipo de mensaje como:

Formato:
HTML

4. Crear o modificar una acción de alertas:

Configuración  
→ Acciones  
→ Acciones de disparador

5. En las operaciones de la acción utilizar el contenido HTML correspondiente según el tipo de evento.

---

# Personalización

Los templates incluyen la identidad visual de OrangeBox:

- Fondo oscuro.
- Tarjetas con bordes redondeados.
- Encabezados diferenciados según estado:

  - 🔴 Problema.
  - 🟢 Recuperado.
  - 🟠 Actualización.

Para cambiar colores, logo, enlaces o textos, basta con modificar directamente los archivos HTML.

---

# Compatibilidad

Probado con:

- Zabbix 7.4.
- Notificaciones por correo electrónico en formato HTML.
- Clientes de correo compatibles con HTML estándar.

---

# Notas

Estos templates dependen de las macros estándar disponibles en Zabbix.

Si se agregan macros personalizadas, deben validarse antes de utilizarlas para evitar que Zabbix envíe variables sin resolver en los correos.

---

# ¿Conoces una PyME que necesite hardening o auditoría?

Recomiéndanos. Ayudamos a empresas a proteger su infraestructura Linux mediante buenas prácticas de seguridad, hardening y monitoreo.

# ¿Quieres más contenido?

🔹 **Blog:** https://www.orangebox.cl/blog/  
Artículos técnicos sobre seguridad, Linux e infraestructura.

🔹 **YouTube:** https://www.youtube.com/@OrangeBoxLinux  
Ataques, defensas, guías y recomendaciones en video.

🔹 **GitHub:** https://github.com/OrangeBox-Labs  
Scripts, automatización y herramientas open-source.

---

— Felipe Román OrangeBox
