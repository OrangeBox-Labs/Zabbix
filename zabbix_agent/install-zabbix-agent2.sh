#!/bin/bash

# ==============================================
# Script: install-zabbix-agent.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Instalacion de Zabbix Agent 7.4 en host remoto
#              con registro automatico via API y TLS/PSK
#              PRIMERO instala y configura el agente, SOLO despues registra
#              Soporta: CentOS 7/8 (Vault), RHEL/AlmaLinux/Rocky 8/9/10
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
API_TOKEN="TU_NUEVO_TOKEN_AQUI"

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
  echo -e "${GREEN}  Soporta: CentOS 7/8, RHEL/AlmaLinux/Rocky 8/9/10${NC}"
  echo -e "${GREEN}============================================${NC}\n"

  echo -e "${YELLOW}DESCRIPCIÓN:${NC}"
  echo -e "  Instala Zabbix Agent 7.4, configura TLS/PSK y registra via API\n"
  echo -e "  IMPORTANTE: Primero instala y configura el agente, solo despues registra en Zabbix\n"

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
log_error() {
  echo -e "${RED}[✗]${NC} ERROR: $1"
  exit 1
}
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_step() { echo -e "\n${BLUE}[*]${NC} $1"; }
log_debug() { [ "$DEBUG_MODE" = true ] && echo -e "${CYAN}[DEBUG]${NC} $1"; }

check_root() {
  if [ "$EUID" -ne 0 ]; then
    log_error "Este script debe ejecutarse como root"
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

  if [ "$OS" = "centos" ] && [[ "$VER" =~ ^7 ]]; then
    OS_FAMILY="centos7"
    log_info "CentOS 7 detectado - usando repositorios Vault"
  elif [ "$OS" = "centos" ] && [[ "$VER" =~ ^8 ]]; then
    OS_FAMILY="centos8"
    log_info "CentOS 8 detectado - usando repositorios Vault"
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

  log_debug "OS Family: $OS_FAMILY, Version: ${ALMA_VERSION:-7}"
}

# ==============================================
# FUNCIONES DE MANEJO DE REPOSITORIOS
# ==============================================

REPO_BACKUP_DIR="/etc/yum.repos.d.backup.$$"

disable_all_repos() {
  log_step "Deshabilitando TODOS los repositorios existentes..."

  mkdir -p "$REPO_BACKUP_DIR"

  for repo in /etc/yum.repos.d/*.repo; do
    if [ -f "$repo" ]; then
      mv "$repo" "$REPO_BACKUP_DIR/"
      log_debug "Deshabilitado: $(basename $repo)"
    fi
  done

  log_info "Todos los repositorios han sido deshabilitados"
}

restore_all_repos() {
  log_step "Restaurando repositorios originales..."

  if [ -d "$REPO_BACKUP_DIR" ]; then
    cp -f "$REPO_BACKUP_DIR"/*.repo /etc/yum.repos.d/ 2>/dev/null
    log_info "Repositorios originales restaurados"
    rm -rf "$REPO_BACKUP_DIR"
  fi

  if command -v dnf &>/dev/null; then
    dnf clean all >/dev/null 2>&1
  else
    yum clean all >/dev/null 2>&1
  fi
}

setup_centos7_repos() {
  log_step "Configurando repositorios para CentOS 7 (usando Vault)..."

  cat >/etc/yum.repos.d/CentOS-Vault.repo <<'EOF'
[base]
name=CentOS-7 - Base
baseurl=http://vault.centos.org/7.9.2009/os/$basearch/
gpgcheck=0
enabled=1

[updates]
name=CentOS-7 - Updates
baseurl=http://vault.centos.org/7.9.2009/updates/$basearch/
gpgcheck=0
enabled=1
EOF

  rpm -Uvh https://repo.zabbix.com/zabbix/7.4/release/rhel/7/noarch/zabbix-release-latest-7.4.el7.noarch.rpm --nodeps 2>/dev/null

  yum clean all >/dev/null 2>&1
  log_info "Repositorios CentOS 7 configurados"
}

setup_centos8_repos() {
  log_step "Configurando repositorios para CentOS 8 (usando Vault)..."

  cat >/etc/yum.repos.d/CentOS-Vault.repo <<'EOF'
[baseos]
name=CentOS-8 - BaseOS
baseurl=http://vault.centos.org/8.5.2111/BaseOS/$basearch/os/
gpgcheck=0
enabled=1

[appstream]
name=CentOS-8 - AppStream
baseurl=http://vault.centos.org/8.5.2111/AppStream/$basearch/os/
gpgcheck=0
enabled=1
EOF

  rpm -Uvh https://repo.zabbix.com/zabbix/7.4/release/rhel/8/noarch/zabbix-release-latest-7.4.el8.noarch.rpm --nodeps 2>/dev/null

  dnf clean all >/dev/null 2>&1
  log_info "Repositorios CentOS 8 configurados"
}

setup_rhel_repos() {
  local version="$1"
  log_step "Configurando repositorios para RHEL/AlmaLinux/Rocky $version..."

  rpm -Uvh https://repo.zabbix.com/zabbix/7.4/release/rhel/${version}/noarch/zabbix-release-latest-7.4.el${version}.noarch.rpm --nodeps 2>/dev/null

  if command -v dnf &>/dev/null; then
    dnf clean all >/dev/null 2>&1
  else
    yum clean all >/dev/null 2>&1
  fi

  log_info "Repositorios RHEL/AlmaLinux/Rocky $version configurados"
}

# ==============================================
# FUNCIONES DE INSTALACIÓN DE DEPENDENCIAS
# ==============================================

install_dependencies() {
  log_step "Instalando dependencias..."

  if command -v dnf &>/dev/null; then
    dnf install -y curl openssl net-tools jq >>/tmp/zabbix_agent_install.log 2>&1
  else
    yum install -y curl openssl net-tools jq >>/tmp/zabbix_agent_install.log 2>&1
  fi

  log_info "Dependencias instaladas"
}

# ==============================================
# FUNCIONES DE INSTALACIÓN DE AGENTE
# ==============================================

install_zabbix_agent2() {
  log_info "Intentando instalar Zabbix Agent 2 desde el repositorio..."

  if [ "$OS_FAMILY" = "centos7" ] || [ "$OS_FAMILY" = "centos8" ]; then
    log_debug "CentOS 7/8 no soporta Zabbix Agent 2"
    return 1
  fi

  if command -v dnf &>/dev/null; then
    if dnf install -y zabbix-agent2 >>/tmp/zabbix_agent_install.log 2>&1; then
      AGENT_TYPE="zabbix_agent2"
      AGENT_SERVICE="zabbix-agent2"
      AGENT_BINARY="zabbix_agent2"
      CONFIG_FILE="/etc/zabbix/zabbix_agent2.conf"
      log_info "Zabbix Agent 2 instalado exitosamente"
      return 0
    fi
  fi
  log_warn "Zabbix Agent 2 no está disponible"
  return 1
}

install_zabbix_agent_legacy() {
  log_info "Intentando instalar Zabbix Agent clásico desde el repositorio..."

  if command -v dnf &>/dev/null; then
    if dnf install -y zabbix-agent >>/tmp/zabbix_agent_install.log 2>&1; then
      AGENT_TYPE="zabbix_agentd"
      AGENT_SERVICE="zabbix-agent"
      AGENT_BINARY="zabbix_agentd"
      CONFIG_FILE="/etc/zabbix/zabbix_agentd.conf"
      log_info "Zabbix Agent clásico instalado exitosamente"
      return 0
    fi
  else
    if yum install -y zabbix-agent >>/tmp/zabbix_agent_install.log 2>&1; then
      AGENT_TYPE="zabbix_agentd"
      AGENT_SERVICE="zabbix-agent"
      AGENT_BINARY="zabbix_agentd"
      CONFIG_FILE="/etc/zabbix/zabbix_agentd.conf"
      log_info "Zabbix Agent clásico instalado exitosamente"
      return 0
    fi
  fi
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
  fi

  tar -xzf zabbix_agent.tar.gz >>/tmp/zabbix_agent_install.log 2>&1

  # Copiar binarios
  cp zabbix_agent/sbin/zabbix_agentd /usr/sbin/
  cp zabbix_agent/bin/zabbix_get /usr/bin/
  cp zabbix_agent/bin/zabbix_sender /usr/bin/

  # Crear usuario si no existe
  id -u zabbix &>/dev/null || useradd -r -s /sbin/nologin zabbix

  AGENT_TYPE="zabbix_agentd"
  AGENT_SERVICE="zabbix-agent"
  AGENT_BINARY="zabbix_agentd"
  CONFIG_FILE="/etc/zabbix/zabbix_agentd.conf"

  log_info "Zabbix Agent instalado desde binario estático"
  return 0
}

install_agent() {
  log_step "Instalando Zabbix Agent (prioridad: Agent2 > Agent clásico > Binario estático)..."

  # Verificar si ya está instalado
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
    return 0
  fi

  # Configurar repositorios según versión e instalar
  if [ "$OS_FAMILY" = "centos7" ]; then
    setup_centos7_repos
    if yum install -y zabbix-agent >>/tmp/zabbix_agent_install.log 2>&1; then
      AGENT_TYPE="zabbix_agentd"
      AGENT_SERVICE="zabbix-agent"
      AGENT_BINARY="zabbix_agentd"
      CONFIG_FILE="/etc/zabbix/zabbix_agentd.conf"
      log_info "Zabbix Agent instalado exitosamente en CentOS 7"
      return 0
    fi
  elif [ "$OS_FAMILY" = "centos8" ]; then
    setup_centos8_repos
    if dnf install -y zabbix-agent >>/tmp/zabbix_agent_install.log 2>&1; then
      AGENT_TYPE="zabbix_agentd"
      AGENT_SERVICE="zabbix-agent"
      AGENT_BINARY="zabbix_agentd"
      CONFIG_FILE="/etc/zabbix/zabbix_agentd.conf"
      log_info "Zabbix Agent instalado exitosamente en CentOS 8"
      return 0
    fi
  else
    setup_rhel_repos "$ALMA_VERSION"
  fi

  # Intentar instalar Agent 2
  if install_zabbix_agent2; then
    return 0
  fi

  # Intentar Agent clásico
  if install_zabbix_agent_legacy; then
    return 0
  fi

  # Último recurso: binario estático
  log_warn "No se pudo instalar desde repositorios, usando binario estático..."
  if install_agent_from_binary; then
    return 0
  fi

  log_error "No se pudo instalar el agente Zabbix por ningún método"
}

# ==============================================
# FUNCIONES DE CONFIGURACIÓN
# ==============================================

configure_permissions() {
  log_step "Configurando permisos de directorios y archivos..."

  mkdir -p /etc/zabbix/ssl
  mkdir -p /var/log/zabbix
  mkdir -p /run/zabbix

  chown -R zabbix:zabbix /etc/zabbix 2>/dev/null
  chmod 755 /etc/zabbix
  chmod 750 /etc/zabbix/ssl 2>/dev/null || chmod 755 /etc/zabbix/ssl
  chmod 755 /var/log/zabbix
  chmod 755 /run/zabbix

  log_info "Permisos configurados correctamente"
}

fix_pid_file() {
  log_step "Corrigiendo archivo PID para systemd..."

  mkdir -p /run/zabbix
  chown zabbix:zabbix /run/zabbix
  chmod 755 /run/zabbix

  log_info "Directorio PID creado y configurado"
}

generate_psk() {
  log_step "Generando PSK para TLS..."

  mkdir -p /etc/zabbix/ssl
  chown -R zabbix:zabbix /etc/zabbix/ssl
  chmod 750 /etc/zabbix/ssl

  PSK_KEY=$(openssl rand -hex 32)
  PSK_IDENTITY="${HOSTNAME}_psk_$(date +%s)"

  echo -n "$PSK_KEY" >/etc/zabbix/ssl/psk.key

  chown zabbix:zabbix /etc/zabbix/ssl/psk.key
  chmod 640 /etc/zabbix/ssl/psk.key

  log_info "PSK generado: $PSK_IDENTITY"
}

configure_agent() {
  log_step "Configurando Zabbix Agent..."

  if [ -z "$CONFIG_FILE" ]; then
    log_error "CONFIG_FILE no está definido"
  fi

  mkdir -p $(dirname "$CONFIG_FILE")

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

  chown root:zabbix "$CONFIG_FILE"
  chmod 640 "$CONFIG_FILE"

  log_info "Agente configurado con TLS/PSK"
  log_info "Archivo de configuración: $CONFIG_FILE"
}

configure_firewall() {
  log_step "Configurando firewall..."
  if command -v firewall-cmd &>/dev/null; then
    if systemctl is-active --quiet firewalld 2>/dev/null; then
      firewall-cmd --permanent --add-port=${ZABBIX_AGENT_PORT}/tcp >>/tmp/zabbix_agent_install.log 2>&1
      firewall-cmd --reload >>/tmp/zabbix_agent_install.log 2>&1
      log_info "Puerto ${ZABBIX_AGENT_PORT}/tcp abierto en firewalld"
    fi
  elif command -v ufw &>/dev/null; then
    ufw allow ${ZABBIX_AGENT_PORT}/tcp >>/tmp/zabbix_agent_install.log 2>&1
    log_info "Puerto ${ZABBIX_AGENT_PORT}/tcp abierto en ufw"
  else
    log_warn "Firewall no detectado, configure manualmente el puerto ${ZABBIX_AGENT_PORT}"
  fi
}

# ==============================================
# FUNCIONES DE SERVICIO
# ==============================================

start_agent() {
  log_step "Iniciando servicio del agente..."

  fix_pid_file

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

  systemctl enable ${AGENT_SERVICE} >>/tmp/zabbix_agent_install.log 2>&1
  systemctl restart ${AGENT_SERVICE} >>/tmp/zabbix_agent_install.log 2>&1

  sleep 3

  if systemctl is-active ${AGENT_SERVICE} &>/dev/null; then
    log_info "Agente iniciado correctamente"
    return 0
  else
    log_error "Error al iniciar agente"
  fi
}

verify_agent_running() {
  log_step "Verificando que el agente está funcionando..."

  if ! systemctl is-active ${AGENT_SERVICE} &>/dev/null; then
    log_error "El agente no está corriendo. No se procederá con el registro en Zabbix"
  fi

  if command -v zabbix_get &>/dev/null; then
    local TEST=$(zabbix_get -s 127.0.0.1 -p ${ZABBIX_AGENT_PORT} -k agent.ping 2>/dev/null)
    if [ "$TEST" = "1" ]; then
      log_info "Agente responde correctamente a consulta local"
    else
      log_warn "El agente no responde a consulta local, pero el servicio está activo"
    fi
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

# ==============================================
# FUNCIONES DE API (SOLO DESPUÉS DE INSTALAR)
# ==============================================

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
    return 0
  elif echo "$RESPONSE" | grep -q "already exists"; then
    log_warn "El host '${HOSTNAME}' ya existe en Zabbix"
    log_warn "Si el agente ya estaba instalado, verificar la configuración manualmente"
    return 0
  else
    log_error "Error al registrar host: $RESPONSE"
  fi
}

# ==============================================
# FUNCIONES FINALES
# ==============================================

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
  echo -e "\n${YELLOW}📋 VERIFICACIÓN:${NC}"
  echo -e "  systemctl status ${AGENT_SERVICE}"
  echo -e "  tail -f /var/log/zabbix/${AGENT_TYPE}.log"
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
    echo -e "${RED}[✗] Opción desconocida: $1${NC}"
    exit 1
    ;;
  esac
done

clear
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Instalador de Agente Zabbix 7.4${NC}"
echo -e "${GREEN}  Soporta: CentOS 7/8, AlmaLinux/RHEL 8/9/10${NC}"
echo -e "${GREEN}  Prioridad: Agent2 > Agent > Binario${NC}"
echo -e "${GREEN}  PRIMERO instala, LUEGO registra${NC}"
echo -e "${GREEN}============================================${NC}\n"

check_root

# Configurar según modo
if [ -n "$CUSTOM_URL" ]; then
  ZABBIX_API_URL="$CUSTOM_URL"
  get_local_ip
  AGENT_IP="$LOCAL_IP"
elif [ "$MODE" = "lan" ]; then
  ZABBIX_API_URL="http://${ZABBIX_SERVER}/zabbix/api_jsonrpc.php"
  get_local_ip
  AGENT_IP="$LOCAL_IP"
  log_info "Modo LAN: $ZABBIX_API_URL"
elif [ "$MODE" = "wan" ]; then
  ZABBIX_API_URL="https://${ZABBIX_SERVER}/api_jsonrpc.php"
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

if [ "$AUTO_MODE" = false ]; then
  get_server_info
else
  [ -z "$API_TOKEN" ] && log_error "Modo automático requiere API_TOKEN"
  [ -z "$ZABBIX_SERVER" ] && log_error "Modo automático requiere ZABBIX_SERVER"
fi

HOSTNAME=$(hostname -f 2>/dev/null || hostname)
log_debug "Hostname final: $HOSTNAME"

# ==============================================
# INSTALACIÓN (PRIMERO)
# ==============================================

detect_os

# Deshabilitar TODOS los repositorios existentes
disable_all_repos

# Instalar dependencias y agente
install_dependencies
install_agent

# Configurar todo
configure_permissions
generate_psk
configure_agent
fix_pid_file
configure_firewall

# Iniciar y verificar agente
start_agent
verify_agent_running
test_local_connection

# Restaurar repositorios originales
restore_all_repos

# ==============================================
# REGISTRO EN ZABBIX (SOLO DESPUÉS)
# ==============================================

log_step "AGENTE INSTALADO Y FUNCIONANDO. Procediendo con registro en Zabbix..."

test_api_connection
register_host

# ==============================================
# FINALIZAR
# ==============================================

save_credentials
show_completion
