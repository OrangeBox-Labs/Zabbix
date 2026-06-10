#!/bin/bash

# ==============================================
# Script: install-zabbix-server.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Instalacion de Zabbix Server 7.4 en AlmaLinux 10
#              con MySQL/MariaDB, Apache y SELinux
# ==============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variables configurables
ZABBIX_VERSION="7.4"
DB_PASSWORD="Zabbix123!"
ZBX_PASSWORD="Zabbix123!"
MYSQL_ROOT_PASSWORD=""
INSTALL_TYPE="server" # server o agent

# ==============================================
# FUNCIONES
# ==============================================

show_usage() {
  echo -e "${GREEN}USO:${NC}"
  echo "  $0                                    - Instalacion interactiva"
  echo "  $0 --auto                             - Instalacion automatica (con passwords por defecto)"
  echo "  $0 --agent                            - Instalar solo Zabbix Agent"
  echo "  $0 --db-password <pass>               - Password para usuario zabbix en DB"
  echo "  $0 --mysql-root-password <pass>       - Password para root de MySQL"
  echo "  $0 --help                             - Mostrar esta ayuda"
  echo ""
  echo -e "${GREEN}EJEMPLOS:${NC}"
  echo "  # Instalacion interactiva"
  echo "  ./install-zabbix-server.sh"
  echo ""
  echo "  # Instalacion automatica con passwords personalizados"
  echo "  ./install-zabbix-server.sh --auto --db-password MiPass123 --mysql-root-password RootPass456"
  echo ""
  echo "  # Instalar solo el agente"
  echo "  ./install-zabbix-server.sh --agent"
  echo ""
}

log_info() {
  echo -e "${GREEN}[✓]${NC} $1"
}

log_error() {
  echo -e "${RED}[✗]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[!]${NC} $1"
}

log_step() {
  echo -e "\n${BLUE}[*]${NC} $1"
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

install_mariadb() {
  log_step "Instalando MariaDB..."
  dnf install mariadb-server mariadb -y
  systemctl enable --now mariadb
  log_info "MariaDB instalado y en ejecucion"
}

secure_mariadb() {
  if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
    log_step "Configurando password de root de MariaDB..."
    mysqladmin -u root password "$MYSQL_ROOT_PASSWORD"
    log_info "Password de root configurado"
  else
    log_step "Configuracion segura de MariaDB..."
    mysql_secure_installation
  fi
}

configure_repository() {
  log_step "Configurando repositorio de Zabbix..."

  # Excluir zabbix de EPEL si existe
  if [ -f /etc/yum.repos.d/epel.repo ]; then
    if ! grep -q "excludepkgs=zabbix" /etc/yum.repos.d/epel.repo; then
      echo "excludepkgs=zabbix*" >>/etc/yum.repos.d/epel.repo
      log_info "Zabbix excluido de EPEL"
    fi
  fi

  # Instalar repositorio de Zabbix
  rpm -Uvh https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/release/alma/10/noarch/zabbix-release-latest-${ZABBIX_VERSION}.el10.noarch.rpm
  dnf clean all
  log_info "Repositorio de Zabbix configurado"
}

install_server() {
  log_step "Instalando Zabbix Server, frontend y agente..."
  dnf install -y zabbix-server-mysql zabbix-web-mysql zabbix-apache-conf zabbix-sql-scripts zabbix-selinux-policy zabbix-agent
  log_info "Paquetes de Zabbix instalados"
}

install_agent_only() {
  log_step "Instalando solo Zabbix Agent..."
  dnf install -y zabbix-agent
  log_info "Zabbix Agent instalado"
}

create_database() {
  log_step "Creando base de datos para Zabbix..."

  if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
    MYSQL_CMD="mysql -uroot -p${MYSQL_ROOT_PASSWORD}"
  else
    MYSQL_CMD="mysql -uroot"
  fi

  $MYSQL_CMD <<EOF
create database if not exists zabbix character set utf8mb4 collate utf8mb4_bin;
create user if not exists zabbix@localhost identified by '${DB_PASSWORD}';
grant all privileges on zabbix.* to zabbix@localhost;
set global log_bin_trust_function_creators = 1;
flush privileges;
EOF

  log_info "Base de datos y usuario creados"

  log_step "Importando esquema inicial..."
  zcat /usr/share/zabbix/sql-scripts/mysql/server.sql.gz | mysql --default-character-set=utf8mb4 -uzabbix -p${DB_PASSWORD} zabbix

  $MYSQL_CMD <<EOF
set global log_bin_trust_function_creators = 0;
flush privileges;
EOF

  log_info "Esquema de base de datos importado"
}

configure_server() {
  log_step "Configurando Zabbix Server..."

  # Configurar password de base de datos
  sed -i "s/^# DBPassword=.*/DBPassword=${DB_PASSWORD}/" /etc/zabbix/zabbix_server.conf
  sed -i "s/^DBPassword=.*/DBPassword=${DB_PASSWORD}/" /etc/zabbix/zabbix_server.conf

  # Configurar PHP timezone
  sed -i "s/^; php_value date.timezone Europe\/Riga/php_value date.timezone America\/Santiago/" /etc/httpd/conf.d/zabbix.conf
  sed -i "s/^# php_value date.timezone Europe\/Riga/php_value date.timezone America\/Santiago/" /etc/httpd/conf.d/zabbix.conf

  log_info "Zabbix Server configurado"
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

  systemctl restart zabbix-server zabbix-agent httpd php-fpm
  systemctl enable zabbix-server zabbix-agent httpd php-fpm

  log_info "Servicios iniciados y habilitados"
}

configure_firewall() {
  log_step "Configurando firewall..."

  if command -v firewall-cmd &>/dev/null; then
    firewall-cmd --permanent --add-service=http
    firewall-cmd --permanent --add-port=10050/tcp
    firewall-cmd --reload
    log_info "Firewall configurado"
  else
    log_warn "firewalld no instalado, omitiendo configuracion"
  fi
}

show_completion() {
  local server_ip=$(hostname -I | awk '{print $1}')
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  INSTALACION DE ZABBIX COMPLETADA${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "\n${YELLOW}URL DE ACCESO:${NC}"
  echo -e "  http://${server_ip}/zabbix"
  echo -e "\n${YELLOW}CREDENCIALES POR DEFECTO:${NC}"
  echo -e "  Usuario: Admin"
  echo -e "  Password: zabbix"
  echo -e "\n${YELLOW}CONFIGURACION DE BASE DE DATOS:${NC}"
  echo -e "  Usuario: zabbix"
  echo -e "  Password: ${DB_PASSWORD}"
  if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
    echo -e "  Root password: ${MYSQL_ROOT_PASSWORD}"
  fi
  echo -e "\n${YELLOW}COMANDOS UTILES:${NC}"
  echo -e "  # Ver logs del servidor"
  echo -e "  tail -f /var/log/zabbix/zabbix_server.log"
  echo -e "  # Ver logs del agente"
  echo -e "  tail -f /var/log/zabbix/zabbix_agentd.log"
  echo -e "  # Estado de servicios"
  echo -e "  systemctl status zabbix-server zabbix-agent httpd php-fpm"
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  🌐 https://www.orangebox.cl${NC}"
  echo -e "${GREEN}============================================${NC}\n"
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
  --db-password)
    DB_PASSWORD="$2"
    shift 2
    ;;
  --mysql-root-password)
    MYSQL_ROOT_PASSWORD="$2"
    shift 2
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
echo -e "${GREEN}============================================${NC}\n"

check_root
detect_os

if [ "$AUTO_MODE" = false ] && [ "$AGENT_ONLY" = false ]; then
  echo -e "${YELLOW}Este script instalara Zabbix Server 7.4 con:${NC}"
  echo -e "  • MariaDB (MySQL)"
  echo -e "  • Apache Web Server"
  echo -e "  • PHP-FPM"
  echo -e "  • Zabbix Server"
  echo -e "  • Zabbix Agent"
  echo -e "  • SELinux Policy"
  echo -e "\n${YELLOW}Password por defecto para DB: ${DB_PASSWORD}${NC}"
  echo -e "${YELLOW}¿Desea continuar? (s/N): ${NC}"
  read -r confirm
  if [[ ! "$confirm" =~ ^[Ss]$ ]]; then
    echo -e "${RED}Instalacion cancelada${NC}"
    exit 0
  fi
fi

if [ "$AGENT_ONLY" = true ]; then
  # Instalacion solo agente
  configure_repository
  install_agent_only
  configure_agent
  start_services
  configure_firewall
  echo -e "\n${GREEN}[✓] Zabbix Agent instalado correctamente${NC}"
  echo -e "Configuracion en: /etc/zabbix/zabbix_agentd.conf"
else
  # Instalacion completa
  install_mariadb

  if [ -z "$MYSQL_ROOT_PASSWORD" ] && [ "$AUTO_MODE" = false ]; then
    secure_mariadb
  else
    secure_mariadb
  fi

  configure_repository
  install_server
  create_database
  configure_server
  configure_agent
  start_services
  configure_firewall
  show_completion
fi
