#!/bin/bash

# ==============================================
# Script: install-zabbix-server.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Instalacion de Zabbix Server 7.4 en AlmaLinux 10
#              con MySQL/MariaDB, Apache y SELinux
#              Incluye hardening de MySQL y tuning para ~200 servidores
#              Configura locales: en_US, es_ES, es_CL
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
MYSQL_HAS_ROOT_PASSWORD=false
ZABBIX_ALREADY_INSTALLED=false
DB_HOST_TYPE="localhost"

# ==============================================
# FUNCIONES
# ==============================================

show_usage() {
  echo -e "${GREEN}USO:${NC}"
  echo "  $0                                    - Instalacion interactiva"
  echo "  $0 --auto                             - Instalacion automatica"
  echo "  $0 --agent                            - Instalar solo Zabbix Agent"
  echo "  $0 --uninstall                        - Desinstalar Zabbix completamente"
  echo "  $0 --reinstall                        - Reinstalar desde cero (desinstala y vuelve a instalar)"
  echo "  $0 --kill-zabbix                      - Matar todos los procesos Zabbix"
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
  echo "  # Reinstalar completamente"
  echo "  ./install-zabbix-server.sh --reinstall"
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

generate_safe_password() {
  local length=${1:-24}
  # Solo caracteres alfanumericos y algunos seguros: A-Za-z0-9._-
  tr -dc 'A-Za-z0-9._-' </dev/urandom 2>/dev/null | head -c "$length"
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
    echo -e "${YELLOW}  Ingrese la nueva password (solo letras, numeros, . _ -):${NC}"
    read -r -s user_input
    echo ""
    echo -e "${YELLOW}  Confirme la password:${NC}"
    read -r -s user_input2
    echo ""
    if [ "$user_input" = "$user_input2" ] && [ -n "$user_input" ] && [[ "$user_input" =~ ^[A-Za-z0-9._-]+$ ]]; then
      eval "$var_name='$user_input'"
      echo -e "${GREEN}  ✓ Password personalizada configurada${NC}"
    else
      echo -e "${RED}  ✗ Las passwords no coinciden, estan vacias o tienen caracteres invalidos. Usando generada.${NC}"
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

validate_mysql_root_password() {
  local password="$1"
  local max_attempts=3
  local attempt=1

  log_step "Validando contraseña de root de MySQL..."

  while [ $attempt -le $max_attempts ]; do
    echo -e "${YELLOW}Intento $attempt de $max_attempts${NC}"

    if mysql -uroot -p"${password}" -e "SELECT 1" >/dev/null 2>&1; then
      log_info "✓ Contraseña de root válida"
      MYSQL_ROOT_PASSWORD="$password"

      # Guardar en archivo .my.cnf
      cat >/root/.my.cnf <<EOF
[client]
user=root
password=${password}
EOF
      chmod 600 /root/.my.cnf
      return 0
    else
      log_error "✗ Contraseña incorrecta o no se puede conectar"

      if [ $attempt -lt $max_attempts ]; then
        echo -e "${YELLOW}Ingrese la contraseña correcta de root de MySQL:${NC}"
        read -r -s password
        echo ""
      fi
      ((attempt++))
    fi
  done

  log_error "No se pudo validar la contraseña de root después de $max_attempts intentos"
  return 1
}

validate_zabbix_db_user() {
  local password="$1"
  local max_attempts=3
  local attempt=1

  log_step "Validando usuario zabbix en la base de datos..."

  # Esperar un momento para que los permisos se apliquen
  sleep 2

  while [ $attempt -le $max_attempts ]; do
    if mysql -uzabbix --password="${password}" -h ${DB_HOST_TYPE} -e "SELECT 1" zabbix >/dev/null 2>&1; then
      log_info "✓ Usuario zabbix válido y con acceso a la base de datos"
      return 0
    else
      log_warn "✗ Usuario zabbix no puede conectar (intento $attempt de $max_attempts)"

      # Re-grantear permisos por si acaso
      mysql --defaults-file=/root/.my.cnf <<EOF
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'${DB_HOST_TYPE}';
FLUSH PRIVILEGES;
EOF
      sleep 2
      ((attempt++))
    fi
  done

  log_error "No se pudo validar el usuario zabbix después de $max_attempts intentos"
  return 1
}

save_credentials_early() {
  local db_pass="$1"
  local root_pass="$2"
  local server_ip=$(hostname -I | awk '{print $1}')

  # Crear archivo temporal de credenciales
  local temp_cred_file="/root/zabbix_credentials_temp.txt"

  cat >"$temp_cred_file" <<EOF
=============================================
  ZABBIX CREDENCIALES (TEMPORAL)
  Generado: $(date)
=============================================

🔐 BASE DE DATOS MYSQL:
  Usuario root: root
  Password root: ${root_pass}
  
  Usuario Zabbix DB: zabbix
  Password Zabbix DB: ${db_pass}

🔐 WEB ZABBIX (por defecto):
  Usuario: Admin
  Password: zabbix

=============================================
EOF
  chmod 600 "$temp_cred_file"
  log_info "Credenciales guardadas temporalmente en: $temp_cred_file"
}

kill_zabbix_processes() {
  log_step "Forzando terminación de procesos Zabbix..."

  # Detener servicios (forma limpia)
  systemctl stop zabbix-server zabbix-agent 2>/dev/null
  systemctl disable zabbix-server zabbix-agent 2>/dev/null

  # Esperar a que terminen graceful
  sleep 2

  # Matar SOLO los binarios específicos por ruta absoluta
  # Esto NO afecta scripts de bash
  pkill -9 -f "^/usr/sbin/zabbix_server" 2>/dev/null
  pkill -9 -f "^/usr/sbin/zabbix_agentd" 2>/dev/null
  pkill -9 -f "^/usr/bin/zabbix" 2>/dev/null

  # Método alternativo con killall (solo binarios)
  killall -9 zabbix_server 2>/dev/null
  killall -9 zabbix_agentd 2>/dev/null

  # Verificar con pgrep específico de binarios (no -f)
  sleep 1
  if pgrep "zabbix_server\|zabbix_agentd" >/dev/null 2>&1; then
    log_warn "Algunos procesos aún persisten"
  else
    log_info "Todos los procesos Zabbix han sido eliminados"
  fi
}

uninstall_zabbix() {
  log_step "PREPARANDO DESINSTALACIÓN DE ZABBIX"

  # Mensaje de advertencia y confirmación
  echo -e "\n${RED}══════════════════════════════════════════════════════════════════════${NC}"
  echo -e "${RED}⚠️  ADVERTENCIA: Se va a DESINSTALAR TODO ZABBIX${NC}"
  echo -e "${RED}══════════════════════════════════════════════════════════════════════${NC}"
  echo -e "${YELLOW}Esto incluye:${NC}"
  echo -e "  • Servicios de Zabbix Server y Agent"
  echo -e "  • Archivos de configuración (/etc/zabbix)"
  echo -e "  • Archivos de datos (/var/lib/zabbix)"
  echo -e "  • Logs (/var/log/zabbix)"
  echo -e "  • Base de datos 'zabbix' (opcional)"
  echo -e "  • Usuario 'zabbix' en MySQL"
  echo -e ""
  echo -e "${RED}⚠️  Esta acción es IRREVERSIBLE y NO se puede deshacer${NC}"
  echo -e ""
  read -p "Presione 's' para CONTINUAR o 'c' para CANCELAR: " confirm
  echo -e "${RED}══════════════════════════════════════════════════════════════════════${NC}\n"

  # Validar respuesta
  if [[ "$confirm" == [cC] ]]; then
    echo -e "${GREEN}✅ Operación cancelada por el usuario.${NC}"
    return 1
  fi

  if [[ "$confirm" != [sS] ]]; then
    echo -e "${RED}❌ Opción inválida. Cancelando operación.${NC}"
    return 1
  fi

  log_info "Iniciando desinstalación forzada de Zabbix..."

  # 1. FORZAR DETENCIÓN DE SERVICIOS
  log_step "Deteniendo servicios de Zabbix..."
  kill_zabbix_processes

  # 2. Eliminar paquetes
  log_step "Eliminando paquetes de Zabbix..."
  dnf remove -y zabbix-server-mysql zabbix-web-mysql zabbix-apache-conf zabbix-sql-scripts zabbix-selinux-policy zabbix-agent 2>/dev/null

  # 3. Eliminar archivos de configuración y datos
  log_step "Eliminando archivos y directorios..."
  rm -rf /etc/zabbix
  rm -rf /usr/share/zabbix
  rm -rf /var/lib/zabbix
  rm -rf /var/log/zabbix
  rm -rf /etc/httpd/conf.d/zabbix.conf
  rm -f /etc/zabbix_server.conf
  rm -f /etc/zabbix_agentd.conf

  # 4. Preguntar por base de datos
  if command -v mysql &>/dev/null && [ -f /root/.my.cnf ]; then
    echo -e "\n${YELLOW}¿Desea eliminar también la base de datos 'zabbix'? (s/N): ${NC}"
    read -r confirm_db
    if [[ "$confirm_db" =~ ^[Ss]$ ]]; then
      log_step "Eliminando base de datos..."
      mysql --defaults-file=/root/.my.cnf -e "DROP DATABASE IF EXISTS zabbix;" 2>/dev/null
      mysql --defaults-file=/root/.my.cnf -e "DROP USER IF EXISTS 'zabbix'@'localhost';" 2>/dev/null
      mysql --defaults-file=/root/.my.cnf -e "DROP USER IF EXISTS 'zabbix'@'127.0.0.1';" 2>/dev/null
      mysql --defaults-file=/root/.my.cnf -e "FLUSH PRIVILEGES;" 2>/dev/null
      log_info "Base de datos y usuario eliminados"
    else
      log_info "Manteniendo base de datos zabbix"
    fi
  fi

  # 5. Eliminar archivos de tuning
  rm -f /etc/my.cnf.d/zabbix-tuning.cnf

  # 6. Limpiar caché de paquetes
  dnf clean all 2>/dev/null

  log_info "Zabbix desinstalado completamente"
  echo -e "${GREEN}✅ Desinstalación completada${NC}"
  return 0
}

check_zabbix_installed() {
  if command -v zabbix_server &>/dev/null || [ -f /etc/zabbix/zabbix_server.conf ]; then
    ZABBIX_ALREADY_INSTALLED=true
    log_warn "Se detecto una instalacion previa de Zabbix"
    return 0
  else
    ZABBIX_ALREADY_INSTALLED=false
    return 1
  fi
}

check_mysql_installed() {
  log_step "Verificando instalacion de MySQL/MariaDB..."

  if command -v mysql &>/dev/null; then
    MYSQL_ALREADY_INSTALLED=true
    log_info "MySQL/MariaDB ya esta instalado"

    # Verificar si root tiene password
    if mysql -uroot -e "SELECT 1" &>/dev/null; then
      MYSQL_HAS_ROOT_PASSWORD=false
      log_info "MySQL accesible sin password root"
    elif [ -f /root/.my.cnf ] && mysql --defaults-file=/root/.my.cnf -e "SELECT 1" &>/dev/null; then
      MYSQL_HAS_ROOT_PASSWORD=true
      log_info "MySQL accesible con archivo de configuracion"
      # Extraer password del archivo .my.cnf
      MYSQL_ROOT_PASSWORD=$(grep "^password" /root/.my.cnf 2>/dev/null | cut -d= -f2 | tr -d ' ')
    else
      log_warn "MySQL instalado pero no se puede acceder como root"
      MYSQL_HAS_ROOT_PASSWORD=true
      echo -e "${YELLOW}Ingrese la password actual de root de MySQL:${NC}"
      read -r -s OLD_MYSQL_ROOT_PASSWORD
      echo ""
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

  local SECURE_SQL="/tmp/mysql_secure_$(date +%s).sql"

  cat >"$SECURE_SQL" <<EOF
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
FLUSH PRIVILEGES;
EOF

  if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
    mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" <"$SECURE_SQL" >>"$LOG_FILE" 2>&1
  else
    mysql -uroot <"$SECURE_SQL" >>"$LOG_FILE" 2>&1
  fi

  rm -f "$SECURE_SQL"
  log_info "Hardening de MySQL aplicado"
}

setup_mysql_root_password() {
  log_step "Configurando password de root de MySQL..."

  if [ "$MYSQL_ALREADY_INSTALLED" = true ]; then
    if [ "$MYSQL_HAS_ROOT_PASSWORD" = false ]; then
      mysqladmin -u root password "$MYSQL_ROOT_PASSWORD" >>"$LOG_FILE" 2>&1
    else
      mysql -uroot -p"${OLD_MYSQL_ROOT_PASSWORD}" -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';" >>"$LOG_FILE" 2>&1
    fi
  else
    mysqladmin -u root password "$MYSQL_ROOT_PASSWORD" >>"$LOG_FILE" 2>&1
  fi

  cat >/root/.my.cnf <<EOF
[client]
user=root
password=${MYSQL_ROOT_PASSWORD}
EOF
  chmod 600 /root/.my.cnf

  log_info "Password de root de MySQL configurado"
}

determine_db_connection() {
  log_step "Determinando metodo optimo de conexion a MySQL..."

  # Verificar si podemos usar socket (mas rapido y seguro)
  if [ -S /var/lib/mysql/mysql.sock ]; then
    DB_HOST_TYPE="localhost"
    log_info "Usando conexion por socket Unix (localhost) - optimo para rendimiento"
  elif [ -S /var/run/mysqld/mysqld.sock ]; then
    DB_HOST_TYPE="localhost"
    log_info "Usando conexion por socket Unix (localhost) - optimo para rendimiento"
  else
    DB_HOST_TYPE="127.0.0.1"
    log_warn "Socket no encontrado, usando TCP/IP (127.0.0.1)"
  fi
}

configure_mysql_tuning() {
  if [ "$MYSQL_TUNING" = false ]; then
    log_info "Tuning de MySQL omitido por peticion del usuario"
    return 0
  fi

  log_step "Aplicando tuning de MySQL para ~${EXPECTED_HOSTS} servidores..."

  local MYSQL_TUNING_FILE="/etc/my.cnf.d/zabbix-tuning.cnf"
  local TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
  local INNODB_BUFFER_POOL_SIZE="2G"
  local INNODB_LOG_FILE_SIZE="512M"

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
max_connections = 500
max_connect_errors = 1000000
thread_cache_size = 128
table_open_cache = 4000
table_definition_cache = 4000

default_storage_engine = InnoDB
innodb_buffer_pool_size = ${INNODB_BUFFER_POOL_SIZE}
innodb_log_file_size = ${INNODB_LOG_FILE_SIZE}
innodb_log_buffer_size = 64M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT
innodb_file_per_table = 1
innodb_read_io_threads = 16
innodb_write_io_threads = 16
innodb_io_capacity = 2000
innodb_io_capacity_max = 4000
innodb_buffer_pool_instances = 4
innodb_lock_wait_timeout = 50
innodb_print_all_deadlocks = 1

connect_timeout = 30
wait_timeout = 600
interactive_timeout = 600
tmp_table_size = 64M
max_heap_table_size = 64M

sort_buffer_size = 2M
join_buffer_size = 2M
read_buffer_size = 1M
read_rnd_buffer_size = 4M

slow_query_log = 1
slow_query_log_file = /var/log/mariadb/slow-queries.log
long_query_time = 2
log_queries_not_using_indexes = 1

expire_logs_days = 7
max_binlog_size = 100M

innodb_strict_mode = ON
sql_mode = "NO_ENGINE_SUBSTITUTION"

character_set_server = utf8mb4
collation_server = utf8mb4_bin

performance_schema = ON
max_allowed_packet = 16M
EOF

  systemctl restart mariadb >>"$LOG_FILE" 2>&1
  log_info "Tuning de MySQL aplicado: buffer_pool=${INNODB_BUFFER_POOL_SIZE}, max_connections=500"
}

setup_passwords() {
  log_step "Configurando passwords..."

  local random_db_pass=$(generate_safe_password 24)
  local random_mysql_root_pass=$(generate_safe_password 24)

  if [ "$AUTO_MODE" = true ]; then
    DB_PASSWORD="$random_db_pass"

    if [ "$MYSQL_ALREADY_INSTALLED" = true ] && [ "$MYSQL_HAS_ROOT_PASSWORD" = true ]; then
      # Si MySQL ya tiene password, no la cambiamos
      log_info "Usando password existente de MySQL"
    else
      MYSQL_ROOT_PASSWORD="$random_mysql_root_pass"
    fi
    log_info "Passwords generadas automaticamente"

    # Guardar credenciales
    save_credentials_early "$DB_PASSWORD" "$MYSQL_ROOT_PASSWORD"
  else
    echo -e "\n${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  CONFIGURACION DE PASSWORDS${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Configurar password de root de MySQL
    if [ "$MYSQL_ALREADY_INSTALLED" = true ] && [ "$MYSQL_HAS_ROOT_PASSWORD" = true ]; then
      echo -e "${YELLOW}MySQL ya tiene una contraseña de root configurada.${NC}"
      echo -e "${YELLOW}Por favor ingrese la contraseña actual de root:${NC}"
      read -r -s MYSQL_ROOT_PASSWORD
      echo ""

      # Validar la contraseña ingresada
      if ! validate_mysql_root_password "$MYSQL_ROOT_PASSWORD"; then
        log_error "No se pudo validar la contraseña de root"
        exit 1
      fi
    else
      # MySQL no tiene contraseña o es nueva instalación
      confirm_password "Password para usuario root de MySQL" "$random_mysql_root_pass" "MYSQL_ROOT_PASSWORD"
    fi

    # Configurar password de usuario zabbix
    confirm_password "Password para usuario Zabbix en MySQL" "$random_db_pass" "DB_PASSWORD"

    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    # Guardar credenciales
    save_credentials_early "$DB_PASSWORD" "$MYSQL_ROOT_PASSWORD"
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
  dnf install -y zabbix-server-mysql zabbix-web-mysql zabbix-apache-conf zabbix-sql-scripts zabbix-selinux-policy zabbix-agent zabbix-get >>"$LOG_FILE" 2>&1
  log_info "Paquetes de Zabbix instalados"
}

install_agent_only() {
  log_step "Instalando solo Zabbix Agent..."
  dnf install -y zabbix-agent >>"$LOG_FILE" 2>&1
  log_info "Zabbix Agent instalado"
}

create_database() {
  log_step "Creando base de datos para Zabbix..."

  # Determinar conexion optima
  determine_db_connection

  log_info "Usando DB_HOST_TYPE: ${DB_HOST_TYPE}"

  # Verificar que podemos conectar como root ANTES de crear nada
  if ! mysql --defaults-file=/root/.my.cnf -e "SELECT 1" >/dev/null 2>&1; then
    log_error "No se puede conectar a MySQL como root"
    log_error "Verifique que MySQL esté corriendo y que /root/.my.cnf tenga la contraseña correcta"
    exit 1
  fi

  log_info "Conexión root verificada"

  # Crear base de datos y usuario
  log_info "Creando base de datos y usuario zabbix..."
  mysql --defaults-file=/root/.my.cnf <<EOF
create database if not exists zabbix character set utf8mb4 collate utf8mb4_bin;
create user if not exists zabbix@${DB_HOST_TYPE} identified by '${DB_PASSWORD}';
grant all privileges on zabbix.* to zabbix@${DB_HOST_TYPE};
set global log_bin_trust_function_creators = 1;
flush privileges;
EOF

  if [ $? -ne 0 ]; then
    log_error "Error al crear base de datos o usuario zabbix"
    exit 1
  fi

  log_info "Base de datos y usuario creados"

  # Validar que el usuario zabbix funciona
  if ! validate_zabbix_db_user "$DB_PASSWORD"; then
    log_error "El usuario zabbix no puede conectar a la base de datos"
    exit 1
  fi

  # Importar esquema
  log_step "Importando esquema inicial (puede tomar varios minutos)..."

  local schema_file="/usr/share/zabbix/sql-scripts/mysql/server.sql.gz"
  if [ ! -f "$schema_file" ]; then
    log_error "Archivo de esquema no encontrado: $schema_file"
    exit 1
  fi

  # Intentar importar con reintentos
  local max_retries=2
  local retry=0

  while [ $retry -lt $max_retries ]; do
    if zcat "$schema_file" | mysql --default-character-set=utf8mb4 -uzabbix --password="${DB_PASSWORD}" -h ${DB_HOST_TYPE} zabbix >>"$LOG_FILE" 2>&1; then
      log_info "Esquema importado correctamente"
      break
    else
      ((retry++))
      if [ $retry -lt $max_retries ]; then
        log_warn "Error al importar, reintentando (intento $retry de $max_retries)..."
        sleep 3
      else
        log_error "Error al importar el esquema después de $max_retries intentos"
        log_error "Revise el log para más detalles: $LOG_FILE"
        exit 1
      fi
    fi
  done

  # Desactivar log_bin_trust_function_creators
  mysql --defaults-file=/root/.my.cnf <<EOF
set global log_bin_trust_function_creators = 0;
flush privileges;
EOF

  # Verificar que las tablas se crearon
  local table_count=$(mysql -uzabbix --password="${DB_PASSWORD}" -h ${DB_HOST_TYPE} -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='zabbix'" -N 2>/dev/null)
  if [ -n "$table_count" ] && [ "$table_count" -gt 0 ]; then
    log_info "✓ Verificación exitosa: $table_count tablas creadas"
  else
    log_error "✗ No se encontraron tablas en la base de datos zabbix"
    exit 1
  fi

  log_info "Base de datos lista para usar"
}

configure_server() {
  log_step "Configurando Zabbix Server..."

  # Usar la conexion optima
  sed -i "s/^# DBHost=.*/DBHost=${DB_HOST_TYPE}/" /etc/zabbix/zabbix_server.conf
  sed -i "s/^DBHost=.*/DBHost=${DB_HOST_TYPE}/" /etc/zabbix/zabbix_server.conf
  sed -i "s/^# DBPassword=.*/DBPassword=${DB_PASSWORD}/" /etc/zabbix/zabbix_server.conf
  sed -i "s/^DBPassword=.*/DBPassword=${DB_PASSWORD}/" /etc/zabbix/zabbix_server.conf

  # Ajustes de rendimiento
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

  log_info "Zabbix Server configurado (pollers=40, trappers=20, cache=256M, db_host=${DB_HOST_TYPE})"
}

configure_web() {
  log_step "Configurando interfaz web de Zabbix..."

  # Crear archivo de configuracion web
  local WEB_CONFIG="/etc/zabbix/web/zabbix.conf.php"

  mkdir -p /etc/zabbix/web

  cat >"$WEB_CONFIG" <<EOF
<?php
// Zabbix GUI configuration file.
global \$DB;

\$DB['TYPE']     = 'MYSQL';
\$DB['SERVER']   = '${DB_HOST_TYPE}';
\$DB['PORT']     = '0';
\$DB['DATABASE'] = 'zabbix';
\$DB['USER']     = 'zabbix';
\$DB['PASSWORD'] = '${DB_PASSWORD}';

// Schema name. Used for IBM DB2 and PostgreSQL.
\$DB['SCHEMA'] = '';

\$ZBX_SERVER      = 'localhost';
\$ZBX_SERVER_PORT = '10051';
\$ZBX_SERVER_NAME = '';

\$IMAGE_FORMAT_DEFAULT = IMAGE_FORMAT_PNG;
?>
EOF

  chmod 640 "$WEB_CONFIG"
  chown apache:apache "$WEB_CONFIG"

  log_info "Configuracion web creada en: $WEB_CONFIG"
}

configure_agent() {
  log_step "Configurando Zabbix Agent..."

  local server_ip=$(hostname -I | awk '{print $1}')
  sed -i "s/^Server=127.0.0.1/Server=127.0.0.1,${server_ip}/" /etc/zabbix/zabbix_agentd.conf
  sed -i "s/^ServerActive=127.0.0.1/ServerActive=127.0.0.1,${server_ip}/" /etc/zabbix/zabbix_agentd.conf
  sed -i "s/^Hostname=Zabbix server/Hostname=$(hostname)/" /etc/zabbix/zabbix_agentd.conf

  log_info "Zabbix Agent configurado"
}

configure_locales() {
  log_step "Configurando locales del sistema..."

  dnf install -y langpacks-en langpacks-es glibc-langpack-en glibc-langpack-es >>"$LOG_FILE" 2>&1

  local LOCALES=(
    "en_US.UTF-8"
    "es_ES.UTF-8"
    "es_CL.UTF-8"
  )

  for locale in "${LOCALES[@]}"; do
    if ! locale -a 2>/dev/null | grep -q "$locale"; then
      log_info "Generando locale: $locale"
      localedef -c -i $(echo $locale | cut -d. -f1) -f UTF-8 "$locale" >>"$LOG_FILE" 2>&1
    else
      log_info "Locale $locale ya existe"
    fi
  done

  cat >/etc/locale.conf <<EOF
LANG=en_US.UTF-8
LC_ALL=en_US.UTF-8
LC_CTYPE=en_US.UTF-8
LC_MESSAGES=en_US.UTF-8
LC_TIME=es_CL.UTF-8
LC_MONETARY=es_CL.UTF-8
EOF

  source /etc/locale.conf 2>/dev/null || true

  if [ -f /etc/httpd/conf.d/zabbix.conf ]; then
    sed -i "s/^; php_value date.timezone.*/php_value date.timezone America\/Santiago/" /etc/httpd/conf.d/zabbix.conf
    sed -i "s/^# php_value date.timezone.*/php_value date.timezone America\/Santiago/" /etc/httpd/conf.d/zabbix.conf
  fi

  log_info "Locales configurados: en_US.UTF-8, es_ES.UTF-8, es_CL.UTF-8"
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

verify_locales() {
  log_step "Verificando locales instalados..."

  echo -e "\n${YELLOW}Locales disponibles:${NC}"
  locale -a | grep -E "en_US|es_ES|es_CL" | while read line; do
    echo -e "  ${GREEN}✓${NC} $line"
  done
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
  Tipo conexion: ${DB_HOST_TYPE}

🌐 LOCALES CONFIGURADOS:
  - en_US.UTF-8 (Ingles - Sistema)
  - es_ES.UTF-8 (Español - España)
  - es_CL.UTF-8 (Español - Chile)

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
  Zabbix Web: /etc/zabbix/web/zabbix.conf.php
  Zabbix Agent: /etc/zabbix/zabbix_agentd.conf
  MySQL Tuning: /etc/my.cnf.d/zabbix-tuning.cnf
  Apache: /etc/httpd/conf.d/zabbix.conf
  Locales: /etc/locale.conf

📋 LOGS:
  Zabbix Server: /var/log/zabbix/zabbix_server.log
  Zabbix Web Error: /var/log/httpd/error_log
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
mysql -uzabbix --password='${DB_PASSWORD}' -h ${DB_HOST_TYPE} zabbix

# Verificar locales
locale -a | grep -E "en_US|es_ES|es_CL"
locale

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
6. En Zabbix Web, ir a Administration → General → Localization
   y seleccionar es_CL (Español - Chile) si se desea

=============================================
  🌐 https://www.orangebox.cl
=============================================
EOF

  chmod 600 "$CREDENTIALS_FILE"

  # Eliminar archivo temporal
  rm -f /root/zabbix_credentials_temp.txt

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
  echo -e "\n${YELLOW}LOCALES DISPONIBLES:${NC}" | tee -a "$LOG_FILE"
  echo -e "  - en_US.UTF-8 (Ingles)" | tee -a "$LOG_FILE"
  echo -e "  - es_ES.UTF-8 (Español - España)" | tee -a "$LOG_FILE"
  echo -e "  - es_CL.UTF-8 (Español - Chile)" | tee -a "$LOG_FILE"
  echo -e "\n${GREEN}============================================${NC}" | tee -a "$LOG_FILE"
  echo -e "${GREEN}  🌐 https://www.orangebox.cl${NC}" | tee -a "$LOG_FILE"
  echo -e "${GREEN}============================================${NC}\n" | tee -a "$LOG_FILE"
}

# ==============================================
# FUNCION PRINCIPAL DE INSTALACION
# ==============================================

main_installation() {
  install_mariadb
  setup_mysql_root_password
  secure_mariadb
  configure_mysql_tuning
  configure_repository
  install_server
  create_database
  configure_server
  configure_web
  configure_agent
  configure_locales
  start_services
  configure_firewall
  verify_mysql_tuning
  verify_locales
  create_credentials_file
  show_completion
}

reinstall_zabbix() {
  log_step "INICIANDO REINSTALACIÓN COMPLETA DE ZABBIX"

  # Llamar a la función de desinstalación con confirmación
  if uninstall_zabbix; then
    log_info "Desinstalación completada. Comenzando instalación fresca..."
    sleep 3
    # Continuar con la instalación normal
    main_installation
  else
    log_error "Reinstalación cancelada o falló la desinstalación"
    exit 1
  fi
}

# ==============================================
# OPCIONES DE LINEA DE COMANDOS
# ==============================================

AUTO_MODE=false
AGENT_ONLY=false
UNINSTALL=false
REINSTALL=false
KILL_ONLY=false

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
  --uninstall)
    UNINSTALL=true
    shift
    ;;
  --reinstall)
    REINSTALL=true
    shift
    ;;
  --kill-zabbix)
    KILL_ONLY=true
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
echo -e "${GREEN}  Locales: en_US, es_ES, es_CL${NC}"
echo -e "${GREEN}============================================${NC}\n"

check_root
detect_os
init_log

# Manejar kill de procesos (opcion independiente)
if [ "$KILL_ONLY" = true ]; then
  kill_zabbix_processes
  exit 0
fi

# Manejar reinstalacion
if [ "$REINSTALL" = true ]; then
  reinstall_zabbix
  exit 0
fi

# Manejar desinstalacion
if [ "$UNINSTALL" = true ]; then
  uninstall_zabbix
  exit 0
fi

# Instalacion normal
if [ "$AGENT_ONLY" = false ]; then
  check_mysql_installed
  setup_passwords
fi

if [ "$AUTO_MODE" = false ] && [ "$AGENT_ONLY" = false ] && [ "$REINSTALL" = false ]; then
  echo -e "${YELLOW}Este script instalara Zabbix Server 7.4 con:${NC}"
  echo -e "  • MariaDB con hardening y tuning (buffer_pool: 2-4GB, max_connections: 500)"
  echo -e "  • Apache Web Server"
  echo -e "  • PHP-FPM"
  echo -e "  • Zabbix Server (configurado para ~200 servidores)"
  echo -e "  • Zabbix Agent"
  echo -e "  • SELinux Policy"
  echo -e "  • Locales: en_US, es_ES, es_CL"
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
  main_installation
fi
