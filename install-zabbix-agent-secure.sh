#!/bin/bash
# ==============================================
# install-zabbix-agent-secure.sh
# Script para instalar Zabbix Agent 2 con PSK única
# Registro automático vía API en monitoreo.orangebox.cl
# ==============================================

# ==============================================
# CONFIGURACIÓN (editar aquí o dejar para prompt)
# ==============================================
ZABBIX_SERVER="" # Ej: monitoreo.orangebox.cl
ZABBIX_SERVER_PORT="10051"
ZABBIX_API_URL=""    # Ej: https://monitoreo.orangebox.cl/api_jsonrpc.php
ZABBIX_ADMIN_USER="" # Ej: Admin
ZABBIX_ADMIN_PASS=""
ZABBIX_VERSION="7.4"

# Archivos
LOG_FILE="/root/zabbix-agent-install.log"
CRED_FILE=""

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ==============================================
# FUNCIONES
# ==============================================
log() {
  echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
  echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"
}

log_warn() {
  echo -e "${YELLOW}[!]${NC} $1" | tee -a "$LOG_FILE"
}

log_step() {
  echo -e "\n${BLUE}[*]${NC} $1" | tee -a "$LOG_FILE"
}

prompt_variable() {
  local var_name="$1"
  local prompt_text="$2"
  local current_value="$3"
  local is_secret="$4"

  if [ -n "$current_value" ]; then
    log "Usando valor predefinido para $var_name"
    return 0
  fi

  echo -e "${YELLOW}${prompt_text}${NC}"
  if [ "$is_secret" = "true" ]; then
    read -s -r value
    echo
  else
    read -r value
  fi

  eval "$var_name='$value'"
}

# ==============================================
# SOLICITAR CONFIGURACIÓN SI NO ESTÁ DEFINIDA
# ==============================================
echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  ZABBIX AGENT SECURE INSTALLER${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

prompt_variable "ZABBIX_SERVER" "Ingrese el servidor Zabbix (ej: monitoreo.orangebox.cl):" "$ZABBIX_SERVER" "false"

if [ -z "$ZABBIX_API_URL" ]; then
  ZABBIX_API_URL="https://${ZABBIX_SERVER}/api_jsonrpc.php"
  log "URL API generada: $ZABBIX_API_URL"
fi

prompt_variable "ZABBIX_ADMIN_USER" "Ingrese usuario administrador de Zabbix (default: Admin):" "$ZABBIX_ADMIN_USER" "false"
if [ -z "$ZABBIX_ADMIN_USER" ]; then
  ZABBIX_ADMIN_USER="Admin"
  log "Usuario Admin por defecto"
fi

prompt_variable "ZABBIX_ADMIN_PASS" "Ingrese password del usuario ${ZABBIX_ADMIN_USER}:" "$ZABBIX_ADMIN_PASS" "true"
if [ -z "$ZABBIX_ADMIN_PASS" ]; then
  log_error "La password es obligatoria"
  exit 1
fi

# ==============================================
# VERIFICAR ROOT
# ==============================================
if [ "$EUID" -ne 0 ]; then
  log_error "Este script debe ejecutarse como root"
  exit 1
fi

# ==============================================
# DETECTAR SISTEMA OPERATIVO
# ==============================================
log_step "Detectando sistema operativo..."

if [ -f /etc/redhat-release ]; then
  OS_FAMILY="rhel"
  OS_VERSION=$(rpm -q --qf "%{VERSION}" $(rpm -q --whatprovides redhat-release) 2>/dev/null | cut -d: -f1 | cut -d. -f1)
  log "Sistema RHEL/AlmaLinux/Rocky detectado (versión $OS_VERSION)"
elif [ -f /etc/debian_version ]; then
  OS_FAMILY="debian"
  OS_VERSION=$(cat /etc/debian_version | cut -d. -f1)
  log "Sistema Debian/Ubuntu detectado (versión $OS_VERSION)"
else
  log_error "Sistema operativo no soportado"
  exit 1
fi

# ==============================================
# GENERAR PSK ÚNICA PARA ESTE AGENTE
# ==============================================
log_step "Generando PSK única para este agente..."

HOSTNAME=$(hostname)
HOST_IP=$(hostname -I | awk '{print $1}')
PSK_IDENTITY="${HOSTNAME}_psk_$(date +%s)"
PSK_KEY=$(openssl rand -hex 32)

log "Hostname: $HOSTNAME"
log "IP: $HOST_IP"
log "PSK Identity: $PSK_IDENTITY"

# ==============================================
# INSTALAR REPOSITORIO ZABBIX
# ==============================================
log_step "Instalando repositorio Zabbix..."

if [ "$OS_FAMILY" = "rhel" ]; then
  if [ "$OS_VERSION" -ge 9 ]; then
    rpm -Uvh https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/release/el${OS_VERSION}/noarch/zabbix-release-latest-${ZABBIX_VERSION}.el${OS_VERSION}.noarch.rpm >>"$LOG_FILE" 2>&1
  elif [ "$OS_VERSION" -eq 8 ]; then
    rpm -Uvh https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/release/el8/noarch/zabbix-release-latest-${ZABBIX_VERSION}.el8.noarch.rpm >>"$LOG_FILE" 2>&1
  else
    rpm -Uvh https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/release/el7/noarch/zabbix-release-latest-${ZABBIX_VERSION}.el7.noarch.rpm >>"$LOG_FILE" 2>&1
  fi

  if command -v dnf &>/dev/null; then
    dnf clean all >>"$LOG_FILE" 2>&1
    dnf install -y zabbix-agent2 >>"$LOG_FILE" 2>&1
  else
    yum clean all >>"$LOG_FILE" 2>&1
    yum install -y zabbix-agent2 >>"$LOG_FILE" 2>&1
  fi
  log "Zabbix Agent 2 instalado"

elif [ "$OS_FAMILY" = "debian" ]; then
  wget -q https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/ubuntu/pool/main/z/zabbix-release/zabbix-release-latest-${ZABBIX_VERSION}.ubuntu24.04_all.deb -O /tmp/zabbix-release.deb
  dpkg -i /tmp/zabbix-release.deb >>"$LOG_FILE" 2>&1
  apt update >>"$LOG_FILE" 2>&1
  apt install -y zabbix-agent2 >>"$LOG_FILE" 2>&1
  log "Zabbix Agent 2 instalado"
fi

# ==============================================
# CONFIGURAR PSK
# ==============================================
log_step "Configurando PSK..."

mkdir -p /etc/zabbix
echo "$PSK_KEY" >/etc/zabbix/zabbix_agentd.psk
chmod 400 /etc/zabbix/zabbix_agentd.psk
chown zabbix:zabbix /etc/zabbix/zabbix_agentd.psk
log "Archivo PSK creado en /etc/zabbix/zabbix_agentd.psk"

# ==============================================
# CONFIGURAR ZABBIX AGENT 2
# ==============================================
log_step "Configurando Zabbix Agent 2..."

cat >/etc/zabbix/zabbix_agent2.conf <<EOF
Server=${ZABBIX_SERVER}
ServerActive=${ZABBIX_SERVER}:${ZABBIX_SERVER_PORT}
Hostname=${HOSTNAME}

TLSConnect=psk
TLSAccept=psk
TLSPSKIdentity=${PSK_IDENTITY}
TLSPSKFile=/etc/zabbix/zabbix_agentd.psk

StartAgents=3
Timeout=30
LogFile=/var/log/zabbix/zabbix_agent2.log
LogFileSize=10
DebugLevel=3

Include=/etc/zabbix/zabbix_agent2.d/*.conf
EOF

log "Archivo de configuración creado"

# ==============================================
# INICIAR SERVICIO
# ==============================================
log_step "Iniciando Zabbix Agent 2..."

systemctl restart zabbix-agent2
systemctl enable zabbix-agent2

if systemctl is-active --quiet zabbix-agent2; then
  log "Zabbix Agent 2 está corriendo"
else
  log_error "Zabbix Agent 2 no pudo iniciar"
  systemctl status zabbix-agent2 --no-pager
  exit 1
fi

# ==============================================
# INSTALAR JQ SI NO EXISTE
# ==============================================
if ! command -v jq &>/dev/null; then
  log_step "Instalando jq..."
  if [ "$OS_FAMILY" = "rhel" ]; then
    dnf install -y jq >>"$LOG_FILE" 2>&1 || yum install -y jq >>"$LOG_FILE" 2>&1
  else
    apt install -y jq >>"$LOG_FILE" 2>&1
  fi
fi

# ==============================================
# REGISTRAR HOST EN ZABBIX VÍA API
# ==============================================
log_step "Registrando host en Zabbix Server via API..."

# Obtener template id
TEMPLATE_ID=$(curl -s -k -X POST \
  -H "Content-Type: application/json-rpc" \
  -d "{
    \"jsonrpc\": \"2.0\",
    \"method\": \"template.get\",
    \"params\": {
      \"filter\": {\"name\": [\"Template OS Linux by Zabbix agent\"]},
      \"output\": [\"templateid\"]
    },
    \"auth\": null,
    \"id\": 1
  }" ${ZABBIX_API_URL} | jq -r '.result[0].templateid')

# Obtener group id
GROUP_ID=$(curl -s -k -X POST \
  -H "Content-Type: application/json-rpc" \
  -d "{
    \"jsonrpc\": \"2.0\",
    \"method\": \"hostgroup.get\",
    \"params\": {
      \"filter\": {\"name\": [\"Linux servers\"]},
      \"output\": [\"groupid\"]
    },
    \"auth\": null,
    \"id\": 1
  }" ${ZABBIX_API_URL} | jq -r '.result[0].groupid')

# Autenticar
AUTH_TOKEN=$(curl -s -k -X POST \
  -H "Content-Type: application/json-rpc" \
  -d "{
    \"jsonrpc\": \"2.0\",
    \"method\": \"user.login\",
    \"params\": {
      \"username\": \"${ZABBIX_ADMIN_USER}\",
      \"password\": \"${ZABBIX_ADMIN_PASS}\"
    },
    \"id\": 1
  }" ${ZABBIX_API_URL} | jq -r '.result')

if [ "$AUTH_TOKEN" = "null" ] || [ -z "$AUTH_TOKEN" ]; then
  log_error "No se pudo autenticar en Zabbix API"
  log_warn "Registro manual requerido"
else
  log "Autenticación exitosa"

  CREATE_RESULT=$(curl -s -k -X POST \
    -H "Content-Type: application/json-rpc" \
    -d "{
        \"jsonrpc\": \"2.0\",
        \"method\": \"host.create\",
        \"params\": {
          \"host\": \"${HOSTNAME}\",
          \"name\": \"${HOSTNAME}\",
          \"groups\": [{\"groupid\": \"${GROUP_ID}\"}],
          \"templates\": [{\"templateid\": \"${TEMPLATE_ID}\"}],
          \"interfaces\": [{
            \"type\": 1,
            \"main\": 1,
            \"useip\": 1,
            \"ip\": \"${HOST_IP}\",
            \"dns\": \"\",
            \"port\": \"10050\"
          }],
          \"tls_connect\": 2,
          \"tls_accept\": 2,
          \"tls_psk_identity\": \"${PSK_IDENTITY}\",
          \"tls_psk\": \"${PSK_KEY}\"
        },
        \"auth\": \"${AUTH_TOKEN}\",
        \"id\": 1
      }" ${ZABBIX_API_URL})

  HOST_ID=$(echo "$CREATE_RESULT" | jq -r '.result.hostids[0]')

  if [ "$HOST_ID" != "null" ] && [ -n "$HOST_ID" ]; then
    log "Host registrado exitosamente (ID: $HOST_ID)"
  else
    log_error "Error al registrar host"
  fi
fi

# ==============================================
# GUARDAR CREDENCIALES
# ==============================================
CRED_FILE="/root/zabbix_agent_${HOSTNAME}_credentials.txt"
cat >"$CRED_FILE" <<EOF
=============================================
ZABBIX AGENT CREDENCIALES
=============================================
Hostname: $HOSTNAME
IP: $HOST_IP
Servidor: $ZABBIX_SERVER
Fecha: $(date)

PSK Identity: $PSK_IDENTITY
PSK Key: $PSK_KEY

Archivos:
  Configuración: /etc/zabbix/zabbix_agent2.conf
  Clave PSK: /etc/zabbix/zabbix_agentd.psk
  Log: $LOG_FILE

Comando de prueba:
zabbix_get -s $HOST_IP -p 10050 -k "agent.ping" \\
    --tls-connect psk \\
    --tls-psk-identity "$PSK_IDENTITY" \\
    --tls-psk-file /etc/zabbix/zabbix_agentd.psk
EOF

chmod 600 "$CRED_FILE"
log "Credenciales guardadas en: $CRED_FILE"

# ==============================================
# RESUMEN FINAL
# ==============================================
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  ZABBIX AGENT INSTALADO CORRECTAMENTE${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Hostname: $HOSTNAME"
echo "IP: $HOST_IP"
echo "Servidor: $ZABBIX_SERVER"
echo ""
echo "PSK Identity: $PSK_IDENTITY"
echo ""
echo "Credenciales: $CRED_FILE"
echo "Log: $LOG_FILE"
echo ""
echo -e "${GREEN}============================================${NC}"
