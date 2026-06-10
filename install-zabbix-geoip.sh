#!/bin/bash

# ==============================================
# Script: install-zabbix-geoip.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Email: froman@orangebox.cl
# Descripcion: Instalacion y configuracion de GeoIP
#              para mapas geograficos en Zabbix
# ==============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variables
LOG_FILE="/root/zabbix_geoip_install_$(date +%Y%m%d_%H%M%S).log"
GEOIP_DIR="/usr/share/GeoIP"
ZABBIX_GEOIP_DIR="/usr/share/zabbix/geoip"
ACCOUNT_ID=""
LICENSE_KEY=""

# ==============================================
# FUNCIONES
# ==============================================

show_help() {
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  Script: install-zabbix-geoip.sh${NC}"
  echo -e "${GREEN}  Mapas geográficos automáticos para Zabbix${NC}"
  echo -e "${GREEN}============================================${NC}\n"

  echo -e "${YELLOW}DESCRIPCIÓN:${NC}"
  echo -e "  Este script instala y configura GeoIP para Zabbix"
  echo -e "  permitiendo la geolocalización automática de hosts"
  echo -e "  en mapas geográficos.\n"

  echo -e "${YELLOW}REQUISITOS PREVIOS:${NC}"
  echo -e "  • Servidor Zabbix instalado y funcionando"
  echo -e "  • Acceso root al servidor"
  echo -e "  • Conexión a internet para descargar bases de datos\n"

  echo -e "${YELLOW}CÓMO OBTENER CREDENCIALES GRATUITAS DE MAXMIND:${NC}"
  echo -e "  ${BLUE}1.${NC} Ve a https://www.maxmind.com/en/geolite2/signup"
  echo -e "  ${BLUE}2.${NC} Regístrate (es gratis, solo necesitas email)"
  echo -e "  ${BLUE}3.${NC} Confirma tu cuenta en el email recibido"
  echo -e "  ${BLUE}4.${NC} Inicia sesión en https://www.maxmind.com/en/account/login"
  echo -e "  ${BLUE}5.${NC} Ve a 'My Account' → 'Manage License Keys'"
  echo -e "  ${BLUE}6.${NC} Haz clic en 'Generate new license key'"
  echo -e "  ${BLUE}7.${NC} Asígnale un nombre (ej: 'Zabbix Server')"
  echo -e "  ${BLUE}8.${NC} Copia el ${GREEN}Account ID${NC} y la ${GREEN}License Key${NC} generados"
  echo -e "  ${BLUE}9.${NC} Pégalos cuando el script los solicite\n"

  echo -e "${YELLOW}USO:${NC}"
  echo -e "  ${GREEN}./install-zabbix-geoip.sh${NC}                    - Modo interactivo"
  echo -e "  ${GREEN}./install-zabbix-geoip.sh --auto ID KEY${NC}      - Modo automático"
  echo -e "  ${GREEN}./install-zabbix-geoip.sh --help${NC}              - Mostrar esta ayuda\n"

  echo -e "${YELLOW}EJEMPLOS:${NC}"
  echo -e "  # Modo interactivo (pregunta credenciales)"
  echo -e "  ${GREEN}./install-zabbix-geoip.sh${NC}"
  echo -e ""
  echo -e "  # Modo automático con credenciales"
  echo -e "  ${GREEN}./install-zabbix-geoip.sh --auto 123456 abc123def456${NC}\n"

  echo -e "${YELLOW}LOGS:${NC}"
  echo -e "  • Instalación: ${GREEN}${LOG_FILE}${NC}"
  echo -e "  • Actualización GeoIP: ${GREEN}/var/log/geoip-update.log${NC}\n"

  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  🌐 https://www.orangebox.cl${NC}"
  echo -e "${GREEN}============================================${NC}"
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

check_root() {
  if [ "$EUID" -ne 0 ]; then
    log_error "Este script debe ejecutarse como root"
    exit 1
  fi
}

show_maxmind_instructions() {
  echo -e "\n${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}  INSTRUCCIONES PARA OBTENER CREDENCIALES GRATUITAS${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e ""
  echo -e "${BLUE}1.${NC} Ve a ${GREEN}https://www.maxmind.com/en/geolite2/signup${NC}"
  echo -e "${BLUE}2.${NC} Regístrate (es ${GREEN}GRATUITO${NC}, solo necesitas email)"
  echo -e "${BLUE}3.${NC} Confirma tu cuenta en el email recibido"
  echo -e "${BLUE}4.${NC} Inicia sesión en ${GREEN}https://www.maxmind.com/en/account/login${NC}"
  echo -e "${BLUE}5.${NC} Ve a ${YELLOW}'My Account' → 'Manage License Keys'${NC}"
  echo -e "${BLUE}6.${NC} Haz clic en ${YELLOW}'Generate new license key'${NC}"
  echo -e "${BLUE}7.${NC} Asígnale un nombre (ej: ${GREEN}'Zabbix Server'${NC})"
  echo -e "${BLUE}8.${NC} Copia el ${GREEN}Account ID${NC} y la ${GREEN}License Key${NC} generados"
  echo -e "${BLUE}9.${NC} Pégalos a continuación cuando se te solicite"
  echo -e ""
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

  read -p "¿Ya tienes tus credenciales de MaxMind? (s/N): " has_credentials
  if [[ ! "$has_credentials" =~ ^[Ss]$ ]]; then
    echo -e "${YELLOW}Por favor, obtén tus credenciales en el enlace indicado y vuelve a ejecutar el script.${NC}"
    echo -e "${YELLOW}Presiona Enter cuando estés listo...${NC}"
    read -r
  fi
}

get_maxmind_credentials() {
  log_step "Configurando credenciales de MaxMind GeoIP..."

  show_maxmind_instructions

  echo -e "${YELLOW}Ingrese sus credenciales de MaxMind:${NC}"
  read -p "Account ID: " ACCOUNT_ID
  read -p "License Key: " LICENSE_KEY

  if [ -z "$ACCOUNT_ID" ] || [ -z "$LICENSE_KEY" ]; then
    log_error "Account ID y License Key son obligatorios"
    exit 1
  fi

  log_info "Credenciales configuradas"
}

install_dependencies() {
  log_step "Instalando dependencias..."

  dnf install -y epel-release >>"$LOG_FILE" 2>&1
  dnf install -y geoipupdate crontabs wget curl >>"$LOG_FILE" 2>&1

  log_info "Dependencias instaladas"
}

configure_geoip() {
  log_step "Configurando GeoIP..."

  # Crear directorios
  mkdir -p "$GEOIP_DIR"
  mkdir -p "$ZABBIX_GEOIP_DIR"

  # Configurar GeoIP.conf
  cat >/etc/GeoIP.conf <<EOF
# Configuración GeoIP Update para Zabbix
AccountID $ACCOUNT_ID
LicenseKey $LICENSE_KEY
EditionIDs GeoLite2-City
DatabaseDirectory $GEOIP_DIR
EOF

  chmod 600 /etc/GeoIP.conf

  log_info "GeoIP configurado"
}

download_initial_geoip() {
  log_step "Descargando base de datos GeoIP inicial..."

  if command -v geoipupdate &>/dev/null; then
    geoipupdate >>"$LOG_FILE" 2>&1
    log_info "Base de datos GeoIP descargada"
  else
    log_error "geoipupdate no encontrado"
    exit 1
  fi
}

setup_geoip_files() {
  log_step "Configurando archivos GeoIP para Zabbix..."

  # Crear enlace simbólico o copiar archivo
  if [ -f "$GEOIP_DIR/GeoLite2-City.mmdb" ]; then
    cp "$GEOIP_DIR/GeoLite2-City.mmdb" "$ZABBIX_GEOIP_DIR/" 2>/dev/null ||
      ln -sf "$GEOIP_DIR/GeoLite2-City.mmdb" "$ZABBIX_GEOIP_DIR/GeoLite2-City.mmdb" 2>/dev/null

    chown -R zabbix:zabbix "$ZABBIX_GEOIP_DIR" 2>/dev/null
    chmod 755 "$ZABBIX_GEOIP_DIR"
    chmod 644 "$ZABBIX_GEOIP_DIR/GeoLite2-City.mmdb" 2>/dev/null

    log_info "Archivo GeoIP configurado en $ZABBIX_GEOIP_DIR"
  else
    log_warn "Archivo GeoLite2-City.mmdb no encontrado"
  fi
}

create_update_script() {
  log_step "Creando script de actualización automática..."

  cat >/usr/local/bin/update-zabbix-geoip.sh <<'EOF'
#!/bin/bash

# Script de actualización de GeoIP para Zabbix
LOG_FILE="/var/log/geoip-update.log"
GEOIP_DIR="/usr/share/GeoIP"
ZABBIX_GEOIP_DIR="/usr/share/zabbix/geoip"

echo "$(date): Iniciando actualización GeoIP..." >> $LOG_FILE

# Actualizar base de datos
/usr/bin/geoipupdate >> $LOG_FILE 2>&1

if [ $? -eq 0 ]; then
    # Copiar al directorio de Zabbix
    cp "$GEOIP_DIR/GeoLite2-City.mmdb" "$ZABBIX_GEOIP_DIR/" 2>/dev/null
    chown zabbix:zabbix "$ZABBIX_GEOIP_DIR/GeoLite2-City.mmdb" 2>/dev/null
    echo "$(date): Actualización GeoIP completada exitosamente" >> $LOG_FILE
else
    echo "$(date): ERROR en actualización GeoIP" >> $LOG_FILE
fi
EOF

  chmod +x /usr/local/bin/update-zabbix-geoip.sh

  log_info "Script de actualización creado: /usr/local/bin/update-zabbix-geoip.sh"
}

setup_cron() {
  log_step "Configurando actualización automática (cron)..."

  # Actualización semanal (domingo a las 2 AM)
  cat >/etc/cron.weekly/geoip-update <<EOF
#!/bin/bash
/usr/local/bin/update-zabbix-geoip.sh
EOF

  chmod +x /etc/cron.weekly/geoip-update

  # También agregar a crontab como respaldo
  (
    crontab -l 2>/dev/null
    echo "0 2 * * 0 /usr/local/bin/update-zabbix-geoip.sh"
  ) | crontab - 2>/dev/null

  log_info "Cron configurado (actualización semanal los domingos a las 2 AM)"
}

configure_zabbix_server() {
  log_step "Configurando Zabbix Server para GeoIP..."

  # Verificar que Zabbix server existe
  if [ -f /etc/zabbix/zabbix_server.conf ]; then
    # Agregar o actualizar configuración GeoIP
    if grep -q "^# GeoIPDatabaseFile" /etc/zabbix/zabbix_server.conf; then
      sed -i "s|^# GeoIPDatabaseFile=.*|GeoIPDatabaseFile=${ZABBIX_GEOIP_DIR}/GeoLite2-City.mmdb|" /etc/zabbix/zabbix_server.conf
    elif grep -q "^GeoIPDatabaseFile" /etc/zabbix/zabbix_server.conf; then
      sed -i "s|^GeoIPDatabaseFile=.*|GeoIPDatabaseFile=${ZABBIX_GEOIP_DIR}/GeoLite2-City.mmdb|" /etc/zabbix/zabbix_server.conf
    else
      echo "GeoIPDatabaseFile=${ZABBIX_GEOIP_DIR}/GeoLite2-City.mmdb" >>/etc/zabbix/zabbix_server.conf
    fi

    log_info "Zabbix Server configurado para usar GeoIP"
  else
    log_warn "Zabbix Server no encontrado, configuración manual requerida"
  fi
}

configure_php() {
  log_step "Configurando PHP para mapas..."

  # Asegurar que PHP tiene extensión curl
  dnf install -y php-curl php-json >>"$LOG_FILE" 2>&1

  # Aumentar límites para mapas
  if [ -f /etc/php.ini ]; then
    sed -i 's/max_execution_time = .*/max_execution_time = 300/' /etc/php.ini
    sed -i 's/memory_limit = .*/memory_limit = 512M/' /etc/php.ini
  fi

  log_info "PHP configurado"
}

configure_apache() {
  log_step "Configurando Apache para mapas..."

  # Configurar CSP para permitir mapas
  if [ -f /etc/httpd/conf.d/zabbix.conf ]; then
    if ! grep -q "Content-Security-Policy.*services.zabbix.com" /etc/httpd/conf.d/zabbix.conf; then
      sed -i '/<IfModule mod_headers.c>/a \    Header set Content-Security-Policy "connect-src '\''self'\'' ws: wss: https://services.zabbix.com https://tile.openstreetmap.org https://api.maptiler.com"' /etc/httpd/conf.d/zabbix.conf
    fi
  fi

  log_info "Apache configurado"
}

restart_services() {
  log_step "Reiniciando servicios..."

  systemctl restart httpd 2>/dev/null
  systemctl restart php-fpm 2>/dev/null
  systemctl restart zabbix-server 2>/dev/null

  log_info "Servicios reiniciados"
}

show_host_update_sql() {
  log_step "Generando script SQL para actualizar coordenadas de hosts existentes..."

  cat >/root/update_host_coordinates.sql <<'EOF'
-- Script para actualizar coordenadas de hosts existentes
-- Ejecutar con: mysql --defaults-file=/root/.my.cnf zabbix < update_host_coordinates.sql

-- Ejemplo: Actualizar host "Zabbix server" con coordenadas de Providencia, Santiago
UPDATE hosts 
SET inventory = JSON_SET(
    COALESCE(inventory, '{}'),
    '$.location_latitude', '-33.43333',
    '$.location_longitude', '-70.61667',
    '$.location', 'Providencia, Santiago, Región Metropolitana, Chile. Altitud: 615 m s.n.m.'
)
WHERE name = 'Zabbix server' 
AND (inventory IS NULL OR JSON_EXTRACT(inventory, '$.location_latitude') IS NULL);

-- Para otros hosts, repetir con sus nombres y coordenadas
-- UPDATE hosts SET inventory = JSON_SET(COALESCE(inventory, '{}'), 
--     '$.location_latitude', 'LATITUD', 
--     '$.location_longitude', 'LONGITUD',
--     '$.location', 'DESCRIPCION')
-- WHERE name = 'NOMBRE_DEL_HOST';

-- Verificar hosts con coordenadas
SELECT name, 
       JSON_EXTRACT(inventory, '$.location_latitude') as latitude,
       JSON_EXTRACT(inventory, '$.location_longitude') as longitude
FROM hosts 
WHERE inventory IS NOT NULL 
  AND JSON_EXTRACT(inventory, '$.location_latitude') IS NOT NULL;
EOF

  log_info "Script SQL creado: /root/update_host_coordinates.sql"
}

show_completion() {
  local server_ip=$(hostname -I | awk '{print $1}')

  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  INSTALACION GEOIP COMPLETADA${NC}"
  echo -e "${GREEN}============================================${NC}\n"

  echo -e "${YELLOW}📋 PASOS SIGUIENTES EN ZABBIX WEB:${NC}"
  echo -e ""
  echo -e "${BLUE}1. Configurar proveedor de mapas:${NC}"
  echo -e "   Administration → General → Geographical maps"
  echo -e "   Seleccione 'OpenStreetMap' o 'MapTiler'"
  echo -e "   Click en 'Update'"
  echo -e ""
  echo -e "${BLUE}2. Agregar widget Geomap al dashboard:${NC}"
  echo -e "   Monitoring → Dashboards → Add widget → Geomap"
  echo -e "   Configurar vista inicial con coordenadas de Chile:"
  echo -e "   Latitud: -33.43333, Longitud: -70.61667, Zoom: 12"
  echo -e ""
  echo -e "${BLUE}3. Para actualizar coordenadas de hosts existentes:${NC}"
  echo -e "   mysql --defaults-file=/root/.my.cnf zabbix < /root/update_host_coordinates.sql"
  echo -e ""
  echo -e "${BLUE}4. O manualmente en cada host:${NC}"
  echo -e "   Data collection → Hosts → [host] → Inventory tab"
  echo -e "   Mode: Manual"
  echo -e "   Location latitude: -33.43333"
  echo -e "   Location longitude: -70.61667"
  echo -e "   Location: Providencia, Santiago, Chile"
  echo -e ""
  echo -e "${YELLOW}📁 ARCHIVOS CREADOS:${NC}"
  echo -e "   Log: ${LOG_FILE}"
  echo -e "   Script SQL: /root/update_host_coordinates.sql"
  echo -e "   Script actualización: /usr/local/bin/update-zabbix-geoip.sh"
  echo -e "   Directorio GeoIP: ${ZABBIX_GEOIP_DIR}"
  echo -e "   Log actualización: /var/log/geoip-update.log"
  echo -e ""
  echo -e "${YELLOW}🔧 COMANDOS ÚTILES:${NC}"
  echo -e "   # Actualizar GeoIP manualmente"
  echo -e "   /usr/local/bin/update-zabbix-geoip.sh"
  echo -e ""
  echo -e "   # Ver log de actualización"
  echo -e "   tail -f /var/log/geoip-update.log"
  echo -e ""
  echo -e "   # Verificar archivo GeoIP"
  echo -e "   ls -la ${ZABBIX_GEOIP_DIR}/GeoLite2-City.mmdb"
  echo -e ""
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  🌐 https://www.orangebox.cl${NC}"
  echo -e "${GREEN}============================================${NC}\n"

  # Ejecución manual del script para probar
  echo -e "${YELLOW}¿Desea ejecutar una actualización GeoIP ahora? (s/N): ${NC}"
  read -r confirm
  if [[ "$confirm" =~ ^[Ss]$ ]]; then
    /usr/local/bin/update-zabbix-geoip.sh
    log_info "Actualización GeoIP ejecutada"
  fi
}

# ==============================================
# MAIN
# ==============================================

# Verificar argumentos
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
  show_help
  exit 0
fi

clear
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Instalador de GeoIP para Zabbix${NC}"
echo -e "${GREEN}  Mapas geográficos automáticos${NC}"
echo -e "${GREEN}============================================${NC}\n"

check_root

# Modo automático
if [ "$1" == "--auto" ] && [ -n "$2" ] && [ -n "$3" ]; then
  ACCOUNT_ID="$2"
  LICENSE_KEY="$3"
  log_info "Modo automático con Account ID: $ACCOUNT_ID"
else
  get_maxmind_credentials
fi

# Confirmar antes de continuar
echo -e "${YELLOW}¿Desea continuar con la instalación? (s/N): ${NC}"
read -r confirm
if [[ ! "$confirm" =~ ^[Ss]$ ]]; then
  echo -e "${RED}Instalación cancelada${NC}"
  exit 0
fi

# Ejecutar instalación
install_dependencies
configure_geoip
download_initial_geoip
setup_geoip_files
create_update_script
setup_cron
configure_zabbix_server
configure_php
configure_apache
restart_services
show_host_update_sql
show_completion
