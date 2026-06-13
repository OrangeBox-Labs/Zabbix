#!/bin/bash
# ============================================================
# Script: install_zabbix_openvpn_monitoring.sh
# Descripción: Instala monitoreo de certificados OpenVPN para Zabbix
#              CON LLD (Low Level Discovery)
# Autor: OrangeBox - Área de Infraestructura
# Web: https://orangebox.cl
# Versión: 3.0 - LLD
# ============================================================

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variables
ZABBIX_CONF_DIR="/etc/zabbix/zabbix_agent2.d"
ZABBIX_CONF_FILE="${ZABBIX_CONF_DIR}/openvpn_certs.conf"
ZABBIX_USER="zabbix"
GROUP_NAME="zabbix-openvpn"

# Logo
echo ""
echo "============================================================"
echo "   ██████╗ ██████╗  █████╗ ███╗   ██╗ ██████╗ ███████╗"
echo "  ██╔═══██╗██╔══██╗██╔══██╗████╗  ██║██╔════╝ ██╔════╝"
echo "  ██║   ██║██████╔╝███████║██╔██╗ ██║██║  ███╗█████╗  "
echo "  ██║   ██║██╔══██╗██╔══██║██║╚██╗██║██║   ██║██╔══╝  "
echo "  ╚██████╔╝██║  ██║██║  ██║██║ ╚████║╚██████╔╝███████╗"
echo "   ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚══════╝"
echo "============================================================"
echo "     MONITOREO OPENVPN CERTIFICADOS - ZABBIX LLD"
echo "                OrangeBox.cl | Infraestructura"
echo "============================================================"
echo ""

# Detectar directorio de certificados
detect_cert_dir() {
  echo -e "${BLUE}ℹ Buscando directorio de certificados OpenVPN...${NC}"

  if [ -d "/etc/openvpn/server/easy-rsa/pki/issued" ] && [ "$(ls -A /etc/openvpn/server/easy-rsa/pki/issued/*.crt 2>/dev/null | wc -l)" -gt 0 ]; then
    CERT_DIR="/etc/openvpn/server/easy-rsa/pki/issued"
  elif [ -d "/etc/openvpn/easy-rsa/pki/issued" ] && [ "$(ls -A /etc/openvpn/easy-rsa/pki/issued/*.crt 2>/dev/null | wc -l)" -gt 0 ]; then
    CERT_DIR="/etc/openvpn/easy-rsa/pki/issued"
  elif [ -d "/etc/openvpn/2.0/keys" ] && [ "$(ls -A /etc/openvpn/2.0/keys/*.crt 2>/dev/null | wc -l)" -gt 0 ]; then
    CERT_DIR="/etc/openvpn/2.0/keys"
  else
    echo -e "${RED}✗ ERROR: No se pudo encontrar el directorio de certificados${NC}"
    exit 1
  fi

  echo -e "${GREEN}✓ Directorio encontrado: $CERT_DIR${NC}"
}

# Crear script de descubrimiento LLD
create_discovery_script() {
  echo -e "${BLUE}ℹ Creando script de descubrimiento LLD...${NC}"

  cat >/usr/local/bin/openvpn_cert_discovery.sh <<'EOF'
#!/bin/bash
CERT_DIR="__CERT_DIR__"

echo -n '{"data":['

FIRST=1
for CERT in "$CERT_DIR"/*.crt; do
    [ -f "$CERT" ] || continue
    NAME=$(basename "$CERT" .crt)
    
    if [ $FIRST -eq 0 ]; then
        echo -n ","
    fi
    
    echo -n "{\"{#CERTNAME}\":\"$NAME\"}"
    FIRST=0
done

echo ']}'
EOF

  sed -i "s|__CERT_DIR__|$CERT_DIR|g" /usr/local/bin/openvpn_cert_discovery.sh
  chmod 755 /usr/local/bin/openvpn_cert_discovery.sh
  echo -e "${GREEN}✓ Script de descubrimiento creado${NC}"
}

# Crear script de días restantes por certificado
create_days_script() {
  echo -e "${BLUE}ℹ Creando script de días restantes...${NC}"

  cat >/usr/local/bin/openvpn_cert_days.sh <<'EOF'
#!/bin/bash
CERT="$1"
CERT_FILE="__CERT_DIR__/${CERT}.crt"

[ -f "$CERT_FILE" ] || { echo "0"; exit 1; }

EXPIRY_DATE=$(openssl x509 -enddate -noout -in "$CERT_FILE" 2>/dev/null | cut -d= -f2)

if [ -z "$EXPIRY_DATE" ]; then
    echo "0"
    exit 1
fi

EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s 2>/dev/null)
CURRENT_EPOCH=$(date +%s)
DIFF_DAYS=$(( (EXPIRY_EPOCH - CURRENT_EPOCH) / 86400 ))

echo "$DIFF_DAYS"
exit 0
EOF

  sed -i "s|__CERT_DIR__|$CERT_DIR|g" /usr/local/bin/openvpn_cert_days.sh
  chmod 755 /usr/local/bin/openvpn_cert_days.sh
  echo -e "${GREEN}✓ Script de días restantes creado${NC}"
}

# Crear script de estado global
create_global_script() {
  echo -e "${BLUE}ℹ Creando script de estado global...${NC}"

  cat >/usr/local/bin/check_openvpn_certs_zabbix.sh <<'EOF'
#!/bin/bash
CERT_DIR="__CERT_DIR__"
DAYS_WARNING=30
DAYS_CRITICAL=15
STATUS=0
OUTPUT=""
WARN_COUNT=0
CRIT_COUNT=0

for CERT in "$CERT_DIR"/*.crt; do
    [ -f "$CERT" ] || continue
    CLIENT_NAME=$(basename "$CERT" .crt)
    EXPIRY_DATE=$(openssl x509 -enddate -noout -in "$CERT" 2>/dev/null | cut -d= -f2)
    [ -z "$EXPIRY_DATE" ] && continue
    EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s 2>/dev/null)
    CURRENT_EPOCH=$(date +%s)
    DIFF_DAYS=$(( (EXPIRY_EPOCH - CURRENT_EPOCH) / 86400 ))
    
    if [ "$DIFF_DAYS" -le "$DAYS_CRITICAL" ]; then
        OUTPUT="${OUTPUT}CRITICAL: ${CLIENT_NAME} vence en ${DIFF_DAYS} días\n"
        CRIT_COUNT=$((CRIT_COUNT + 1))
        STATUS=2
    elif [ "$DIFF_DAYS" -le "$DAYS_WARNING" ]; then
        OUTPUT="${OUTPUT}WARNING: ${CLIENT_NAME} vence en ${DIFF_DAYS} días\n"
        WARN_COUNT=$((WARN_COUNT + 1))
        [ "$STATUS" -lt 1 ] && STATUS=1
    else
        OUTPUT="${OUTPUT}OK: ${CLIENT_NAME} vence en ${DIFF_DAYS} días\n"
    fi
done


if [ $STATUS -eq 0 ]; then
    echo "OK: - Todos los certificados estan vigentes"
elif [ $STATUS -eq 1 ]; then
    echo "WARNING: - $WARN_COUNT certificado(s) proximos a vencer"
else
    echo "CRITICAL: - $CRIT_COUNT certificado(s) por vencer"
fi
echo "========================================"
echo -e "$OUTPUT"
echo "========================================"
exit $STATUS
EOF

  sed -i "s|__CERT_DIR__|$CERT_DIR|g" /usr/local/bin/check_openvpn_certs_zabbix.sh
  chmod 755 /usr/local/bin/check_openvpn_certs_zabbix.sh
  echo -e "${GREEN}✓ Script de estado global creado${NC}"
}

# Configurar UserParameters
setup_zabbix_config() {
  echo -e "${BLUE}ℹ Configurando UserParameters...${NC}"

  # Eliminar configuraciones antiguas
  rm -f ${ZABBIX_CONF_DIR}/openvpn*.conf 2>/dev/null

  cat >"$ZABBIX_CONF_FILE" <<'EOF'
# OpenVPN Certificate Monitoring - OrangeBox
# LLD Discovery
UserParameter=openvpn.certs.discovery,/usr/local/bin/openvpn_cert_discovery.sh

# Días restantes por certificado
UserParameter=openvpn.cert.days[*],/usr/local/bin/openvpn_cert_days.sh "$1"

# Estado global
UserParameter=openvpn.certs.check,/usr/local/bin/check_openvpn_certs_zabbix.sh
UserParameter=openvpn.certs.status,/usr/local/bin/check_openvpn_certs_zabbix.sh > /dev/null 2>&1 ; echo $?
UserParameter=openvpn.certs.warning,/usr/local/bin/check_openvpn_certs_zabbix.sh | grep -q "WARNING:" && echo 1 || echo 0
UserParameter=openvpn.certs.critical,/usr/local/bin/check_openvpn_certs_zabbix.sh | grep -q "CRITICAL:" && echo 1 || echo 0
EOF

  chmod 644 "$ZABBIX_CONF_FILE"
  echo -e "${GREEN}✓ Configuración Zabbix creada${NC}"
}

# Configurar permisos
setup_permissions() {
  echo -e "${BLUE}ℹ Configurando permisos...${NC}"

  groupadd -f "$GROUP_NAME"
  usermod -a -G "$GROUP_NAME" "$ZABBIX_USER"

  chgrp -R "$GROUP_NAME" /etc/openvpn 2>/dev/null || true
  find /etc/openvpn -type d -exec chmod 750 {} \; 2>/dev/null || true
  find /etc/openvpn -type f -name "*.crt" -exec chmod 640 {} \; 2>/dev/null || true

  echo -e "${GREEN}✓ Permisos configurados${NC}"
}

# Probar scripts
test_scripts() {
  echo ""
  echo -e "${BLUE}ℹ Probando scripts...${NC}"

  echo -e "\n${YELLOW}1. Script de descubrimiento LLD:${NC}"
  sudo -u "$ZABBIX_USER" /usr/local/bin/openvpn_cert_discovery.sh
  echo ""

  echo -e "\n${YELLOW}2. Script de días restantes (primer certificado):${NC}"
  FIRST_CERT=$(sudo -u "$ZABBIX_USER" /usr/local/bin/openvpn_cert_discovery.sh | grep -o '"{#CERTNAME}":"[^"]*"' | head -1 | cut -d'"' -f4)
  if [ -n "$FIRST_CERT" ]; then
    sudo -u "$ZABBIX_USER" /usr/local/bin/openvpn_cert_days.sh "$FIRST_CERT"
  fi
  echo ""

  echo -e "\n${YELLOW}3. Script de estado global:${NC}"
  sudo -u "$ZABBIX_USER" /usr/local/bin/check_openvpn_certs_zabbix.sh
  echo ""
}

# Reiniciar agente
restart_agent() {
  echo -e "${BLUE}ℹ Reiniciando Zabbix Agent 2...${NC}"
  systemctl restart zabbix-agent2
  echo -e "${GREEN}✓ Zabbix Agent 2 reiniciado${NC}"
}

# Mostrar resumen
show_summary() {
  echo ""
  echo "============================================================"
  echo -e "${GREEN}              INSTALACIÓN COMPLETADA              ${NC}"
  echo "============================================================"
  echo -e "📁 Directorio certificados: ${BLUE}$CERT_DIR${NC}"
  echo -e "👤 Usuario Zabbix: ${BLUE}$ZABBIX_USER${NC}"
  echo -e "👥 Grupo: ${BLUE}$GROUP_NAME${NC}"
  echo ""
  echo -e "📊 Scripts instalados:"
  echo -e "  • ${GREEN}/usr/local/bin/openvpn_cert_discovery.sh${NC} - LLD Discovery"
  echo -e "  • ${GREEN}/usr/local/bin/openvpn_cert_days.sh${NC} - Días por certificado"
  echo -e "  • ${GREEN}/usr/local/bin/check_openvpn_certs_zabbix.sh${NC} - Estado global"
  echo ""
  echo -e "📋 Próximos pasos en Zabbix WEB:"
  echo -e "  1. ${YELLOW}Recopilación de datos → Plantillas${NC}"
  echo -e "  2. ${YELLOW}Crear plantilla${NC} 'Openvpn certs by OrangeBox'"
  echo -e "  3. ${YELLOW}Crear regla LLD${NC} con los datos de abajo"
  echo -e "  4. ${YELLOW}Aplicar plantilla${NC} al host"
  echo "============================================================"
  echo -e "         ${BLUE}OrangeBox.cl - Monitoreo Zabbix${NC}"
  echo "============================================================"
}

# Main
main() {
  detect_cert_dir
  create_discovery_script
  create_days_script
  create_global_script
  setup_zabbix_config
  setup_permissions
  test_scripts
  restart_agent
  show_summary
}

main "$@"
