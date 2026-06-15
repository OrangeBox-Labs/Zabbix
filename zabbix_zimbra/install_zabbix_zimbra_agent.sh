#!/bin/bash
# =============================================================================
# Script: install_zabbix_zimbra_agent.sh
# Autor: Felipe Roman
# Web: https://www.orangebox.cl
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ZIMBRA_HOME="/opt/zimbra"
SCRIPT_DIR="/usr/local/bin"
ZABBIX_ETC="/etc/zabbix"
AGENT2_INCLUDE_DIR="$ZABBIX_ETC/zabbix_agent2.d"
AGENT_INCLUDE_DIR="$ZABBIX_ETC/zabbix_agentd.d"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Instalador de monitoreo Zabbix para Zimbra${NC}"
echo -e "${GREEN}Autor: Felipe Roman - OrangeBox.cl${NC}"
echo -e "${GREEN}========================================${NC}"

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}✗ Ejecutar como root${NC}"
  exit 1
fi

# =============================================================================
# 1. Crear scripts (usando sudo -u zimbra dentro)
# =============================================================================
echo -e "${YELLOW}[1/5] Creando scripts de monitoreo...${NC}"

cat >"$SCRIPT_DIR/zabbix_zimbra_discovery.sh" <<'EOF'
#!/bin/bash
ZIMBRA_STATUS=$(sudo -u zimbra /opt/zimbra/bin/zmcontrol status 2>/dev/null)
NORMALIZED=$(echo "$ZIMBRA_STATUS" | grep -v "^Host" | sed 's/[[:space:]]\+/ /g' | sed 's/^ //g')
SERVICES=$(echo "$NORMALIZED" | awk '{print $1}' | grep -v "^$")
EXCLUDE_LIST="service zimbra zimbraAdmin zimlet"
echo '{"data":['
FIRST=1
for SERVICE in $SERVICES; do
    EXCLUDE=0
    for EX in $EXCLUDE_LIST; do
        [ "$SERVICE" = "$EX" ] && EXCLUDE=1
    done
    echo "$SERVICE" | grep -q "[[:space:]]" && EXCLUDE=1
    if [ $EXCLUDE -eq 0 ]; then
        [ $FIRST -eq 1 ] && FIRST=0 || echo ','
        echo "    {\"{#ZIMBRA_SERVICE}\":\"$SERVICE\"}"
    fi
done
echo ']}'
EOF

cat >"$SCRIPT_DIR/zabbix_zimbra_status.sh" <<'EOF'
#!/bin/bash
SERVICE=$1
[ -z "$SERVICE" ] && { echo "ERROR"; exit 1; }
ZIMBRA_STATUS=$(sudo -u zimbra /opt/zimbra/bin/zmcontrol status 2>/dev/null)
NORMALIZED=$(echo "$ZIMBRA_STATUS" | grep -v "^Host" | sed 's/[[:space:]]\+/ /g' | sed 's/^ //g')
STATUS=$(echo "$NORMALIZED" | grep -E "^${SERVICE} " | awk '{print $NF}')
[ -z "$STATUS" ] && STATUS=$(echo "$NORMALIZED" | grep -i "^${SERVICE}" | awk '{print $NF}')
case "$STATUS" in "Running") echo "1" ;; "Stopped") echo "0" ;; *) echo "-1" ;; esac
EOF

cat >"$SCRIPT_DIR/zabbix_zimbra_queue.sh" <<'EOF'
#!/bin/bash
QUEUE=$(sudo -u zimbra /opt/zimbra/common/sbin/postqueue -p 2>/dev/null)
if echo "$QUEUE" | grep -q "Mail queue is empty"; then echo "0"; else echo "$QUEUE" | grep -c "^[A-F0-9]"; fi
EOF

cat >"$SCRIPT_DIR/zabbix_zimbra_mailstats.sh" <<'EOF'
#!/bin/bash
LOG="/var/log/zimbra.log"
[ ! -f "$LOG" ] && LOG="/opt/zimbra/log/mailbox.log"
[ ! -f "$LOG" ] && { echo "0"; exit 0; }
count() { grep -c "$1" "$LOG" 2>/dev/null; }
case "$1" in
    "sent") count "status=sent" ;;
    "received") count "status=received" ;;
    "spam") count "[Ss]pam" ;;
    "virus") count "[Vv]irus" ;;
    *) echo "{\"sent\":$(count "status=sent"),\"received\":$(count "status=received"),\"spam\":$(count "[Ss]pam"),\"virus\":$(count "[Vv]irus")}" ;;
esac
EOF

cat >"$SCRIPT_DIR/zabbix_zimbra_version.sh" <<'EOF'
#!/bin/bash
VERSION=$(sudo -u zimbra /opt/zimbra/bin/zmcontrol -v 2>/dev/null | grep -oP "release \K[0-9.]+" | head -1)
[ -z "$VERSION" ] && VERSION=$(sudo -u zimbra /opt/zimbra/bin/zmcontrol -v 2>/dev/null | grep -oP "\d+\.\d+\.\d+" | head -1)
echo "${VERSION:-0}"
EOF

cat >"$SCRIPT_DIR/zabbix_zimbra_extra.sh" <<'EOF'
#!/bin/bash
case "$1" in
    "mailbox_size")   du -sb /opt/zimbra/store 2>/dev/null | awk '{print $1}' || echo "0" ;;
    "index_size")     du -sb /opt/zimbra/index 2>/dev/null | awk '{print $1}' || echo "0" ;;
    "db_size")        sudo -u zimbra mysql -N -e "SELECT sum(data_length+index_length)/1024/1024 FROM information_schema.tables WHERE table_schema='zimbra';" 2>/dev/null | cut -d. -f1 || echo "0" ;;
    "accounts_count") sudo -u zimbra /opt/zimbra/bin/zmprov gaaa 2>/dev/null | wc -l || echo "0" ;;
    "domains_count")  sudo -u zimbra /opt/zimbra/bin/zmprov gad 2>/dev/null | wc -l || echo "0" ;;
    *) echo "0" ;;
esac
EOF

chmod 755 "$SCRIPT_DIR"/zabbix_zimbra_*.sh
echo -e "${GREEN}✓ Scripts creados${NC}"

# =============================================================================
# 2. Crear directorios include
# =============================================================================
echo -e "${YELLOW}[2/5] Creando directorios...${NC}"
mkdir -p "$AGENT2_INCLUDE_DIR" "$AGENT_INCLUDE_DIR"

# =============================================================================
# 3. Crear UserParameters
# =============================================================================
echo -e "${YELLOW}[3/5] Creando UserParameters...${NC}"

TARGET_DIR="$AGENT2_INCLUDE_DIR"
[ -f "/etc/zabbix/zabbix_agentd.conf" ] && TARGET_DIR="$AGENT_INCLUDE_DIR"

cat >"$TARGET_DIR/zabbix_zimbra.conf" <<'EOF'
UserParameter=zimbra.discovery, /usr/local/bin/zabbix_zimbra_discovery.sh
UserParameter=zimbra.service.status[*], /usr/local/bin/zabbix_zimbra_status.sh "$1"
UserParameter=zimbra.queue, /usr/local/bin/zabbix_zimbra_queue.sh
UserParameter=zimbra.mailstats.sent, /usr/local/bin/zabbix_zimbra_mailstats.sh sent
UserParameter=zimbra.mailstats.received, /usr/local/bin/zabbix_zimbra_mailstats.sh received
UserParameter=zimbra.mailstats.spam, /usr/local/bin/zabbix_zimbra_mailstats.sh spam
UserParameter=zimbra.mailstats.virus, /usr/local/bin/zabbix_zimbra_mailstats.sh virus
UserParameter=zimbra.version, /usr/local/bin/zabbix_zimbra_version.sh
UserParameter=zimbra.extra[*], /usr/local/bin/zabbix_zimbra_extra.sh "$1"
EOF

echo -e "${GREEN}✓ UserParameters creados${NC}"

# =============================================================================
# 4. Configurar sudoers (CORRECTO)
# =============================================================================
echo -e "${YELLOW}[4/5] Configurando sudoers...${NC}"

cat >"/etc/sudoers.d/zabbix_zimbra" <<EOF
# Permisos para monitoreo Zimbra - zabbix puede ejecutar comandos como zimbra
zabbix ALL=(zimbra) NOPASSWD: /opt/zimbra/bin/zmcontrol status
zabbix ALL=(zimbra) NOPASSWD: /opt/zimbra/bin/zmcontrol -v
zabbix ALL=(zimbra) NOPASSWD: /opt/zimbra/common/sbin/postqueue -p
zabbix ALL=(zimbra) NOPASSWD: /opt/zimbra/bin/zmprov gaaa
zabbix ALL=(zimbra) NOPASSWD: /opt/zimbra/bin/zmprov gad
zabbix ALL=(zimbra) NOPASSWD: /usr/bin/mysql
zabbix ALL=(zimbra) NOPASSWD: /usr/local/bin/zabbix_zimbra_*.sh

Defaults:zabbix !requiretty
EOF

chmod 440 "/etc/sudoers.d/zabbix_zimbra"
visudo -c -f "/etc/sudoers.d/zabbix_zimbra"
echo -e "${GREEN}✓ Sudoers configurado${NC}"

# =============================================================================
# 5. Reiniciar servicios
# =============================================================================
echo -e "${YELLOW}[5/5] Reiniciando Zabbix agent...${NC}"

systemctl restart zabbix-agent2 2>/dev/null && echo -e "${GREEN}✓ Zabbix Agent 2 reiniciado${NC}"
systemctl restart zabbix-agent 2>/dev/null && echo -e "${GREEN}✓ Zabbix Agent reiniciado${NC}"
systemctl restart zabbix-agentd 2>/dev/null && echo -e "${GREEN}✓ Zabbix Agent (daemon) reiniciado${NC}"

# =============================================================================
# Resumen
# =============================================================================
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}¡Instalación completada!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Autor: Felipe Roman - OrangeBox.cl${NC}"
echo ""
echo -e "${BLUE}Probar como usuario zabbix:${NC}"
echo -e "  sudo -u zabbix /usr/local/bin/zabbix_zimbra_discovery.sh"
echo -e "  sudo -u zabbix /usr/local/bin/zabbix_zimbra_status.sh antivirus"
echo ""
echo -e "${GREEN}========================================${NC}"
