#!/bin/bash
# ============================================================
# Script: configure_apache_status.sh
# Autor: Felipe Román <froman@orangebox.cl>
# Web: www.orangebox.cl
# Descripción: Configura mod_status en Apache para Zabbix (RHEL)
# ============================================================

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Variables
STATUS_FILE="/etc/httpd/conf.d/status.conf"
HTTPD_SERVICE="httpd"

# --- Verificar root ---
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}✗ Ejecutar como root${NC}"
  exit 1
fi

# --- Verificar Apache ---
if ! command -v httpd &>/dev/null; then
  echo -e "${RED}✗ Apache no instalado${NC}"
  exit 1
fi

echo -e "${GREEN}✅ Configurando mod_status...${NC}"

# --- Verificar si ya está configurado ---
if [ -f "$STATUS_FILE" ] && grep -q "server-status" "$STATUS_FILE" 2>/dev/null; then
  echo -e "${GREEN}✅ mod_status ya está configurado${NC}"
else
  # Crear configuración
  cat >"$STATUS_FILE" <<'EOF'
  ExtendedStatus On

<VirtualHost 127.0.0.1:80>
    ServerName localhost

    <Location /server-status>
        SetHandler server-status
        Require local
    </Location>
</VirtualHost>
EOF
  echo -e "${GREEN}✅ Archivo creado: $STATUS_FILE${NC}"
fi

# --- Verificar módulo cargado ---
if ! httpd -M 2>/dev/null | grep -q "status_module"; then
  echo -e "${YELLOW}⚠ mod_status no cargado, habilitando...${NC}"
  echo "LoadModule status_module modules/mod_status.so" >/etc/httpd/conf.modules.d/00-status.conf
fi

# --- Verificar configuración ---
if ! httpd -t 2>/dev/null; then
  echo -e "${RED}✗ Error en configuración${NC}"
  httpd -t
  exit 1
fi

# --- Recargar Apache ---
systemctl reload $HTTPD_SERVICE 2>/dev/null || service $HTTPD_SERVICE reload 2>/dev/null
sleep 1

# --- Probar ---
if curl -s http://127.0.0.1/server-status?auto | grep -q "Total" 2>/dev/null; then
  echo -e "${GREEN}✅ mod_status funcionando correctamente${NC}"
else
  echo -e "${YELLOW}⚠ No se pudo verificar. Prueba manual:${NC}"
  echo "curl http://127.0.0.1/server-status?auto"
fi

echo -e "${GREEN}✅ Configuración completada${NC}"
echo -e "${GREEN}Autor: Felipe Román <froman@orangebox.cl>${NC}"
