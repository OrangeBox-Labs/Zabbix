#!/bin/bash
# =============================================================================
# Script: setup_mysql_zabbix_user.sh
# Autor: Felipe Román froman@orangebox.cl
# Descripción: Crea usuario zbx_monitor para monitoreo MySQL con Zabbix
#              Detecta versión de MySQL y adapta la sintaxis según sea necesario
#              SOLO crea el usuario y otorga permisos - NO toca el agente Zabbix
# Uso: ./setup_mysql_zabbix_user.sh
# =============================================================================

# --- Colores ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Variables ---
MYSQL_USER="zbx_monitor"
MYSQL_HOST="%"
LOG_FILE="/var/log/mysql_zabbix_setup.log"
MYSQL_ROOT_PASS=""
MYSQL_PASSWORD=""

# --- Funciones de logging ---
log() {
  echo -e "$1"
  echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" >>$LOG_FILE
}

log_info() { log "${GREEN}✅${NC} $1"; }
log_error() {
  log "${RED}❌${NC} $1"
  exit 1
}
log_warn() { log "${YELLOW}⚠️${NC} $1"; }
log_step() { log "${BLUE}🔧${NC} $1"; }

# --- Función para generar contraseña aleatoria ---
generate_random_password() {
  # Caracteres alfanuméricos solamente (seguros para MySQL y bash)
  local chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
  local password=""
  for i in {1..20}; do
    password="${password}${chars:RANDOM%${#chars}:1}"
  done
  echo "$password"
}

# --- Función para detectar versión de MySQL ---
detect_mysql_version() {
  local version=$(mysql --version 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)

  if [ -z "$version" ]; then
    log_error "No se pudo detectar la versión de MySQL. ¿Está instalado?"
  fi

  # Extraer versión mayor y menor
  local major=$(echo $version | cut -d. -f1)
  local minor=$(echo $version | cut -d. -f2)

  log_info "Versión de MySQL detectada: $version"

  # Determinar tipo de MySQL
  if [[ "$major" -ge 8 ]] || [[ "$major" -eq 5 && "$minor" -ge 7 ]] || [[ "$major" -eq 10 && "$minor" -ge 2 ]]; then
    echo "modern"
  else
    echo "legacy"
  fi
}

# --- Función para ejecutar comandos SQL ---
execute_sql() {
  local sql="$1"
  local mysql_cmd="mysql -s -N"

  # Si hay contraseña, usarla
  if [ -n "$MYSQL_ROOT_PASS" ]; then
    mysql_cmd="$mysql_cmd -p'$MYSQL_ROOT_PASS'"
  fi

  echo "$sql" | eval $mysql_cmd 2>&1
}

# --- Función para probar conexión sin contraseña ---
test_mysql_connection() {
  log_step "Probando conexión a MySQL sin contraseña..."
  if mysql -s -N -e "SELECT 1" 2>/dev/null | grep -q "1"; then
    log_info "Conexión exitosa sin contraseña"
    MYSQL_ROOT_PASS=""
    return 0
  else
    log_warn "No se pudo conectar sin contraseña"
    return 1
  fi
}

# --- Función para probar conexión con contraseña ---
test_mysql_with_password() {
  local password="$1"
  log_step "Probando conexión con contraseña proporcionada..."
  if mysql -s -N -p"$password" -e "SELECT 1" 2>/dev/null | grep -q "1"; then
    log_info "Conexión exitosa con contraseña"
    return 0
  else
    log_warn "Contraseña incorrecta o sin permisos suficientes"
    return 1
  fi
}

# --- Función para verificar si el usuario ya existe ---
check_user_exists() {
  local sql="SELECT COUNT(*) FROM mysql.user WHERE User='$MYSQL_USER';"
  local result=$(execute_sql "$sql" | tr -d '[:space:]')

  if [ "$result" = "1" ]; then
    return 0
  else
    return 1
  fi
}

# --- Función para crear el usuario según la versión de MySQL ---
create_zabbix_user() {
  local mysql_type="$1"
  local password="$2"

  log_step "Creando usuario $MYSQL_USER para MySQL ($mysql_type)..."

  # SQL para crear usuario según la versión
  local create_user_sql=""

  if [ "$mysql_type" = "modern" ]; then
    # MySQL 5.7+, 8.0+, MariaDB 10.2+
    create_user_sql="CREATE USER IF NOT EXISTS '$MYSQL_USER'@'$MYSQL_HOST' IDENTIFIED BY '$password';"
  else
    # MySQL 5.1, 5.5, 5.6, MariaDB 5.5, 10.0, 10.1
    if check_user_exists; then
      log_warn "El usuario $MYSQL_USER ya existe. Actualizando contraseña..."
      create_user_sql="SET PASSWORD FOR '$MYSQL_USER'@'$MYSQL_HOST' = PASSWORD('$password');"
    else
      create_user_sql="CREATE USER '$MYSQL_USER'@'$MYSQL_HOST' IDENTIFIED BY '$password';"
    fi
  fi

  # Ejecutar creación de usuario
  local result=$(execute_sql "$create_user_sql" 2>&1)
  local exit_code=$?

  if [ $exit_code -ne 0 ]; then
    log_error "Error al crear usuario: $result"
  fi

  log_info "Usuario creado/actualizado exitosamente"

  # Otorgar permisos
  log_step "Otorgando permisos al usuario..."

  local grant_sql="GRANT REPLICATION CLIENT, PROCESS, SHOW DATABASES, SHOW VIEW ON *.* TO '$MYSQL_USER'@'$MYSQL_HOST';"

  local grant_result=$(execute_sql "$grant_sql" 2>&1)
  local grant_exit=$?

  if [ $grant_exit -ne 0 ]; then
    log_error "Error al otorgar permisos: $grant_result"
  fi

  # Aplicar cambios
  execute_sql "FLUSH PRIVILEGES;"

  log_info "Permisos otorgados correctamente"

  # Probar la conexión del nuevo usuario
  test_zabbix_user_connection "$MYSQL_USER" "$password"

  return 0
}

# --- Función para probar conexión del usuario Zabbix ---
test_zabbix_user_connection() {
  local user="$1"
  local password="$2"
  log_step "Probando conexión del usuario $user..."

  if mysql -u "$user" -p"$password" -e "SELECT 1" 2>/dev/null | grep -q "1"; then
    log_info "✅ Conexión exitosa del usuario $user"
    return 0
  else
    log_error "❌ Falló la conexión del usuario $user con la contraseña generada"
  fi
}

# --- Función para mostrar resumen ---
show_summary() {
  echo ""
  echo "================================================================================"
  log_info "✅ CONFIGURACIÓN COMPLETADA EXITOSAMENTE"
  echo "================================================================================"
  log_info "📊 MySQL:"
  log_info "   Usuario creado: $MYSQL_USER@$MYSQL_HOST"
  log_info "   Contraseña: $MYSQL_PASSWORD"
  echo ""
  log_info "📝 Para probar la conexión MySQL:"
  echo "   mysql -u $MYSQL_USER -p'$MYSQL_PASSWORD' -e 'SHOW DATABASES;'"
  echo ""
  log_info "⚠️  Para configurar en Zabbix (Web UI), agrega al Host:"
  echo "   Si usas Agent 2 (recomendado):"
  echo "     1. Template: \"MySQL by Zabbix agent 2\""
  echo "     2. Macros:"
  echo "        - {\$MYSQL.USER} = $MYSQL_USER"
  echo "        - {\$MYSQL.PASSWORD} = $MYSQL_PASSWORD"
  echo "        - {\$MYSQL.DSN} = tcp://localhost:3306"
  echo ""
  echo "   Si usas Agent clásico:"
  echo "     1. Template: \"MySQL by Zabbix agent\""
  echo "     2. Crear archivo .my.cnf en /var/lib/zabbix/ con:"
  echo "        [client]"
  echo "        user=$MYSQL_USER"
  echo "        password=$MYSQL_PASSWORD"
  echo "================================================================================"
}

# --- Función principal ---
main() {
  echo "================================================================================"
  log "🔧 Script de Configuración de Usuario MySQL para Zabbix"
  echo "================================================================================"

  # Verificar que MySQL está instalado
  if ! command -v mysql &>/dev/null; then
    log_error "MySQL no está instalado en el sistema"
  fi

  # Detectar versión de MySQL
  local mysql_type=$(detect_mysql_version)
  log_info "Tipo de MySQL: $mysql_type"

  # Intentar conectar sin contraseña
  if test_mysql_connection; then
    MYSQL_ROOT_PASS=""
  else
    # Si falla, pedir contraseña
    log_step "Por favor, introduce la contraseña de root de MySQL:"
    read -s MYSQL_ROOT_PASS
    echo ""

    if ! test_mysql_with_password "$MYSQL_ROOT_PASS"; then
      log_error "No se pudo conectar a MySQL con la contraseña proporcionada"
    fi
  fi

  # Verificar si el usuario ya existe
  if check_user_exists; then
    log_warn "El usuario $MYSQL_USER ya existe"
    read -p "¿Deseas actualizar su contraseña y permisos? (s/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
      log_info "Operación cancelada por el usuario"
      exit 0
    fi
  fi

  # Generar contraseña aleatoria (SOLO alfanumérica)
  MYSQL_PASSWORD=$(generate_random_password)
  log_info "Contraseña generada: $MYSQL_PASSWORD"

  # Crear usuario
  if create_zabbix_user "$mysql_type" "$MYSQL_PASSWORD"; then
    show_summary
  else
    log_error "❌ Falló la creación del usuario. Revisa los errores arriba."
  fi

  # Guardar credenciales en un archivo seguro
  echo ""
  log_step "Guardando credenciales en archivo seguro..."

  local cred_file="/root/.zbx_mysql_credentials"
  cat >$cred_file <<EOF
# Credenciales para monitoreo MySQL con Zabbix
# Generado: $(date)
# Usuario: $MYSQL_USER
# Contraseña: $MYSQL_PASSWORD
# Host: $MYSQL_HOST
EOF
  chmod 600 $cred_file
  log_info "Credenciales guardadas en: $cred_file"

  echo ""
  log_info "=== PROCESO COMPLETADO ==="
  log_info "Log: $LOG_FILE"
}

# --- Ejecución ---
main "$@"
