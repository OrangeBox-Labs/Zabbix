#!/bin/bash

# ==============================================
# Script: install-zabbix-agent.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Instalacion de Zabbix Agent 7.4 en host remoto
#              con registro automatico via API y TLS/PSK
#              Repositorio oficial Zabbix + fallback a binario estatico
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

  # Detectar versión de AlmaLinux específicamente
  if [ -f /etc/almalinux-release ]; then
    OS_FAMILY="almalinux"
    ALMA_VERSION=$(grep -oE '[0-9]+' /etc/almalinux-release | head -1)
  elif [ -f /etc/redhat-release ]; then
    OS_FAMILY="rhel"
    ALMA_VERSION=$(grep -oE '[0-9]+' /etc/redhat-release | head -1)
  else
    case $OS in
    centos | rhel | almalinux | rocky | fedora | amzn | ol) OS_FAMILY="rhel" ;;
    debian | ubuntu | raspbian | linuxmint) OS_FAMILY="debian" ;;
    suse | opensuse | sles) OS_FAMILY="suse" ;;
    *) OS_FAMILY="unknown" ;;
    esac
    ALMA_VERSION=$(echo $VER | cut -d. -f1)
  fi

  log_debug "OS Family: $OS_FAMILY, Version: $ALMA_VERSION"
}

install_dependencies() {
  log_step "Instalando dependencias..."
  case $OS_FAMILY in
  rhel | almalinux)
    dnf install -y curl openssl net-tools jq >>/tmp/zabbix_agent_install.log 2>&1
    ;;
  debian)
    apt-get update -qq && apt-get install -y curl openssl net-tools jq >>/tmp/zabbix_agent_install.log 2>&1
    ;;
  suse)
    zypper install -y curl openssl net-tools jq >>/tmp/zabbix_agent_install.log 2>&1
    ;;
  esac
  log_info "Dependencias instaladas"
}

disable_epel_conflict() {
  log_step "Deshabilitando conflicto con EPEL..."

  if [ -f /etc/yum.repos.d/epel.repo ]; then
    if ! grep -q "excludepkgs=zabbix" /etc/yum.repos.d/epel.repo; then
      sed -i '/^\[epel\]/a excludepkgs=zabbix*' /etc/yum.repos.d/epel.repo
      log_info "EPEL configurado para excluir zabbix"
    else
      log_info "EPEL ya excluye zabbix"
    fi
  fi
}

install_zabbix_repo() {
  log_step "Configurando repositorio Zabbix 7.4..."

  # Limpiar repositorios viejos
  rm -f /etc/yum.repos.d/zabbix.repo
  dnf remove -y zabbix-release >>/tmp/zabbix_agent_install.log 2>&1

  case $OS_FAMILY in
  rhel | almalinux)
    # Validar que la versión es soportada (8, 9, 10)
    if [[ ! "$ALMA_VERSION" =~ ^(8|9|10)$ ]]; then
      log_error "Versión $ALMA_VERSION no soportada. Versiones soportadas: 8, 9, 10"
      log_info "Intentando método alternativo: binario estático..."
      install_agent_from_binary
      return $?
    fi

    # URL CORRECTA según documentación oficial de Zabbix
    local REPO_URL="https://repo.zabbix.com/zabbix/7.4/release/alma/${ALMA_VERSION}/noarch/zabbix-release-latest-7.4.el${ALMA_VERSION}.noarch.rpm"
    log_info "Repositorio: $REPO_URL"
    log_debug "URL: $REPO_URL"

    rpm -Uvh "$REPO_URL" >>/tmp/zabbix_agent_install.log 2>&1

    if [ $? -ne 0 ] || [ ! -f /etc/yum.repos.d/zabbix.repo ]; then
      log_warn "No se pudo instalar el repositorio desde $REPO_URL"
      log_info "Intentando método alternativo: binario estático..."
      install_agent_from_binary
      return $?
    fi

    # Limpiar caché
    dnf clean all >>/tmp/zabbix_agent_install.log 2>&1
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
    local REPO_URL="https://repo.zabbix.com/zabbix/7.4/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.4+${DEB_VERSION}_all.deb"
    wget -q "$REPO_URL" -O /tmp/zabbix-release.deb >>/tmp/zabbix_agent_install.log 2>&1
    dpkg -i /tmp/zabbix-release.deb >>/tmp/zabbix_agent_install.log 2>&1
    apt-get update -qq >>/tmp/zabbix_agent_install.log 2>&1
    ;;
  esac

  # Verificar que el repositorio se instaló correctamente
  if [ ! -f /etc/yum.repos.d/zabbix.repo ] && [ "$OS_FAMILY" != "debian" ]; then
    log_error "No se pudo instalar el repositorio Zabbix"
    log_info "Intentando método alternativo: binario estático..."
    install_agent_from_binary
    return $?
  fi

  log_info "Repositorio Zabbix 7.4 configurado correctamente"
}

install_agent_from_binary() {
  log_step "Instalando Zabbix Agent desde binario estático..."

  local BINARY_URL="https://cdn.zabbix.com/zabbix/binaries/stable/7.4/7.4.11/zabbix_agent-7.4.11-linux-3.0-amd64-static.tar.gz"
  local TMP_DIR="/tmp/zabbix_agent_binary_$$"

  mkdir -p "$TMP_DIR"
  cd "$TMP_DIR"

  log_info "Descargando binario desde: $BINARY_URL"
  curl -L -o zabbix_agent.tar.gz "$BINARY_URL" >>/tmp/zabbix_agent_install.log 2>&1

  if [ $? -ne 0 ] || [ ! -f zabbix_agent.tar.gz ]; then
    log_error "No se pudo descargar el binario"
    return 1
  fi

  tar -xzf zabbix_agent.tar.gz >>/tmp/zabbix_agent_install.log 2>&1

  # Copiar binarios incluyendo herramientas adicionales
  cp zabbix_agent/sbin/zabbix_agentd /usr/sbin/ 2>/dev/null
  cp zabbix_agent/bin/zabbix_get /usr/bin/ 2>/dev/null
  cp zabbix_agent/bin/zabbix_sender /usr/bin/ 2>/dev/null

  # Crear usuario si no existe
  id -u zabbix &>/dev/null || useradd -r -s /sbin/nologin zabbix

  # Crear directorios
  mkdir -p /etc/zabbix
  mkdir -p /var/log/zabbix
  mkdir -p /run/zabbix
  chown -R zabbix:zabbix /var/log/zabbix /run/zabbix
  chown -R zabbix:zabbix /etc/zabbix 2>/dev/null || true

  # Crear servicio systemd
  cat >/etc/systemd/system/zabbix-agent.service <<'EOF'
[Unit]
Description=Zabbix Agent
After=network.target

[Service]
Type=simple
User=zabbix
Group=zabbix
ExecStart=/usr/sbin/zabbix_agentd -f -c /etc/zabbix/zabbix_agentd.conf
ExecStop=/bin/kill -TERM $MAINPID
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload

  AGENT_TYPE="zabbix_agentd"
  AGENT_SERVICE="zabbix-agent"

  log_info "Zabbix Agent instalado desde binario estático"
  return 0
}

install_agent() {
  log_step "Instalando Zabbix Agent 7.4 y herramientas adicionales..."

  # Si ya se instaló desde binario, salir
  if command -v zabbix_agentd &>/dev/null && [ -f /etc/yum.repos.d/zabbix.repo ]; then
    AGENT_VERSION=$(zabbix_agentd --version 2>/dev/null | head -1 | grep -o '[0-9]\.[0-9]*\.[0-9]*')
    log_info "Zabbix Agent ya instalado: $AGENT_VERSION"
    AGENT_TYPE="zabbix_agentd"
    AGENT_SERVICE="zabbix-agent"
    return 0
  fi

  case $OS_FAMILY in
  rhel | almalinux)
    # Instalar agente y herramientas adicionales
    dnf install -y zabbix-agent zabbix-get zabbix-sender >>/tmp/zabbix_agent_install.log 2>&1
    ;;
  debian)
    apt-get install -y zabbix-agent zabbix-get zabbix-sender >>/tmp/zabbix_agent_install.log 2>&1
    ;;
  suse)
    zypper install -y zabbix-agent >>/tmp/zabbix_agent_install.log 2>&1
    ;;
  esac

  # Verificar instalación
  if command -v zabbix_agentd &>/dev/null; then
    AGENT_VERSION=$(zabbix_agentd --version | head -1 | grep -o '[0-9]\.[0-9]*\.[0-9]*')
    if [[ "$AGENT_VERSION" == 7.4* ]]; then
      log_info "Zabbix Agent $AGENT_VERSION instalado desde repositorio"
    else
      log_warn "Se instaló versión $AGENT_VERSION, no es 7.4"
    fi
    AGENT_TYPE="zabbix_agentd"
    AGENT_SERVICE="zabbix-agent"
  else
    log_warn "No se pudo instalar desde repositorio, intentando binario estático..."
    install_agent_from_binary
    if [ $? -ne 0 ]; then
      log_error "No se pudo instalar el agente Zabbix"
      exit 1
    fi
  fi

  # Verificar herramientas adicionales
  if command -v zabbix_get &>/dev/null; then
    log_info "zabbix_get instalado"
  else
    log_warn "zabbix_get no disponible, se puede instalar manualmente"
  fi

  if command -v zabbix_sender &>/dev/null; then
    log_info "zabbix_sender instalado"
  else
    log_warn "zabbix_sender no disponible"
  fi
}

configure_permissions() {
  log_step "Configurando permisos de directorios y archivos..."

  # Crear directorios necesarios
  mkdir -p /etc/zabbix/ssl
  mkdir -p /var/log/zabbix
  mkdir -p /run/zabbix

  # Establecer propietario y permisos recursivos para /etc/zabbix
  chown -R zabbix:zabbix /etc/zabbix
  chmod 755 /etc/zabbix
  chmod 750 /etc/zabbix/ssl 2>/dev/null || chmod 755 /etc/zabbix/ssl
  chmod 755 /var/log/zabbix
  chmod 755 /run/zabbix

  log_info "Permisos configurados correctamente"
}

generate_psk() {
  log_step "Generando PSK para TLS..."

  # Asegurar directorio SSL con permisos correctos
  mkdir -p /etc/zabbix/ssl
  chown -R zabbix:zabbix /etc/zabbix/ssl
  chmod 750 /etc/zabbix/ssl

  PSK_KEY=$(openssl rand -hex 32)
  PSK_IDENTITY="${HOSTNAME}_psk_$(date +%s)"

  echo -n "$PSK_KEY" >/etc/zabbix/ssl/psk.key

  # Permisos específicos para el archivo PSK
  chown zabbix:zabbix /etc/zabbix/ssl/psk.key
  chmod 640 /etc/zabbix/ssl/psk.key

  log_info "PSK generado: $PSK_IDENTITY"
  log_debug "PSK Key: $PSK_KEY"
}

configure_agent() {
  log_step "Configurando Zabbix Agent..."

  # Crear configuración limpia
  cat >/etc/zabbix/zabbix_agentd.conf <<EOF
Server=127.0.0.1,${ZABBIX_SERVER}
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

  # Permisos del archivo de configuración
  chown root:zabbix /etc/zabbix/zabbix_agentd.conf
  chmod 640 /etc/zabbix/zabbix_agentd.conf

  log_info "Agente configurado con TLS/PSK"
  log_info "Servidores permitidos: 127.0.0.1, ${ZABBIX_SERVER}"
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
    local API_VERSION=$(echo "$RESPONSE" | grep -o '"result":"[^"]*"' | cut -d'"' -f4)
    log_info "API accesible (versión: $API_VERSION)"
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
    local HOST_ID=$(echo "$RESPONSE" | grep -o '"hostids":\["[0-9]*"' | grep -o '[0-9]*')
    log_info "Host '${HOSTNAME}' registrado exitosamente (ID: ${HOST_ID})"
    log_info "TLS/PSK habilitado"
  elif echo "$RESPONSE" | grep -q "already exists"; then
    log_warn "El host '${HOSTNAME}' ya existe en Zabbix"
    log_info "Puedes eliminarlo manualmente y volver a ejecutar el script"
  else
    log_error "Error al registrar host: $RESPONSE"
    exit 1
  fi
}

start_agent() {
  log_step "Iniciando servicio del agente..."

  # Asegurar que el servicio systemd existe (RPM lo crea, binario lo necesita)
  if [ ! -f /usr/lib/systemd/system/zabbix-agent.service ] && [ ! -f /etc/systemd/system/zabbix-agent.service ]; then
    log_warn "Servicio systemd no encontrado, creando..."
    cat >/etc/systemd/system/zabbix-agent.service <<'EOF'
[Unit]
Description=Zabbix Agent
After=network.target

[Service]
Type=simple
User=zabbix
Group=zabbix
ExecStart=/usr/sbin/zabbix_agentd -f -c /etc/zabbix/zabbix_agentd.conf
ExecStop=/bin/kill -TERM $MAINPID
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
  fi

  # Habilitar e iniciar
  systemctl enable zabbix-agent >>/tmp/zabbix_agent_install.log 2>&1
  systemctl restart zabbix-agent >>/tmp/zabbix_agent_install.log 2>&1

  sleep 3

  if systemctl is-active zabbix-agent &>/dev/null; then
    log_info "Agente iniciado correctamente"
  else
    log_error "Error al iniciar agente"
    journalctl -u zabbix-agent -n 10 --no-pager
    exit 1
  fi
}

test_local_connection() {
  log_step "Probando conexión local al agente..."

  if command -v zabbix_get &>/dev/null; then
    local RESULT=$(zabbix_get -s 127.0.0.1 -p ${ZABBIX_AGENT_PORT} -k system.hostname 2>/dev/null)
    if [ "$RESULT" = "${HOSTNAME}" ]; then
      log_info "Conexión local exitosa: $RESULT"
    else
      log_warn "Conexión local falló: $RESULT"
    fi
  else
    log_warn "zabbix_get no disponible para probar conexión local"
  fi
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
  systemctl status zabbix-agent
  tail -f /var/log/zabbix/zabbix_agentd.log
  zabbix_get -s ${AGENT_IP} -p ${ZABBIX_AGENT_PORT} -k system.hostname

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
  echo -e "\n${YELLOW}📋 VERIFICACIÓN:${NC}"
  echo -e "  systemctl status zabbix-agent"
  echo -e "  zabbix_get -s ${AGENT_IP} -p ${ZABBIX_AGENT_PORT} -k system.hostname"
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
  log_info "Modo LAN: $ZABBIX_API_URL"
elif [ "$MODE" = "wan" ]; then
  ZABBIX_API_URL="https://${ZABBIX_SERVER}/api_jsonrpc.php"
  MODE_NAME="WAN"
  get_public_ip
  AGENT_IP="$PUBLIC_IP"
  log_info "Modo WAN: $ZABBIX_API_URL"
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
log_debug "Hostname final: $HOSTNAME"

# Instalación
detect_os
install_dependencies
disable_epel_conflict
install_zabbix_repo
install_agent
configure_permissions
generate_psk
configure_agent
configure_firewall
test_api_connection
register_host
start_agent
test_local_connection
save_credentials
show_completion
