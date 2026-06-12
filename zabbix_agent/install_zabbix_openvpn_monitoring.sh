#!/bin/bash
# ============================================================
# Script: install_zabbix_openvpn_monitoring.sh
# Descripción: Instala monitoreo de certificados OpenVPN para Zabbix
#              CON DETECCIÓN Y REEMPLAZO DE CONFIGURACIÓN PREVIA
#              Versión mejorada con detalle por certificado
# ============================================================
# Autor: OrangeBox - Área de Infraestructura
# Web: https://orangebox.cl
# Fecha: $(date '+%Y-%m-%d')
# Versión: 2.0
# ============================================================

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variables
SCRIPT_NAME="check_openvpn_certs_zabbix.sh"
SCRIPT_PATH="/usr/local/bin/${SCRIPT_NAME}"
ZABBIX_CONF_DIR="/etc/zabbix/zabbix_agent2.d"
ZABBIX_CONF_FILE="${ZABBIX_CONF_DIR}/openvpn_certs.conf"
ZABBIX_USER="zabbix"
GROUP_NAME="zabbix-openvpn"
LOG_FILE="/var/log/zabbix_openvpn_install.log"
INSTALLED_FLAG="/etc/zabbix/.openvpn_monitoring_installed"

# Logo de OrangeBox
show_banner() {
  echo ""
  echo "============================================================"
  echo "   ██████╗ ██████╗  █████╗ ███╗   ██╗ ██████╗ ███████╗"
  echo "  ██╔═══██╗██╔══██╗██╔══██╗████╗  ██║██╔════╝ ██╔════╝"
  echo "  ██║   ██║██████╔╝███████║██╔██╗ ██║██║  ███╗█████╗  "
  echo "  ██║   ██║██╔══██╗██╔══██║██║╚██╗██║██║   ██║██╔══╝  "
  echo "  ╚██████╔╝██║  ██║██║  ██║██║ ╚████║╚██████╔╝███████╗"
  echo "   ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚══════╝"
  echo "============================================================"
  echo "     MONITOREO OPENVPN CERTIFICADOS - ZABBIX"
  echo "                OrangeBox.cl | Infraestructura"
  echo "============================================================"
  echo ""
}

# Funciones
log() {
  echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_success() {
  echo -e "${GREEN}✓ $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
  echo -e "${RED}✗ ERROR: $1${NC}" | tee -a "$LOG_FILE"
  exit 1
}

log_info() {
  echo -e "${BLUE}ℹ $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
  echo -e "${YELLOW}⚠ $1${NC}" | tee -a "$LOG_FILE"
}

# Verificar si ya está instalado
check_existing_installation() {
  log_info "Verificando si ya existe monitoreo OpenVPN..."

  INSTALLED=false
  OLD_CONFIGS_FOUND=false

  # Verificar flag de instalación
  if [ -f "$INSTALLED_FLAG" ]; then
    log_warning "Se encontró flag de instalación previa"
    INSTALLED=true
  fi

  # Verificar si el script existe
  if [ -f "$SCRIPT_PATH" ]; then
    log_warning "El script $SCRIPT_NAME ya existe"
    INSTALLED=true
  fi

  # Verificar si hay configuraciones antiguas de OpenVPN
  if ls ${ZABBIX_CONF_DIR}/*openvpn*.conf 2>/dev/null | grep -v "openvpn_certs.conf" >/dev/null 2>&1; then
    log_warning "Se encontraron configuraciones antiguas de OpenVPN"
    OLD_CONFIGS_FOUND=true
    INSTALLED=true
  fi

  # Verificar UserParameters antiguos
  if grep -r "openvpn.certs" "$ZABBIX_CONF_DIR" 2>/dev/null | grep -q "UserParameter"; then
    log_warning "Ya existen UserParameters de OpenVPN configurados"
    INSTALLED=true
  fi

  # Si ya está instalado, preguntar qué hacer
  if [ "$INSTALLED" = true ]; then
    echo ""
    log_warning "=========================================="
    log_warning "MONITOREO OPENVPN YA ESTÁ INSTALADO"
    log_warning "=========================================="
    echo ""
    echo "Opciones:"
    echo "  1) Reinstalar (eliminar configuraciones antiguas y reinstalar)"
    echo "  2) Solo actualizar script"
    echo "  3) Verificar estado actual"
    echo "  4) Desinstalar completamente"
    echo "  5) Salir"
    echo ""
    read -p "Selecciona una opción [1-5]: " OPTION

    case $OPTION in
    1)
      log_info "Limpiando configuraciones antiguas y reinstalando..."
      cleanup_old_config
      ;;
    2)
      log_info "Actualizando script solamente..."
      update_script_only
      exit 0
      ;;
    3)
      check_status
      exit 0
      ;;
    4)
      uninstall_monitoring
      exit 0
      ;;
    5)
      log_info "Saliendo sin cambios"
      exit 0
      ;;
    *)
      log_error "Opción inválida"
      ;;
    esac
  else
    log_success "No se encontró instalación previa. Procediendo con instalación nueva."
  fi
}

# Limpiar configuraciones antiguas
cleanup_old_config() {
  log_info "Limpiando configuraciones antiguas de OpenVPN..."

  # Eliminar script antiguo
  rm -f "$SCRIPT_PATH"

  # Eliminar todos los archivos de configuración antiguos de OpenVPN
  find "$ZABBIX_CONF_DIR" -name "*openvpn*.conf" -type f -exec rm -v {} \; | tee -a "$LOG_FILE"

  # Eliminar flag de instalación
  rm -f "$INSTALLED_FLAG"

  log_success "Limpieza completada"
}

# Actualizar solo el script
update_script_only() {
  log_info "Actualizando script de monitoreo..."
  create_monitoring_script
  log_success "Script actualizado"
}

# Desinstalar monitoreo
uninstall_monitoring() {
  log_warning "Desinstalando monitoreo OpenVPN..."

  read -p "¿Estás seguro? Esto eliminará toda la configuración. (y/N): " CONFIRM

  if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
    # Eliminar script
    rm -f "$SCRIPT_PATH"

    # Eliminar todos los archivos de configuración de OpenVPN
    find "$ZABBIX_CONF_DIR" -name "*openvpn*.conf" -type f -exec rm -v {} \;

    # Eliminar flag
    rm -f "$INSTALLED_FLAG"

    # Remover usuario del grupo
    if getent group "$GROUP_NAME" >/dev/null; then
      gpasswd -d "$ZABBIX_USER" "$GROUP_NAME" 2>/dev/null || true
    fi

    systemctl restart zabbix-agent2

    log_success "Desinstalación completada"
  else
    log_info "Desinstalación cancelada"
  fi
}

# Verificar estado actual
check_status() {
  echo ""
  echo "=========================================="
  echo "ESTADO DEL MONITOREO OPENVPN"
  echo "=========================================="

  echo -e "\n📁 Script:"
  if [ -f "$SCRIPT_PATH" ]; then
    echo -e "  ${GREEN}✓ Existe${NC} - $SCRIPT_PATH"
    echo -e "  Permisos: $(ls -l $SCRIPT_PATH | awk '{print $1}')"
  else
    echo -e "  ${RED}✗ No existe${NC}"
  fi

  echo -e "\n⚙️ UserParameters:"
  if grep -r "openvpn.certs" "$ZABBIX_CONF_DIR" 2>/dev/null | grep -q "UserParameter"; then
    echo -e "  ${GREEN}✓ Configurados${NC}"
    grep -r "openvpn.certs" "$ZABBIX_CONF_DIR" 2>/dev/null | grep "UserParameter" | while read line; do
      echo "    • $(echo $line | awk -F'=' '{print $1}')"
    done
  else
    echo -e "  ${RED}✗ No configurados${NC}"
  fi

  echo -e "\n👤 Usuario Zabbix:"
  if groups "$ZABBIX_USER" 2>/dev/null | grep -q "$GROUP_NAME"; then
    echo -e "  ${GREEN}✓ Miembro del grupo $GROUP_NAME${NC}"
  else
    echo -e "  ${YELLOW}⚠ No es miembro del grupo $GROUP_NAME${NC}"
  fi

  echo -e "\n🔧 Prueba del script:"
  if [ -f "$SCRIPT_PATH" ]; then
    sudo -u "$ZABBIX_USER" "$SCRIPT_PATH" 2>&1 | head -20
  else
    echo -e "  ${RED}Script no disponible${NC}"
  fi

  echo -e "\n📊 Items en Zabbix (desde agente):"
  for item in openvpn.certs.check openvpn.certs.status openvpn.certs.warning openvpn.certs.critical; do
    if zabbix_get -s 127.0.0.1 -k "$item" 2>/dev/null >/dev/null; then
      echo -e "  ${GREEN}✓ $item${NC}"
    else
      echo -e "  ${RED}✗ $item${NC}"
    fi
  done

  echo "=========================================="
}

# Detectar directorio de certificados
detect_cert_dir() {
  log_info "Buscando directorio de certificados OpenVPN..."

  if [ -d "/etc/openvpn/server/easy-rsa/pki/issued" ] && [ "$(ls -A /etc/openvpn/server/easy-rsa/pki/issued/*.crt 2>/dev/null | wc -l)" -gt 0 ]; then
    CERT_DIR="/etc/openvpn/server/easy-rsa/pki/issued"
  elif [ -d "/etc/openvpn/easy-rsa/pki/issued" ] && [ "$(ls -A /etc/openvpn/easy-rsa/pki/issued/*.crt 2>/dev/null | wc -l)" -gt 0 ]; then
    CERT_DIR="/etc/openvpn/easy-rsa/pki/issued"
  elif [ -d "/etc/openvpn/2.0/keys" ] && [ "$(ls -A /etc/openvpn/2.0/keys/*.crt 2>/dev/null | wc -l)" -gt 0 ]; then
    CERT_DIR="/etc/openvpn/2.0/keys"
  else
    log_error "No se pudo encontrar el directorio de certificados"
  fi

  log_success "Directorio encontrado: $CERT_DIR"
}

# Crear script de monitoreo mejorado
create_monitoring_script() {
  log_info "Creando script de monitoreo mejorado..."

  cat >"$SCRIPT_PATH" <<'SCRIPT_EOF'
#!/bin/bash
# ============================================================
# Script: check_openvpn_certs_zabbix.sh
# Descripción: Monitorea certificados OpenVPN con detalle individual
# Autor: OrangeBox - Área de Infraestructura
# Web: https://orangebox.cl
# ============================================================

CERT_DIR="__CERT_DIR__"
DAYS_WARNING=30
DAYS_CRITICAL=15
STATUS=0
OUTPUT=""
WARN_COUNT=0
CRIT_COUNT=0

if [ ! -d "$CERT_DIR" ]; then
    echo "CRITICAL - No se encontro el directorio de certificados: $CERT_DIR"
    exit 2
fi

CERT_COUNT=$(ls "$CERT_DIR"/*.crt 2>/dev/null | wc -l)
if [ "$CERT_COUNT" -eq 0 ]; then
    echo "OK - No hay certificados para monitorear"
    exit 0
fi

for CERT in "$CERT_DIR"/*.crt; do
    [ -f "$CERT" ] || continue
    
    CLIENT_NAME=$(basename "$CERT" .crt)
    EXPIRY_DATE=$(openssl x509 -enddate -noout -in "$CERT" 2>/dev/null | cut -d= -f2)
    
    if [ -z "$EXPIRY_DATE" ]; then
        OUTPUT="${OUTPUT}error: ${CLIENT_NAME} - No se pudo leer certificado\n"
        continue
    fi
    
    EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s 2>/dev/null)
    CURRENT_EPOCH=$(date +%s)
    DIFF_DAYS=$(( (EXPIRY_EPOCH - CURRENT_EPOCH) / 86400 ))
    
    if [ "$DIFF_DAYS" -le "$DAYS_CRITICAL" ]; then
        OUTPUT="${OUTPUT}CRITICAL: ${CLIENT_NAME} vence en ${DIFF_DAYS} días\n"
        CRIT_COUNT=$((CRIT_COUNT + 1))
        STATUS=2
    elif [ "$DIFF_DAYS" -le "$DAYS_WARNING" ]; then
        OUTPUT="${OUTPUT}WARNING: ${CLIENT_NAME} vence en ${DIFF_DAYS} días\n"
        WARN_COUNT=$((WARN_COUNT + 1))
        [ "$STATUS" -lt 1 ] && STATUS=1
    else
        OUTPUT="${OUTPUT}OK: ${CLIENT_NAME} vence en ${DIFF_DAYS} días\n"
    fi
done

echo "========================================"
echo "RESUMEN DE CERTIFICADOS OPENVPN"
echo "========================================"
echo -e "$OUTPUT"
echo "========================================"

if [ $STATUS -eq 0 ]; then
    echo "ESTADO GLOBAL: OK - Todos los certificados estan vigentes"
elif [ $STATUS -eq 1 ]; then
    echo "ESTADO GLOBAL: WARNING - $WARN_COUNT certificado(s) proximos a vencer (menos de $DAYS_WARNING dias)"
elif [ $STATUS -eq 2 ]; then
    echo "ESTADO GLOBAL: CRITICAL - $CRIT_COUNT certificado(s) por vencer (menos de $DAYS_CRITICAL dias)"
fi

echo "========================================"
exit $STATUS
SCRIPT_EOF

  sed -i "s|__CERT_DIR__|$CERT_DIR|g" "$SCRIPT_PATH"
  chmod +x "$SCRIPT_PATH"

  log_success "Script creado: $SCRIPT_PATH"
}

# Configurar permisos
setup_permissions() {
  log_info "Configurando permisos para usuario $ZABBIX_USER..."

  # Crear grupo si no existe
  if ! getent group "$GROUP_NAME" >/dev/null; then
    groupadd "$GROUP_NAME"
    log_success "Grupo $GROUP_NAME creado"
  fi

  # Agregar usuario al grupo
  usermod -a -G "$GROUP_NAME" "$ZABBIX_USER"

  # Aplicar permisos
  OPENVPN_BASE="/etc/openvpn"
  chgrp -R "$GROUP_NAME" "$OPENVPN_BASE" 2>/dev/null || true
  find "$OPENVPN_BASE" -type d -exec chmod 750 {} \; 2>/dev/null || true
  find "$OPENVPN_BASE" -type f \( -name "*.crt" -o -name "*.key" -o -name "*.pem" \) -exec chmod 640 {} \; 2>/dev/null || true

  log_success "Permisos configurados"
}

# Configurar Zabbix
setup_zabbix_config() {
  log_info "Configurando UserParameters..."

  # Eliminar archivos antiguos de OpenVPN (ya limpiamos en cleanup)
  # Crear nuevo archivo de configuración
  cat >"$ZABBIX_CONF_FILE" <<EOF
# OpenVPN Certificate Monitoring
# Instalado: $(date '+%Y-%m-%d %H:%M:%S')
# Autor: OrangeBox - Infraestructura
# Web: https://orangebox.cl

# Script principal con detalle de certificados
UserParameter=openvpn.certs.check,$SCRIPT_PATH

# Código de estado (0=OK, 1=WARNING, 2=CRITICAL)
UserParameter=openvpn.certs.status,$SCRIPT_PATH > /dev/null 2>&1 ; echo \$?

# Flag de warning (1 si hay certificados en WARNING)
UserParameter=openvpn.certs.warning,test -n "\$($SCRIPT_PATH | grep 'WARNING:')" && echo 1 || echo 0

# Flag de critical (1 si hay certificados en CRITICAL)
UserParameter=openvpn.certs.critical,test -n "\$($SCRIPT_PATH | grep 'CRITICAL:')" && echo 1 || echo 0
EOF

  chmod 644 "$ZABBIX_CONF_FILE"
  log_success "Configuración creada: $ZABBIX_CONF_FILE"
}

# Probar instalación
test_installation() {
  log_info "Probando instalación..."

  # Probar script
  if sudo -u "$ZABBIX_USER" "$SCRIPT_PATH" >/dev/null 2>&1; then
    log_success "Script funciona correctamente"
  else
    log_error "Script falla al ejecutarse como $ZABBIX_USER"
  fi

  # Mostrar salida
  echo ""
  log_info "Salida del script:"
  sudo -u "$ZABBIX_USER" "$SCRIPT_PATH"
  echo ""
}

# Crear flag de instalación
create_install_flag() {
  cat >"$INSTALLED_FLAG" <<EOF
Instalado: $(date '+%Y-%m-%d %H:%M:%S')
Script: $SCRIPT_PATH
Directorio certificados: $CERT_DIR
Usuario: $ZABBIX_USER
Grupo: $GROUP_NAME
Autor: OrangeBox - Infraestructura
Version: 2.0
EOF
  log_success "Flag de instalación creado"
}

# Mostrar resumen final
show_summary() {
  echo ""
  echo "============================================================"
  echo -e "${GREEN}              INSTALACIÓN COMPLETADA              ${NC}"
  echo "============================================================"
  echo -e "📁 Directorio certificados: ${BLUE}$CERT_DIR${NC}"
  echo -e "👤 Usuario Zabbix: ${BLUE}$ZABBIX_USER${NC}"
  echo -e "👥 Grupo: ${BLUE}$GROUP_NAME${NC}"
  echo ""
  echo -e "🔧 Comandos útiles:"
  echo -e "  • Probar script: ${YELLOW}sudo -u $ZABBIX_USER $SCRIPT_PATH${NC}"
  echo -e "  • Ver estado: ${YELLOW}$0 --status${NC}"
  echo -e "  • Desinstalar: ${YELLOW}$0 --uninstall${NC}"
  echo ""
  echo -e "📊 Items disponibles en Zabbix:"
  echo -e "  • ${GREEN}openvpn.certs.check${NC}     - Estado detallado"
  echo -e "  • ${GREEN}openvpn.certs.status${NC}    - Código (0,1,2)"
  echo -e "  • ${GREEN}openvpn.certs.warning${NC}   - Flag WARNING"
  echo -e "  • ${GREEN}openvpn.certs.critical${NC}  - Flag CRITICAL"
  echo ""
  echo -e "📋 Ejemplo de salida del script:"
  echo "========================================"
  echo "RESUMEN DE CERTIFICADOS OPENVPN"
  echo "========================================"
  echo "OK: cliente1 vence en 180 días"
  echo "WARNING: cliente2 vence en 25 días"
  echo "CRITICAL: cliente3 vence en 10 días"
  echo "========================================"
  echo "ESTADO GLOBAL: CRITICAL - 1 certificado(s) por vencer"
  echo "========================================"
  echo ""
  echo -e "${GREEN}✓ Script listo para usar${NC}"
  echo "============================================================"
  echo -e "         ${BLUE}OrangeBox.cl - Monitoreo Zabbix${NC}"
  echo "============================================================"
}

# Main
main() {
  show_banner

  log "=== Instalación Monitoreo OpenVPN para Zabbix ==="

  case "${1:-}" in
  --status | -s)
    check_status
    exit 0
    ;;
  --uninstall | -u)
    uninstall_monitoring
    exit 0
    ;;
  --help | -h)
    echo "Uso: $0 [opciones]"
    echo ""
    echo "Opciones:"
    echo "  --status, -s    Ver estado actual del monitoreo"
    echo "  --uninstall, -u Desinstalar monitoreo completamente"
    echo "  --help, -h      Mostrar esta ayuda"
    echo ""
    echo "Sin opciones: Ejecuta la instalación completa"
    exit 0
    ;;
  esac

  check_existing_installation
  detect_cert_dir
  create_monitoring_script
  setup_permissions
  setup_zabbix_config
  test_installation
  create_install_flag

  # Reiniciar agente
  log_info "Reiniciando Zabbix Agent 2..."
  systemctl restart zabbix-agent2
  log_success "Zabbix Agent 2 reiniciado"

  show_summary
  log_success "Instalación completada exitosamente"
}

# Ejecutar main
main "$@"
