#!/bin/bash

# ==============================================
# Script: install-zabbix-geoip.sh
# Autor: Felipe Roman
# Web: www.orangebox.cl
# Descripcion: Instalacion de GeoIP para Zabbix
# ==============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

LOG_FILE="/root/zabbix_geoip_install_$(date +%Y%m%d_%H%M%S).log"
GEOIP_DIR="/usr/share/GeoIP"
ZABBIX_GEOIP_DIR="/usr/share/zabbix/geoip"

log_info() { echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"; }
log_error() { echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1" | tee -a "$LOG_FILE"; }
log_step() { echo -e "\n${BLUE}[*]${NC} $1" | tee -a "$LOG_FILE"; }

check_root() {
  if [ "$EUID" -ne 0 ]; then
    log_error "Este script debe ejecutarse como root"
    exit 1
  fi
}

install_dependencies() {
  log_step "Instalando dependencias..."

  # Asegurar que curl está instalado
  if ! command -v curl &>/dev/null; then
    dnf install -y curl >>"$LOG_FILE" 2>&1
  fi

  # Habilitar EPEL
  dnf install -y epel-release >>"$LOG_FILE" 2>&1

  # Intentar instalar desde EPEL
  dnf install -y geoipupdate --enablerepo=epel >>"$LOG_FILE" 2>&1

  # Si falla, instalar desde GitHub
  if ! command -v geoipupdate &>/dev/null; then
    log_warn "Instalando geoipupdate desde GitHub..."
    cd /tmp
    curl -L -o geoipupdate.rpm https://github.com/maxmind/geoipupdate/releases/download/v7.1.1/geoipupdate_7.1.1_linux_amd64.rpm
    dnf install -y ./geoipupdate.rpm >>"$LOG_FILE" 2>&1
    rm -f geoipupdate.rpm
    cd -
  fi

  # Instalar crontabs
  dnf install -y crontabs >>"$LOG_FILE" 2>&1

  # Verificar
  if command -v geoipupdate &>/dev/null; then
    log_info "geoipupdate instalado correctamente"
  else
    log_error "No se pudo instalar geoipupdate"
    exit 1
  fi
}

configure_geoip() {
  log_step "Configurando GeoIP..."

  read -p "Ingrese su Account ID de MaxMind: " ACCOUNT_ID
  read -p "Ingrese su License Key de MaxMind: " LICENSE_KEY

  mkdir -p "$GEOIP_DIR" "$ZABBIX_GEOIP_DIR"

  cat >/etc/GeoIP.conf <<EOF
AccountID $ACCOUNT_ID
LicenseKey $LICENSE_KEY
EditionIDs GeoLite2-City
DatabaseDirectory $GEOIP_DIR
EOF

  chmod 600 /etc/GeoIP.conf
  log_info "GeoIP configurado"
}

download_geoip() {
  log_step "Descargando base de datos GeoIP..."
  geoipupdate -v >>"$LOG_FILE" 2>&1

  if [ -f "$GEOIP_DIR/GeoLite2-City.mmdb" ]; then
    cp "$GEOIP_DIR/GeoLite2-City.mmdb" "$ZABBIX_GEOIP_DIR/"
    chown -R zabbix:zabbix "$ZABBIX_GEOIP_DIR" 2>/dev/null
    log_info "Base de datos descargada"
  else
    log_error "Error al descargar base de datos"
    exit 1
  fi
}

create_update_script() {
  log_step "Creando script de actualización..."

  cat >/usr/local/bin/update-zabbix-geoip.sh <<'EOF'
#!/bin/bash
LOG_FILE="/var/log/geoip-update.log"
/usr/bin/geoipupdate >> $LOG_FILE 2>&1
cp /usr/share/GeoIP/GeoLite2-City.mmdb /usr/share/zabbix/geoip/ 2>/dev/null
echo "$(date): Actualización completada" >> $LOG_FILE
EOF

  chmod +x /usr/local/bin/update-zabbix-geoip.sh

  # Configurar cron semanal
  echo "0 2 * * 0 /usr/local/bin/update-zabbix-geoip.sh" | crontab -
  log_info "Script de actualización y cron configurados"
}

configure_zabbix() {
  log_step "Configurando Zabbix Server..."

  if [ -f /etc/zabbix/zabbix_server.conf ]; then
    sed -i '/^GeoIPDatabaseFile/d' /etc/zabbix/zabbix_server.conf
    echo "GeoIPDatabaseFile=${ZABBIX_GEOIP_DIR}/GeoLite2-City.mmdb" >>/etc/zabbix/zabbix_server.conf
    systemctl restart zabbix-server
    log_info "Zabbix Server configurado"
  fi
}

show_completion() {
  echo -e "\n${GREEN}============================================${NC}"
  echo -e "${GREEN}  INSTALACION GEOIP COMPLETADA${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo -e "\n${YELLOW}📋 PASOS EN ZABBIX WEB:${NC}"
  echo -e "   Administration → General → Geographical maps"
  echo -e "   Seleccione OpenStreetMap y haga click en Update"
  echo -e "\n   Monitoring → Dashboards → Add widget → Geomap"
  echo -e "   Latitud: -33.43333, Longitud: -70.61667, Zoom: 12"
  echo -e "\n${GREEN}============================================${NC}\n"
}

# ==============================================
# MAIN
# ==============================================

clear
echo -e "${GREEN}Instalador de GeoIP para Zabbix${NC}\n"
check_root
install_dependencies
configure_geoip
download_geoip
create_update_script
configure_zabbix
show_completion
