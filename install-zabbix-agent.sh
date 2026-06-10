#!/bin/bash

# ==============================================
# Script: install-zabbix-agent.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Instalacion de Zabbix Agent 7.4 en host remoto
#              con registro automatico via API y TLS/PSK
# ==============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ==============================================
# VARIABLES EDITABLES (cambiar antes de ejecutar)
# ==============================================

# Token de API de Zabbix (dejar vacio para preguntar)
API_TOKEN="b416db4bb91c549b20ac6b22c2b1303429855cd98968130b2393b3ce54e3e7fe"

# Servidor Zabbix (dejar vacio para preguntar)
ZABBIX_SERVER="monitoreo.orangebox.cl"

# Puerto del servidor Zabbix (default: 10051)
ZABBIX_SERVER_PORT="10051"

# Puerto del agente Zabbix (default: 10050)
ZABBIX_AGENT_PORT="10050"

# ID del grupo en Zabbix (2 = Linux Servers)
GROUP_ID="2"

# ID de la plantilla (10001 = Template OS Linux by Zabbix agent)
TEMPLATE_ID="10001"

# URL API personalizada (dejar vacia para que se construya según modo)
ZABBIX_API_URL=""

# ==============================================
# MODO DEBUG (false = desactivado, true = activado)
# ==============================================
DEBUG_MODE=false

# ==============================================
# FUNCIONES DE AYUDA
# ==============================================

show_help() {
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  Script: install-zabbix-agent.sh${NC}"
  echo -e "${GREEN}  Instalador de Agente Zabbix 7.4${NC}"
  echo -e "${GREEN}============================================${NC}\n"

  echo -e "${YELLOW}DESCRIPCIÓN:${NC}"
  echo -e "  Instala Zabbix Agent 7.4, configura TLS/PSK y registra via API\n"

  echo -e "${YELLOW}MODOS DE EJECUCIÓN:${NC}"
  echo -e "  ${GREEN}--lan${NC}      - Modo Red Local (HTTP + /zabbix)"
  echo -e "  ${GREEN}--wan${NC}      - Modo Internet (HTTPS + sin /zabbix)"
  echo -e "  ${GREEN}--url URL${NC}  - URL personalizada de la API\n"

  echo -e "${YELLOW}OPCIONES:${NC}"
  echo -e "  ${GREEN}--auto${NC}     - Modo automático (no pregunta nada)"
  echo -e "  ${GREEN}--debug${NC}    - Modo debug (muestra peticiones API)"
  echo -e "  ${GREEN}--help${NC}     - Mostrar esta ayuda\n"

  echo -e "${YELLOW}EJEMPLOS:${NC}"
  echo -e "  ${GREEN}./install-zabbix-agent.sh --lan --auto${NC}\n"
  echo -e "  ${GREEN}./install-zabbix-agent.sh --wan --debug${NC}\n"

  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  🌐 https://www.orangebox.cl${NC}"
  echo -e "${GREEN}============================================${NC}"
}

log_info() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_step() { echo -e "\n${BLUE}[*]${NC} $1"; }
log_debug() { [ "$DEBUG_MODE" = true ] && echo -e "${CYAN}[DEBUG]${NC} $1"; }

check_root() {
  if [ "$EUID" -ne 0 ]; then
    log_error "Este script debe ejecutarse como root"
    exit 1
  fi
}

get_public_ip() {
  log_step "Detectando IP pública del agente..."
  PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null)
  [ -z "$PUBLIC_IP" ] && PUBLIC_IP=$(curl -s --max-time 5 https://icanhazip.com 2>/dev/null | tr -d ' ')
  [ -z "$PUBLIC_IP" ] && PUBLIC_IP=$(curl -s --max-time 5 https://ifconfig.me/ip 2>/dev/null)

  if [ -n "$PUBLIC_IP" ]; then
    log_info "IP Pública detectada: $PUBLIC_IP"
  else
    log_warn "No se pudo detectar IP pública"
    read -p "Ingrese la IP pública manualmente: " PUBLIC_IP
  fi
}

get_local_ip() {
  log_step "Detectando IP local del agente..."
  LOCAL_IP=$(hostname -I | awk '{print $1}')
  if [ -n "$LOCAL_IP" ]; then
    log_info "IP Local detectada: $LOCAL_IP"
  else
    log_error "No se pudo detectar IP local"
    exit 1
  fi
}

get_server_info() {
  if [ -z "$ZABBIX_SERVER" ]; then
    read -p "Ingrese el servidor Zabbix: " ZABBIX_SERVER
  fi
  if [ -z "$API_TOKEN" ]; then
    read -p "Ingrese el token API: " API_TOKEN
  fi
  log_info "Servidor: $ZABBIX_SERVER"
}

detect_os() {
  log_step "Detectando sistema operativo..."
  . /etc/os-release
  OS=$ID
  VER=$VERSION_ID
  log_info "Sistema: $NAME $VERSION_ID"

  case $OS in
  centos | rhel | almalinux | rocky | fedora | amzn | ol) OS_FAMILY="rhel" ;;
  debian | ubuntu | raspbian | linuxmint) OS_FAMILY="debian" ;;
  suse | opensuse | sles) OS_FAMILY="suse" ;;
  *) OS_FAMILY="unknown" ;;
  esac
}

install_dependencies() {
  log_step "Instalando dependencias..."
  case $OS_FAMILY in
  rhel) dnf install -y curl openssl net-tools jq >>/tmp/zabbix_agent_install.log 2>&1 ;;
  debian) apt-get update -qq && apt-get install -y curl openssl net-tools jq >>/tmp/zabbix_agent_install.log 2>&1 ;;
  suse) zypper install -y curl openssl net-tools jq >>/tmp/zabbix_agent_install.log 2>&1 ;;
  esac
  log_info "Dependencias instaladas"
}

disable_epel_conflict() {
  log_step "Deshabilitando conflicto con EPEL..."

  # Excluir zabbix de EPEL para que no interfiera
  if [ -f /etc/yum.repos.d/epel.repo ]; then
    if ! grep -q "excludepkgs=zabbix" /etc/yum.repos.d/epel.repo; then
      sed -i '/^\[epel\]/a excludepkgs=zabbix*' /etc/yum.repos.d/epel.repo
      log_info "EPEL configurado para excluir zabbix"
    else
      log_info "EPEL ya excluye zabbix"
    fi
  fi

  # Backup temporal de EPEL durante la instalación
  if [ -f /etc/yum.repos.d/epel.repo ]; then
    mv /etc/yum.repos.d/epel.repo /etc/yum.repos.d/epel.repo.bak 2>/dev/null
    log_debug "EPEL temporalmente deshabilitado"
  fi
}

restore_epel() {
  if [ -f /etc/yum.repos.d/epel.repo.bak ]; then
    mv /etc/yum.repos.d/epel.repo.bak /etc/yum.repos.d/epel.repo 2>/dev/null
    log_debug "EPEL restaurado"
  fi
}

install_zabbix_repo() {
  log_step "Configurando repositorio Zabbix 7.4..."

  case $OS_FAMILY in
  rhel)
    case $VER in
    10*) ZBX_REPO_VERSION="10" ;;
    9*) ZBX_REPO_VERSION="9" ;;
    8*) ZBX_REPO_VERSION="8" ;;
    7*) ZBX_REPO_VERSION="7" ;;
    *) ZBX_REPO_VERSION="9" ;;
    esac

    # Limpiar repositorios viejos
    rm -f /etc/yum.repos.d/zabbix.repo
    dnf clean all >>/tmp/zabbix_agent_install.log 2>&1

    # Instalar repo 7.4 (sin fallback a versiones antiguas)
    rpm -Uvh "https://repo.zabbix.com/zabbix/7.4/rhel/${ZBX_REPO_VERSION}/x86_64/zabbix-release-7.4-1.el${ZBX_REPO_VERSION}.noarch.rpm" >>/tmp/zabbix_agent_install.log 2>&1
    ;;
  debian)
    local DEB_VERSION=""
    case $OS in
    ubuntu)
      case $VER in
      24.04*) DEB_VERSION="noble" ;;
      22.04*) DEB_VERSION="jammy" ;;
      20.04*) DEB_VERSION="focal" ;;
      *) DEB_VERSION="jammy" ;;
      esac
      ;;
    debian)
      case $VER in
      12*) DEB_VERSION="bookworm" ;;
      11*) DEB_VERSION="bullseye" ;;
      *) DEB_VERSION="bookworm" ;;
      esac
      ;;
    esac
    wget -q "https://repo.zabbix.com/zabbix/7.4/debian/pool/main/z/zabbix-release/zabbix-release_latest_7.4+${DEB_VERSION}_all.deb" -O /tmp/zabbix-release.deb >>/tmp/zabbix_agent_install.log 2>&1
    dpkg -i /tmp/zabbix-release.deb >>/tmp/zabbix_agent_install.log 2>&1
    apt-get update -qq >>/tmp/zabbix_agent_install.log 2>&1
    ;;
  esac

  log_info "Repositorio Zabbix 7.4 configurado"
}

install_agent() {
  log_step "Instalando Zabbix Agent 7.4..."

  case $OS_FAMILY in
  rhel)
    # Deshabilitar EPEL temporalmente para forzar instalación desde repo Zabbix
    dnf --disablerepo=epel install -y zabbix-agent >>/tmp/zabbix_agent_install.log 2>&1
    ;;
  debian)
    apt-get install -y zabbix-agent >>/tmp/zabbix_agent_install.log 2>&1
    ;;
  suse)
    zypper install -y zabbix-agent >>/tmp/zabbix_agent_install.log 2>&1
    ;;
  esac

  # Verificar versión
  AGENT_VERSION=$(zabbix_agentd --version | head -1 | grep -o '[0-9]\.[0-9]*\.[0-9]*')
  if [[ "$AGENT_VERSION" == 7.4* ]]; then
    log_info "Zabbix Agent $AGENT_VERSION instalado"
  else
    log_error "Se instaló versión $AGENT_VERSION, se esperaba 7.4"
    log_info "Forzando instalación manual desde RPM..."
    cd /tmp
    wget -q "https://repo.zabbix.com/zabbix/7.4/rhel/9/x86_64/zabbix-agent-7.4.11-1.el9.x86_64.rpm"
    dnf install -y ./zabbix-agent-7.4.11-1.el9.x86_64.rpm >>/tmp/zabbix_agent_install.log 2>&1
    cd -
  fi

  AGENT_TYPE="zabbix_agentd"
  AGENT_SERVICE="zabbix-agent"
  log_info "Agente instalado: $AGENT_TYPE"
}

generate_psk() {
  log_step "Generando PSK para TLS..."
  mkdir -p /etc/zabbix/ssl
  PSK_KEY=$(openssl rand -hex 32)
  PSK_IDENTITY="${HOSTNAME}_psk_$(date +%s)"
  echo -n "$PSK_KEY" >/etc/zabbix/ssl/psk.key
  chown -R zabbix:zabbix /etc/zabbix/ssl
  chmod 600 /etc/zabbix/ssl/psk.key
  log_info "PSK generado: $PSK_IDENTITY"
}

configure_agent() {
  log_step "Configurando Zabbix Agent..."

  cat >/etc/zabbix/zabbix_agentd.conf <<EOF
Server=${ZABBIX_SERVER}
ServerActive=${ZABBIX_SERVER}:${ZABBIX_SERVER_PORT}
Hostname=${HOSTNAME}
ListenPort=${ZABBIX_AGENT_PORT}
ListenIP=0.0.0.0
StartAgents=3
LogFile=/var/log/zabbix/zabbix_agentd.log
LogFileSize=10
DebugLevel=3
Timeout=30

# TLS/PSK - Conexión segura
TLSConnect=psk
TLSAccept=psk
TLSPSKIdentity=${PSK_IDENTITY}
TLSPSKFile=/etc/zabbix/ssl/psk.key
EOF

  chown root:zabbix /etc/zabbix/zabbix_agentd.conf
  chmod 640 /etc/zabbix/zabbix_agentd.conf
  log_info "Agente configurado con TLS/PSK"
}

configure_firewall() {
  log_step "Configurando firewall..."
  if command -v firewall-cmd &>/dev/null; then
    firewall-cmd --permanent --add-port=${ZABBIX_AGENT_PORT}/tcp >>/tmp/zabbix_agent_install.log 2>&1
    firewall-cmd --reload >>/tmp/zabbix_agent_install.log 2>&1
    log_info "Puerto ${ZABBIX_AGENT_PORT}/tcp abierto"
  elif command -v ufw &>/dev/null; then
    ufw allow ${ZABBIX_AGENT_PORT}/tcp >>/tmp/zabbix_agent_install.log 2>&1
    log_info "Puerto ${ZABBIX_AGENT_PORT}/tcp abierto"
  else
    log_warn "Firewall no detectado, configure manualmente el puerto ${ZABBIX_AGENT_PORT}"
  fi
}

test_api_connection() {
  log_step "Probando conexión a la API de Zabbix..."
  local JSON_PAYLOAD='{"jsonrpc":"2.0","method":"apiinfo.version","params":[],"id":1}'
  local RESPONSE=$(curl -s -k -X POST -H "Content-Type: application/json-rpc" -d "$JSON_PAYLOAD" "${ZABBIX_API_URL}")

  if echo "$RESPONSE" | grep -q '"result"'; then
    log_info "API accesible"
    return 0
  else
    log_error "No se pudo conectar a la API: $ZABBIX_API_URL"
    return 1
  fi
}

register_host() {
  log_step "Registrando host en Zabbix via API..."

  local JSON_PAYLOAD=$(
    cat <<EOF
{
    "jsonrpc": "2.0",
    "method": "host.create",
    "params": {
        "host": "${HOSTNAME}",
        "name": "${HOSTNAME}",
        "groups": [{"groupid": "${GROUP_ID}"}],
        "templates": [{"templateid": "${TEMPLATE_ID}"}],
        "interfaces": [{
            "type": 1,
            "main": 1,
            "useip": 1,
            "ip": "${AGENT_IP}",
            "dns": "${HOSTNAME}",
            "port": "${ZABBIX_AGENT_PORT}"
        }],
        "tls_connect": 2,
        "tls_accept": 2,
        "tls_psk_identity": "${PSK_IDENTITY}",
        "tls_psk": "${PSK_KEY}"
    },
    "id": 1
}
EOF
  )

  local RESPONSE=$(curl -s -k -X POST \
    -H "Content-Type: application/json-rpc" \
    -H "Authorization: Bearer ${API_TOKEN}" \
    -d "$JSON_PAYLOAD" \
    "${ZABBIX_API_URL}")

  if echo "$RESPONSE" | grep -q '"hostids"'; then
    log_info "Host '${HOSTNAME}' registrado con TLS/PSK"
  else
    log_error "Error al registrar host: $RESPONSE"
    exit 1
  fi
}

start_agent() {
  log_step "Iniciando servicio del agente..."
  systemctl enable "$AGENT_SERVICE" >>/tmp/zabbix_agent_install.log 2>&1
  systemctl restart "$AGENT_SERVICE" >>/tmp/zabbix_agent_install.log 2>&1

  if systemctl is-active "$AGENT_SERVICE" &>/dev/null; then
    log_info "Agente iniciado correctamente"
  else
    log_error "Error al iniciar agente"
    systemctl status "$AGENT_SERVICE" --no-pager
    exit 1
  fi
}

verify_connection() {
  log_step "Verificando conexión TLS desde el servidor..."
  echo -n "${PSK_KEY}" >/tmp/psk_test.key
  log_info "Desde el servidor Zabbix, ejecute:"
  echo -e "${YELLOW}  zabbix_get -s ${AGENT_IP} -p ${ZABBIX_AGENT_PORT} -k system.hostname \\"
  echo -e "    --tls-connect psk \\"
  echo -e "    --tls-psk-identity \"${PSK_IDENTITY}\" \\"
  echo -e "    --tls-psk-file /tmp/psk_test.key${NC}"
}

save_credentials() {
  local CRED_FILE="/root/zabbix_agent_$(date +%Y%m%d_%H%M%S).txt"
  cat >"$CRED_FILE" <<EOF
=============================================
  ZABBIX AGENT - CREDENCIALES
=============================================

Host: ${HOSTNAME}
IP: ${AGENT_IP}
Servidor: ${ZABBIX_SERVER}

🔐 TLS/PSK:
  Identity: ${PSK_IDENTITY}
  Key: ${PSK_KEY}
  Archivo: /etc/zabbix/ssl/psk.key

📋 Comandos útiles:
  systemctl status ${AGENT_SERVICE}
  tail -f /var/log/zabbix/zabbix_agentd.log

=============================================
EOF
  chmod 600 "$CRED_FILE"
  log_info "Credenciales guardadas: $CRED_FILE"
}

show_completion() {
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  INSTALACION COMPLETADA${NC}"
  echo -e "${GREEN}============================================${NC}\n"
  echo -e "${YELLOW}📋 RESUMEN:${NC}"
  echo -e "  • Hostname: ${GREEN}${HOSTNAME}${NC}"
  echo -e "  • IP: ${GREEN}${AGENT_IP}${NC}"
  echo -e "  • Servidor: ${GREEN}${ZABBIX_SERVER}:${ZABBIX_SERVER_PORT}${NC}"
  echo -e "  • TLS/PSK: ${GREEN}Habilitado${NC}"
  echo -e "\n${GREEN}============================================${NC}\n"
}

# ==============================================
# MAIN
# ==============================================

MODE=""
AUTO_MODE=false
CUSTOM_URL=""

while [[ $# -gt 0 ]]; do
  case $1 in
  --lan)
    MODE="lan"
    shift
    ;;
  --wan)
    MODE="wan"
    shift
    ;;
  --url)
    CUSTOM_URL="$2"
    shift 2
    ;;
  --auto)
    AUTO_MODE=true
    shift
    ;;
  --debug)
    DEBUG_MODE=true
    shift
    ;;
  --help | -h)
    show_help
    exit 0
    ;;
  *)
    log_error "Opción desconocida: $1"
    exit 1
    ;;
  esac
done

clear
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Instalador de Agente Zabbix 7.4${NC}"
echo -e "${GREEN}  con TLS/PSK y registro automático${NC}"
echo -e "${GREEN}============================================${NC}\n"

check_root

# Configurar según modo
if [ -n "$CUSTOM_URL" ]; then
  ZABBIX_API_URL="$CUSTOM_URL"
  MODE_NAME="Personalizado"
  get_local_ip
  AGENT_IP="$LOCAL_IP"
elif [ "$MODE" = "lan" ]; then
  ZABBIX_API_URL="http://${ZABBIX_SERVER}/zabbix/api_jsonrpc.php"
  MODE_NAME="LAN"
  get_local_ip
  AGENT_IP="$LOCAL_IP"
elif [ "$MODE" = "wan" ]; then
  ZABBIX_API_URL="https://${ZABBIX_SERVER}/api_jsonrpc.php"
  MODE_NAME="WAN"
  get_public_ip
  AGENT_IP="$PUBLIC_IP"
else
  echo -e "${YELLOW}Seleccione modo: 1) LAN 2) WAN 3) URL personalizada${NC}"
  read -p "Opción: " mode_opt
  case $mode_opt in
  1)
    ZABBIX_API_URL="http://${ZABBIX_SERVER}/zabbix/api_jsonrpc.php"
    get_local_ip
    AGENT_IP="$LOCAL_IP"
    ;;
  2)
    ZABBIX_API_URL="https://${ZABBIX_SERVER}/api_jsonrpc.php"
    get_public_ip
    AGENT_IP="$PUBLIC_IP"
    ;;
  3)
    read -p "URL API: " ZABBIX_API_URL
    get_local_ip
    AGENT_IP="$LOCAL_IP"
    ;;
  esac
fi

# Obtener credenciales
if [ "$AUTO_MODE" = false ]; then
  get_server_info
else
  [ -z "$API_TOKEN" ] && log_error "Modo automático requiere API_TOKEN" && exit 1
  [ -z "$ZABBIX_SERVER" ] && log_error "Modo automático requiere ZABBIX_SERVER" && exit 1
fi

HOSTNAME=$(hostname -f 2>/dev/null || hostname)

# Instalación
detect_os
install_dependencies
disable_epel_conflict
install_zabbix_repo
install_agent
restore_epel
generate_psk
configure_agent
configure_firewall
test_api_connection
register_host
start_agent
save_credentials
verify_connection
show_completion
