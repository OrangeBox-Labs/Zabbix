#!/bin/bash

# ==============================================
# Script: install-zabbix-server.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Instalacion de Zabbix Server 7.4 en AlmaLinux 10
#              con MySQL/MariaDB, Apache y SELinux
#              Incluye hardening de MySQL y tuning para ~200 servidores
# ==============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variables configurables
ZABBIX_VERSION="7.4"
INSTALL_TYPE="server"
MYSQL_TUNING=true

# Variables estimadas para Zabbix con 200 servidores
# Aprox 200 servidores x 30 items x 60 segundos de intervalo = 6000 valores por segundo
EXPECTED_HOSTS=200
EXPECTED_ITEMS=30
EXPECTED_VALUES_PER_SECOND=6000

# Archivos de log y credenciales
CREDENTIALS_FILE="/root/zabbix_credentials_$(date +%Y%m%d_%H%M%S).txt"
LOG_FILE="/root/zabbix_install_$(date +%Y%m%d_%H%M%S).log"

# Variables que se llenaran durante la ejecucion
DB_PASSWORD=""
MYSQL_ROOT_PASSWORD=""
MYSQL_ALREADY_INSTALLED=false

# ==============================================
# FUNCIONES
# ==============================================

show_usage() {
  echo -e "${GREEN}USO:${NC}"
  echo "  $0                                    - Instalacion interactiva"
  echo "  $0 --auto                             - Instalacion automatica"
  echo "  $0 --agent                            - Instalar solo Zabbix Agent"
  echo "  $0 --no-tune                          - No aplicar tuning a MySQL"
  echo "  $0 --help                             - Mostrar esta ayuda"
  echo ""
  echo -e "${GREEN}EJEMPLOS:${NC}"
  echo "  # Instalacion interactiva"
  echo "  ./install-zabbix-server.sh"
  echo ""
  echo "  # Instalacion automatica"
  echo "  ./install-zabbix-server.sh --auto"
  echo ""
  echo "  # Instalar solo el agente"
  echo "  ./install-zabbix-server.sh --agent"
  echo ""
}

log_info() {
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

generate_password() {
  local length=${1:-24}
  tr -dc 'A-Za-z0-9!?@#%$&*' </dev/urandom 2>/dev/null | head -c "$length"
}

confirm_password() {
  local desc="$1"
  local generated="$2"
  local var_name="$3"
  local user_input=""

  echo -e "\n${YELLOW}${desc}:${NC}"
  echo -e "  Password generada: ${GREEN}${generated}${NC}"
  echo -e "${YELLOW}¿Desea usar esta password? (s/N para cambiarla): ${NC}"
  read -r confirm

  if [[ "$confirm" =~ ^[Ss]$ ]]; then
    eval "$var_name='$generated'"
    echo -e "${GREEN}  ✓ Usando password generada${NC}"
  else
    echo -e "${YELLOW}  Ingrese la nueva password:${NC}"
    read -r -s user_input
    echo -e "${YELLOW}  Confirme la password:${NC}"
    read -r -s user_input2
    if [ "$user_input" = "$user_input2" ] && [ -n "$user_input" ]; then
      eval "$var_name='$user_input'"
      echo -e "${GREEN}  ✓ Password personalizada configurada${NC}"
    else
      echo -e "${RED}  ✗ Las passwords no coinciden o estan vacias. Usando generada.${NC}"
      eval "$var_name='$generated'"
    fi
  fi
}

check_root() {
  if [ "$EUID" -ne 0 ]; then
    log_error "Este script debe ejecutarse como root"
    exit 1
  fi
}

detect_os() {
  if [ -f /etc/redhat-release ]; then
    OS_VERSION=$(rpm -q --qf "%{VERSION}" $(rpm -q --whatprovides redhat-release) 2>/dev/null | cut -d: -f1 | cut -d. -f1)
    if [ "$OS_VERSION" != "10" ]; then
      log_warn "Este script fue diseñado para AlmaLinux 10. Version detectada: $OS_VERSION"
      read -p "¿Desea continuar de todas formas? (s/N): " -r
      if [[ ! "$REPLY" =~ ^[Ss]$ ]]; then
        exit 1
      fi
    else
      log_info "Sistema operativo compatible: AlmaLinux $OS_VERSION"
    fi
  else
    log_warn "No se pudo detectar la distribucion"
  fi
}

init_log() {
  echo "==============================================" >"$LOG_FILE"
  echo "Instalacion de Zabbix Server - $(date)" >>"$LOG_FILE"
  echo "==============================================" >>"$LOG_FILE"
  echo "" >>"$LOG_FILE"
  log_info "Log de instalacion: $LOG_FILE"
}

check_mysql_installed() {
  log_step "Verificando instalacion de MySQL/MariaDB..."

  if command -v mysql &>/dev/null; then
    MYSQL_ALREADY_INSTALLED=true
    log_info "MySQL/MariaDB ya esta instalado"

    # Verificar si podemos conectar como root
    if mysql -uroot -e "SELECT 1" &>/dev/null; then
      log_info "MySQL/MariaDB esta accesible (sin password)"
    elif [ -f /root/.my.cnf ] && mysql --defaults-file=/root/.my.cnf -e "SELECT 1" &>/dev/null; then
      log_info "MySQL/MariaDB esta accesible (con archivo de configuracion)"
    else
      log_warn "MySQL/MariaDB instalado pero no se puede acceder como root"
    fi
  else
    MYSQL_ALREADY_INSTALLED=false
    log_info "MySQL/MariaDB no instalado, se procedera con la instalacion"
  fi
}

install_mariadb() {
  if [ "$MYSQL_ALREADY_INSTALLED" = true ]; then
    log_info "Saltando instalacion de MariaDB (ya existe)"
    return 0
  fi

  log_step "Instalando MariaDB..."
  dnf install mariadb-server mariadb -y >>"$LOG_FILE" 2>&1
  systemctl enable --now mariadb >>"$LOG_FILE" 2>&1
  log_info "MariaDB instalado y en ejecucion"
}

secure_mariadb() {
  log_step "Aplicando hardening a MySQL/MariaDB..."

  # Crear archivo temporal con comandos de seguridad
  local SECURE_SQL="/tmp/mysql_secure_$(date +%s).sql"

  cat >"$SECURE_SQL" <<EOF
-- Eliminar usuarios anonimos
DELETE FROM mysql.user WHERE User='';

-- Eliminar base de datos test
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';

-- Eliminar acceso remoto para root
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');

-- Limitar usuarios
FLUSH PRIVILEGES;
EOF

  # Ejecutar comandos de seguridad
  if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
    mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" <"$SECURE_SQL" >>"$LOG_FILE" 2>&1
  else
    mysql -uroot <"$SECURE_SQL" >>"$LOG_FILE" 2>&1
  fi

  rm -f "$SECURE_SQL"

  log_info "Hardening de MySQL aplicado: usuarios anonimos eliminados, DB test eliminada, acceso remoto deshabilitado"
}

setup_mysql_root_password() {
  log_step "Configurando password de root de MySQL..."

  if [ "$MYSQL_ALREADY_INSTALLED" = true ]; then
    # Cambiar password existente
    if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
      mysqladmin -u root password "$MYSQL_ROOT_PASSWORD" >>"$LOG_FILE" 2>&1 2>/dev/null ||
        mysql -uroot -p"${OLD_MYSQL_ROOT_PASSWORD}" -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';" >>"$LOG_FILE" 2>&1
    fi
  else
    # Configurar password por primera vez
    mysqladmin -u root password "$MYSQL_ROOT_PASSWORD" >>"$LOG_FILE" 2>&1
  fi

  # Crear archivo de configuracion para mysql client
  cat >/root/.my.cnf <<EOF
[client]
user=root
password=${MYSQL_ROOT_PASSWORD}
EOF
  chmod 600 /root/.my.cnf

  log_info "Password de root de MySQL configurado"
}

configure_mysql_tuning() {
  if [ "$MYSQL_TUNING" = false ]; then
    log_info "Tuning de MySQL omitido por peticion del usuario"
    return 0
  fi

  log_step "Aplicando tuning de MySQL para ~${EXPECTED_HOSTS} servidores..."

  local MYSQL_TUNING_FILE="/etc/my.cnf.d/zabbix-tuning.cnf"
  local MYSQL_VERSION=$(mysql --version | grep -oP 'Ver \K[0-9.]+' | cut -d. -f1)

  # Calcular valores optimos para ~200 servidores Zabbix
  # InnoDB: Los datos de Zabbix crecen ~1GB por 100 hosts por mes (aprox)
  local INNODB_BUFFER_POOL_SIZE="2G" # 25% de RAM si hay 8GB, ajustar
  local INNODB_LOG_FILE_SIZE="512M"
  local INNODB_LOG_BUFFER_SIZE="64M"
  local INNODB_FLUSH_LOG_AT_TRX_COMMIT="2" # Mejor performance para Zabbix

  # Calcular RAM disponible
  local TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
  if [ "$TOTAL_RAM" -ge 16 ]; then
    INNODB_BUFFER_POOL_SIZE="4G"
    INNODB_LOG_FILE_SIZE="1G"
  elif [ "$TOTAL_RAM" -ge 8 ]; then
    INNODB_BUFFER_POOL_SIZE="2G"
    INNODB_LOG_FILE_SIZE="512M"
  else
    INNODB_BUFFER_POOL_SIZE="1G"
    INNODB_LOG_FILE_SIZE="256M"
  fi

  cat >"$MYSQL_TUNING_FILE" <<EOF
# ==============================================
# Zabbix MySQL Tuning - Optimizado para ${EXPECTED_HOSTS} servidores
# Generado: $(date)
# ==============================================
[mysqld]

# --- Configuracion basica ---
max_connections = 500
max_connect_errors = 1000000
thread_cache_size = 128
table_open_cache = 4000
table_definition_cache = 4000

# --- InnoDB (motor usado por Zabbix) ---
default_storage_engine = InnoDB
innodb_buffer_pool_size = ${INNODB_BUFFER_POOL_SIZE}
innodb_log_file_size = ${INNODB_LOG_FILE_SIZE}
innodb_log_buffer_size = ${INNODB_LOG_BUFFER_SIZE}
innodb_flush_log_at_trx_commit = ${INNODB_FLUSH_LOG_AT_TRX_COMMIT}
innodb_flush_method = O_DIRECT
innodb_file_per_table = 1
innodb_read_io_threads = 16
innodb_write_io_threads = 16
innodb_io_capacity = 2000
innodb_io_capacity_max = 4000
innodb_buffer_pool_instances = 4
innodb_lock_wait_timeout = 50
innodb_print_all_deadlocks = 1

# --- Query cache (deshabilitado en MySQL 8+) ---
$([ "$MYSQL_VERSION" -lt 8 ] && echo "query_cache_size = 0" || echo "# query_cache_size = 0 (no aplica en MySQL 8+)")
$([ "$MYSQL_VERSION" -lt 8 ] && echo "query_cache_type = 0" || echo "# query_cache_type = 0")

# --- Timeouts y limites ---
connect_timeout = 30
wait_timeout = 600
interactive_timeout = 600
tmp_table_size = 64M
max_heap_table_size = 64M

# --- Sorting y temporales ---
sort_buffer_size = 2M
join_buffer_size = 2M
read_buffer_size = 1M
read_rnd_buffer_size = 4M

# --- Logging (minimo para Zabbix) ---
slow_query_log = 1
slow_query_log_file = /var/log/mariadb/slow-queries.log
long_query_time = 2
log_queries_not_using_indexes = 1

# --- Binlog (si aplica) ---
expire_logs_days = 7
max_binlog_size = 100M

# --- Zabbix especifico ---
# Optimizaciones para el esquema de Zabbix
innodb_strict_mode = ON
sql_mode = "NO_ENGINE_SUBSTITUTION"

# --- Caracteres ---
character_set_server = utf8mb4
collation_server = utf8mb4_bin

# --- Performance adicional ---
performance_schema = ON
max_allowed_packet = 16M
EOF

  # Reiniciar MariaDB para aplicar cambios
  systemctl restart mariadb >>"$LOG_FILE" 2>&1
  log_info "Tuning de MySQL aplicado: buffer_pool=${INNODB_BUFFER_POOL_SIZE}, log_file=${INNODB_LOG_FILE_SIZE}, max_connections=500"
}

setup_passwords() {
  log_step "Configurando passwords..."

  local random_db_pass=$(generate_password 24)
  local random_mysql_root_pass=$(generate_password 24)

  if [ "$AUTO_MODE" = true ]; then
    DB_PASSWORD="$random_db_pass"
    MYSQL_ROOT_PASSWORD="$random_mysql_root_pass"
    log_info "Passwords generadas automaticamente"
  else
    echo -e "\n${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  CONFIGURACION DE PASSWORDS${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    confirm_password "Password para usuario Zabbix en MySQL" "$random_db_pass" "DB_PASSWORD"
    confirm_password "Password para usuario root de MySQL" "$random_mysql_root_pass" "MYSQL_ROOT_PASSWORD"

    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
  fi
}

configure_repository() {
  log_step "Configurando repositorio de Zabbix..."

  if [ -f /etc/yum.repos.d/epel.repo ]; then
    if ! grep -q "excludepkgs=zabbix" /etc/yum.repos.d/epel.repo; then
      echo "excludepkgs=zabbix*" >>/etc/yum.repos.d/epel.repo
      log_info "Zabbix excluido de EPEL"
    fi
  fi

  rpm -Uvh https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/release/alma/10/noarch/zabbix-release-latest-${ZABBIX_VERSION}.el10.noarch.rpm >>"$LOG_FILE" 2>&1
  dnf clean all >>"$LOG_FILE" 2>&1
  log_info "Repositorio de Zabbix configurado"
}

install_server() {
  log_step "Instalando Zabbix Server, frontend y agente..."
  dnf install -y zabbix-server-mysql zabbix-web-mysql zabbix-apache-conf zabbix-sql-scripts zabbix-selinux-policy zabbix-agent >>"$LOG_FILE" 2>&1
  log_info "Paquetes de Zabbix instalados"
}

install_agent_only() {
  log_step "Instalando solo Zabbix Agent..."
  dnf install -y zabbix-agent >>"$LOG_FILE" 2>&1
  log_info "Zabbix Agent instalado"
}

create_database() {
  log_step "Creando base de datos para Zabbix..."

  mysql --defaults-file=/root/.my.cnf <<EOF
create database if not exists zabbix character set utf8mb4 collate utf8mb4_bin;
create user if not exists zabbix@localhost identified by '${DB_PASSWORD}';
grant all privileges on zabbix.* to zabbix@localhost;
set global log_bin_trust_function_creators = 1;
flush privileges;
EOF

  log_info "Base de datos y usuario creados"

  log_step "Importando esquema inicial..."
  zcat /usr/share/zabbix/sql-scripts/mysql/server.sql.gz | mysql --default-character-set=utf8mb4 -uzabbix -p${DB_PASSWORD} zabbix >>"$LOG_FILE" 2>&1

  mysql --defaults-file=/root/.my.cnf <<EOF
set global log_bin_trust_function_creators = 0;
flush privileges;
EOF

  log_info "Esquema de base de datos importado"
}

configure_server() {
  log_step "Configurando Zabbix Server..."

  sed -i "s/^# DBPassword=.*/DBPassword=${DB_PASSWORD}/" /etc/zabbix/zabbix_server.conf
  sed -i "s/^DBPassword=.*/DBPassword=${DB_PASSWORD}/" /etc/zabbix/zabbix_server.conf

  # Ajustes adicionales para rendimiento con 200 servidores
  sed -i "s/^# StartPollers=.*/StartPollers=40/" /etc/zabbix/zabbix_server.conf
  sed -i "s/^# StartPollersUnreachable=.*/StartPollersUnreachable=10/" /etc/zabbix/zabbix_server.conf
  sed -i "s/^# StartTrappers=.*/StartTrappers=20/" /etc/zabbix/zabbix_server.conf
  sed -i "s/^# StartPingers=.*/StartPingers=5/" /etc/zabbix/zabbix_server.conf
  sed -i "s/^# StartDiscoverers=.*/StartDiscoverers=5/" /etc/zabbix/zabbix_server.conf
  sed -i "s/^# CacheSize=.*/CacheSize=256M/" /etc/zabbix/zabbix_server.conf
  sed -i "s/^# HistoryCacheSize=.*/HistoryCacheSize=128M/" /etc/zabbix/zabbix_server.conf
  sed -i "s/^# TrendCacheSize=.*/TrendCacheSize=64M/" /etc/zabbix/zabbix_server.conf
  sed -i "s/^# ValueCacheSize=.*/ValueCacheSize=128M/" /etc/zabbix/zabbix_server.conf
  sed -i "s/^# Timeout=.*/Timeout=10/" /etc/zabbix/zabbix_server.conf

  sed -i "s/^; php_value date.timezone Europe\/Riga/php_value date.timezone America\/Santiago/" /etc/httpd/conf.d/zabbix.conf
  sed -i "s/^# php_value date.timezone Europe\/Riga/php_value date.timezone America\/Santiago/" /etc/httpd/conf.d/zabbix.conf

  log_info "Zabbix Server configurado (pollers=40, trappers=20, cache=256M)"
}

configure_agent() {
  log_step "Configurando Zabbix Agent..."

  local server_ip=$(hostname -I | awk '{print $1}')
  sed -i "s/^Server=127.0.0.1/Server=127.0.0.1,${server_ip}/" /etc/zabbix/zabbix_agentd.conf
  sed -i "s/^ServerActive=127.0.0.1/ServerActive=127.0.0.1,${server_ip}/" /etc/zabbix/zabbix_agentd.conf
  sed -i "s/^Hostname=Zabbix server/Hostname=$(hostname)/" /etc/zabbix/zabbix_agentd.conf

  log_info "Zabbix Agent configurado"
}

start_services() {
  log_step "Iniciando servicios..."

  systemctl restart zabbix-server zabbix-agent httpd php-fpm >>"$LOG_FILE" 2>&1
  systemctl enable zabbix-server zabbix-agent httpd php-fpm >>"$LOG_FILE" 2>&1

  log_info "Servicios iniciados y habilitados"
}

configure_firewall() {
  log_step "Configurando firewall..."

  if command -v firewall-cmd &>/dev/null; then
    firewall-cmd --permanent --add-service=http >>"$LOG_FILE" 2>&1
    firewall-cmd --permanent --add-port=10050/tcp >>"$LOG_FILE" 2>&1
    firewall-cmd --reload >>"$LOG_FILE" 2>&1
    log_info "Firewall configurado (http, 10050/tcp)"
  else
    log_warn "firewalld no instalado, omitiendo configuracion"
  fi
}

verify_mysql_tuning() {
  log_step "Verificando configuracion de MySQL..."

  local buffer_pool=$(mysql --defaults-file=/root/.my.cnf -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';" 2>/dev/null | awk 'NR==2 {print $2}')
  local max_conn=$(mysql --defaults-file=/root/.my.cnf -e "SHOW VARIABLES LIKE 'max_connections';" 2>/dev/null | awk 'NR==2 {print $2}')

  if [ -n "$buffer_pool" ]; then
    log_info "InnoDB Buffer Pool: $buffer_pool bytes"
  fi
  if [ -n "$max_conn" ]; then
    log_info "Max Connections: $max_conn"
  fi
}

create_credentials_file() {
  local server_ip=$(hostname -I | awk '{print $1}')

  cat >"$CREDENTIALS_FILE" <<EOF
=============================================
  ZABBIX SERVER - CREDENCIALES DE ACCESO
  Instalacion: $(date)
  Servidor: $(hostname)
  IP: ${server_ip}
=============================================

🔐 ACCESO WEB ZABBIX:
  URL: http://${server_ip}/zabbix
  Usuario: Admin
  Password: zabbix

🗄️ BASE DE DATOS MYSQL:
  Usuario root: root
  Password root: ${MYSQL_ROOT_PASSWORD}
  
  Usuario Zabbix DB: zabbix
  Password Zabbix DB: ${DB_PASSWORD}
  Base de datos: zabbix

⚙️ CONFIGURACION DE RENDIMIENTO:
  Servidores esperados: ${EXPECTED_HOSTS}
  Items por servidor: ${EXPECTED_ITEMS}
  Valores por segundo: ~${EXPECTED_VALUES_PER_SECOND}
  
  MySQL Tuning:
    - InnoDB Buffer Pool: $(mysql --defaults-file=/root/.my.cnf -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';" 2>/dev/null | awk 'NR==2 {print $2}' || echo "N/A")
    - Max Connections: $(mysql --defaults-file=/root/.my.cnf -e "SHOW VARIABLES LIKE 'max_connections';" 2>/dev/null | awk 'NR==2 {print $2}' || echo "N/A")
  
  Zabbix Server Tuning:
    - StartPollers: 40
    - StartTrappers: 20
    - CacheSize: 256M
    - HistoryCacheSize: 128M

📁 ARCHIVOS DE CONFIGURACION:
  Zabbix Server: /etc/zabbix/zabbix_server.conf
  Zabbix Agent: /etc/zabbix/zabbix_agentd.conf
  MySQL Tuning: /etc/my.cnf.d/zabbix-tuning.cnf
  Apache: /etc/httpd/conf.d/zabbix.conf

📋 LOGS:
  Zabbix Server: /var/log/zabbix/zabbix_server.log
  Zabbix Agent: /var/log/zabbix/zabbix_agentd.log
  MySQL: /var/log/mariadb/mariadb.log
  Slow Queries: /var/log/mariadb/slow-queries.log
  Instalacion: ${LOG_FILE}

=============================================
  COMANDOS UTILES
=============================================

# Estado de servicios
systemctl status zabbix-server zabbix-agent httpd php-fpm mariadb

# Ver logs
tail -f /var/log/zabbix/zabbix_server.log
tail -f /var/log/mariadb/slow-queries.log

# Conectar a MySQL
mysql --defaults-file=/root/.my.cnf
mysql -uzabbix -p'${DB_PASSWORD}' zabbix

# Monitorear performance
mysqladmin --defaults-file=/root/.my.cnf status
mysql --defaults-file=/root/.my.cnf -e "SHOW ENGINE INNODB STATUS\G"

=============================================
  ⚠️  RECOMENDACIONES POST-INSTALACION
=============================================

1. Cambiar password del usuario Admin en Zabbix Web
2. Configurar backups automaticos de la base de datos
3. Monitorear el tamaño de la DB: du -sh /var/lib/mysql/zabbix
4. Revisar logs de slow queries para optimizar
5. Configurar particion separada para /var/lib/mysql si es posible

=============================================
  🌐 https://www.orangebox.cl
=============================================
EOF

  chmod 600 "$CREDENTIALS_FILE"
  log_info "Archivo de credenciales creado: $CREDENTIALS_FILE"
}

show_completion() {
  local server_ip=$(hostname -I | awk '{print $1}')

  echo -e "\n${GREEN}============================================${NC}" | tee -a "$LOG_FILE"
  echo -e "${GREEN}  INSTALACION DE ZABBIX COMPLETADA${NC}" | tee -a "$LOG_FILE"
  echo -e "${GREEN}============================================${NC}" | tee -a "$LOG_FILE"
  echo -e "\n${YELLOW}URL DE ACCESO:${NC}" | tee -a "$LOG_FILE"
  echo -e "  http://${server_ip}/zabbix" | tee -a "$LOG_FILE"
  echo -e "\n${YELLOW}CREDENCIALES POR DEFECTO:${NC}" | tee -a "$LOG_FILE"
  echo -e "  Usuario: Admin" | tee -a "$LOG_FILE"
  echo -e "  Password: zabbix" | tee -a "$LOG_FILE"
  echo -e "\n${YELLOW}ARCHIVO DE CREDENCIALES:${NC}" | tee -a "$LOG_FILE"
  echo -e "  ${CREDENTIALS_FILE}" | tee -a "$LOG_FILE"
  echo -e "\n${YELLOW}LOG DE INSTALACION:${NC}" | tee -a "$LOG_FILE"
  echo -e "  ${LOG_FILE}" | tee -a "$LOG_FILE"
  echo -e "\n${GREEN}============================================${NC}" | tee -a "$LOG_FILE"
  echo -e "${GREEN}  🌐 https://www.orangebox.cl${NC}" | tee -a "$LOG_FILE"
  echo -e "${GREEN}============================================${NC}\n" | tee -a "$LOG_FILE"
}

# ==============================================
# OPCIONES DE LINEA DE COMANDOS
# ==============================================

AUTO_MODE=false
AGENT_ONLY=false

while [[ $# -gt 0 ]]; do
  case $1 in
  --auto)
    AUTO_MODE=true
    shift
    ;;
  --agent)
    AGENT_ONLY=true
    INSTALL_TYPE="agent"
    shift
    ;;
  --no-tune)
    MYSQL_TUNING=false
    shift
    ;;
  --help | -h)
    show_usage
    exit 0
    ;;
  *)
    log_error "Opcion desconocida: $1"
    show_usage
    exit 1
    ;;
  esac
done

# ==============================================
# MAIN
# ==============================================

clear
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Instalador de Zabbix Server 7.4${NC}"
echo -e "${GREEN}  para AlmaLinux 10${NC}"
echo -e "${GREEN}  Optimizado para ~200 servidores${NC}"
echo -e "${GREEN}============================================${NC}\n"

check_root
detect_os
init_log

if [ "$AGENT_ONLY" = false ]; then
  check_mysql_installed
  setup_passwords
fi

if [ "$AUTO_MODE" = false ] && [ "$AGENT_ONLY" = false ]; then
  echo -e "${YELLOW}Este script instalara Zabbix Server 7.4 con:${NC}"
  echo -e "  • MariaDB con hardening y tuning (buffer_pool: 2-4GB, max_connections: 500)"
  echo -e "  • Apache Web Server"
  echo -e "  • PHP-FPM"
  echo -e "  • Zabbix Server (configurado para ~200 servidores)"
  echo -e "  • Zabbix Agent"
  echo -e "  • SELinux Policy"
  echo -e "\n${YELLOW}¿Desea continuar? (s/N): ${NC}"
  read -r confirm
  if [[ ! "$confirm" =~ ^[Ss]$ ]]; then
    echo -e "${RED}Instalacion cancelada${NC}"
    exit 0
  fi
fi

if [ "$AGENT_ONLY" = true ]; then
  configure_repository
  install_agent_only
  configure_agent
  start_services
  configure_firewall
  echo -e "\n${GREEN}[✓] Zabbix Agent instalado correctamente${NC}"
  echo -e "Configuracion en: /etc/zabbix/zabbix_agentd.conf"
  echo -e "Log de instalacion: $LOG_FILE"
else
  install_mariadb
  setup_mysql_root_password
  secure_mariadb
  configure_mysql_tuning
  configure_repository
  install_server
  create_database
  configure_server
  configure_agent
  start_services
  configure_firewall
  verify_mysql_tuning
  create_credentials_file
  show_completion
fi
