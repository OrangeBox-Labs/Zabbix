zabbix_psk_get.sh
#!/bin/bash
# zabbix_get_psk.sh - Consulta cualquier host con PSK automáticamente

TEMP_PSK="/tmp/psk_$$.key"

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Si se pasa un argumento, usarlo como host
if [ -n "$1" ]; then
  HOST="$1"
else
  clear
  echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
  echo -e "${BLUE}     🚀 Zabbix PSK Get${NC}"
  echo -e "${BLUE}════════════════════════════════════════════════════════${NC}\n"

  # Mostrar hosts disponibles
  echo -e "${GREEN}📋 Hosts con PSK configurado:${NC}"
  mysql -uzabbix -D zabbix -sN -e "
    SELECT CONCAT('   • ', host, ' → ', tls_psk_identity)
    FROM hosts 
    WHERE tls_psk_identity IS NOT NULL 
      AND tls_psk_identity != ''
    ORDER BY host;"

  echo ""
  read -p "➤ Ingresa IP o hostname: " HOST
fi

if [ -z "$HOST" ]; then
  echo -e "${RED}❌ Host no puede estar vacío${NC}"
  exit 1
fi

# Buscar en MySQL
MYSQL_RESULT=$(mysql -uzabbix -D zabbix -sN -e "
SELECT 
    h.host,
    COALESCE(i.ip, h.host) as target_ip,
    h.tls_psk_identity,
    h.tls_psk
FROM hosts h
LEFT JOIN interface i ON h.hostid = i.hostid AND i.main = 1
WHERE h.host = '$HOST' 
   OR h.host LIKE '%$HOST%'
   OR i.ip = '$HOST'
LIMIT 1;")

if [ -z "$MYSQL_RESULT" ]; then
  echo -e "${RED}❌ No se encontró el host '$HOST'${NC}"
  exit 1
fi

HOST_NAME=$(echo "$MYSQL_RESULT" | awk '{print $1}')
TARGET_IP=$(echo "$MYSQL_RESULT" | awk '{print $2}')
PSK_ID=$(echo "$MYSQL_RESULT" | awk '{print $3}')
PSK_KEY=$(echo "$MYSQL_RESULT" | awk '{print $4}')

echo -e "${GREEN}✅ Host: $HOST_NAME ($TARGET_IP)${NC}"
echo -e "${GREEN}✅ PSK Identity: $PSK_ID${NC}"

# Crear archivo PSK
echo "$PSK_KEY" >"$TEMP_PSK"
chmod 600 "$TEMP_PSK"

# Si hay segundo argumento, usarlo como key
if [ -n "$2" ]; then
  ZBX_KEY="$2"
else
  echo ""
  echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
  read -p "➤ Key a consultar [agent.variant]: " ZBX_KEY
  ZBX_KEY=${ZBX_KEY:-agent.variant}
fi

read -p "➤ Puerto [10050]: " ZBX_PORT
ZBX_PORT=${ZBX_PORT:-10050}

echo ""
echo -e "${BLUE}📡 Consultando: $ZBX_KEY${NC}"
echo ""

# Ejecutar
RESULT=$(zabbix_get -s "$TARGET_IP" \
  -p "$ZBX_PORT" \
  -k "$ZBX_KEY" \
  --tls-connect=psk \
  --tls-psk-identity="$PSK_ID" \
  --tls-psk-file="$TEMP_PSK" \
  2>&1)

if [ $? -eq 0 ]; then
  echo -e "${GREEN}✅ Resultado:${NC} $RESULT"
else
  echo -e "${RED}❌ Error:${NC} $RESULT"
fi

rm -f "$TEMP_PSK"
