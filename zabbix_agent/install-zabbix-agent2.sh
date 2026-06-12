#!/bin/bash

# ==============================================
# Script: install-zabbix-agent.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Instalacion de Zabbix Agent 7.4 en host remoto
#              con registro automatico via API y TLS/PSK
#              Soporta: CentOS 7 (binario), AlmaLinux/RHEL 8/9/10 (repo)
#              Prioridad: Agent2 > Agent clasico > Binario estatico
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
  echo -e "${GREEN}  Soporta: CentOS 7, AlmaLinux/RHEL 8/9/10${NC}"
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

  # Detectar CentOS 7 específicamente
  if [ "$OS" = "centos" ] && [[ "$VER" =~ ^7 ]]; then
    OS_FAMILY="centos7"
    CENTOS7_VERSION="7"
    log_info "CentOS 7 detectado - usando binario estático Zabbix 7.4"
  elif [ -f /etc/almalinux-release ]; then
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

  log_debug "OS Family: $OS_FAMILY, Version: ${ALMA_VERSION:-$CENTOS7_VERSION}"
}

install_dependencies() {
  log_step "Instalando dependencias..."
  case $OS_FAMILY in
  centos7)
    yum install -y curl openssl net-tools jq >>/tmp/zabbix_agent_install.log 2>&1
    ;;
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

  # CentOS 7 no tiene EPEL configurado por defecto
  if [ "$OS_FAMILY" = "centos7" ]; then
    log_debug "CentOS 7 - omitiendo configuracion EPEL"
    return 0
  fi

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
  log_step "Configurando repositorio Zabbix..."

  # Limpiar repositorios viejos
  rm -f /etc/yum.repos.d/zabbix.repo

  # CentOS 7 no usa repositorio, usa binario directamente
  if [ "$OS_FAMILY" = "centos7" ]; then
    log_info "CentOS 7: no se necesita repositorio (usando binario estático)"
    return 0
  fi

  case $OS_FAMILY in
  rhel | almalinux)
    # Validar que la versión es soportada (8, 9, 10)
    if [[ ! "$ALMA_VERSION" =~ ^(8|9|10)$ ]]; then
      log_error "Versión $ALMA_VERSION no soportada. Versiones soportadas: 8, 9, 10"
      return 1
    fi

    # URL CORRECTA según documentación oficial de Zabbix
    local REPO_URL="https://repo.zabbix.com/zabbix/7.4/release/alma/${ALMA_VERSION}/noarch/zabbix-release-latest-7.4.el${ALMA_VERSION}.noarch.rpm"
    log_info "Repositorio: $REPO_URL"
    log_debug "URL: $REPO_URL"

    rpm -Uvh "$REPO_URL" >>/tmp/zabbix_agent_install.log 2>&1

    if [ $? -ne 0 ] || [ ! -f /etc/yum.repos.d/zabbix.repo ]; then
      log_warn "No se pudo instalar el repositorio desde $REPO_URL"
      return 1
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

  log_info "Repositorio Zabbix configurado correctamente"
  return 0
}

# -----------------------------------------------------------------------------
# FUNCIONES DE INSTALACIÓN DE AGENTE (Prioridad: Agent2 > Agent > Binario)
# -----------------------------------------------------------------------------

install_zabbix_agent_centos7_binary() {
  log_step "Instalando Zabbix Agent 7.4 en CentOS 7 desde binario estático..."

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

  # Copiar binarios
  cp zabbix_agent/sbin/zabbix_agentd /usr/sbin/
  cp zabbix_agent/bin/zabbix_get /usr/bin/
  cp zabbix_agent/bin/zabbix_sender /usr/bin/

  # Crear usuario si no existe
  id -u zabbix &>/dev/null || useradd -r -s /sbin/nologin zabbix

  # Configurar variables
  AGENT_TYPE="zabbix_agentd"
  AGENT_SERVICE="zabbix-agent"
  AGENT_BINARY="zabbix_agentd"
  CONFIG_FILE="/etc/zabbix/zabbix_agentd.conf"

  log_info "Zabbix Agent 7.4.11 instalado desde binario estático en CentOS 7"
  return 0
}

install_zabbix_agent2() {
  log_info "Intentando instalar Zabbix Agent 2 desde el repositorio..."

  # CentOS 7 no tiene Agent2
  if [ "$OS_FAMILY" = "centos7" ]; then
    log_debug "CentOS 7 no soporta Zabbix Agent 2"
    return 1
  fi

  case $OS_FAMILY in
  rhel | almalinux)
    if dnf install -y zabbix-agent2 >>/tmp/zabbix_agent_install.log 2>&1; then
      AGENT_TYPE="zabbix_agent2"
      AGENT_SERVICE="zabbix-agent2"
      AGENT_BINARY="zabbix_agent2"
      CONFIG_FILE="/etc/zabbix/zabbix_agent2.conf"
      log_info "Zabbix Agent 2 instalado exitosamente"
      return 0
    fi
    ;;
  debian)
    if apt-get install -y zabbix-agent2 >>/tmp/zabbix_agent_install.log 2>&1; then
      AGENT_TYPE="zabbix_agent2"
      AGENT_SERVICE="zabbix-agent2"
      AGENT_BINARY="zabbix_agent2"
      CONFIG_FILE="/etc/zabbix/zabbix_agent2.conf"
      log_info "Zabbix Agent 2 instalado exitosamente"
      return 0
    fi
    ;;
  esac
  log_warn "Zabbix Agent 2 no está disponible"
  return 1
}

install_zabbix_agent_legacy() {
  log_info "Intentando instalar Zabbix Agent clásico desde el repositorio..."

  case $OS_FAMILY in
  rhel | almalinux)
    if dnf install -y zabbix-agent >>/tmp/zabbix_agent_install.log 2>&1; then
      AGENT_TYPE="zabbix_agentd"
      AGENT_SERVICE="zabbix-agent"
      AGENT_BINARY="zabbix_agentd"
      CONFIG_FILE="/etc/zabbix/zabbix_agentd.conf"
      log_info "Zabbix Agent clásico instalado exitosamente"
      return 0
    fi
    ;;
  centos7)
    if yum install -y zabbix-agent >>/tmp/zabbix_agent_install.log 2>&1; then
      AGENT_TYPE="zabbix_agentd"
      AGENT_SERVICE="zabbix-agent"
      AGENT_BINARY="zabbix_agentd"
      CONFIG_FILE="/etc/zabbix/zabbix_agentd.conf"
      log_info "Zabbix Agent clásico instalado exitosamente"
      return 0
    fi
    ;;
  debian)
    if apt-get install -y zabbix-agent >>/tmp/zabbix_agent_install.log 2>&1; then
      AGENT_TYPE="zabbix_agentd"
      AGENT_SERVICE="zabbix-agent"
      AGENT_BINARY="zabbix_agentd"
      CONFIG_FILE="/etc/zabbix/zabbix_agentd.conf"
      log_info "Zabbix Agent clásico instalado exitosamente"
      return 0
    fi
    ;;
  esac
  log_warn "Zabbix Agent clásico no está disponible"
  return 1
}

install_agent_from_binary() {
  log_step "Instalando Zabbix Agent desde binario estático (último recurso)..."

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

  # Copiar binarios
  cp zabbix_agent/sbin/zabbix_agentd /usr/sbin/
  cp zabbix_agent/bin/zabbix_get /usr/bin/
  cp zabbix_agent/bin/zabbix_sender /usr/bin/

  # Crear usuario si no existe
  id -u zabbix &>/dev/null || useradd -r -s /sbin/nologin zabbix

  # Configurar variables para el agente clásico (el binario es el clásico)
  AGENT_TYPE="zabbix_agentd"
  AGENT_SERVICE="zabbix-agent"
  AGENT_BINARY="zabbix_agentd"
  CONFIG_FILE="/etc/zabbix/zabbix_agentd.conf"

  log_info "Zabbix Agent instalado desde binario estático"
  return 0
}

install_agent() {
  log_step "Instalando Zabbix Agent (prioridad: Agent2 > Agent clásico > Binario estático)..."

  # Verificar si ya está instalado (cualquier versión)
  if command -v zabbix_agent2 &>/dev/null; then
    AGENT_TYPE="zabbix_agent2"
    AGENT_SERVICE="zabbix-agent2"
    AGENT_BINARY="zabbix_agent2"
    CONFIG_FILE="/etc/zabbix/zabbix_agent2.conf"
    log_info "Zabbix Agent 2 ya está instalado"
    return 0
  elif command -v zabbix_agentd &>/dev/null; then
    AGENT_TYPE="zabbix_agentd"
    AGENT_SERVICE="zabbix-agent"
    AGENT_BINARY="zabbix_agentd"
    CONFIG_FILE="/etc/zabbix/zabbix_agentd.conf"
    log_info "Zabbix Agent clásico ya está instalado"
    # Verificar versión
    local VERSION=$(zabbix_agentd --version | head -1 | grep -o '[0-9]\.[0-9]*\.[0-9]*')
    if [[ "$VERSION" != 7.4* ]]; then
      log_warn "Versión actual: $VERSION. Se recomienda actualizar a 7.4"
    fi
    return 0
  fi

  # Caso especial: CentOS 7 usa binario directamente (más confiable)
  if [ "$OS_FAMILY" = "centos7" ]; then
    if install_zabbix_agent_centos7_binary; then
      return 0
    fi
  fi

  # Intentar instalar Agent 2 primero
  if install_zabbix_agent2; then
    return 0
  fi

  # Si Agent 2 falla, intentar Agent clásico
  if install_zabbix_agent_legacy; then
    return 0
  fi

  # Si ambos fallan, usar binario estático (último recurso)
  log_warn "No se pudo instalar desde repositorios, usando binario estático..."
  if install_agent_from_binary; then
    return 0
  fi

  log_error "No se pudo instalar el agente Zabbix por ningún método"
  exit 1
}

# -----------------------------------------------------------------------------
# FUNCIONES DE CONFIGURACIÓN (comunes para ambos tipos de agente)
# -----------------------------------------------------------------------------

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

fix_pid_file() {
  log_step "Corrigiendo archivo PID para systemd..."

  # Crear directorio para PID
  mkdir -p /run/zabbix
  chown zabbix:zabbix /run/zabbix
  chmod 755 /run/zabbix

  log_info "Directorio PID creado y configurado"
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

  # Verificar que CONFIG_FILE está definida
  if [ -z "$CONFIG_FILE" ]; then
    log_error "CONFIG_FILE no está definido"
    exit 1
  fi

  # Crear directorio de configuración si no existe
  mkdir -p $(dirname "$CONFIG_FILE")

  # Crear configuración limpia (compatible con Agent2 y Agent clásico)
  cat >"$CONFIG_FILE" <<EOF
Server=127.0.0.1,${ZABBIX_SERVER}
ServerActive=${ZABBIX_SERVER}:${ZABBIX_SERVER_PORT}
Hostname=${HOSTNAME}
ListenPort=${ZABBIX_AGENT_PORT}
ListenIP=0.0.0.0
StartAgents=3
LogFile=/var/log/zabbix/${AGENT_TYPE}.log
LogFileSize=10
DebugLevel=3
Timeout=30

# TLS/PSK - Conexión segura
TLSConnect=psk
TLSAccept=psk
TLSPSKIdentity=${PSK_IDENTITY}
TLSPSKFile=/etc/zabbix/ssl/psk.key

# Archivo PID para systemd
PidFile=/run/zabbix/${AGENT_TYPE}.pid
EOF

  # Permisos del archivo de configuración
  chown root:zabbix "$CONFIG_FILE"
  chmod 640 "$CONFIG_FILE"

  log_info "Agente configurado con TLS/PSK"
  log_info "Archivo de configuración: $CONFIG_FILE"
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

  # Corregir archivo PID antes de iniciar
  fix_pid_file

  # Si es instalación desde binario o CentOS 7, crear servicio systemd
  if [ ! -f /usr/lib/systemd/system/${AGENT_SERVICE}.service ] && [ ! -f /etc/systemd/system/${AGENT_SERVICE}.service ]; then
    log_warn "Servicio systemd no encontrado, creando..."
    cat >/etc/systemd/system/${AGENT_SERVICE}.service <<EOF
[Unit]
Description=Zabbix Agent
After=network.target

[Service]
Type=simple
User=zabbix
Group=zabbix
ExecStart=/usr/sbin/${AGENT_BINARY} -f -c ${CONFIG_FILE}
ExecStop=/bin/kill -TERM \$MAINPID
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
  fi

  # Habilitar e iniciar
  systemctl enable ${AGENT_SERVICE} >>/tmp/zabbix_agent_install.log 2>&1
  systemctl restart ${AGENT_SERVICE} >>/tmp/zabbix_agent_install.log 2>&1

  sleep 2

  if systemctl is-active ${AGENT_SERVICE} &>/dev/null; then
    log_info "Agente iniciado correctamente"
  else
    log_error "Error al iniciar agente"
    journalctl -u ${AGENT_SERVICE} -n 10 --no-pager
    exit 1
  fi
}

test_local_connection() {
  log_step "Probando conexión local al agente con TLS..."

  if command -v zabbix_get &>/dev/null; then
    local RESULT=$(zabbix_get -s 127.0.0.1 -p ${ZABBIX_AGENT_PORT} -k system.hostname \
      --tls-connect psk \
      --tls-psk-identity "${PSK_IDENTITY}" \
      --tls-psk-file /etc/zabbix/ssl/psk.key 2>/dev/null)

    if [ "$RESULT" = "${HOSTNAME}" ]; then
      log_info "Conexión local TLS exitosa: $RESULT"
    else
      log_warn "Conexión local TLS falló: $RESULT"
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
Tipo Agente: ${AGENT_TYPE}
Archivo Config: ${CONFIG_FILE}

🔐 TLS/PSK:
  Identity: ${PSK_IDENTITY}
  Key: ${PSK_KEY}
  Archivo: /etc/zabbix/ssl/psk.key

📋 Comandos útiles:
  systemctl status ${AGENT_SERVICE}
  tail -f /var/log/zabbix/${AGENT_TYPE}.log
  zabbix_get -s ${AGENT_IP} -p ${ZABBIX_AGENT_PORT} -k system.hostname \\
    --tls-connect psk \\
    --tls-psk-identity "${PSK_IDENTITY}" \\
    --tls-psk-file /etc/zabbix/ssl/psk.key

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
  echo -e "  • Tipo Agente: ${GREEN}${AGENT_TYPE}${NC}"
  echo -e "  • TLS/PSK: ${GREEN}Habilitado${NC}"
  echo -e "  • Archivo PID: ${GREEN}/run/zabbix/${AGENT_TYPE}.pid${NC}"
  echo -e "\n${YELLOW}📋 VERIFICACIÓN:${NC}"
  echo -e "  systemctl status ${AGENT_SERVICE}"
  echo -e "  zabbix_get -s ${AGENT_IP} -p ${ZABBIX_AGENT_PORT} -k system.hostname \\"
  echo -e "    --tls-connect psk \\"
  echo -e "    --tls-psk-identity \"${PSK_IDENTITY}\" \\"
  echo -e "    --tls-psk-file /etc/zabbix/ssl/psk.key"
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
echo -e "${GREEN}  Soporta: CentOS 7, AlmaLinux/RHEL 8/9/10${NC}"
echo -e "${GREEN}  Prioridad: Agent2 > Agent > Binario${NC}"
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
fix_pid_file
configure_firewall
test_api_connection
register_host
start_agent
test_local_connection
save_credentials
show_completion
