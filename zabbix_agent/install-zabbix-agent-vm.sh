#!/bin/bash
# =============================================================================
# Autor: Felipe Román froman@orangebox.cl
# Script de Instalación/Reparación del Agente Zabbix para RHEL (6/7/8/9/10)
# Incluye registro automático en Zabbix vía API, vinculación de plantillas
# y configuración de firewall (firewalld/iptables)
# Uso: ./install_zabbix_agent.sh [IP_O_HOSTNAME_DEL_SERVIDOR_ZABBIX]
# =============================================================================

# --- Variables de configuración (EDITAR SEGÚN ENTORNO) ---
DEFAULT_ZABBIX_SERVER="192.168.200.240"
ZABBIX_API_URL="http://monitoreo.orangebox.cl/zabbix/api_jsonrpc.php"
API_TOKEN="TU_NUEVO_TOKEN_AQUI"

# Plantillas a vincular (nombre exacto en Zabbix)
TEMPLATE_NAMES=(
  "Linux by Zabbix agent"
  "VMware Guest"
)

# --- Archivos de configuración ---
ZABBIX_AGENT_CONFIG="/etc/zabbix/zabbix_agentd.conf"
ZABBIX_AGENT2_CONFIG="/etc/zabbix/zabbix_agent2.conf"
LOG_FILE="/var/log/zabbix_install.log"

# Variable para trackear qué agente se instaló
AGENT_INSTALLED=""
DISTRO_TYPE=""
ZABBIX_VERSION_INSTALLED=""

# --- Colores ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Funciones de logging ---
log() {
  echo -e "$1"
  echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" >>$LOG_FILE
}

log_info() { log "${GREEN}✅${NC} $1"; }
log_error() { log "${RED}❌${NC} $1"; }
log_warn() { log "${YELLOW}⚠️${NC} $1"; }
log_step() { log "${BLUE}🔧${NC} $1"; }

# =============================================================================
# FUNCIONES DE DETECCIÓN Y MANEJO DE SERVICIOS
# =============================================================================

# --- Función para detectar el sistema de inicialización ---
detect_init_system() {
  if command -v systemctl &>/dev/null && [ -d /run/systemd/system ]; then
    echo "systemd"
  elif [ -d /etc/init.d ]; then
    echo "sysvinit"
  else
    echo "unknown"
  fi
}

# --- Función para manejar servicios de forma unificada ---
service_control() {
  local action="$1"
  local service_name="$2"
  local init_system=$(detect_init_system)

  case "$init_system" in
  "systemd")
    systemctl "$action" "$service_name" 2>/dev/null
    return $?
    ;;
  "sysvinit")
    if [ "$action" = "enable" ]; then
      if command -v chkconfig &>/dev/null; then
        chkconfig "$service_name" on 2>/dev/null
        return $?
      elif [ -f "/etc/init.d/$service_name" ]; then
        return 0
      fi
    elif [ "$action" = "is-active" ]; then
      if [ -f "/etc/init.d/$service_name" ]; then
        /etc/init.d/"$service_name" status >/dev/null 2>&1
        return $?
      fi
    else
      if [ -f "/etc/init.d/$service_name" ]; then
        /etc/init.d/"$service_name" "$action" >/dev/null 2>&1
        return $?
      fi
    fi
    return 1
    ;;
  *)
    return 1
    ;;
  esac
}

# --- Función para verificar si un servicio está activo ---
service_is_active() {
  local service_name="$1"
  local init_system=$(detect_init_system)

  case "$init_system" in
  "systemd")
    systemctl is-active --quiet "$service_name" 2>/dev/null
    return $?
    ;;
  "sysvinit")
    if [ -f "/etc/init.d/$service_name" ]; then
      /etc/init.d/"$service_name" status >/dev/null 2>&1
      return $?
    fi
    return 1
    ;;
  *)
    return 1
    ;;
  esac
}

# --- Función para recargar daemons (solo systemd) ---
service_daemon_reload() {
  local init_system=$(detect_init_system)
  if [ "$init_system" = "systemd" ]; then
    systemctl daemon-reload 2>/dev/null
  fi
}

# =============================================================================
# FUNCIONES DE FIREWALL
# =============================================================================

# --- Función para configurar firewalld ---
configure_firewalld() {
  local zabbix_server_ip="$1"

  if ! command -v firewall-cmd &>/dev/null; then
    return 1
  fi

  if ! systemctl is-active --quiet firewalld 2>/dev/null; then
    log_info "firewalld está instalado pero no activo. Omitiendo configuración."
    return 1
  fi

  log_info "firewalld detectado y activo. Configurando reglas..."

  local zone=$(firewall-cmd --get-default-zone 2>/dev/null)
  [ -z "$zone" ] && zone="public"

  if firewall-cmd --zone="$zone" --list-rich-rule 2>/dev/null | grep -q "source address=\"$zabbix_server_ip\" port port=\"10050\""; then
    log_info "Regla firewalld ya existente para $zabbix_server_ip"
    return 0
  fi

  log_step "Agregando regla a firewalld: permitir $zabbix_server_ip al puerto 10050"
  firewall-cmd --permanent --zone="$zone" --add-rich-rule="rule family=\"ipv4\" source address=\"$zabbix_server_ip\" port protocol=\"tcp\" port=\"10050\" accept" 2>/dev/null
  firewall-cmd --reload 2>/dev/null

  if [ $? -eq 0 ]; then
    log_info "Regla firewalld agregada correctamente"
    return 0
  else
    log_warn "No se pudo agregar la regla a firewalld"
    return 1
  fi
}

# --- Función para guardar reglas de iptables ---
save_iptables_rules() {
  if [ -f /etc/redhat-release ] || [ -f /etc/almalinux-release ] || [ -f /etc/rocky-release ] || [ -f /etc/centos-release ]; then
    if command -v iptables-save &>/dev/null; then
      iptables-save >/etc/sysconfig/iptables 2>/dev/null && log_info "Reglas iptables guardadas en /etc/sysconfig/iptables"
    fi
  elif [ -f /etc/debian_version ]; then
    if command -v iptables-save &>/dev/null; then
      iptables-save >/etc/iptables/rules.v4 2>/dev/null && log_info "Reglas iptables guardadas en /etc/iptables/rules.v4"
    fi
  else
    iptables-save >/etc/iptables.rules 2>/dev/null && log_info "Reglas iptables guardadas en /etc/iptables.rules"
  fi
}

# --- Función para configurar iptables ---
configure_iptables() {
  local zabbix_server_ip="$1"

  if ! command -v iptables &>/dev/null; then
    return 1
  fi

  if ! iptables -L -n 2>/dev/null | grep -q "Chain INPUT"; then
    return 1
  fi

  local input_policy=$(iptables -L INPUT -n 2>/dev/null | grep -i "Chain INPUT" | grep -o '(policy [A-Z]*)' | grep -o '[A-Z]*' | head -1)

  if [ -z "$input_policy" ]; then
    log_warn "No se pudo determinar la política de INPUT de iptables"
    return 1
  fi

  log_info "Política actual de INPUT: $input_policy"

  if iptables -L INPUT -n 2>/dev/null | grep -q "ACCEPT.*tcp dpt:10050.*$zabbix_server_ip"; then
    log_info "Regla iptables ya existente para $zabbix_server_ip al puerto 10050"
    return 0
  fi

  if [ "$input_policy" = "DROP" ] || [ "$input_policy" = "REJECT" ]; then
    log_step "Política INPUT en DROP/REJECT. Agregando regla para Zabbix Server..."
    iptables -I INPUT 1 -s "$zabbix_server_ip" -p tcp --dport 10050 -j ACCEPT
    log_info "Regla iptables agregada: iptables -I INPUT 1 -s $zabbix_server_ip -p tcp --dport 10050 -j ACCEPT"
    save_iptables_rules
    return 0
  else
    log_info "Política INPUT es $input_policy. No se requieren reglas adicionales."
    return 0
  fi
}

# --- Función principal de configuración de firewall ---
configure_firewall() {
  local zabbix_server_ip="$1"

  log_step "Configurando firewall para permitir conexiones desde Zabbix Server ($zabbix_server_ip)..."

  if configure_firewalld "$zabbix_server_ip"; then
    log_info "Firewall configurado correctamente con firewalld"
    return 0
  fi

  if configure_iptables "$zabbix_server_ip"; then
    log_info "Firewall configurado correctamente con iptables"
    return 0
  fi

  log_warn "No se detectó firewalld activo ni iptables configurado"
  log_warn "Verifica manualmente que el puerto 10050 esté accesible desde $zabbix_server_ip"
  return 1
}

# =============================================================================
# FUNCIONES DE API DE ZABBIX
# =============================================================================

# --- Función para llamar a la API de Zabbix ---
zabbix_api_call() {
  local method="$1"
  local params="$2"

  local response=$(curl -s -k -X POST \
    -H "Content-Type: application/json-rpc" \
    -H "Authorization: Bearer ${API_TOKEN}" \
    -d "{
            \"jsonrpc\": \"2.0\",
            \"method\": \"${method}\",
            \"params\": ${params},
            \"id\": 1
        }" ${ZABBIX_API_URL})

  echo "$response"
}

# --- Función para obtener el ID de una plantilla por nombre ---
get_template_id() {
  local template_name="$1"
  local response=$(zabbix_api_call "template.get" "{\"output\": [\"templateid\"], \"filter\": {\"name\": \"${template_name}\"}}")
  local template_id=$(echo "$response" | grep -o '"templateid":"[^"]*"' | head -1 | cut -d'"' -f4)
  echo "$template_id"
}

# --- Función para obtener el ID de un grupo por nombre ---
get_group_id() {
  local group_name="$1"
  local response=$(zabbix_api_call "hostgroup.get" "{\"output\": [\"groupid\"], \"filter\": {\"name\": \"${group_name}\"}}")
  local group_id=$(echo "$response" | grep -o '"groupid":"[^"]*"' | head -1 | cut -d'"' -f4)

  if [ -z "$group_id" ]; then
    log_step "Creando grupo '$group_name'..."
    response=$(zabbix_api_call "hostgroup.create" "{\"name\": \"${group_name}\"}")
    group_id=$(echo "$response" | grep -o '"groupids":\["[^"]*"' | grep -o '[0-9]*' | head -1)
  fi
  echo "$group_id"
}

# --- Función para obtener el ID de un host por nombre visible ---
get_host_id_by_name() {
  local hostname="$1"
  local response=$(zabbix_api_call "host.get" "{\"output\": [\"hostid\"], \"filter\": {\"name\": \"${hostname}\"}}")
  local host_id=$(echo "$response" | grep -o '"hostid":"[^"]*"' | head -1 | cut -d'"' -f4)
  echo "$host_id"
}

# --- Función para actualizar templates de un host existente ---
update_host_templates() {
  local host_id="$1"
  shift
  local template_ids=("$@")

  local templates_json="["
  for i in "${!template_ids[@]}"; do
    if [ -n "${template_ids[$i]}" ]; then
      [ "$i" -gt 0 ] && templates_json+=","
      templates_json+="{\"templateid\": \"${template_ids[$i]}\"}"
    fi
  done
  templates_json+="]"

  log_step "Actualizando plantillas del host $host_id..."
  local response=$(zabbix_api_call "host.update" "{\"hostid\": \"${host_id}\", \"templates\": ${templates_json}}")

  if echo "$response" | grep -q '"result"'; then
    log_info "Plantillas actualizadas correctamente."
    return 0
  else
    local error_msg=$(echo "$response" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
    log_error "Error al actualizar plantillas: $error_msg"
    return 1
  fi
}

# --- Función para crear un nuevo host en Zabbix ---
create_host() {
  local hostname="$1"
  local ip_address="$2"
  local group_id="$3"
  shift 3
  local template_ids=("$@")

  log_step "Creando nuevo host '$hostname' en Zabbix..."

  local interfaces_json="[{
        \"type\": 1,
        \"main\": 1,
        \"useip\": 1,
        \"ip\": \"${ip_address}\",
        \"dns\": \"\",
        \"port\": \"10050\"
    }]"

  local templates_json="["
  for i in "${!template_ids[@]}"; do
    if [ -n "${template_ids[$i]}" ]; then
      [ "$i" -gt 0 ] && templates_json+=","
      templates_json+="{\"templateid\": \"${template_ids[$i]}\"}"
    fi
  done
  templates_json+="]"

  local response=$(zabbix_api_call "host.create" "{
        \"host\": \"${hostname}\",
        \"name\": \"${hostname}\",
        \"groups\": [{\"groupid\": \"${group_id}\"}],
        \"interfaces\": ${interfaces_json},
        \"templates\": ${templates_json}
    }")

  if echo "$response" | grep -q '"result"'; then
    local new_host_id=$(echo "$response" | grep -o '"hostids":\["[^"]*"' | grep -o '[0-9]*' | head -1)
    log_info "Host '$hostname' creado exitosamente (ID: $new_host_id)"
    return 0
  else
    local error_msg=$(echo "$response" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
    log_error "Error al crear host: $error_msg"
    return 1
  fi
}

# --- Función para registrar o actualizar host en Zabbix ---
register_host_in_zabbix() {
  local hostname="$1"
  local ip_address="$2"
  local group_id="$3"
  shift 3
  local template_ids=("$@")

  log_step "Verificando host '$hostname' en Zabbix..."

  local existing_host_id=$(get_host_id_by_name "$hostname")

  if [ -n "$existing_host_id" ]; then
    log_info "El host '$hostname' ya existe (ID: $existing_host_id)"
    update_host_templates "$existing_host_id" "${template_ids[@]}"
  else
    log_info "El host '$hostname' no existe. Creándolo..."
    create_host "$hostname" "$ip_address" "$group_id" "${template_ids[@]}"
  fi
}

# =============================================================================
# FUNCIONES DE INSTALACIÓN DEL AGENTE
# =============================================================================

# --- Función de resolución DNS ---
resolve_dns() {
  local hostname="$1"
  local resolved_ip=""

  if command -v getent &>/dev/null; then
    resolved_ip=$(getent hosts "$hostname" 2>/dev/null | awk '{print $1}' | head -1)
    if [ -n "$resolved_ip" ]; then
      echo "$resolved_ip"
      return 0
    fi
  fi

  if command -v ping &>/dev/null; then
    resolved_ip=$(ping -c 1 -W 2 "$hostname" 2>/dev/null | head -1 | sed -n 's/.*(\([0-9.]*\)).*/\1/p')
    if [ -n "$resolved_ip" ]; then
      echo "$resolved_ip"
      return 0
    fi
  fi

  resolved_ip=$(grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\s+$hostname" /etc/hosts 2>/dev/null | awk '{print $1}' | head -1)
  if [ -n "$resolved_ip" ]; then
    echo "$resolved_ip"
    return 0
  fi

  return 1
}

# --- Función de precheck ---
precheck_and_resolve() {
  local input_server="$1"

  log_step "Realizando prechecks del sistema..."

  if [ "$EUID" -ne 0 ]; then
    log_error "Este script debe ejecutarse como root"
    exit 1
  fi
  log_info "Ejecutando como root"

  if [ -n "$input_server" ]; then
    ZABBIX_SERVER="$input_server"
    log_info "Usando servidor Zabbix desde parámetro: $ZABBIX_SERVER"
  else
    ZABBIX_SERVER="$DEFAULT_ZABBIX_SERVER"
    log_info "Usando servidor Zabbix por defecto: $ZABBIX_SERVER"
  fi

  echo ""
  log_step "Resolviendo servidor Zabbix: $ZABBIX_SERVER"

  if [[ "$ZABBIX_SERVER" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    RESOLVED_IP="$ZABBIX_SERVER"
    log_info "El servidor Zabbix es una IP: $RESOLVED_IP"
  else
    RESOLVED_IP=$(resolve_dns "$ZABBIX_SERVER")
    if [ -z "$RESOLVED_IP" ]; then
      log_error "No se pudo resolver el hostname: $ZABBIX_SERVER"
      exit 1
    fi
    log_info "Hostname resuelto: $ZABBIX_SERVER → $RESOLVED_IP"
  fi

  echo ""
  log_info "=== RESUMEN DE CONFIGURACIÓN ==="
  log_info "Servidor Zabbix: $RESOLVED_IP"
  log_info "Hostname local: $(hostname -f 2>/dev/null || hostname)"
  log_info "Init system: $(detect_init_system)"
  echo ""
}

# --- Función para determinar la distribución ---
get_distribution() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
  else
    if [ -f /etc/redhat-release ]; then
      OS="rhel"
      VER=$(rpm -q --qf "%{VERSION}" $(rpm -q --whatprovides redhat-release) | cut -d. -f1)
    else
      log_error "No se pudo determinar la distribución."
    fi
  fi

  case $OS in
  rhel | centos | almalinux | rocky | ol | fedora | redhat)
    OS_FAMILY="rhel"
    ;;
  *)
    OS_FAMILY="unknown"
    ;;
  esac

  OS_MAJOR_VER=$(echo $VER | cut -d. -f1)
  log_info "Distribución detectada: $OS $OS_MAJOR_VER"

  # Determinar tipo de distribución
  get_distribution_type
}

# --- Función para determinar el tipo de distribución ---
get_distribution_type() {
  # Detectar si es CentOS (EOL) o AlmaLinux/Rocky/RHEL (activos)
  if [ "$OS" = "centos" ]; then
    if [ "$OS_MAJOR_VER" -eq 6 ] || [ "$OS_MAJOR_VER" -eq 7 ] || [ "$OS_MAJOR_VER" -eq 8 ]; then
      DISTRO_TYPE="centos_eol"
    else
      DISTRO_TYPE="centos"
    fi
  elif [ "$OS" = "almalinux" ] || [ "$OS" = "rocky" ] || [ "$OS" = "rhel" ]; then
    DISTRO_TYPE="active"
  else
    DISTRO_TYPE="unknown"
  fi
  log_info "Tipo de distribución: $DISTRO_TYPE"
}

# --- Función para configurar repositorios para CentOS 6 (EOL) ---
configure_centos6_repos() {
  log_step "Configurando repositorios para CentOS 6 (EOL)..."

  # Crear backup de repos existentes si no existe
  if [ ! -d /etc/yum.repos.d/backup_original ]; then
    mkdir -p /etc/yum.repos.d/backup_original
    cp -r /etc/yum.repos.d/*.repo /etc/yum.repos.d/backup_original/ 2>/dev/null
  fi

  # Eliminar repos existentes para limpiar
  rm -f /etc/yum.repos.d/*.repo

  # Configurar repositorio Vault para CentOS 6
  cat >/etc/yum.repos.d/CentOS-Base.repo <<'EOF'
[base]
name=CentOS-6 - Base
baseurl=http://vault.centos.org/6.10/os/x86_64/
gpgcheck=1
gpgkey=http://vault.centos.org/6.10/os/x86_64/RPM-GPG-KEY-CentOS-6
enabled=1

[updates]
name=CentOS-6 - Updates
baseurl=http://vault.centos.org/6.10/updates/x86_64/
gpgcheck=1
gpgkey=http://vault.centos.org/6.10/os/x86_64/RPM-GPG-KEY-CentOS-6
enabled=1

[extras]
name=CentOS-6 - Extras
baseurl=http://vault.centos.org/6.10/extras/x86_64/
gpgcheck=1
gpgkey=http://vault.centos.org/6.10/os/x86_64/RPM-GPG-KEY-CentOS-6
enabled=1
EOF

  # Limpiar caché
  yum clean all &>/dev/null
  rm -rf /var/cache/yum/* &>/dev/null

  log_info "Repositorios CentOS 6 configurados correctamente"
}

# --- Función para configurar repositorios para CentOS 7 (EOL) ---
configure_centos7_repos() {
  log_step "Configurando repositorios para CentOS 7 (EOL)..."

  # Crear backup de repos existentes si no existe
  if [ ! -d /etc/yum.repos.d/backup_original ]; then
    mkdir -p /etc/yum.repos.d/backup_original
    cp -r /etc/yum.repos.d/*.repo /etc/yum.repos.d/backup_original/ 2>/dev/null
  fi

  # Eliminar repos existentes para limpiar
  rm -f /etc/yum.repos.d/*.repo

  # Configurar repositorio Base (Vault)
  cat >/etc/yum.repos.d/CentOS-Base.repo <<'EOF'
[base]
name=CentOS-7 - Base
baseurl=http://vault.centos.org/7.9.2009/os/x86_64/
gpgcheck=1
gpgkey=http://vault.centos.org/7.9.2009/os/x86_64/RPM-GPG-KEY-CentOS-7
enabled=1

[updates]
name=CentOS-7 - Updates
baseurl=http://vault.centos.org/7.9.2009/updates/x86_64/
gpgcheck=1
gpgkey=http://vault.centos.org/7.9.2009/os/x86_64/RPM-GPG-KEY-CentOS-7
enabled=1

[extras]
name=CentOS-7 - Extras
baseurl=http://vault.centos.org/7.9.2009/extras/x86_64/
gpgcheck=1
gpgkey=http://vault.centos.org/7.9.2009/os/x86_64/RPM-GPG-KEY-CentOS-7
enabled=1

[centosplus]
name=CentOS-7 - Plus
baseurl=http://vault.centos.org/7.9.2009/centosplus/x86_64/
gpgcheck=1
gpgkey=http://vault.centos.org/7.9.2009/os/x86_64/RPM-GPG-KEY-CentOS-7
enabled=0
EOF

  # Configurar EPEL
  cat >/etc/yum.repos.d/epel.repo <<'EOF'
[epel]
name=Extra Packages for Enterprise Linux 7 - x86_64
baseurl=http://download.fedoraproject.org/pub/epel/7/x86_64/
gpgcheck=0
enabled=1
EOF

  # Instalar EPEL release manualmente si es necesario
  if ! rpm -q epel-release &>/dev/null; then
    log_step "Instalando epel-release..."
    rpm -Uvh http://download.fedoraproject.org/pub/epel/7/x86_64/Packages/e/epel-release-7-14.noarch.rpm 2>/dev/null || true
  fi

  # Limpiar caché de yum
  yum clean all &>/dev/null
  rm -rf /var/cache/yum/* &>/dev/null

  log_info "Repositorios CentOS 7 configurados correctamente"
}

# --- Función para configurar repositorios para CentOS 8 (EOL) ---
configure_centos8_repos() {
  log_step "Configurando repositorios para CentOS 8 (EOL)..."

  # Crear backup de repos existentes si no existe
  if [ ! -d /etc/yum.repos.d/backup_original ]; then
    mkdir -p /etc/yum.repos.d/backup_original
    cp -r /etc/yum.repos.d/*.repo /etc/yum.repos.d/backup_original/ 2>/dev/null
  fi

  # Eliminar repos existentes para limpiar
  rm -f /etc/yum.repos.d/*.repo

  # Configurar repositorio Vault para CentOS 8
  cat >/etc/yum.repos.d/CentOS-Base.repo <<'EOF'
[base]
name=CentOS-8 - Base
baseurl=http://vault.centos.org/8.5.2111/BaseOS/x86_64/os/
gpgcheck=1
gpgkey=http://vault.centos.org/8.5.2111/BaseOS/x86_64/os/RPM-GPG-KEY-CentOS-Official
enabled=1

[appstream]
name=CentOS-8 - AppStream
baseurl=http://vault.centos.org/8.5.2111/AppStream/x86_64/os/
gpgcheck=1
gpgkey=http://vault.centos.org/8.5.2111/BaseOS/x86_64/os/RPM-GPG-KEY-CentOS-Official
enabled=1

[extras]
name=CentOS-8 - Extras
baseurl=http://vault.centos.org/8.5.2111/extras/x86_64/os/
gpgcheck=1
gpgkey=http://vault.centos.org/8.5.2111/BaseOS/x86_64/os/RPM-GPG-KEY-CentOS-Official
enabled=1

[powertools]
name=CentOS-8 - PowerTools
baseurl=http://vault.centos.org/8.5.2111/PowerTools/x86_64/os/
gpgcheck=1
gpgkey=http://vault.centos.org/8.5.2111/BaseOS/x86_64/os/RPM-GPG-KEY-CentOS-Official
enabled=1
EOF

  # Instalar EPEL para CentOS 8
  cat >/etc/yum.repos.d/epel.repo <<'EOF'
[epel]
name=Extra Packages for Enterprise Linux 8 - x86_64
baseurl=http://download.fedoraproject.org/pub/epel/8/Everything/x86_64/
gpgcheck=0
enabled=1

[epel-modular]
name=Extra Packages for Enterprise Linux Modular 8 - x86_64
baseurl=http://download.fedoraproject.org/pub/epel/8/Modular/x86_64/
gpgcheck=0
enabled=1
EOF

  # Limpiar caché de yum
  yum clean all &>/dev/null
  rm -rf /var/cache/yum/* &>/dev/null

  log_info "Repositorios CentOS 8 configurados correctamente"
}

# --- Función para verificar repositorios ---
check_repositories() {
  log_step "Verificando repositorios disponibles..."

  # Intentar hacer un yum repolist para verificar
  local repolist=$(yum repolist 2>&1)

  if echo "$repolist" | grep -q "Error"; then
    log_warn "Problemas detectados con los repositorios:"
    echo "$repolist" | grep -i "error" | head -5
    log_warn "Intentando continuar con la instalación..."
  else
    log_info "Repositorios verificados correctamente"
    local repo_count=$(echo "$repolist" | grep -E "^repo\s+id" -A 100 | grep -c "^[a-zA-Z]")
    log_info "Repositorios activos: $repo_count"
  fi
}

# --- Función para manejar repositorios (backup/restore) ---
manage_repos() {
  local action="$1"
  local REPO_BACKUP_DIR="/etc/yum.repos.d/backup_$(date +%Y%m%d_%H%M%S)"

  case "$action" in
  "backup")
    log_step "Respaldando repositorios existentes..."
    mkdir -p "$REPO_BACKUP_DIR"
    if [ -d "/etc/yum.repos.d" ]; then
      for repo_file in /etc/yum.repos.d/*.repo; do
        if [ -f "$repo_file" ]; then
          mv "$repo_file" "$REPO_BACKUP_DIR/" 2>/dev/null
        fi
      done
      log_info "Repositorios respaldados en: $REPO_BACKUP_DIR"
      echo "$REPO_BACKUP_DIR" >/tmp/zabbix_repo_backup_dir
    fi
    ;;
  "restore")
    if [ -f /tmp/zabbix_repo_backup_dir ]; then
      local BACKUP_DIR=$(cat /tmp/zabbix_repo_backup_dir)
      if [ -d "$BACKUP_DIR" ]; then
        log_step "Restaurando repositorios..."
        # Si existe backup original, restaurarlo
        if [ -d /etc/yum.repos.d/backup_original ]; then
          rm -f /etc/yum.repos.d/*.repo
          cp /etc/yum.repos.d/backup_original/*.repo /etc/yum.repos.d/ 2>/dev/null
        else
          mv "$BACKUP_DIR"/*.repo /etc/yum.repos.d/ 2>/dev/null
        fi
        rm -f /tmp/zabbix_repo_backup_dir
        log_info "Repositorios restaurados"
        yum clean all &>/dev/null
      fi
    fi
    ;;
  esac
}

# --- Función para instalar desde repositorio ---
install_from_repo() {

  # === LIMPIAR REPOSITORIO ZABBIX EXISTENTE ===
  log_step "Verificando repositorios Zabbix existentes..."

  # Buscar y eliminar cualquier paquete de repositorio Zabbix instalado
  ZABBIX_REPO_PACKAGES=$(rpm -qa | grep -i "zabbix-release" 2>/dev/null)

  if [ -n "$ZABBIX_REPO_PACKAGES" ]; then
    log_warn "Repositorios Zabbix existentes detectados: $ZABBIX_REPO_PACKAGES"
    log_step "Eliminando repositorios Zabbix antiguos..."

    for pkg in $ZABBIX_REPO_PACKAGES; do
      log_info "Eliminando: $pkg"
      rpm -e --nodeps "$pkg" 2>/dev/null
      if [ $? -eq 0 ]; then
        log_info "✅ $pkg eliminado correctamente"
      else
        log_warn "⚠️ No se pudo eliminar $pkg, intentando con yum..."
        yum remove -y "$pkg" 2>/dev/null
      fi
    done

    # Limpiar archivos residuales del repositorio
    rm -f /etc/yum.repos.d/zabbix*.repo 2>/dev/null
    rm -f /etc/pki/rpm-gpg/RPM-GPG-KEY-ZABBIX* 2>/dev/null

    # Limpiar caché de yum
    yum clean all 2>/dev/null
    log_info "✅ Repositorios Zabbix antiguos eliminados"
  else
    log_info "No se encontraron repositorios Zabbix existentes"
  fi

  # === CONTINUAR CON LA INSTALACIÓN ===

  log_step "Instalando Zabbix Agent desde repositorio oficial..."

  local REPO_URL=""
  local ZABBIX_VERSION=""

  # === CONFIGURACIÓN DE REPOSITORIOS SEGÚN DISTRIBUCIÓN ===

  # Para RHEL/CentOS 6 (EOL)
  if [ "$OS_MAJOR_VER" -eq 6 ]; then
    log_info "CentOS 6 EOL detectado - Configurando repositorios Vault..."
    configure_centos6_repos
    ZABBIX_VERSION="7.0"
    REPO_URL="https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/rhel/${OS_MAJOR_VER}/x86_64/zabbix-release-latest-${ZABBIX_VERSION}.el${OS_MAJOR_VER}.noarch.rpm"

  # Para CentOS 7 (EOL)
  elif [ "$OS_MAJOR_VER" -eq 7 ] && [ "$DISTRO_TYPE" = "centos_eol" ]; then
    log_info "CentOS 7 EOL detectado - Configurando repositorios Vault..."
    configure_centos7_repos
    ZABBIX_VERSION="7.0"
    REPO_URL="https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/rhel/${OS_MAJOR_VER}/x86_64/zabbix-release-latest-${ZABBIX_VERSION}.el${OS_MAJOR_VER}.noarch.rpm"

  # Para CentOS 8 (EOL)
  elif [ "$OS_MAJOR_VER" -eq 8 ] && [ "$DISTRO_TYPE" = "centos_eol" ]; then
    log_info "CentOS 8 EOL detectado - Configurando repositorios Vault..."
    configure_centos8_repos
    ZABBIX_VERSION="7.4"
    REPO_URL="https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/release/centos/${OS_MAJOR_VER}/noarch/zabbix-release-latest-${ZABBIX_VERSION}.el${OS_MAJOR_VER}.noarch.rpm"

  # Para AlmaLinux 8 / Rocky 8 / RHEL 8 (activos)
  elif [ "$OS_MAJOR_VER" -eq 8 ] && [ "$DISTRO_TYPE" = "active" ]; then
    log_info "Distribución activa EL8 detectada - Usando repositorios oficiales"
    ZABBIX_VERSION="7.4"
    REPO_URL="https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/release/alma/${OS_MAJOR_VER}/noarch/zabbix-release-latest-${ZABBIX_VERSION}.el${OS_MAJOR_VER}.noarch.rpm"

  # Para EL9
  elif [ "$OS_MAJOR_VER" -eq 9 ]; then
    log_info "EL9 detectado - Usando repositorios oficiales"
    ZABBIX_VERSION="7.4"
    REPO_URL="https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/release/alma/${OS_MAJOR_VER}/noarch/zabbix-release-latest-${ZABBIX_VERSION}.el${OS_MAJOR_VER}.noarch.rpm"

  # Para EL10
  elif [ "$OS_MAJOR_VER" -eq 10 ]; then
    log_info "EL10 detectado - Usando repositorios oficiales"
    ZABBIX_VERSION="7.4"
    REPO_URL="https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/release/alma/${OS_MAJOR_VER}/noarch/zabbix-release-latest-${ZABBIX_VERSION}.el${OS_MAJOR_VER}.noarch.rpm"

  else
    log_error "Versión de RHEL no soportada: $OS_MAJOR_VER"
    return 1
  fi

  log_info "Usando repositorio: $REPO_URL"
  log_info "Versión Zabbix: $ZABBIX_VERSION"
  ZABBIX_VERSION_INSTALLED="$ZABBIX_VERSION"

  # Backup de repositorios existentes (si no se hizo ya)
  if [ ! -f /tmp/zabbix_repo_backup_dir ]; then
    manage_repos "backup"
  fi

  # Instalar repositorio de Zabbix
  log_step "Instalando repositorio Zabbix..."
  if ! rpm -Uvh $REPO_URL 2>/dev/null; then
    log_error "Fallo al instalar repositorio Zabbix"
    manage_repos "restore"
    return 1
  fi

  # Limpiar caché de yum
  yum clean all &>/dev/null

  # Verificar repositorios
  check_repositories

  # Intentar instalar zabbix-agent2 primero
  log_step "Intentando instalar zabbix-agent2..."
  if yum install -y zabbix-agent2 2>/dev/null; then
    log_info "✅ zabbix-agent2 instalado correctamente desde repositorio"
    AGENT_INSTALLED="agent2"
    configure_agent_config "$AGENT_INSTALLED"
    manage_repos "restore"
    return 0
  fi

  # Si falla agent2, intentar con zabbix-agent
  log_warn "Fallo instalación de zabbix-agent2, intentando con zabbix-agent..."
  if yum install -y zabbix-agent 2>/dev/null; then
    log_info "✅ zabbix-agent instalado correctamente desde repositorio"
    AGENT_INSTALLED="agent"
    configure_agent_config "$AGENT_INSTALLED"
    manage_repos "restore"
    return 0
  fi

  # Si ambos fallan, mostrar diagnóstico
  log_error "❌ Falló la instalación de ambos agentes"
  log_warn "Posibles causas:"
  log_warn "  - Repositorios no disponibles"
  log_warn "  - Dependencias faltantes"
  log_warn "  - Problemas de red"

  log_step "Diagnóstico de repositorios:"
  yum repolist 2>&1 | head -20

  manage_repos "restore"
  return 1
}

# --- Función para configurar el agente ---
configure_agent_config() {
  local agent_type="$1"

  if [ "$agent_type" = "agent2" ] && [ -f "$ZABBIX_AGENT2_CONFIG" ]; then
    log_step "Configurando Zabbix Agent 2..."
    sed -i "s/^Server=.*/Server=$RESOLVED_IP/" $ZABBIX_AGENT2_CONFIG
    sed -i "s/^ServerActive=.*/ServerActive=$RESOLVED_IP/" $ZABBIX_AGENT2_CONFIG
    if ! grep -q "^Hostname=" $ZABBIX_AGENT2_CONFIG; then
      echo "Hostname=$(hostname -f 2>/dev/null || hostname)" >>$ZABBIX_AGENT2_CONFIG
    fi
    mkdir -p /run/zabbix
    chown zabbix:zabbix /run/zabbix 2>/dev/null

  elif [ "$agent_type" = "agent" ] && [ -f "$ZABBIX_AGENT_CONFIG" ]; then
    log_step "Configurando Zabbix Agent..."
    sed -i "s/^Server=.*/Server=$RESOLVED_IP/" $ZABBIX_AGENT_CONFIG
    sed -i "s/^ServerActive=.*/ServerActive=$RESOLVED_IP/" $ZABBIX_AGENT_CONFIG
    if ! grep -q "^Hostname=" $ZABBIX_AGENT_CONFIG; then
      echo "Hostname=$(hostname -f 2>/dev/null || hostname)" >>$ZABBIX_AGENT_CONFIG
    fi
    sed -i 's|^PidFile=.*|PidFile=/run/zabbix/zabbix_agentd.pid|' $ZABBIX_AGENT_CONFIG
  fi
}

# --- Función para reparar errores del agente ---
fix_agent_errors() {
  local service_name="$1"
  local config_file="$2"

  log_step "Reparando errores del servicio $service_name..."

  mkdir -p /run/zabbix /var/run/zabbix /var/log/zabbix /etc/zabbix/zabbix_agentd.d
  chown -R zabbix:zabbix /run/zabbix /var/run/zabbix /var/log/zabbix /etc/zabbix 2>/dev/null
  chmod 755 /run/zabbix /var/run/zabbix /var/log/zabbix 2>/dev/null

  if [ -f "$config_file" ]; then
    if [ "$service_name" = "zabbix-agent2" ]; then
      sed -i 's|^PidFile=.*|PidFile=/run/zabbix/zabbix_agent2.pid|' "$config_file" 2>/dev/null
    else
      sed -i 's|^PidFile=.*|PidFile=/run/zabbix/zabbix_agentd.pid|' "$config_file" 2>/dev/null
      if ! grep -q "^PidFile=" "$config_file"; then
        echo "PidFile=/run/zabbix/zabbix_agentd.pid" >>"$config_file"
      fi
    fi
  fi

  if ! id -u zabbix &>/dev/null; then
    useradd -r -s /sbin/nologin -d /var/lib/zabbix zabbix
  fi

  service_daemon_reload
  service_control "stop" "$service_name" 2>/dev/null
  sleep 1
  service_control "start" "$service_name"
  sleep 2

  if service_is_active "$service_name"; then
    log_info "Servicio $service_name reparado exitosamente."
    return 0
  else
    return 1
  fi
}

# =============================================================================
# FUNCIÓN PRINCIPAL
# =============================================================================

main() {
  echo "================================================================================"
  log "🚀 Script de Instalación/Registro de Zabbix Agent"
  echo "================================================================================"

  precheck_and_resolve "$1"

  # Configurar firewall ANTES de instalar el agente
  configure_firewall "$RESOLVED_IP"

  get_distribution

  if [[ "$OS_FAMILY" != "rhel" ]]; then
    log_error "Distribución no soportada: $OS"
    exit 1
  fi

  # Obtener IP y hostname local
  LOCAL_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v "127.0.0.1" | head -1)
  LOCAL_HOSTNAME=$(hostname -f 2>/dev/null || hostname)

  # --- Verificar API de Zabbix (opcional, no bloqueante) ---
  log_step "Verificando conexión con API de Zabbix..."
  API_TEST=$(curl -s -k -X POST \
    -H "Content-Type: application/json-rpc" \
    -d '{"jsonrpc":"2.0","method":"apiinfo.version","params":[],"id":1}' \
    ${ZABBIX_API_URL} 2>/dev/null)

  if echo "$API_TEST" | grep -q '"result"'; then
    ZABBIX_VERSION_API=$(echo "$API_TEST" | grep -o '"result":"[^"]*"' | cut -d'"' -f4)
    log_info "API de Zabbix accesible (versión: $ZABBIX_VERSION_API)"

    TOKEN_TEST=$(zabbix_api_call "user.get" "{\"output\": [\"userid\"], \"limit\": 1}" 2>/dev/null)
    if echo "$TOKEN_TEST" | grep -q '"result"'; then
      log_info "Token de API válido"

      TEMPLATE_IDS=()
      for template_name in "${TEMPLATE_NAMES[@]}"; do
        template_id=$(get_template_id "$template_name")
        if [ -n "$template_id" ]; then
          TEMPLATE_IDS+=("$template_id")
          log_info "Plantilla encontrada: $template_name (ID: $template_id)"
        else
          log_warn "Plantilla no encontrada: $template_name"
        fi
      done

      if [ ${#TEMPLATE_IDS[@]} -gt 0 ]; then
        GROUP_ID=$(get_group_id "Linux Servers")
        log_info "Grupo ID: $GROUP_ID"
        register_host_in_zabbix "$LOCAL_HOSTNAME" "$LOCAL_IP" "$GROUP_ID" "${TEMPLATE_IDS[@]}"
      else
        log_warn "No se encontraron plantillas. Omitiendo registro en Zabbix."
      fi
    else
      log_error "Token de API inválido o expirado"
      log_warn "El agente se instalará pero NO se registrará automáticamente"
    fi
  else
    log_warn "No se pudo conectar a la API de Zabbix (HTTP 404 o similar)"
    log_warn "El agente se instalará pero NO se registrará automáticamente"
  fi

  # --- Instalación del agente ---
  log_step "Procediendo con instalación del agente..."

  if ! install_from_repo; then
    log_error "❌ Falló la instalación del agente desde repositorio"
    log_warn "Revisa el archivo de log para más detalles: $LOG_FILE"
    exit 1
  fi

  log_info "Agente instalado: $AGENT_INSTALLED"
  log_info "Versión Zabbix: $ZABBIX_VERSION_INSTALLED"

  # Iniciar el agente instalado
  if [ "$AGENT_INSTALLED" = "agent2" ]; then
    service_daemon_reload
    service_control "enable" "zabbix-agent2" 2>/dev/null
    service_control "restart" "zabbix-agent2" 2>/dev/null
    sleep 2

    if ! service_is_active "zabbix-agent2"; then
      fix_agent_errors "zabbix-agent2" "$ZABBIX_AGENT2_CONFIG"
    fi

  elif [ "$AGENT_INSTALLED" = "agent" ]; then
    service_daemon_reload
    service_control "enable" "zabbix-agent" 2>/dev/null
    service_control "restart" "zabbix-agent" 2>/dev/null
    sleep 2

    if ! service_is_active "zabbix-agent"; then
      fix_agent_errors "zabbix-agent" "$ZABBIX_AGENT_CONFIG"
    fi
  fi

  # Verificación final
  echo ""
  log_step "Verificación final..."
  if service_is_active "zabbix-agent2" || service_is_active "zabbix-agent"; then
    log_info "✅ Zabbix Agent está funcionando correctamente."
    log_info "   Servidor configurado: $RESOLVED_IP"
    if service_is_active "zabbix-agent2"; then
      log_info "   Versión: Agent2 ($ZABBIX_VERSION_INSTALLED)"
    else
      log_info "   Versión: Agent ($ZABBIX_VERSION_INSTALLED)"
    fi
  else
    log_error "❌ No se pudo iniciar Zabbix Agent."
    log_warn "Revisa manualmente el estado del servicio."
  fi

  echo ""
  log_info "=== PROCESO COMPLETADO ==="
  log_info "Log: $LOG_FILE"
  echo "================================================================================"
}

# --- Ejecución ---
main "$@"
