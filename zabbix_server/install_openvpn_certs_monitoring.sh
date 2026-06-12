#!/bin/bash
# ============================================================
# Script: install_openvpn_cers_monitoring.sh
# Descripción: Instala monitoreo de certificados OpenVPN en Zabbix
# Ejecutar: En el servidor Zabbix (no en el agente)
# ============================================================

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================
# CONFIGURACIÓN - EDITAR SEGÚN TU ENTORNO
# ============================================================

# Configuración del servidor Zabbix
ZABBIX_SERVER="monitoreo.orangebox.cl"        # IP o hostname del servidor Zabbix
ZABBIX_URL="http://${ZABBIX_SERVER}/zabbix"  # URL de la web Zabbix
API_URL="${ZABBIX_URL}/api_jsonrpc.php"
ZABBIX_USER="Admin"                           # Usuario de Zabbix (cambiar)
ZABBIX_PASS="zabbix"                          # Contraseña (cambiar)

# Configuración del host OpenVPN (opcional - si quieres aplicar plantilla automáticamente)
OPENVPN_HOST="fw-vizcachas.orangebox.cl"      # Nombre del host en Zabbix
OPENVPN_HOST_IP="186.79.131.105"              # IP del agente OpenVPN

# Configuración de la plantilla
TEMPLATE_NAME="Template OpenVPN Monitoring"
TEMPLATE_GROUP="Templates/Applications"

# Umbrales de certificados
DAYS_WARNING=30
DAYS_CRITICAL=15

# ============================================================
# FUNCIONES PRINCIPALES
# ============================================================

# Helper: Logging
log_info() {
    echo -e "${BLUE}ℹ$(date '+%H:%M:%S')${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓$(date '+%H:%M:%S')${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠$(date '+%H:%M:%S')${NC} $1"
}

log_error() {
    echo -e "${RED}✗$(date '+%H:%M:%S')${NC} ERROR: $1"
}

log_step() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}▶ $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Obtener token de autenticación
get_auth_token() {
    log_info "Autenticando en Zabbix API..."
    
    AUTH_TOKEN=$(curl -s -k -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -d "{
            \"jsonrpc\": \"2.0\",
            \"method\": \"user.login\",
            \"params\": {
                \"user\": \"$ZABBIX_USER\",
                \"password\": \"$ZABBIX_PASS\"
            },
            \"id\": 1
        }" | jq -r '.result')
    
    if [ -z "$AUTH_TOKEN" ] || [ "$AUTH_TOKEN" = "null" ]; then
        log_error "No se pudo autenticar. Verifica usuario/contraseña y URL"
        exit 1
    fi
    
    log_success "Autenticación exitosa"
}

# Verificar si el agente OpenVPN está accesible
check_agent() {
    log_info "Verificando agente OpenVPN..."
    
    if ! command -v zabbix_get &> /dev/null; then
        log_warning "zabbix_get no instalado, saltando verificación"
        return 0
    fi
    
    if zabbix_get -s "$OPENVPN_HOST_IP" -k "agent.ping" 2>/dev/null | grep -q 1; then
        log_success "Agente OpenVPN responde correctamente"
    else
        log_warning "No se puede contactar al agente OpenVPN"
        log_warning "Asegúrate de que el script check_openvpn_certs_zabbix.sh esté instalado"
    fi
}

# Crear plantilla
create_template() {
    log_info "Creando plantilla: $TEMPLATE_NAME"
    
    # Verificar si ya existe
    EXISTING_TEMPLATE=$(curl -s -k -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -d "{
            \"jsonrpc\": \"2.0\",
            \"method\": \"template.get\",
            \"params\": {
                \"filter\": {\"host\": \"$TEMPLATE_NAME\"},
                \"output\": [\"templateid\"]
            },
            \"auth\": \"$AUTH_TOKEN\",
            \"id\": 2
        }" | jq -r '.result[0].templateid')
    
    if [ -n "$EXISTING_TEMPLATE" ] && [ "$EXISTING_TEMPLATE" != "null" ]; then
        TEMPLATE_ID="$EXISTING_TEMPLATE"
        log_warning "La plantilla ya existe (ID: $TEMPLATE_ID)"
        read -p "¿Deseas actualizarla? (s/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            log_info "Manteniendo plantilla existente"
            return 0
        fi
        # Eliminar plantilla existente para recrearla
        curl -s -k -X POST "$API_URL" \
            -H "Content-Type: application/json" \
            -d "{
                \"jsonrpc\": \"2.0\",
                \"method\": \"template.delete\",
                \"params\": [\"$TEMPLATE_ID\"],
                \"auth\": \"$AUTH_TOKEN\",
                \"id\": 3
            }" > /dev/null
        log_info "Plantilla antigua eliminada"
    fi
    
    # Crear plantilla nueva
    TEMPLATE_ID=$(curl -s -k -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -d "{
            \"jsonrpc\": \"2.0\",
            \"method\": \"template.create\",
            \"params\": {
                \"host\": \"$TEMPLATE_NAME\",
                \"name\": \"$TEMPLATE_NAME\",
                \"groups\": [{\"name\": \"$TEMPLATE_GROUP\"}],
                \"description\": \"Monitoreo de certificados OpenVPN\\n\\nMonitorea expiración de certificados de clientes y CA del servidor.\\n- WARNING: menos de $DAYS_WARNING días\\n- CRITICAL: menos de $DAYS_CRITICAL días\\n\\nRequisitos en el agente:\\n- Script: /usr/local/bin/check_openvpn_certs_zabbix.sh\\n- Permisos de lectura en /etc/openvpn para usuario zabbix\\n- UserParameter: openvpn.certs.check, openvpn.certs.status, openvpn.certs.warning, openvpn.certs.critical\"
            },
            \"auth\": \"$AUTH_TOKEN\",
            \"id\": 4
        }" | jq -r '.result.templateids[0]')
    
    if [ -z "$TEMPLATE_ID" ] || [ "$TEMPLATE_ID" = "null" ]; then
        log_error "No se pudo crear la plantilla"
    fi
    
    log_success "Plantilla creada (ID: $TEMPLATE_ID)"
}

# Crear items en la plantilla
create_items() {
    log_info "Creando items en la plantilla..."
    
    # Item 1: Estado completo (Texto)
    curl -s -k -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -d "{
            \"jsonrpc\": \"2.0\",
            \"method\": \"item.create\",
            \"params\": {
                \"name\": \"OpenVPN: Certificates Status\",
                \"key_\": \"openvpn.certs.check\",
                \"hostid\": \"$TEMPLATE_ID\",
                \"type\": 0,
                \"value_type\": 4,
                \"delay\": \"1d\",
                \"history\": \"90d\",
                \"description\": \"Estado detallado de todos los certificados OpenVPN\\n\\nFormato:\\n- OK, todos los certificados validos\\n- warn: cliente vence en X días\\n- crit: cliente vence en X días\",
                \"tags\": [{\"tag\": \"application\", \"value\": \"openvpn\"}]
            },
            \"auth\": \"$AUTH_TOKEN\",
            \"id\": 5
        }" > /dev/null
    log_success "  ✓ openvpn.certs.check (Texto)"
    
    # Item 2: Código de estado (Numérico)
    curl -s -k -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -d "{
            \"jsonrpc\": \"2.0\",
            \"method\": \"item.create\",
            \"params\": {
                \"name\": \"OpenVPN: Status Code\",
                \"key_\": \"openvpn.certs.status\",
                \"hostid\": \"$TEMPLATE_ID\",
                \"type\": 0,
                \"value_type\": 3,
                \"delay\": \"1d\",
                \"history\": \"90d\",
                \"trends\": \"365d\",
                \"description\": \"Código de estado:\\n0 = OK\\n1 = WARNING\\n2 = CRITICAL\",
                \"tags\": [{\"tag\": \"application\", \"value\": \"openvpn\"}]
            },
            \"auth\": \"$AUTH_TOKEN\",
            \"id\": 6
        }" > /dev/null
    log_success "  ✓ openvpn.certs.status (Numérico)"
    
    # Item 3: Flag Warning
    curl -s -k -X POST "$API_URL\" \
        -H "Content-Type: application/json\" \
        -d \"{
            \"jsonrpc\": \"2.0\",
            \"method\": \"item.create\",
            \"params\": {
                \"name\": \"OpenVPN: Has Warnings\",
                \"key_\": \"openvpn.certs.warning\",
                \"hostid\": \"$TEMPLATE_ID\",
                \"type\": 0,
                \"value_type\": 3,
                \"delay\": \"1d\",
                \"description\": \"1 si hay certificados en WARNING, 0 si no\",
                \"tags\": [{\"tag\": \"application\", \"value\": \"openvpn\"}]
            },
            \"auth\": \"$AUTH_TOKEN\",
            \"id\": 7
        }" > /dev/null
    log_success "  ✓ openvpn.certs.warning (Booleano)"
    
    # Item 4: Flag Critical
    curl -s -k -X POST "$API_URL\" \
        -H "Content-Type: application/json\" \
        -d \"{
            \"jsonrpc\": \"2.0\",
            \"method\": \"item.create\",
            \"params\": {
                \"name\": \"OpenVPN: Has Criticals\",
                \"key_\": \"openvpn.certs.critical\",
                \"hostid\": \"$TEMPLATE_ID\",
                \"type\": 0,
                \"value_type\": 3,
                \"delay\": \"1d\",
                \"description\": \"1 si hay certificados en CRITICAL, 0 si no\",
                \"tags\": [{\"tag\": \"application\", \"value\": \"openvpn\"}]
            },
            \"auth\": \"$AUTH_TOKEN\",
            \"id\": 8
        }" > /dev/null
    log_success "  ✓ openvpn.certs.critical (Booleano)"
}

# Crear triggers
create_triggers() {
    log_info \"Creando triggers...\"
    
    # Trigger Warning
    curl -s -k -X POST \"$API_URL\" \
        -H "Content-Type: application/json" \
        -d "{
            \"jsonrpc\": \"2.0\",
            \"method\": \"trigger.create\",
            \"params\": {
                \"description\": \"OpenVPN: Certificados próximos a vencer (WARNING)\",
                \"expression\": \"last(/$TEMPLATE_NAME/openvpn.certs.warning)=1\",
                \"priority\": 3,
                \"status\": 0,
                \"comments\": \"Uno o más certificados expirarán en menos de $DAYS_WARNING días.\",
                \"tags\": [{\"tag\": \"application\", \"value\": \"openvpn\"}, {\"tag\": \"severity\", \"value\": \"warning\"}]
            },
            \"auth\": \"$AUTH_TOKEN\",
            \"id\": 9
        }" > /dev/null
    log_success \"  ✓ Trigger WARNING\"
    
    # Trigger Critical
    curl -s -k -X POST \"$API_URL\" \
        -H "Content-Type: application/json" \
        -d "{
            \"jsonrpc\": \"2.0\",
            \"method\": \"trigger.create\",
            \"params\": {
                \"description\": \"OpenVPN: Certificados próximos a vencer (CRITICAL)\",
                \"expression\": \"last(/$TEMPLATE_NAME/openvpn.certs.critical)=1\",
                \"priority\": 4,
                \"status\": 0,
                \"comments\": \"Uno o más certificados expirarán en menos de $DAYS_CRITICAL días. ¡Acción requerida!\",
                \"tags\": [{\"tag\": \"application\", \"value\": \"openvpn\"}, {\"tag\": \"severity\", \"value\": \"critical\"}]
            },
            \"auth\": \"$AUTH_TOKEN\",
            \"id\": 10
        }" > /dev/null
    log_success \"  ✓ Trigger CRITICAL\"
    
    # Trigger Error de script
    curl -s -k -X POST \"$API_URL\" \
        -H "Content-Type: application/json" \
        -d "{
            \"jsonrpc\": \"2.0\",
            \"method\": \"trigger.create\",
            \"params\": {
                \"description\": \"OpenVPN: Error en monitoreo de certificados\",
                \"expression\": \"find(/$TEMPLATE_NAME/openvpn.certs.check,\\\"CRITICAL - No se encontro\\\")=1 or find(/$TEMPLATE_NAME/openvpn.certs.check,\\\"ERROR\\\")=1\",
                \"priority\": 5,
                \"status\": 0,
                \"comments\": \"El script de monitoreo no puede acceder a los certificados. Verificar permisos.\",
                \"tags\": [{\"tag\": \"application\", \"value\": \"openvpn\"}, {\"tag\": \"severity\", \"value\": \"disaster\"}]
            },
            \"auth\": \"$AUTH_TOKEN\",
            \"id\": 11
        }" > /dev/null
    log_success \"  ✓ Trigger ERROR\"
}

# Crear gráfico
create_graph() {
    log_info \"Creando gráfico...\"
    
    # Obtener item IDs
    ITEM_IDS=$(curl -s -k -X POST \"$API_URL\" \
        -H "Content-Type: application/json" \
        -d "{
            \"jsonrpc\": \"2.0\",
            \"method\": \"item.get\",
            \"params\": {
                \"hostids\": \"$TEMPLATE_ID\",
                \"filter\": {\"key_\": [\"openvpn.certs.status\", \"openvpn.certs.warning\", \"openvpn.certs.critical\"]}
            },
            \"auth\": \"$AUTH_TOKEN\",
            \"id\": 12
        }" | jq -r '.result[].itemid')
    
    curl -s -k -X POST \"$API_URL\" \
        -H "Content-Type: application/json" \
        -d "{
            \"jsonrpc\": \"2.0\",
            \"method\": \"graph.create\",
            \"params\": {
                \"name\": \"OpenVPN: Certificates Status Evolution\",
                \"width\": 900,
                \"height\": 200,
                \"templateid\": \"$TEMPLATE_ID\",
                \"gitems\": [
                    {\"itemid\": \"$(echo \"$ITEM_IDS\" | sed -n '1p')\", \"color\": \"1A7C11\", \"drawtype\": 5, \"sortorder\": 0},
                    {\"itemid\": \"$(echo \"$ITEM_IDS\" | sed -n '2p')\", \"color\": \"F63100\", \"sortorder\": 1},
                    {\"itemid\": \"$(echo \"$ITEM_IDS\" | sed -n '3p')\", \"color\": \"FF0000\", \"sortorder\": 2}
                ]
            },
            \"auth\": \"$AUTH_TOKEN\",
            \"id\": 13
        }" > /dev/null
    log_success \"  ✓ Gráfico creado\"
}

# Crear dashboard
create_dashboard() {
    log_info \"Creando dashboard OpenVPN Monitoring...\"
    
    DASHBOARD_ID=$(curl -s -k -X POST \"$API_URL\" \
        -H "Content-Type: application/json" \
        -d "{
            \"jsonrpc\": \"2.0\",
            \"method\": \"dashboard.create\",
            \"params\": {
                \"name\": \"OpenVPN Certificate Monitoring\",
                \"pages\": [{
                    \"name\": \"Overview\",
                    \"widgets\": [
                        {
                            \"type\": \"plaintext\",
                            \"name\": \"📜 Estado de Certificados\",
                            \"x\": 0,
                            \"y\": 0,
                            \"width\": 12,
                            \"height\": 6,
                            \"fields\": [
                                {\"type\": 4, \"name\": \"itemid\", \"value\": \"openvpn.certs.check\"}
                            ]
                        },
                        {
                            \"type\": \"gauge\",
                            \"name\": \"📊 Estado General\",
                            \"x\": 12,
                            \"y\": 0,
                            \"width\": 4,
                            \"height\": 4,
                            \"fields\": [
                                {\"type\": 4, \"name\": \"itemid\", \"value\": \"openvpn.certs.status\"},
                                {\"type\": 1, \"name\": \"min\", \"value\": \"0\"},
                                {\"type\": 1, \"name\": \"max\", \"value\": \"2\"}
                            ]
                        },
                        {
                            \"type\": \"item_value\",
                            \"name\": \"⚠️ Warnings\",
                            \"x\": 12,
                            \"y\": 4,
                            \"width\": 2,
                            \"height\": 2,
                            \"fields\": [
                                {\"type\": 4, \"name\": \"itemid\", \"value\": \"openvpn.certs.warning\"}
                            ]
                        },
                        {
                            \"type\": \"item_value\",
                            \"name\": \"🔴 Criticals\",
                            \"x\": 14,
                            \"y\": 4,
                            \"width\": 2,
                            \"height\": 2,
                            \"fields\": [
                                {\"type\": 4, \"name\": \"itemid\", \"value\": \"openvpn.certs.critical\"}
                            ]
                        },
                        {
                            \"type\": \"graph\",
                            \"name\": \"📈 Evolución Histórica\",
                            \"x\": 0,
                            \"y\": 6,
                            \"width\": 12,
                            \"height\": 6,
                            \"fields\": [
                                {\"type\": 3, \"name\": \"graphid\", \"value\": \"openvpn.certs.status\"}
                            ]
                        },
                        {
                            \"type\": \"problems\",
                            \"name\": \"🚨 Problemas Activos\",
                            \"x\": 0,
                            \"y\": 12,
                            \"width\": 16,
                            \"height\": 5,
                            \"fields\": [
                                {\"type\": 5, \"name\": \"tags\", \"value\": \"application:openvpn\"}
                            ]
                        }
                    ]
                }]
            },
            \"auth\": \"$AUTH_TOKEN\",
            \"id\": 14
        }" | jq -r '.result.dashboardids[0]')
    
    if [ -n "$DASHBOARD_ID" ] && [ "$DASHBOARD_ID" != "null" ]; then
        log_success "  ✓ Dashboard creado (ID: $DASHBOARD_ID)"
    else
        log_warning "No se pudo crear el dashboard (puede que ya exista)"
    fi
}

# Aplicar plantilla al host OpenVPN
apply_template_to_host() {
    log_info "Aplicando plantilla al host: $OPENVPN_HOST"
    
    # Obtener host ID
    HOST_ID=$(curl -s -k -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -d "{
            \"jsonrpc\": \"2.0\",
            \"method\": \"host.get\",
            \"params\": {
                \"filter\": {\"host\": \"$OPENVPN_HOST\"},
                \"output\": [\"hostid\"]
            },
            \"auth\": \"$AUTH_TOKEN\",
            \"id\": 15
        }" | jq -r '.result[0].hostid')
    
    if [ -z "$HOST_ID" ] || [ "$HOST_ID" = "null" ]; then
        log_warning "Host '$OPENVPN_HOST' no encontrado en Zabbix"
        log_info "Puedes aplicar la plantilla manualmente después"
        return 1
    fi
    
    # Aplicar plantilla
    curl -s -k -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -d "{
            \"jsonrpc\": \"2.0\",
            \"method\": \"template.massadd\",
            \"params\": {
                \"hosts\": [{\"hostid\": \"$HOST_ID\"}],
                \"templates\": [{\"templateid\": \"$TEMPLATE_ID\"}]
            },
            \"auth\": \"$AUTH_TOKEN\",
            \"id\": 16
        }" > /dev/null
    
    log_success "Plantilla aplicada al host: $OPENVPN_HOST"
}

# Generar script de instalación para el agente
generate_agent_installer() {
    cat > /tmp/install_openvpn_agent.sh << 'AGENT_SCRIPT'
#!/bin/bash
# Script para instalar en el AGENTE OpenVPN
# Ejecutar: ssh root@openvpn-server 'bash -s' < /tmp/install_openvpn_agent.sh

set -e

echo "=== Instalando monitoreo OpenVPN en el agente ==="

# Detectar directorio de certificados
if [ -d "/etc/openvpn/server/easy-rsa/pki/issued" ]; then
    CERT_DIR="/etc/openvpn/server/easy-rsa/pki/issued"
elif [ -d "/etc/openvpn/easy-rsa/pki/issued" ]; then
    CERT_DIR="/etc/openvpn/easy-rsa/pki/issued"
elif [ -d "/etc/openvpn/2.0/keys" ]; then
    CERT_DIR="/etc/openvpn/2.0/keys"
else
    echo "ERROR: No se encontró directorio de certificados"
    exit 1
fi

echo "Directorio encontrado: $CERT_DIR"

# Crear script de monitoreo
cat > /usr/local/bin/check_openvpn_certs_zabbix.sh << 'SCRIPT'
#!/bin/bash
CERT_DIR="__CERT_DIR__"
DAYS_WARNING=30
DAYS_CRITICAL=15
STATUS=0
WARN_LIST=""
CRIT_LIST=""

[ ! -d "$CERT_DIR" ] && echo "CRITICAL - No se encontro el directorio" && exit 2

for CERT in "$CERT_DIR"/*.crt; do
    [ -f "$CERT" ] || continue
    CLIENT_NAME=$(basename "$CERT" .crt)
    EXPIRY_DATE=$(openssl x509 -enddate -noout -in "$CERT" 2>/dev/null | cut -d= -f2)
    [ -z "$EXPIRY_DATE" ] && continue
    EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s 2>/dev/null)
    CURRENT_EPOCH=$(date +%s)
    DIFF_DAYS=$(( (EXPIRY_EPOCH - CURRENT_EPOCH) / 86400 ))
    
    if [ "$DIFF_DAYS" -le "$DAYS_CRITICAL" ]; then
        CRIT_LIST="${CRIT_LIST}crit: ${CLIENT_NAME} vence en ${DIFF_DAYS} días\n"
        STATUS=2
    elif [ "$DIFF_DAYS" -le "$DAYS_WARNING" ]; then
        WARN_LIST="${WARN_LIST}warn: ${CLIENT_NAME} vence en ${DIFF_DAYS} días\n"
        [ "$STATUS" -lt 1 ] && STATUS=1
    fi
done

if [ $STATUS -eq 0 ]; then
    echo "OK, todos los certificados validos"
elif [ $STATUS -eq 1 ]; then
    echo -e "${WARN_LIST}${CRIT_LIST}"
elif [ $STATUS -eq 2 ]; then
    echo -e "${CRIT_LIST}${WARN_LIST}"
fi
exit $STATUS
SCRIPT

sed -i "s|__CERT_DIR__|$CERT_DIR|g" /usr/local/bin/check_openvpn_certs_zabbix.sh
chmod +x /usr/local/bin/check_openvpn_certs_zabbix.sh

# Configurar permisos
groupadd -f zabbix-openvpn
usermod -a -G zabbix-openvpn zabbix
chgrp -R zabbix-openvpn /etc/openvpn
find /etc/openvpn -type d -exec chmod 750 {} \;
find /etc/openvpn -type f \( -name "*.crt" -o -name "*.key" \) -exec chmod 640 {} \;

# Configurar UserParameter
mkdir -p /etc/zabbix/zabbix_agent2.d
cat > /etc/zabbix/zabbix_agent2.d/openvpn.conf << 'USERPARAM'
UserParameter=openvpn.certs.check,/usr/local/bin/check_openvpn_certs_zabbix.sh
UserParameter=openvpn.certs.status,/usr/local/bin/check_openvpn_certs_zabbix.sh > /dev/null 2>&1 ; echo $?
UserParameter=openvpn.certs.warning,test -n "$(/usr/local/bin/check_openvpn_certs_zabbix.sh | grep 'warn:')" && echo 1 || echo 0
UserParameter=openvpn.certs.critical,test -n "$(/usr/local/bin/check_openvpn_certs_zabbix.sh | grep 'crit:')" && echo 1 || echo 0
USERPARAM

# Reiniciar agente
systemctl restart zabbix-agent2

echo "=== Instalación en el agente completada ==="
echo "Prueba: sudo -u zabbix /usr/local/bin/check_openvpn_certs_zabbix.sh"
AGENT_SCRIPT

    chmod +x /tmp/install_openvpn_agent.sh
    log_success "Script del agente generado: /tmp/install_openvpn_agent.sh"
}

# Mostrar resumen final
show_summary() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                INSTALACIÓN COMPLETADA EXITOSAMENTE               ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "📋 RESULTADOS:"
    echo "   ├─ Plantilla:      $TEMPLATE_NAME"
    echo "   ├─ Items:          4 items creados"
    echo "   ├─ Triggers:       3 triggers creados"
    echo "   ├─ Gráfico:        1 gráfico creado"
    echo "   ├─ Dashboard:      OpenVPN Certificate Monitoring"
    echo "   └─ Host:           $OPENVPN_HOST (plantilla aplicada)"
    echo ""
    echo "🔧 PRÓXIMOS PASOS EN EL AGENTE OPENVPN:"
    echo ""
    echo "   1. Copiar el script al agente:"
    echo "      scp /tmp/install_openvpn_agent.sh root@$OPENVPN_HOST_IP:/tmp/"
    echo ""
    echo "   2. Ejecutar en el agente:"
    echo "      ssh root@$OPENVPN_HOST_IP 'bash /tmp/install_openvpn_agent.sh'"
    echo ""
    echo "   3. Verificar en el agente:"
    echo "      ssh root@$OPENVPN_HOST_IP 'sudo -u zabbix /usr/local/bin/check_openvpn_certs_zabbix.sh'"
    echo ""
    echo "📊 VER RESULTADOS EN ZABBIX:"
    echo "   ├─ Dashboard:      Monitorización → Dashboards → OpenVPN Certificate Monitoring"
    echo "   ├─ Últimos datos:   Monitorización → Últimos datos → filtrar por $OPENVPN_HOST"
    echo "   └─ Problemas:       Monitorización → Problemas → filtrar por aplicación openvpn"
    echo ""
    echo "🎯 USO FUTURO:"
    echo "   Para aplicar a otros hosts, simplemente:"
    echo "   Recopilación de datos → Hosts → Seleccionar host → Plantillas → Añadir"
    echo "   Buscar: $TEMPLATE_NAME"
    echo ""
}

# ============================================================
# MAIN
# ============================================================

main() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║     INSTALADOR DE MONITOREO OPENVPN PARA ZABBIX                  ║"
    echo "║     Versión 1.0 - Compatible con Zabbix 7.4                      ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Verificar dependencias
    if ! command -v jq &> /dev/null; then
        log_error "jq no está instalado. Instalar con: yum install jq -y"
        exit 1
    fi
    
    if ! command -v curl &> /dev/null; then
        log_error "curl no está instalado"
        exit 1
    fi
    
    # Ejecutar pasos
    log_step "Paso 1: Autenticación en Zabbix API"
    get_auth_token
    
    log_step "Paso 2: Crear plantilla en Zabbix"
    create_template
    
    log_step "Paso 3: Crear items en la plantilla"
    create_items
    
    log_step "Paso 4: Crear triggers"
    create_triggers
    
    log_step "Paso 5: Crear gráfico"
    create_graph
    
    log_step "Paso 6: Crear dashboard"
    create_dashboard
    
    log_step "Paso 7: Aplicar plantilla al host"
    apply_template_to_host
    
    log_step "Paso 8: Generar script para el agente"
    generate_agent_installer
    
    show_summary
}

# Ejecutar
main "$@"
EOF

