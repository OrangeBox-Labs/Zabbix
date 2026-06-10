#!/bin/bash
# ==============================================
# Script: install-zabbix-agent-secure.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Instalacion de Zabbix Agent con PSK unica
#              Registro automatico via API usando API Token
#              Compatible con RHEL/AlmaLinux/Rocky 8/9/10
# ==============================================

# ==============================================
# CONFIGURACION (EDITAR AQUI)
# ==============================================
ZABBIX_SERVER="monitoreo.orangebox.cl"
ZABBIX_SERVER_PORT="10051"
ZABBIX_API_URL="https://${ZABBIX_SERVER}/api_jsonrpc.php"
API_TOKEN="aea418dfd357074b808e151b5d23a47d14f8290642f0984101a75e3654355408"
TEMPLATE_ID="10343" # Linux by Zabbix agent active
GROUP_ID="2"        # Linux servers

# ==============================================
# COLORES
# ==============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ==============================================
# VARIABLES
# ==============================================
LOG_FILE="/root/zabbix-agent-install.log"
HOSTNAME=$(hostname)
HOST_IP=$(hostname -I | awk '{print $1}')
PSK_IDENTITY="${HOSTNAME}_psk_$(date +%s)"
PSK_KEY=$(openssl rand -hex 32)
SERVICE_NAME=""
CONFIG_FILE=""

# ==============================================
# FUNCIONES
# ==============================================
log() {
  echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
  echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"
}

log_step() {
  echo -e "\n${BLUE}[*]${NC} $1" | tee -a "$LOG_FILE"
}

detect_os() {
  if [ -f /etc/redhat-release ]; then
    OS_FAMILY="rhel"
    OS_VERSION=$(rpm -q --qf "%{VERSION}" $(rpm -q --whatprovides redhat-release) 2>/dev/null | cut -d: -f1 | cut -d. -f1)
    log "Sistema RHEL/AlmaLinux/Rocky detectado (version $OS_VERSION)"
  else
    log_error "Sistema operativo no soportado"
    exit 1
  fi
}

detect_zabbix_agent() {
  log_step "Detectando paquete Zabbix Agent disponible..."

  local PACKAGES=("zabbix-agent2" "zabbix7.0-agent" "zabbix-agent")

  for pkg in "${PACKAGES[@]}"; do
    if dnf list available "$pkg" &>/dev/null; then
      INSTALLED_PACKAGE="$pkg"
      log "Paquete disponible: $pkg"
      return 0
    fi
  done

  log_error "No se encontro paquete Zabbix Agent"
  exit 1
}

install_agent() {
  log_step "Instalando $INSTALLED_PACKAGE..."

  if [[ "$INSTALLED_PACKAGE" == *"agent2"* ]]; then
    SERVICE_NAME="zabbix-agent2"
    CONFIG_FILE="/etc/zabbix/zabbix_agent2.conf"
  else
    SERVICE_NAME="zabbix-agent"
    CONFIG_FILE="/etc/zabbix/zabbix_agentd.conf"
  fi

  dnf install -y "$INSTALLED_PACKAGE" >>"$LOG_FILE" 2>&1
  log "$INSTALLED_PACKAGE instalado"
}

configure_psk() {
  log_step "Configurando PSK..."

  mkdir -p /etc/zabbix
  echo "$PSK_KEY" >/etc/zabbix/zabbix_agentd.psk
  chmod 400 /etc/zabbix/zabbix_agentd.psk
  chown zabbix:zabbix /etc/zabbix/zabbix_agentd.psk 2>/dev/null
  log "Archivo PSK creado"
}

configure_agent() {
  log_step "Configurando agente..."

  cat >"$CONFIG_FILE" <<EOF
Server=127.0.0.1
ServerActive=${ZABBIX_SERVER}:${ZABBIX_SERVER_PORT}
Hostname=${HOSTNAME}

TLSConnect=psk
TLSAccept=psk
TLSPSKIdentity=${PSK_IDENTITY}
TLSPSKFile=/etc/zabbix/zabbix_agentd.psk

StartAgents=0
Timeout=30
LogFile=/var/log/zabbix/zabbix_agentd.log
LogFileSize=10
DebugLevel=3
EOF

  log "Configuracion creada en $CONFIG_FILE"
}

start_agent() {
  log_step "Iniciando agente..."

  systemctl restart "$SERVICE_NAME"
  systemctl enable "$SERVICE_NAME"

  if systemctl is-active --quiet "$SERVICE_NAME"; then
    log "Agente corriendo"
  else
    log_error "Error al iniciar agente"
    exit 1
  fi
}

register_host() {
  log_step "Registrando host en Zabbix via API..."

  RESPONSE=$(curl -s -k -X POST \
    -H "Content-Type: application/json-rpc" \
    -H "Authorization: Bearer ${API_TOKEN}" \
    -d '{
            "jsonrpc": "2.0",
            "method": "host.create",
            "params": {
                "host": "'"${HOSTNAME}"'",
                "name": "'"${HOSTNAME}"'",
                "groups": [{"groupid": "'"${GROUP_ID}"'"}],
                "templates": [{"templateid": "'"${TEMPLATE_ID}"'"}],
                "interfaces": [{
                    "type": 1,
                    "main": 1,
                    "useip": 1,
                    "ip": "'"${HOST_IP}"'",
                    "dns": "",
                    "port": "10050"
                }],
                "tls_connect": 2,
                "tls_accept": 2,
                "tls_psk_identity": "'"${PSK_IDENTITY}"'",
                "tls_psk": "'"${PSK_KEY}"'"
            },
            "id": 1
        }' ${ZABBIX_API_URL})

  if echo "$RESPONSE" | grep -q "hostids"; then
    log "Host registrado exitosamente"
  else
    log_error "Error al registrar host: $RESPONSE"
  fi
}

save_credentials() {
  CRED_FILE="/root/zabbix_agent_${HOSTNAME}_credentials.txt"
  cat >"$CRED_FILE" <<EOF
=============================================
ZABBIX AGENT CREDENCIALES
=============================================
Hostname: $HOSTNAME
IP: $HOST_IP
Servidor: $ZABBIX_SERVER
PSK Identity: $PSK_IDENTITY
PSK Key: $PSK_KEY
=============================================
EOF
  chmod 600 "$CRED_FILE"
  log "Credenciales guardadas en: $CRED_FILE"
}

show_summary() {
  echo ""
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  ZABBIX AGENT INSTALADO CORRECTAMENTE${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo ""
  echo "Hostname: $HOSTNAME"
  echo "IP: $HOST_IP"
  echo "Servidor: $ZABBIX_SERVER"
  echo "PSK Identity: $PSK_IDENTITY"
  echo ""
  echo "Credenciales: $CRED_FILE"
  echo "Log: $LOG_FILE"
  echo ""
  echo -e "${GREEN}============================================${NC}"
}

# ==============================================
# MAIN
# ==============================================
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  ZABBIX AGENT SECURE INSTALLER${NC}"
echo -e "${GREEN}============================================${NC}\n"

detect_os
detect_zabbix_agent
install_agent
configure_psk
configure_agent
start_agent
register_host
save_credentials
show_summary
