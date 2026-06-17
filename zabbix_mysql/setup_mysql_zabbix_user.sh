#!/bin/bash
# ============================================================
# Script: mysql_zabbix_setup.sh
# Autor: Felipe Román <froman@orangebox.cl>
# Web: www.orangebox.cl
# Descripción: Configura usuario zbx_monitor para Zabbix en MySQL
# ============================================================

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Función para generar password aleatoria
generate_password() {
  local chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.,$'
  local password=''
  for i in {1..20}; do
    password+="${chars:RANDOM%${#chars}:1}"
  done
  echo "$password"
}

# Función para probar conexión MySQL sin password
test_mysql_connection() {
  mysql -u root -e "SELECT 1;" 2>/dev/null
  return $?
}

# Función para probar conexión MySQL con password
test_mysql_connection_with_pass() {
  local pass=$1
  mysql -u root -p"$pass" -e "SELECT 1;" 2>/dev/null
  return $?
}

# Función para obtener password de root
get_root_password() {
  local pass
  echo -e "${YELLOW}El usuario root de MySQL requiere password${NC}"
  read -s -p "Ingrese la password de root de MySQL: " pass
  echo
  echo "$pass"
}

# Función para ejecutar comandos MySQL
run_mysql_command() {
  local command=$1
  local root_pass=$2
  local output

  if [ -z "$root_pass" ]; then
    output=$(mysql -u root -e "$command" 2>&1)
    local ret=$?
  else
    output=$(mysql -u root -p"$root_pass" -e "$command" 2>&1)
    local ret=$?
  fi

  # Mostrar errores solo si no es un error de "usuario no existe"
  if [ $ret -ne 0 ] && [[ ! "$output" =~ "doesn't exist" ]] && [[ ! "$output" =~ "Unknown user" ]] && [[ ! "$output" =~ "There is no such grant" ]]; then
    echo -e "${RED}Error en MySQL: $output${NC}" >&2
  fi

  return $ret
}

# Función para verificar si el usuario zbx_monitor puede conectar
test_zbx_monitor_connection() {
  local user_pass=$1
  local host=$2

  if [ -z "$host" ]; then
    host="localhost"
  fi

  mysql -h "$host" -u zbx_monitor -p"$user_pass" -e "SELECT 1;" 2>/dev/null
  return $?
}

# Función para eliminar usuario en MySQL 5.1
delete_user_if_exists() {
  local user=$1
  local host=$2
  local root_pass=$3

  # Verificar si el usuario existe
  local exists=$(run_mysql_command "SELECT COUNT(*) FROM mysql.user WHERE User='$user' AND Host='$host';" "$root_pass" 2>/dev/null | tail -n 1)

  if [[ "$exists" == "1" ]]; then
    run_mysql_command "DROP USER '$user'@'$host';" "$root_pass" 2>/dev/null
    return $?
  else
    return 0 # El usuario no existe, no es error
  fi
}

# Función para crear usuario en MySQL 5.1 (usando GRANT)
create_user_mysql51() {
  local host=$1
  local password=$2
  local root_pass=$3

  # En MySQL 5.1, se usa GRANT para crear el usuario
  run_mysql_command "GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'zbx_monitor'@'$host' IDENTIFIED BY '$password';" "$root_pass"
  return $?
}

# Función para crear usuario
create_user() {
  local mysql_version=$1
  local root_pass=$2
  local new_password=$3

  echo -e "${GREEN}Creando usuario zbx_monitor...${NC}"

  # Eliminar el usuario si existe en todos los hosts
  echo -e "${YELLOW}  Eliminando usuarios existentes...${NC}"
  delete_user_if_exists "zbx_monitor" "localhost" "$root_pass"
  delete_user_if_exists "zbx_monitor" "127.0.0.1" "$root_pass"
  delete_user_if_exists "zbx_monitor" "%" "$root_pass"

  echo -e "${YELLOW}  Creando usuarios...${NC}"

  # Verificar versión para usar el método adecuado
  if [[ "$mysql_version" == "5.1"* ]] || [[ "$mysql_version" == "5.0"* ]]; then
    # MySQL 5.1 o anterior - usar GRANT
    echo -e "${YELLOW}  Usando método GRANT para MySQL 5.1${NC}"

    create_user_mysql51 "localhost" "$new_password" "$root_pass"
    if [ $? -ne 0 ]; then
      echo -e "${RED}  ✗ Error creando localhost${NC}"
      return 1
    fi

    create_user_mysql51 "127.0.0.1" "$new_password" "$root_pass"
    if [ $? -ne 0 ]; then
      echo -e "${RED}  ✗ Error creando 127.0.0.1${NC}"
      return 1
    fi

    # Intentar con % (opcional)
    echo -e "${YELLOW}  Creando usuario para cualquier host (%)...${NC}"
    create_user_mysql51 "%" "$new_password" "$root_pass" 2>/dev/null
    if [ $? -ne 0 ]; then
      echo -e "${YELLOW}  ⚠ No se pudo crear usuario para '%%', continuando...${NC}"
    fi

  else
    # MySQL 5.5+ - usar CREATE USER
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

    run_mysql_command "CREATE USER 'zbx_monitor'@'%' IDENTIFIED BY '$new_password';" "$root_pass" 2>/dev/null

    # Otorgar permisos
    echo -e "${YELLOW}  Otorgando permisos...${NC}"
    run_mysql_command "GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'zbx_monitor'@'localhost';" "$root_pass"
    run_mysql_command "GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'zbx_monitor'@'127.0.0.1';" "$root_pass"
    run_mysql_command "GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'zbx_monitor'@'%';" "$root_pass" 2>/dev/null
  fi

  echo -e "${YELLOW}  Aplicando privilegios...${NC}"
  run_mysql_command "FLUSH PRIVILEGES;" "$root_pass"

  echo -e "${GREEN}✓ Usuario creado exitosamente${NC}"
  echo -e "${GREEN}✓ Password generada: ${YELLOW}$new_password${NC}"

  # Verificar conexión del nuevo usuario
  echo -e "\n${YELLOW}Verificando conexiones del usuario zbx_monitor...${NC}"
  sleep 1

  # Probar localhost (socket)
  echo -n "  - Probando localhost (socket)... "
  if test_zbx_monitor_connection "$new_password" "localhost"; then
    echo -e "${GREEN}✓ OK${NC}"
  else
    echo -e "${RED}✗ FALLÓ${NC}"
  fi

  # Probar 127.0.0.1 (TCP/IP)
  echo -n "  - Probando 127.0.0.1 (TCP/IP)... "
  if test_zbx_monitor_connection "$new_password" "127.0.0.1"; then
    echo -e "${GREEN}✓ OK${NC}"
  else
    echo -e "${RED}✗ FALLÓ${NC}"
  fi

  return 0
}

# Función para cambiar password
change_password() {
  local mysql_version=$1
  local root_pass=$2
  local new_password=$3

  echo -e "${YELLOW}Cambiando password del usuario zbx_monitor...${NC}"

  if [[ "$mysql_version" == "5.1"* ]] || [[ "$mysql_version" == "5.0"* ]]; then
    # MySQL 5.1 - usar SET PASSWORD
    run_mysql_command "SET PASSWORD FOR 'zbx_monitor'@'localhost' = PASSWORD('$new_password');" "$root_pass"
    run_mysql_command "SET PASSWORD FOR 'zbx_monitor'@'127.0.0.1' = PASSWORD('$new_password');" "$root_pass"
    run_mysql_command "SET PASSWORD FOR 'zbx_monitor'@'%' = PASSWORD('$new_password');" "$root_pass" 2>/dev/null
  else
    # MySQL 5.5+ - usar ALTER USER
    run_mysql_command "ALTER USER 'zbx_monitor'@'localhost' IDENTIFIED BY '$new_password';" "$root_pass"
    run_mysql_command "ALTER USER 'zbx_monitor'@'127.0.0.1' IDENTIFIED BY '$new_password';" "$root_pass"
    run_mysql_command "ALTER USER 'zbx_monitor'@'%' IDENTIFIED BY '$new_password';" "$root_pass" 2>/dev/null
  fi

  run_mysql_command "FLUSH PRIVILEGES;" "$root_pass"

  if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Password actualizada exitosamente${NC}"
    echo -e "${GREEN}✓ Nueva password: ${YELLOW}$new_password${NC}"

    # Verificar conexiones
    echo -e "\n${YELLOW}Verificando conexiones con nueva password...${NC}"
    sleep 1

    echo -n "  - Probando localhost (socket)... "
    if test_zbx_monitor_connection "$new_password" "localhost"; then
      echo -e "${GREEN}✓ OK${NC}"
    else
      echo -e "${RED}✗ FALLÓ${NC}"
    fi

    echo -n "  - Probando 127.0.0.1 (TCP/IP)... "
    if test_zbx_monitor_connection "$new_password" "127.0.0.1"; then
      echo -e "${GREEN}✓ OK${NC}"
    else
      echo -e "${RED}✗ FALLÓ${NC}"
    fi

    return 0
  else
    echo -e "${RED}✗ Error al cambiar la password${NC}"
    return 1
  fi
}

# Función para eliminar usuario
delete_user() {
  local root_pass=$1

  echo -e "${YELLOW}Eliminando usuario zbx_monitor...${NC}"

  echo -n "  - Eliminando localhost... "
  delete_user_if_exists "zbx_monitor" "localhost" "$root_pass"
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC}"
  fi

  echo -n "  - Eliminando 127.0.0.1... "
  delete_user_if_exists "zbx_monitor" "127.0.0.1" "$root_pass"
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC}"
  fi

  echo -n "  - Eliminando %... "
  delete_user_if_exists "zbx_monitor" "%" "$root_pass"
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC}"
  fi

  run_mysql_command "FLUSH PRIVILEGES;" "$root_pass"
  echo -e "${GREEN}✓ Usuario eliminado exitosamente${NC}"
  return 0
}

# Función para verificar existencia de usuario
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

# Función para obtener versión de MySQL
get_mysql_version() {
  local root_pass=$1
  local version

  if [ -z "$root_pass" ]; then
    version=$(mysql -u root -e "SELECT VERSION();" 2>/dev/null | grep -v "VERSION" | head -n 1)
  else
    version=$(mysql -u root -p"$root_pass" -e "SELECT VERSION();" 2>/dev/null | grep -v "VERSION" | head -n 1)
  fi

  if [ -z "$version" ]; then
    echo -e "${RED}✗ Error al obtener versión de MySQL${NC}"
    echo -e "${RED}✗ Verifique que el servicio MySQL esté funcionando${NC}"
    exit 1
  fi

  echo "$version"
}

# ============================================================
# INICIO DEL SCRIPT
# ============================================================

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Configuración de zbx_monitor para Zabbix${NC}"
echo -e "${GREEN}========================================${NC}"

# 1. Verificar permisos de root del sistema
ROOT_PASS=""

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}✗ Este script debe ejecutarse como root del sistema${NC}"
  echo -e "${YELLOW}Por favor, ejecute: sudo $0${NC}"
  exit 1
fi

echo -e "${GREEN}✓ Script ejecutándose como root del sistema${NC}"

# 2. Verificar conexión a MySQL
echo -e "\n${YELLOW}Verificando conexión a MySQL...${NC}"

if test_mysql_connection; then
  echo -e "${GREEN}✓ Conexión exitosa a MySQL (sin password)${NC}"
  ROOT_PASS=""
else
  echo -e "${YELLOW}⚠ No se pudo conectar a MySQL sin password${NC}"
  ROOT_PASS=$(get_root_password)

  if test_mysql_connection_with_pass "$ROOT_PASS"; then
    echo -e "${GREEN}✓ Conexión exitosa a MySQL (con password)${NC}"
  else
    echo -e "${RED}✗ No se pudo conectar a MySQL${NC}"
    echo -e "${RED}✗ Verifique la password o que el servicio esté funcionando${NC}"
    exit 1
  fi
fi

# 3. Obtener versión de MySQL
echo -e "\n${YELLOW}Obteniendo versión de MySQL...${NC}"
MYSQL_VERSION=$(get_mysql_version "$ROOT_PASS")
echo -e "${GREEN}✓ Versión de MySQL: ${MYSQL_VERSION}${NC}"

# 4. Verificar si usuario existe
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
        echo -e "${GREEN}Hosts permitidos: localhost, 127.0.0.1, %${NC}"
        echo -e "\n${YELLOW}Para probar la conexión ejecute:${NC}"
        echo -e "mysql -h 127.0.0.1 -u zbx_monitor -p'$NEW_PASS' -e \"SHOW DATABASES;\""
      fi
      exit 0
      ;;
    2)
      delete_user "$ROOT_PASS"
      echo -e "\n${GREEN}Usuario eliminado. ¿Desea crearlo nuevamente?${NC}"
      read -p "Crear usuario? (s/n): " create_again
      if [[ "$create_again" =~ ^[Ss]$ ]]; then
        NEW_PASS=$(generate_password)
        create_user "$MYSQL_VERSION" "$ROOT_PASS" "$NEW_PASS"
        if [ $? -eq 0 ]; then
          echo -e "\n${GREEN}¡Proceso completado exitosamente!${NC}"
          echo -e "${GREEN}Usuario: zbx_monitor${NC}"
          echo -e "${GREEN}Password: ${YELLOW}$NEW_PASS${NC}"
          echo -e "${GREEN}Permisos: PROCESS, REPLICATION CLIENT, SELECT${NC}"
          echo -e "${GREEN}Hosts permitidos: localhost, 127.0.0.1, %${NC}"
          echo -e "\n${YELLOW}Para probar la conexión ejecute:${NC}"
          echo -e "mysql -h 127.0.0.1 -u zbx_monitor -p'$NEW_PASS' -e \"SHOW DATABASES;\""
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
  create_user "$MYSQL_VERSION" "$ROOT_PASS" "$NEW_PASS"

  if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}¡Proceso completado exitosamente!${NC}"
    echo -e "${GREEN}Usuario: zbx_monitor${NC}"
    echo -e "${GREEN}Password: ${YELLOW}$NEW_PASS${NC}"
    echo -e "${GREEN}Permisos: PROCESS, REPLICATION CLIENT, SELECT${NC}"
    echo -e "${GREEN}Hosts permitidos: localhost, 127.0.0.1, %${NC}"
    echo -e "\n${YELLOW}Para probar la conexión ejecute:${NC}"
    echo -e "mysql -h 127.0.0.1 -u zbx_monitor -p'$NEW_PASS' -e \"SHOW DATABASES;\""
    echo -e "mysql -h localhost -u zbx_monitor -p'$NEW_PASS' -e \"SHOW DATABASES;\""
  else
    echo -e "\n${RED}¡Error en el proceso! Por favor verifique los logs${NC}"
  fi
fi

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Script finalizado${NC}"
echo -e "${GREEN}Autor: Felipe Román <froman@orangebox.cl>${NC}"
echo -e "${GREEN}Web: www.orangebox.cl${NC}"
echo -e "${GREEN}========================================${NC}"
