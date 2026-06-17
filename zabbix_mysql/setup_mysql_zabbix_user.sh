#!/bin/bash
# ============================================================
# Script: mysql_zabbix_setup.sh
# Autor: Felipe Román <froman@orangebox.cl>
# Web: www.orangebox.cl
# Descripción: Configura usuario zbx_monitor para Zabbix en MySQL
# Soporta: MySQL 5.x, 8.x y MariaDB
# ============================================================

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables globales
MYSQL_CMD="mysql"
MYSQL_VERSION=""
ROOT_PASS=""
NEW_PASSWORD=""
MYSQL_SOCKET=""
DB_TYPE=""

# =============================================================================
# FUNCIONES DE LOGGING
# =============================================================================

log_info() { echo -e "${GREEN}✅${NC} $1"; }
log_error() { echo -e "${RED}❌${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠️${NC} $1"; }
log_step() { echo -e "${BLUE}🔧${NC} $1"; }

# =============================================================================
# FUNCIONES DE DETECCIÓN
# =============================================================================

# --- Función para detectar socket de MySQL/MariaDB ---
detect_mysql_socket() {
  # Buscar socket en ubicaciones comunes
  local socket_paths=(
    "/var/lib/mysql/mysql.sock"
    "/var/run/mysqld/mysqld.sock"
    "/run/mysqld/mysqld.sock"
    "/tmp/mysql.sock"
    "/var/lib/mysql/mysql.sock"
  )

  for sock in "${socket_paths[@]}"; do
    if [ -S "$sock" ]; then
      echo "$sock"
      return 0
    fi
  done

  # Si no encuentra, intentar obtener de la configuración
  if [ -f /etc/my.cnf ]; then
    local sock=$(grep -E "^socket\s*=" /etc/my.cnf 2>/dev/null | awk -F= '{print $2}' | tr -d ' ')
    if [ -n "$sock" ] && [ -S "$sock" ]; then
      echo "$sock"
      return 0
    fi
  fi

  if [ -f /etc/mysql/my.cnf ]; then
    local sock=$(grep -E "^socket\s*=" /etc/mysql/my.cnf 2>/dev/null | awk -F= '{print $2}' | tr -d ' ')
    if [ -n "$sock" ] && [ -S "$sock" ]; then
      echo "$sock"
      return 0
    fi
  fi

  return 1
}

# --- Función para detectar el tipo de base de datos ---
detect_database_type() {
  if ! command -v mysql &>/dev/null; then
    echo "not_installed"
    return
  fi

  # Intentar obtener versión
  local version=$(mysql --version 2>/dev/null | head -1)

  if echo "$version" | grep -qi "maria"; then
    echo "mariadb"
  elif echo "$version" | grep -qi "mysql"; then
    echo "mysql"
  else
    echo "unknown"
  fi
}

# --- Función para obtener versión de MySQL/MariaDB ---
get_mysql_version() {
  local version=""

  # Intentar diferentes métodos para obtener la versión
  if [ -n "$MYSQL_SOCKET" ]; then
    version=$(mysql -S "$MYSQL_SOCKET" -e "SELECT VERSION();" 2>/dev/null | tail -n 1)
  fi

  if [ -z "$version" ] && [ -n "$ROOT_PASS" ]; then
    version=$(mysql -u root -p"$ROOT_PASS" -e "SELECT VERSION();" 2>/dev/null | tail -n 1)
  fi

  if [ -z "$version" ]; then
    version=$(mysql -u root -e "SELECT VERSION();" 2>/dev/null | tail -n 1)
  fi

  # Si todo falla, intentar con mysqladmin
  if [ -z "$version" ]; then
    if [ -n "$ROOT_PASS" ]; then
      version=$(mysqladmin -u root -p"$ROOT_PASS" version 2>/dev/null | grep -i "Server version" | awk '{print $3}' | cut -d'-' -f1)
    else
      version=$(mysqladmin -u root version 2>/dev/null | grep -i "Server version" | awk '{print $3}' | cut -d'-' -f1)
    fi
  fi

  echo "$version"
}

# --- Función para generar password aleatoria ---
generate_password() {
  local chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.,$'
  local password=''
  for i in {1..20}; do
    password+="${chars:RANDOM%${#chars}:1}"
  done
  echo "$password"
}

# =============================================================================
# FUNCIONES DE CONEXIÓN
# =============================================================================

# --- Función para probar conexión MySQL (sin password) ---
test_mysql_connection() {
  if [ -n "$MYSQL_SOCKET" ]; then
    mysql -S "$MYSQL_SOCKET" -e "SELECT 1;" 2>/dev/null
    return $?
  else
    mysql -e "SELECT 1;" 2>/dev/null
    return $?
  fi
}

# --- Función para probar conexión MySQL (con password) ---
test_mysql_connection_with_pass() {
  local pass=$1

  if [ -n "$MYSQL_SOCKET" ]; then
    mysql -S "$MYSQL_SOCKET" -u root -p"$pass" -e "SELECT 1;" 2>/dev/null
    return $?
  else
    mysql -u root -p"$pass" -e "SELECT 1;" 2>/dev/null
    return $?
  fi
}

# --- Función para ejecutar comandos MySQL ---
run_mysql_command() {
  local command=$1
  local root_pass=$2
  local use_socket=${3:-true}

  if [ "$use_socket" = "true" ] && [ -n "$MYSQL_SOCKET" ]; then
    if [ -z "$root_pass" ]; then
      mysql -S "$MYSQL_SOCKET" -e "$command" 2>/dev/null
    else
      mysql -S "$MYSQL_SOCKET" -u root -p"$root_pass" -e "$command" 2>/dev/null
    fi
  else
    if [ -z "$root_pass" ]; then
      mysql -e "$command" 2>/dev/null
    else
      mysql -u root -p"$root_pass" -e "$command" 2>/dev/null
    fi
  fi
}

# --- Función para probar conexión del usuario zbx_monitor ---
test_zbx_monitor_connection() {
  local user_pass=$1
  local host=$2

  if [ -z "$host" ]; then
    host="localhost"
  fi

  mysql -h "$host" -u zbx_monitor -p"$user_pass" -e "SELECT 1;" 2>/dev/null
  return $?
}

# =============================================================================
# FUNCIONES DE MANEJO DE USUARIO
# =============================================================================

# --- Función para verificar si el usuario zbx_monitor existe ---
user_exists() {
  local root_pass=$1
  local result

  result=$(run_mysql_command "SELECT COUNT(*) FROM mysql.user WHERE User='zbx_monitor' AND Host IN ('localhost','127.0.0.1','%');" "$root_pass" 2>/dev/null | tail -n 1)

  if [[ "$result" =~ ^[0-9]+$ ]] && [[ "$result" -gt 0 ]]; then
    return 0
  else
    return 1
  fi
}

# --- Función para eliminar usuario ---
delete_user() {
  local root_pass=$1

  echo -e "${YELLOW}Eliminando usuario zbx_monitor...${NC}"

  echo -n "  - Eliminando localhost... "
  run_mysql_command "DROP USER IF EXISTS 'zbx_monitor'@'localhost';" "$root_pass" >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC}"
  else
    echo -e "${YELLOW}ℹ No existe o ya fue eliminado${NC}"
  fi

  echo -n "  - Eliminando 127.0.0.1... "
  run_mysql_command "DROP USER IF EXISTS 'zbx_monitor'@'127.0.0.1';" "$root_pass" >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC}"
  else
    echo -e "${YELLOW}ℹ No existe o ya fue eliminado${NC}"
  fi

  echo -n "  - Eliminando %... "
  run_mysql_command "DROP USER IF EXISTS 'zbx_monitor'@'%';" "$root_pass" >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC}"
  else
    echo -e "${YELLOW}ℹ No existe o ya fue eliminado${NC}"
  fi

  run_mysql_command "FLUSH PRIVILEGES;" "$root_pass"
  echo -e "${GREEN}✓ Usuario eliminado exitosamente${NC}"
  return 0
}

# --- Función para cambiar password ---
change_password() {
  local mysql_version=$1
  local root_pass=$2
  local new_password=$3

  echo -e "${YELLOW}Cambiando password del usuario zbx_monitor...${NC}"

  # Para MySQL 8.x
  if [[ "$mysql_version" == "8"* ]]; then
    echo -e "${BLUE}  Usando método ALTER USER (MySQL 8.x)${NC}"
    run_mysql_command "ALTER USER 'zbx_monitor'@'localhost' IDENTIFIED BY '$new_password';" "$root_pass"
    run_mysql_command "ALTER USER 'zbx_monitor'@'127.0.0.1' IDENTIFIED BY '$new_password';" "$root_pass"
    run_mysql_command "ALTER USER 'zbx_monitor'@'%' IDENTIFIED BY '$new_password';" "$root_pass" 2>/dev/null
  else
    # MySQL 5.x o MariaDB
    echo -e "${BLUE}  Usando método SET PASSWORD${NC}"
    run_mysql_command "SET PASSWORD FOR 'zbx_monitor'@'localhost' = PASSWORD('$new_password');" "$root_pass"
    run_mysql_command "SET PASSWORD FOR 'zbx_monitor'@'127.0.0.1' = PASSWORD('$new_password');" "$root_pass"
    run_mysql_command "SET PASSWORD FOR 'zbx_monitor'@'%' = PASSWORD('$new_password');" "$root_pass" 2>/dev/null
  fi

  run_mysql_command "FLUSH PRIVILEGES;" "$root_pass"

  if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Password actualizada exitosamente${NC}"
    echo -e "${GREEN}✓ Nueva password: ${YELLOW}$new_password${NC}"
    return 0
  else
    echo -e "${RED}✗ Error al cambiar la password${NC}"
    return 1
  fi
}

# --- Función para crear usuario ---
create_user() {
  local mysql_version=$1
  local root_pass=$2
  local new_password=$3
  local db_type=$4

  echo -e "${GREEN}Creando usuario zbx_monitor...${NC}"

  # Eliminar el usuario si existe en todos los hosts
  echo -e "${YELLOW}  Eliminando usuarios existentes...${NC}"
  run_mysql_command "DROP USER IF EXISTS 'zbx_monitor'@'localhost';" "$root_pass" >/dev/null 2>&1
  run_mysql_command "DROP USER IF EXISTS 'zbx_monitor'@'127.0.0.1';" "$root_pass" >/dev/null 2>&1
  run_mysql_command "DROP USER IF EXISTS 'zbx_monitor'@'%';" "$root_pass" >/dev/null 2>&1

  echo -e "${YELLOW}  Creando usuarios...${NC}"

  # Para MySQL 8.x (AlmaLinux 9)
  if [[ "$mysql_version" == "8"* ]] || [[ "$db_type" == "mysql" ]]; then
    echo -e "${BLUE}  Usando método CREATE USER (MySQL 8.x)${NC}"

    run_mysql_command "CREATE USER 'zbx_monitor'@'localhost' IDENTIFIED BY '$new_password';" "$root_pass"
    if [ $? -ne 0 ]; then
      echo -e "${RED}  ✗ Error creando localhost${NC}"
      return 1
    fi

    run_mysql_command "CREATE USER 'zbx_monitor'@'127.0.0.1' IDENTIFIED BY '$new_password';" "$root_pass"
    if [ $? -ne 0 ]; then
      echo -e "${RED}  ✗ Error creando 127.0.0.1${NC}"
      return 1
    fi

    # % es opcional
    run_mysql_command "CREATE USER 'zbx_monitor'@'%' IDENTIFIED BY '$new_password';" "$root_pass" 2>/dev/null

    # Otorgar permisos
    echo -e "${YELLOW}  Otorgando permisos...${NC}"
    run_mysql_command "GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'zbx_monitor'@'localhost';" "$root_pass"
    run_mysql_command "GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'zbx_monitor'@'127.0.0.1';" "$root_pass"
    run_mysql_command "GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'zbx_monitor'@'%';" "$root_pass" 2>/dev/null

  else
    # MySQL 5.x o MariaDB
    echo -e "${BLUE}  Usando método GRANT (MySQL 5.x/MariaDB)${NC}"

    # Usar GRANT para crear y dar permisos en un solo paso
    run_mysql_command "GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'zbx_monitor'@'localhost' IDENTIFIED BY '$new_password';" "$root_pass"
    if [ $? -ne 0 ]; then
      echo -e "${RED}  ✗ Error creando localhost${NC}"
      return 1
    fi

    run_mysql_command "GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'zbx_monitor'@'127.0.0.1' IDENTIFIED BY '$new_password';" "$root_pass"
    if [ $? -ne 0 ]; then
      echo -e "${RED}  ✗ Error creando 127.0.0.1${NC}"
      return 1
    fi

    run_mysql_command "GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'zbx_monitor'@'%' IDENTIFIED BY '$new_password';" "$root_pass" 2>/dev/null
  fi

  echo -e "${YELLOW}  Aplicando privilegios...${NC}"
  run_mysql_command "FLUSH PRIVILEGES;" "$root_pass"

  if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Usuario creado exitosamente${NC}"
    echo -e "${GREEN}✓ Password generada: ${YELLOW}$new_password${NC}"
    return 0
  else
    echo -e "${RED}✗ Error al crear el usuario${NC}"
    return 1
  fi
}

# =============================================================================
# FUNCIÓN PRINCIPAL
# =============================================================================

main() {
  echo -e "${GREEN}========================================${NC}"
  echo -e "${GREEN}Configuración de zbx_monitor para Zabbix${NC}"
  echo -e "${GREEN}========================================${NC}"

  # 1. Verificar permisos de root del sistema
  if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}✗ Este script debe ejecutarse como root del sistema${NC}"
    echo -e "${YELLOW}Por favor, ejecute: sudo $0${NC}"
    exit 1
  fi
  echo -e "${GREEN}✓ Script ejecutándose como root del sistema${NC}"

  # 2. Verificar que MySQL/MariaDB esté instalado
  if ! command -v mysql &>/dev/null; then
    echo -e "${RED}✗ MySQL/MariaDB no está instalado${NC}"
    echo -e "${YELLOW}Instale MySQL/MariaDB primero${NC}"
    exit 1
  fi
  echo -e "${GREEN}✓ MySQL/MariaDB instalado${NC}"

  # 3. Detectar socket de MySQL
  echo -e "\n${YELLOW}Detectando socket de MySQL...${NC}"
  MYSQL_SOCKET=$(detect_mysql_socket)

  if [ -n "$MYSQL_SOCKET" ]; then
    echo -e "${GREEN}✓ Socket detectado: ${MYSQL_SOCKET}${NC}"
  else
    echo -e "${YELLOW}⚠ No se encontró socket, usando conexión TCP/IP${NC}"
  fi

  # 4. Detectar tipo de base de datos
  echo -e "\n${YELLOW}Detectando tipo de base de datos...${NC}"
  DB_TYPE=$(detect_database_type)

  case $DB_TYPE in
  "mysql")
    echo -e "${GREEN}✓ Base de datos: MySQL${NC}"
    ;;
  "mariadb")
    echo -e "${GREEN}✓ Base de datos: MariaDB${NC}"
    ;;
  "not_installed")
    echo -e "${RED}✗ MySQL/MariaDB no está instalado${NC}"
    exit 1
    ;;
  *)
    echo -e "${YELLOW}⚠ No se pudo determinar el tipo de base de datos${NC}"
    ;;
  esac

  # 5. Verificar conexión a MySQL
  echo -e "\n${YELLOW}Verificando conexión a MySQL...${NC}"

  # Intentar conectar sin password (usando socket)
  if test_mysql_connection; then
    echo -e "${GREEN}✓ Conexión exitosa a MySQL (sin password)${NC}"
    ROOT_PASS=""
  else
    echo -e "${YELLOW}⚠ No se pudo conectar a MySQL sin password${NC}"

    # Intentar con password
    read -s -p "Ingrese la password de root de MySQL: " ROOT_PASS
    echo

    if test_mysql_connection_with_pass "$ROOT_PASS"; then
      echo -e "${GREEN}✓ Conexión exitosa a MySQL (con password)${NC}"
    else
      echo -e "${RED}✗ No se pudo conectar a MySQL${NC}"
      echo -e "${RED}✗ Verifique la password o que el servicio esté funcionando${NC}"
      echo -e "\n${YELLOW}Diagnóstico:${NC}"
      echo -e "  - Socket: ${MYSQL_SOCKET:-No detectado}"
      echo -e "  - Estado del servicio:"
      systemctl status mysql 2>/dev/null || systemctl status mariadb 2>/dev/null || echo "    Servicio no encontrado"
      exit 1
    fi
  fi

  # 6. Obtener versión de MySQL
  echo -e "\n${YELLOW}Obteniendo versión de MySQL...${NC}"
  MYSQL_VERSION=$(get_mysql_version)

  if [ -z "$MYSQL_VERSION" ]; then
    echo -e "${RED}✗ Error al obtener versión de MySQL${NC}"
    echo -e "${RED}✗ Verifique que el servicio MySQL esté funcionando${NC}"
    exit 1
  fi
  echo -e "${GREEN}✓ Versión de MySQL: ${MYSQL_VERSION}${NC}"

  # 7. Verificar si usuario existe
  echo -e "\n${YELLOW}Verificando existencia del usuario zbx_monitor...${NC}"
  if user_exists "$ROOT_PASS"; then
    echo -e "${YELLOW}⚠ El usuario zbx_monitor ya existe${NC}"

    while true; do
      echo -e "\n¿Qué desea hacer?"
      echo "1) Cambiar password (generar nueva aleatoria)"
      echo "2) Eliminar usuario"
      echo "3) Salir sin cambios"
      read -p "Seleccione una opción (1/2/3): " option

      case $option in
      1)
        NEW_PASS=$(generate_password)
        change_password "$MYSQL_VERSION" "$ROOT_PASS" "$NEW_PASS"
        if [ $? -eq 0 ]; then
          echo -e "\n${GREEN}¡Proceso completado exitosamente!${NC}"
          echo -e "${GREEN}Usuario: zbx_monitor${NC}"
          echo -e "${GREEN}Password: ${YELLOW}$NEW_PASS${NC}"
          echo -e "${GREEN}Permisos: PROCESS, REPLICATION CLIENT, SELECT${NC}"
          echo -e "${GREEN}Hosts permitidos: localhost, 127.0.0.1${NC}"
          echo -e "\n${YELLOW}Para probar la conexión ejecute:${NC}"
          echo -e "mysql -h 127.0.0.1 -u zbx_monitor -p'$NEW_PASS' -e \"SHOW DATABASES;\""
        fi
        exit 0
        ;;
      2)
        delete_user "$ROOT_PASS"
        if [ $? -eq 0 ]; then
          echo -e "\n${GREEN}Usuario eliminado. ¿Desea crearlo nuevamente?${NC}"
          read -p "Crear usuario? (s/n): " create_again
          if [[ "$create_again" =~ ^[Ss]$ ]]; then
            NEW_PASS=$(generate_password)
            create_user "$MYSQL_VERSION" "$ROOT_PASS" "$NEW_PASS" "$DB_TYPE"
            if [ $? -eq 0 ]; then
              echo -e "\n${GREEN}¡Proceso completado exitosamente!${NC}"
              echo -e "${GREEN}Usuario: zbx_monitor${NC}"
              echo -e "${GREEN}Password: ${YELLOW}$NEW_PASS${NC}"
              echo -e "${GREEN}Permisos: PROCESS, REPLICATION CLIENT, SELECT${NC}"
              echo -e "${GREEN}Hosts permitidos: localhost, 127.0.0.1${NC}"
              echo -e "\n${YELLOW}Para probar la conexión ejecute:${NC}"
              echo -e "mysql -h 127.0.0.1 -u zbx_monitor -p'$NEW_PASS' -e \"SHOW DATABASES;\""
            fi
          fi
        fi
        exit 0
        ;;
      3)
        echo -e "${YELLOW}Saliendo sin cambios...${NC}"
        exit 0
        ;;
      *)
        echo -e "${RED}Opción inválida, intente nuevamente${NC}"
        ;;
      esac
    done
  else
    echo -e "${GREEN}✓ El usuario zbx_monitor no existe${NC}"
    NEW_PASS=$(generate_password)
    create_user "$MYSQL_VERSION" "$ROOT_PASS" "$NEW_PASS" "$DB_TYPE"

    if [ $? -eq 0 ]; then
      echo -e "\n${GREEN}¡Proceso completado exitosamente!${NC}"
      echo -e "${GREEN}Usuario: zbx_monitor${NC}"
      echo -e "${GREEN}Password: ${YELLOW}$NEW_PASS${NC}"
      echo -e "${GREEN}Permisos: PROCESS, REPLICATION CLIENT, SELECT${NC}"
      echo -e "${GREEN}Hosts permitidos: localhost, 127.0.0.1${NC}"
      echo -e "\n${YELLOW}Para probar la conexión ejecute:${NC}"
      echo -e "mysql -h 127.0.0.1 -u zbx_monitor -p'$NEW_PASS' -e \"SHOW DATABASES;\""
      echo -e "mysql -h localhost -u zbx_monitor -p'$NEW_PASS' -e \"SHOW DATABASES;\""

      # Prueba automática
      echo -e "\n${YELLOW}Probando conexión...${NC}"
      sleep 2
      if test_zbx_monitor_connection "$NEW_PASS" "127.0.0.1"; then
        echo -e "${GREEN}✓ Conexión exitosa desde 127.0.0.1${NC}"
      else
        echo -e "${YELLOW}⚠ No se pudo conectar desde 127.0.0.1, probando localhost...${NC}"
        if test_zbx_monitor_connection "$NEW_PASS" "localhost"; then
          echo -e "${GREEN}✓ Conexión exitosa desde localhost${NC}"
        else
          echo -e "${RED}✗ No se pudo conectar desde ningún host${NC}"
          echo -e "${YELLOW}Verifique la configuración de MySQL${NC}"
        fi
      fi
    else
      echo -e "\n${RED}¡Error en el proceso! Por favor verifique los logs${NC}"
    fi
  fi

  echo -e "\n${GREEN}========================================${NC}"
  echo -e "${GREEN}Script finalizado${NC}"
  echo -e "${GREEN}Autor: Felipe Román <froman@orangebox.cl>${NC}"
  echo -e "${GREEN}Web: www.orangebox.cl${NC}"
  echo -e "${GREEN}========================================${NC}"
}

# --- Ejecutar ---
main "$@"
