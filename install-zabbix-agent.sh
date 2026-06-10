#!/bin/bash

# ==============================================
# Script: install-zabbix-agent.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Instalacion de Zabbix Agent en host remoto
#              con registro automatico via API
#              Soporta LAN (red local) y WAN (internet)
#              Conexion TLS/PSK segura
# ==============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
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

# Modo TLS (psk = solo PSK, cert = solo certificados, psk_cert = ambos)
TLS_MODE="psk"

# ==============================================
# URLS DE API POR MODO (NO EDITAR DIRECTAMENTE)
# ==============================================
# Estas se construyen automáticamente según el modo
# LAN: http://${ZABBIX_SERVER}/zabbix/api_jsonrpc.php
# WAN: https://${ZABBIX_SERVER}/api_jsonrpc.php
# Si quieres una URL personalizada, edita ZABBIX_API_URL directamente
# ==============================================

# URL personalizada (si está vacía, se construye según el modo)
ZABBIX_API_URL=""

# ==============================================
# FUNCIONES DE AYUDA
# ==============================================

show_help() {
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  Script: install-zabbix-agent.sh${NC}"
  echo -e "${GREEN}  Instalador de Agente Zabbix${NC}"
  echo -e "${GREEN}============================================${NC}\n"

  echo -e "${YELLOW}DESCRIPCIÓN:${NC}"
  echo -e "  Instala y configura Zabbix Agent en el host"
  echo -e "  Registro automático via API de Zabbix"
  echo -e "  Soporta TLS/PSK para conexión segura\n"

  echo -e "${YELLOW}MODOS DE EJECUCIÓN:${NC}"
  echo -e "  ${GREEN}--lan${NC}      - Modo Red Local (HTTP + /zabbix)"
  echo -e "                URL API: http://servidor/zabbix/api_jsonrpc.php"
  echo -e "                Usa IP local del agente para registro\n"
  echo -e "  ${GREEN}--wan${NC}      - Modo Internet (HTTPS + sin /zabbix)"
  echo -e "                URL API: https://servidor/api_jsonrpc.php"
  echo -e "                Usa IP pública del agente para registro\n"
  echo -e "  ${GREEN}--url URL${NC}  - URL personalizada de la API"
  echo -e "                Ej: --url https://zabbix.midominio.com/api_jsonrpc.php\n"

  echo -e "${YELLOW}OPCIONES ADICIONALES:${NC}"
  echo -e "  ${GREEN}--auto${NC}     - Modo automático (no pregunta nada)"
  echo -e "  ${GREEN}--help${NC}     - Mostrar esta ayuda\n"

  echo -e "${YELLOW}VARIABLES EDITABLES EN EL SCRIPT:${NC}"
  echo -e "  API_TOKEN        - Token de API de Zabbix"
  echo -e "  ZABBIX_SERVER    - Servidor Zabbix (IP o hostname)"
  echo -e "  ZABBIX_SERVER_PORT - Puerto del servidor (default: 10051)"
  echo -e "  ZABBIX_AGENT_PORT  - Puerto del agente (default: 10050)"
  echo -e "  GROUP_ID         - ID del grupo en Zabbix (default: 2)"
  echo -e "  TEMPLATE_ID      - ID de plantilla (default: 10001)"
  echo -e "  TLS_MODE         - psk, cert, psk_cert (default: psk)"
  echo -e "  ZABBIX_API_URL   - URL personalizada (opcional)\n"

  echo -e "${YELLOW}EJEMPLOS:${NC}"
  echo -e "  # Instalación en red local (automático)"
  echo -e "  ${GREEN}./install-zabbix-agent.sh --lan --auto${NC}\n"
  echo -e "  # Instalación en internet (pregunta credenciales)"
  echo -e "  ${GREEN}./install-zabbix-agent.sh --wan${NC}\n"
  echo -e "  # URL personalizada"
  echo -e "  ${GREEN}./install-zabbix-agent.sh --url https://zabbix.domain.com/api_jsonrpc.php --auto${NC}\n"

  echo -e "${YELLOW}NOTAS IMPORTANTES:${NC}"
  echo -e "  • Modo LAN:  Asume que el agente está en la misma red"
  echo -e "  • Modo WAN:  Usa IP pública y HTTPS, requiere puerto 10051 abierto"
  echo -e "  • TLS/PSK es obligatorio para modo WAN"
  echo -e "  • Si las variables están configuradas, no pregunta nada\n"

  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  🌐 https://www.orangebox.cl${NC}"
  echo -e "${GREEN}============================================${NC}"
}

log_info() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_step() { echo -e "\n${BLUE}[*]${NC} $1"; }

check_root() {
  if [ "$EUID" -ne 0 ]; then
    log_error "Este script debe ejecutarse como root"
    exit 1
  fi
}

get_public_ip() {
  log_step "Detectando IP pública del agente..."

  PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null)
  if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP=$(curl -s --max-time 5 https://icanhazip.com 2>/dev/null | tr -d ' ')
  fi
  if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP=$(curl -s --max-time 5 https://ifconfig.me/ip 2>/dev/null)
  fi

  if [ -n "$PUBLIC_IP" ]; then
    log_info "IP Pública detectada: $PUBLIC_IP"
  else
    log_warn "No se pudo detectar IP pública automáticamente"
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
    echo -e "${YELLOW}Ingrese la IP o hostname del servidor Zabbix:${NC}"
    read -p "> " ZABBIX_SERVER
    while [ -z "$ZABBIX_SERVER" ]; do
      log_error "El servidor Zabbix es obligatorio"
      read -p "> " ZABBIX_SERVER
    done
  fi

  if [ -z "$API_TOKEN" ]; then
    echo -e "${YELLOW}Ingrese el token de API de Zabbix:${NC}"
    read -p "> " API_TOKEN
    while [ -z "$API_TOKEN" ]; do
      log_error "El token de API es obligatorio"
      read -p "> " API_TOKEN
    done
  fi

  log_info "Servidor Zabbix: $ZABBIX_SERVER"
  log_info "Token API: ${API_TOKEN:0:20}..."
}

detect_os() {
  log_step "Detectando sistema operativo..."

  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
    OS_NAME="$NAME $VERSION_ID"
  else
    log_error "No se pudo detectar el sistema operativo"
    exit 1
  fi

  log_info "Sistema detectado: $OS_NAME"

  case $OS in
  centos | rhel | almalinux | rocky | fedora | amzn | ol)
    OS_FAMILY="rhel"
    ;;
  debian | ubuntu | raspbian | linuxmint)
    OS_FAMILY="debian"
    ;;
  suse | opensuse | sles)
    OS_FAMILY="suse"
    ;;
  *)
    OS_FAMILY="unknown"
    ;;
  esac
}

install_dependencies() {
  log_step "Instalando dependencias..."

  case $OS_FAMILY in
  rhel)
    dnf install -y curl openssl net-tools >>/tmp/zabbix_agent_install.log 2>&1
    ;;
  debian)
    apt-get update -qq >>/tmp/zabbix_agent_install.log 2>&1
    apt-get install -y curl openssl net-tools >>/tmp/zabbix_agent_install.log 2>&1
    ;;
  suse)
    zypper install -y curl openssl net-tools >>/tmp/zabbix_agent_install.log 2>&1
    ;;
  esac

  log_info "Dependencias instaladas"
}

install_zabbix_repo() {
  log_step "Configurando repositorio de Zabbix..."

  case $OS_FAMILY in
  rhel)
    case $VER in
    10*) ZBX_REPO_VERSION="10" ;;
    9*) ZBX_REPO_VERSION="9" ;;
    8*) ZBX_REPO_VERSION="8" ;;
    7*) ZBX_REPO_VERSION="7" ;;
    *) ZBX_REPO_VERSION="9" ;;
    esac
    rpm -Uvh "https://repo.zabbix.com/zabbix/7.4/rhel/${ZBX_REPO_VERSION}/x86_64/zabbix-release-latest-7.4.el${ZBX_REPO_VERSION}.noarch.rpm" >>/tmp/zabbix_agent_install.log 2>&1
    if [ $? -ne 0 ]; then
      rpm -Uvh "https://repo.zabbix.com/zabbix/7.2/rhel/${ZBX_REPO_VERSION}/x86_64/zabbix-release-latest-7.2.el${ZBX_REPO_VERSION}.noarch.rpm" >>/tmp/zabbix_agent_install.log 2>&1
    fi
    ;;
  debian)
    local DEB_VERSION=""
    case $OS in
    ubuntu)
      case $VER in
      24.04*) DEB_VERSION="noble" ;;
      22.04*) DEB_VERSION="jammy" ;;
      20.04*) DEB_VERSION="focal" ;;
      18.04*) DEB_VERSION="bionic" ;;
      *) DEB_VERSION="jammy" ;;
      esac
      ;;
    debian)
      case $VER in
      12*) DEB_VERSION="bookworm" ;;
      11*) DEB_VERSION="bullseye" ;;
      10*) DEB_VERSION="buster" ;;
      *) DEB_VERSION="bookworm" ;;
      esac
      ;;
    linuxmint)
      DEB_VERSION="jammy"
      ;;
    esac
    wget -q "https://repo.zabbix.com/zabbix/7.4/debian/pool/main/z/zabbix-release/zabbix-release_latest_7.4+${DEB_VERSION}_all.deb" -O /tmp/zabbix-release.deb >>/tmp/zabbix_agent_install.log 2>&1
    dpkg -i /tmp/zabbix-release.deb >>/tmp/zabbix_agent_install.log 2>&1
    apt-get update -qq >>/tmp/zabbix_agent_install.log 2>&1
    rm -f /tmp/zabbix-release.deb
    ;;
  suse)
    rpm -Uvh "https://repo.zabbix.com/zabbix/7.4/suse/15/x86_64/zabbix-release-7.4-1.sle15.noarch.rpm" >>/tmp/zabbix_agent_install.log 2>&1
    ;;
  esac

  log_info "Repositorio Zabbix configurado"
}

install_agent() {
  log_step "Instalando Zabbix Agent..."

  case $OS_FAMILY in
  rhel)
    dnf install -y zabbix-agent2 >>/tmp/zabbix_agent_install.log 2>&1
    if [ $? -ne 0 ]; then
      dnf install -y zabbix-agent >>/tmp/zabbix_agent_install.log 2>&1
    fi
    ;;
  debian)
    apt-get install -y zabbix-agent2 >>/tmp/zabbix_agent_install.log 2>&1
    if [ $? -ne 0 ]; then
      apt-get install -y zabbix-agent >>/tmp/zabbix_agent_install.log 2>&1
    fi
    ;;
  suse)
    zypper install -y zabbix-agent >>/tmp/zabbix_agent_install.log 2>&1
    ;;
  esac

  if command -v zabbix_agent2 &>/dev/null; then
    AGENT_TYPE="zabbix_agent2"
    AGENT_SERVICE="zabbix-agent2"
  else
    AGENT_TYPE="zabbix_agentd"
    AGENT_SERVICE="zabbix-agent"
  fi

  log_info "Agente instalado: $AGENT_TYPE"
}

generate_psk() {
  log_step "Generando PSK para TLS..."

  mkdir -p /etc/zabbix/ssl
  PSK_KEY=$(openssl rand -hex 32)
  PSK_IDENTITY="${HOSTNAME}_psk_$(date +%s)"

  echo "$PSK_KEY" >/etc/zabbix/ssl/psk.key
  chown -R zabbix:zabbix /etc/zabbix/ssl
  chmod 600 /etc/zabbix/ssl/psk.key

  log_info "PSK generado: $PSK_IDENTITY"
}

generate_self_signed_cert() {
  log_step "Generando certificado SSL autofirmado por 50 años..."

  local CERT_DIR="/etc/zabbix/ssl"
  mkdir -p "$CERT_DIR"

  cd "$CERT_DIR"
  openssl genrsa -out zabbix_agent.key 2048 >>/tmp/zabbix_agent_install.log 2>&1
  openssl req -new -x509 -days 18250 -key zabbix_agent.key -out zabbix_agent.crt \
    -subj "/C=CL/ST=Santiago/L=Santiago/O=OrangeBox/OU=Monitoring/CN=$(hostname)" \
    -addext "subjectAltName=DNS:$(hostname),DNS:localhost,IP:127.0.0.1,IP:${AGENT_IP}" >>/tmp/zabbix_agent_install.log 2>&1

  chown -R zabbix:zabbix "$CERT_DIR"
  chmod 600 "$CERT_DIR"/zabbix_agent.key
  chmod 644 "$CERT_DIR"/zabbix_agent.crt

  log_info "Certificado SSL generado (válido por 50 años)"
}

configure_agent() {
  log_step "Configurando Zabbix Agent..."

  local CONFIG_FILE=""
  if [ "$AGENT_TYPE" = "zabbix_agent2" ]; then
    CONFIG_FILE="/etc/zabbix/zabbix_agent2.conf"
  else
    CONFIG_FILE="/etc/zabbix/zabbix_agentd.conf"
  fi

  cp "$CONFIG_FILE" "${CONFIG_FILE}.backup"

  cat >"$CONFIG_FILE" <<EOF
# Configuracion Zabbix Agent
# Generado: $(date)
# Modo: ${MODE_NAME}

Server=${ZABBIX_SERVER}
ServerActive=127.0.0.1
Hostname=${HOSTNAME}
ListenPort=${ZABBIX_AGENT_PORT}
ListenIP=0.0.0.0
StartAgents=3

# TLS/PSK
TLSConnect=psk
TLSAccept=psk
TLSPSKIdentity=${PSK_IDENTITY}
TLSPSKFile=/etc/zabbix/ssl/psk.key

# Logs
LogFile=/var/log/zabbix/${AGENT_TYPE}.log
LogFileSize=10
DebugLevel=3
Timeout=30
EOF

  log_info "Agente configurado"
}

configure_firewall() {
  log_step "Configurando firewall..."

  if command -v firewall-cmd &>/dev/null; then
    firewall-cmd --permanent --add-port=${ZABBIX_AGENT_PORT}/tcp >>/tmp/zabbix_agent_install.log 2>&1
    firewall-cmd --reload >>/tmp/zabbix_agent_install.log 2>&1
    log_info "Firewalld: puerto ${ZABBIX_AGENT_PORT}/tcp abierto"
  elif command -v ufw &>/dev/null; then
    ufw allow ${ZABBIX_AGENT_PORT}/tcp >>/tmp/zabbix_agent_install.log 2>&1
    log_info "UFW: puerto ${ZABBIX_AGENT_PORT}/tcp abierto"
  else
    log_warn "Firewall no detectado, asegure que el puerto ${ZABBIX_AGENT_PORT} esté accesible"
  fi
}

test_api_connection() {
  log_step "Probando conexión a la API de Zabbix..."

  log_info "URL API: $ZABBIX_API_URL"

  local TEST_RESPONSE=$(curl -s -k -X POST \
    -H "Content-Type: application/json-rpc" \
    -d "{
      \"jsonrpc\": \"2.0\",
      \"method\": \"apiinfo.version\",
      \"params\": [],
      \"id\": 1
    }" \
    "${ZABBIX_API_URL}" 2>/dev/null)

  if echo "$TEST_RESPONSE" | grep -q '"result"'; then
    local API_VERSION=$(echo "$TEST_RESPONSE" | grep -o '"result":"[^"]*"' | cut -d'"' -f4)
    log_info "API accesible (versión: $API_VERSION)"
    return 0
  else
    log_error "No se pudo conectar a la API"
    log_error "URL: $ZABBIX_API_URL"
    return 1
  fi
}

register_host() {
  log_step "Registrando host en Zabbix via API..."

  log_info "IP del agente: $AGENT_IP"
  log_info "Hostname: $HOSTNAME"

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
    "auth": "${API_TOKEN}",
    "id": 1
}
EOF
  )

  local RESPONSE=$(curl -s -k -X POST \
    -H "Content-Type: application/json-rpc" \
    -d "$JSON_PAYLOAD" \
    "${ZABBIX_API_URL}")

  if echo "$RESPONSE" | grep -q '"hostids"'; then
    local HOST_ID=$(echo "$RESPONSE" | grep -o '"hostids":\["[0-9]*"' | grep -o '[0-9]*')
    log_info "Host '${HOSTNAME}' registrado exitosamente (ID: ${HOST_ID})"
    log_info "IP registrada: ${AGENT_IP}"
  else
    log_error "Error al registrar host: $RESPONSE"
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
    exit 1
  fi
}

test_connection() {
  log_step "Verificando conectividad..."

  if ss -tlnp | grep -q ":${ZABBIX_AGENT_PORT}"; then
    log_info "Agente escuchando en puerto ${ZABBIX_AGENT_PORT}"
  else
    log_warn "Agente no está escuchando en puerto ${ZABBIX_AGENT_PORT}"
  fi
}

save_credentials() {
  local CRED_FILE="/root/zabbix_agent_$(date +%Y%m%d_%H%M%S).txt"

  cat >"$CRED_FILE" <<EOF
=============================================
  ZABBIX AGENT - CREDENCIALES
=============================================

📍 HOST:
  Nombre: ${HOSTNAME}
  IP: ${AGENT_IP}
  Modo: ${MODE_NAME}

🔐 TLS/PSK:
  PSK Identity: ${PSK_IDENTITY}
  PSK Key: ${PSK_KEY}
  Archivo: /etc/zabbix/ssl/psk.key

🌐 CONEXION:
  Servidor: ${ZABBIX_SERVER}:${ZABBIX_SERVER_PORT}
  Puerto agente: ${ZABBIX_AGENT_PORT}
  URL API: ${ZABBIX_API_URL}

📋 COMANDOS UTILES:
  systemctl status ${AGENT_SERVICE}
  tail -f /var/log/zabbix/${AGENT_TYPE}.log
  ss -tlnp | grep ${ZABBIX_AGENT_PORT}

=============================================
  🌐 https://www.orangebox.cl
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
  echo -e "  • Modo: ${GREEN}${MODE_NAME}${NC}"
  echo -e "  • Hostname: ${GREEN}${HOSTNAME}${NC}"
  echo -e "  • IP: ${GREEN}${AGENT_IP}${NC}"
  echo -e "  • Servidor: ${GREEN}${ZABBIX_SERVER}:${ZABBIX_SERVER_PORT}${NC}"
  echo -e "  • URL API: ${GREEN}${ZABBIX_API_URL}${NC}"

  echo -e "\n${YELLOW}📋 EN ZABBIX WEB:${NC}"
  echo -e "  Configuración → Hosts → ${HOSTNAME}"

  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  🌐 https://www.orangebox.cl${NC}"
  echo -e "${GREEN}============================================${NC}\n"
}

# ==============================================
# PROCESAMIENTO DE ARGUMENTOS
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
  --help | -h)
    show_help
    exit 0
    ;;
  *)
    log_error "Opción desconocida: $1"
    show_help
    exit 1
    ;;
  esac
done

# ==============================================
# MAIN
# ==============================================

clear
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Instalador de Agente Zabbix${NC}"
echo -e "${GREEN}============================================${NC}\n"

check_root

# Configurar según modo seleccionado
if [ -n "$CUSTOM_URL" ]; then
  ZABBIX_API_URL="$CUSTOM_URL"
  MODE_NAME="Personalizado (URL: $ZABBIX_API_URL)"
  get_local_ip
  AGENT_IP="$LOCAL_IP"

elif [ "$MODE" = "lan" ]; then
  ZABBIX_API_URL="http://${ZABBIX_SERVER}/zabbix/api_jsonrpc.php"
  MODE_NAME="LAN (Red Local)"
  get_local_ip
  AGENT_IP="$LOCAL_IP"
  log_info "Modo LAN: usando HTTP y IP local"

elif [ "$MODE" = "wan" ]; then
  ZABBIX_API_URL="https://${ZABBIX_SERVER}/api_jsonrpc.php"
  MODE_NAME="WAN (Internet)"
  get_public_ip
  AGENT_IP="$PUBLIC_IP"
  log_info "Modo WAN: usando HTTPS, IP pública y TLS obligatorio"

else
  # Si no se especificó modo, preguntar
  echo -e "${YELLOW}Seleccione el modo de instalación:${NC}"
  echo -e "  ${GREEN}1${NC}) LAN (Red Local) - HTTP + /zabbix"
  echo -e "  ${GREEN}2${NC}) WAN (Internet) - HTTPS + IP pública"
  echo -e "  ${GREEN}3${NC}) URL personalizada"
  read -p "Opción [1-3]: " mode_opt

  case $mode_opt in
  1)
    ZABBIX_API_URL="http://${ZABBIX_SERVER}/zabbix/api_jsonrpc.php"
    MODE_NAME="LAN (Red Local)"
    get_local_ip
    AGENT_IP="$LOCAL_IP"
    ;;
  2)
    ZABBIX_API_URL="https://${ZABBIX_SERVER}/api_jsonrpc.php"
    MODE_NAME="WAN (Internet)"
    get_public_ip
    AGENT_IP="$PUBLIC_IP"
    ;;
  3)
    echo -e "${YELLOW}Ingrese la URL completa de la API:${NC}"
    read -p "> " ZABBIX_API_URL
    MODE_NAME="Personalizado"
    get_local_ip
    AGENT_IP="$LOCAL_IP"
    ;;
  *)
    log_error "Opción inválida"
    exit 1
    ;;
  esac
fi

# Si no está en modo automático, obtener credenciales
if [ "$AUTO_MODE" = false ]; then
  get_server_info
else
  if [ -z "$API_TOKEN" ] || [ -z "$ZABBIX_SERVER" ]; then
    log_error "Modo automático requiere API_TOKEN y ZABBIX_SERVER configurados"
    exit 1
  fi
  log_info "Modo automático: usando variables preconfiguradas"
fi

# Verificar conexión a la API
if ! test_api_connection; then
  log_error "No se puede continuar sin acceso a la API"
  exit 1
fi

# Ejecutar instalación
detect_os
install_dependencies
install_zabbix_repo
install_agent
generate_psk
configure_agent
configure_firewall
register_host
start_agent
test_connection
save_credentials
show_completion
