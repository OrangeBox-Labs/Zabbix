#!/bin/bash

# ==============================================
# Script: zabbix-host-manager-API.sh
# Autor: OrangeBox - Area de Infraestructura
# Web: https://orangebox.cl
# Descripcion: Gestion de hosts en Zabbix via API
#              Buscar, eliminar, agregar y modificar PSK
# ==============================================

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ==============================================
# CONFIGURACION (EDITAR SEGUN TU ENTORNO)
# ==============================================

API_TOKEN="e47fd64883410c3c41e1515fk9ec7acadfg2d9f316d671a71e95e353cd5a6780d5"
ZABBIX_API_URL="http://monitoreo.orangebox.cl/zabbix/api_jsonrpc.php"
DEBUG_MODE=false

# ==============================================
# FUNCIONES
# ==============================================

clear_screen() {
  clear
  echo -e "${CYAN}============================================${NC}"
  echo -e "${CYAN}     ZABBIX HOST MANAGER - API v1.0${NC}"
  echo -e "${CYAN}     OrangeBox - Infraestructura${NC}"
  echo -e "${CYAN}============================================${NC}"
  echo ""
}

show_menu() {
  echo -e "${YELLOW}MENU PRINCIPAL:${NC}"
  echo ""
  echo -e "${GREEN}1.${NC} Buscar host por nombre"
  echo -e "${GREEN}2.${NC} Buscar host por IP"
  echo -e "${GREEN}3.${NC} Agregar nuevo host"
  echo -e "${GREEN}4.${NC} Eliminar host por nombre"
  echo -e "${GREEN}5.${NC} Eliminar host por IP (elimina todos los hosts con esa IP)"
  echo -e "${GREEN}6.${NC} Cambiar datos de encriptacion PSK"
  echo -e "${GREEN}7.${NC} Listar todos los hosts"
  echo -e "${GREEN}8.${NC} Ver detalles completos de un host"
  echo -e "${RED}0.${NC} Salir"
  echo ""
  echo -ne "${BLUE}Seleccione una opcion: ${NC}"
}

zabbix_api_call() {
  local method="$1"
  local params="$2"

  local response=$(curl -s -k -X POST \
    -H "Content-Type: application/json-rpc" \
    -H "Authorization: Bearer ${API_TOKEN}" \
    -d "{
            \"jsonrpc\": \"2.0\",
            \"method\": \"${method}\",
            \"params\": ${params},
            \"id\": 1
        }" ${ZABBIX_API_URL})

  echo "$response"
}

# ==============================================
# BUSQUEDAS
# ==============================================

buscar_host_por_nombre() {
  echo ""
  echo -ne "${BLUE}Ingrese el nombre del host: ${NC}"
  read HOSTNAME

  echo ""
  echo -e "${YELLOW}Buscando host: ${HOSTNAME}...${NC}"

  RESULT=$(zabbix_api_call "host.get" "{
        \"filter\": {\"name\": \"${HOSTNAME}\"},
        \"output\": [\"hostid\", \"name\", \"host\"],
        \"selectInterfaces\": [\"ip\", \"port\"],
        \"selectTLS\": [\"tls_psk_identity\", \"tls_psk\"]
    }")

  echo ""
  echo -e "${GREEN}Resultado:${NC}"
  echo "$RESULT" | jq -r '.result[] | "Host ID: \(.hostid) | Nombre: \(.name) | IP: \(.interfaces[0].ip // "N/A") | Puerto: \(.interfaces[0].port // "N/A")"' 2>/dev/null || echo "$RESULT"

  echo ""
  read -p "Presione Enter para continuar..."
}

buscar_host_por_ip() {
  echo ""
  echo -ne "${BLUE}Ingrese la IP del host: ${NC}"
  read HOST_IP

  echo ""
  echo -e "${YELLOW}Buscando hosts con IP: ${HOST_IP}...${NC}"

  RESULT=$(zabbix_api_call "hostinterface.get" "{
        \"filter\": {\"ip\": \"${HOST_IP}\"},
        \"output\": [\"interfaceid\", \"ip\", \"port\", \"hostid\"],
        \"selectHost\": [\"hostid\", \"name\", \"host\"]
    }")

  echo ""
  echo -e "${GREEN}Resultado:${NC}"
  echo "$RESULT" | jq -r '.result[] | "Host ID: \(.hostid) | Nombre: \(.host.name) | Interfaz ID: \(.interfaceid) | IP: \(.ip) | Puerto: \(.port)"' 2>/dev/null || echo "$RESULT"

  echo ""
  read -p "Presione Enter para continuar..."
}

# ==============================================
# AGREGAR HOST
# ==============================================

agregar_host() {
  echo ""
  echo -e "${YELLOW}=== AGREGAR NUEVO HOST ===${NC}"
  echo ""

  echo -ne "${BLUE}Nombre del host (ej: servidor.example.com): ${NC}"
  read HOSTNAME

  if [ -z "$HOSTNAME" ]; then
    echo -e "${RED}El nombre del host es obligatorio${NC}"
    read -p "Presione Enter para continuar..."
    return
  fi

  echo -ne "${BLUE}Nombre visible (dejar vacio para usar el mismo): ${NC}"
  read VISIBLE_NAME
  if [ -z "$VISIBLE_NAME" ]; then
    VISIBLE_NAME="$HOSTNAME"
  fi

  echo -ne "${BLUE}IP del host: ${NC}"
  read HOST_IP

  if [ -z "$HOST_IP" ]; then
    echo -e "${RED}La IP del host es obligatoria${NC}"
    read -p "Presione Enter para continuar..."
    return
  fi

  echo -ne "${BLUE}Puerto (default 10050): ${NC}"
  read HOST_PORT
  if [ -z "$HOST_PORT" ]; then
    HOST_PORT="10050"
  fi

  echo -ne "${BLUE}ID del grupo (default 2 - Linux Servers): ${NC}"
  read GROUP_ID
  if [ -z "$GROUP_ID" ]; then
    GROUP_ID="2"
  fi

  echo ""
  echo -e "${YELLOW}Plantillas disponibles:${NC}"
  echo "  10001 - Template OS Linux by Zabbix agent"
  echo "  10005 - Template Linux by Zabbix agent"
  echo "  Otra - Ingresar ID manualmente"
  echo ""
  echo -ne "${BLUE}ID de la plantilla (default 10001): ${NC}"
  read TEMPLATE_ID
  if [ -z "$TEMPLATE_ID" ]; then
    TEMPLATE_ID="10001"
  fi

  echo ""
  echo -e "${YELLOW}¿Habilitar encriptacion TLS/PSK? (s/N): ${NC}"
  read ENABLE_TLS

  TLS_CONNECT="1"
  TLS_ACCEPT="1"
  PSK_IDENTITY=""
  PSK_KEY=""

  if [[ "$ENABLE_TLS" =~ ^[Ss]$ ]]; then
    TLS_CONNECT="2"
    TLS_ACCEPT="2"

    echo ""
    echo -e "${YELLOW}Configuracion TLS/PSK:${NC}"
    echo -ne "${BLUE}PSK Identity (dejar vacio para generar automatico): ${NC}"
    read PSK_IDENTITY

    if [ -z "$PSK_IDENTITY" ]; then
      PSK_IDENTITY="${HOSTNAME}_psk_$(date +%s)"
      echo -e "${GREEN}Identity generada: ${PSK_IDENTITY}${NC}"
    fi

    echo -ne "${BLUE}PSK Key hex 32 bytes (dejar vacio para generar automatico): ${NC}"
    read PSK_KEY

    if [ -z "$PSK_KEY" ]; then
      PSK_KEY=$(openssl rand -hex 32)
      echo -e "${GREEN}Key generada: ${PSK_KEY}${NC}"
    fi
  fi

  echo ""
  echo -e "${YELLOW}Resumen del host a crear:${NC}"
  echo "  Nombre: $HOSTNAME"
  echo "  Nombre visible: $VISIBLE_NAME"
  echo "  IP: $HOST_IP:$HOST_PORT"
  echo "  Grupo ID: $GROUP_ID"
  echo "  Plantilla ID: $TEMPLATE_ID"
  echo "  TLS/PSK: $([ "$TLS_CONNECT" = "2" ] && echo "Habilitado" || echo "Deshabilitado")"
  if [ "$TLS_CONNECT" = "2" ]; then
    echo "  PSK Identity: $PSK_IDENTITY"
    echo "  PSK Key: $PSK_KEY"
  fi
  echo ""

  echo -ne "${RED}¿Confirmar creacion del host? (s/N): ${NC}"
  read CONFIRM

  if [[ ! "$CONFIRM" =~ ^[Ss]$ ]]; then
    echo -e "${YELLOW}Creacion cancelada${NC}"
    read -p "Presione Enter para continuar..."
    return
  fi

  # Construir JSON como string de una sola línea para evitar problemas
  if [ "$TLS_CONNECT" = "2" ] && [ -n "$PSK_IDENTITY" ] && [ -n "$PSK_KEY" ]; then
    JSON_PARAMS="{\"host\":\"${HOSTNAME}\",\"name\":\"${VISIBLE_NAME}\",\"groups\":[{\"groupid\":\"${GROUP_ID}\"}],\"templates\":[{\"templateid\":\"${TEMPLATE_ID}\"}],\"interfaces\":[{\"type\":1,\"main\":1,\"useip\":1,\"ip\":\"${HOST_IP}\",\"dns\":\"\",\"port\":\"${HOST_PORT}\"}],\"tls_connect\":${TLS_CONNECT},\"tls_accept\":${TLS_ACCEPT},\"tls_psk_identity\":\"${PSK_IDENTITY}\",\"tls_psk\":\"${PSK_KEY}\"}"
  else
    JSON_PARAMS="{\"host\":\"${HOSTNAME}\",\"name\":\"${VISIBLE_NAME}\",\"groups\":[{\"groupid\":\"${GROUP_ID}\"}],\"templates\":[{\"templateid\":\"${TEMPLATE_ID}\"}],\"interfaces\":[{\"type\":1,\"main\":1,\"useip\":1,\"ip\":\"${HOST_IP}\",\"dns\":\"\",\"port\":\"${HOST_PORT}\"}],\"tls_connect\":${TLS_CONNECT},\"tls_accept\":${TLS_ACCEPT}}"
  fi

  if [ "$DEBUG_MODE" = true ]; then
    echo ""
    echo -e "${CYAN}DEBUG - JSON a enviar:${NC}"
    echo "$JSON_PARAMS"
    echo ""
  fi

  echo ""
  echo -e "${YELLOW}Creando host...${NC}"

  RESULT=$(zabbix_api_call "host.create" "$JSON_PARAMS")

  echo ""
  if echo "$RESULT" | grep -q '"hostids"'; then
    HOST_ID=$(echo "$RESULT" | jq -r '.result.hostids[0]' 2>/dev/null)
    echo -e "${GREEN}Host creado exitosamente!${NC}"
    echo -e "${GREEN}Host ID: ${HOST_ID}${NC}"

    if [ "$TLS_CONNECT" = "2" ] && [ -n "$PSK_IDENTITY" ] && [ -n "$PSK_KEY" ]; then
      CRED_FILE="/root/zabbix_psk_${HOSTNAME}_$(date +%Y%m%d_%H%M%S).txt"
      cat >"$CRED_FILE" <<EOF2
=============================================
  ZABBIX HOST PSK - ${HOSTNAME}
=============================================

Host: ${HOSTNAME}
IP: ${HOST_IP}:${HOST_PORT}
Host ID: ${HOST_ID}

TLS/PSK:
  Identity: ${PSK_IDENTITY}
  Key: ${PSK_KEY}

=============================================
EOF2
      chmod 600 "$CRED_FILE"
      echo -e "${GREEN}Credenciales PSK guardadas en: ${CRED_FILE}${NC}"
    fi
  else
    echo -e "${RED}Error al crear host:${NC}"
    echo "$RESULT" | jq '.' 2>/dev/null || echo "$RESULT"
  fi

  echo ""
  read -p "Presione Enter para continuar..."
}

# ==============================================
# ELIMINACIONES
# ==============================================

eliminar_host_por_nombre() {
  echo ""
  echo -ne "${BLUE}Ingrese el nombre del host a eliminar: ${NC}"
  read HOSTNAME

  echo ""
  echo -e "${YELLOW}Buscando host: ${HOSTNAME}...${NC}"

  HOST_RESULT=$(zabbix_api_call "host.get" "{
        \"filter\": {\"name\": \"${HOSTNAME}\"},
        \"output\": [\"hostid\", \"name\"],
        \"selectInterfaces\": [\"ip\", \"port\"]
    }")

  HOST_ID=$(echo "$HOST_RESULT" | jq -r '.result[0].hostid' 2>/dev/null)
  HOST_IP=$(echo "$HOST_RESULT" | jq -r '.result[0].interfaces[0].ip // "N/A"' 2>/dev/null)

  if [ -z "$HOST_ID" ] || [ "$HOST_ID" = "null" ]; then
    echo -e "${RED}Host no encontrado: ${HOSTNAME}${NC}"
    read -p "Presione Enter para continuar..."
    return
  fi

  echo -e "${YELLOW}Host encontrado:${NC}"
  echo "  Host ID: $HOST_ID | Nombre: $HOSTNAME | IP: $HOST_IP"
  echo ""
  echo -ne "${RED}¿Esta seguro de eliminar este host? (y/N): ${NC}"
  read CONFIRM

  if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
    RESULT=$(zabbix_api_call "host.delete" "[\"${HOST_ID}\"]")
    echo ""
    if echo "$RESULT" | grep -q '"result"'; then
      echo -e "${GREEN}Host eliminado exitosamente${NC}"
    else
      echo "$RESULT" | jq '.' 2>/dev/null || echo "$RESULT"
    fi
  else
    echo -e "${YELLOW}Eliminacion cancelada${NC}"
  fi

  echo ""
  read -p "Presione Enter para continuar..."
}

eliminar_host_por_ip() {
  echo ""
  echo -ne "${BLUE}Ingrese la IP del host a eliminar: ${NC}"
  read HOST_IP

  echo ""
  echo -e "${YELLOW}Buscando hosts con IP: ${HOST_IP}...${NC}"

  INTERFACE_RESULT=$(zabbix_api_call "hostinterface.get" "{
        \"filter\": {\"ip\": \"${HOST_IP}\"},
        \"output\": [\"hostid\"],
        \"selectHost\": [\"hostid\", \"name\"]
    }")

  echo ""
  echo -e "${YELLOW}Hosts encontrados:${NC}"
  echo "$INTERFACE_RESULT" | jq -r '.result[] | "  Host ID: \(.hostid) | Nombre: \(.host.name)"' 2>/dev/null

  HOST_IDS=$(echo "$INTERFACE_RESULT" | jq -r '.result[].hostid' 2>/dev/null)

  if [ -z "$HOST_IDS" ]; then
    echo -e "${RED}No se encontraron hosts con IP: ${HOST_IP}${NC}"
    read -p "Presione Enter para continuar..."
    return
  fi

  echo ""
  echo -ne "${RED}¿Esta seguro de eliminar TODOS estos hosts? (y/N): ${NC}"
  read CONFIRM

  if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
    # Construir array JSON manualmente
    IDS_ARRAY="["
    FIRST=true
    for ID in $HOST_IDS; do
      if [ "$FIRST" = true ]; then
        IDS_ARRAY="${IDS_ARRAY}\"${ID}\""
        FIRST=false
      else
        IDS_ARRAY="${IDS_ARRAY},\"${ID}\""
      fi
    done
    IDS_ARRAY="${IDS_ARRAY}]"

    RESULT=$(zabbix_api_call "host.delete" "$IDS_ARRAY")
    echo ""
    if echo "$RESULT" | grep -q '"result"'; then
      echo -e "${GREEN}Hosts eliminados exitosamente${NC}"
    else
      echo "$RESULT" | jq '.' 2>/dev/null || echo "$RESULT"
    fi
  else
    echo -e "${YELLOW}Eliminacion cancelada${NC}"
  fi

  echo ""
  read -p "Presione Enter para continuar..."
}

# ==============================================
# MODIFICACIONES
# ==============================================

cambiar_psk() {
  echo ""
  echo -ne "${BLUE}Ingrese el nombre del host: ${NC}"
  read HOSTNAME

  echo ""
  echo -e "${YELLOW}Buscando host: ${HOSTNAME}...${NC}"

  HOST_RESULT=$(zabbix_api_call "host.get" "{
        \"filter\": {\"name\": \"${HOSTNAME}\"},
        \"output\": [\"hostid\", \"name\"],
        \"selectInterfaces\": [\"ip\", \"port\"],
        \"selectTLS\": [\"tls_psk_identity\", \"tls_psk\"]
    }")

  HOST_ID=$(echo "$HOST_RESULT" | jq -r '.result[0].hostid' 2>/dev/null)
  HOST_IP=$(echo "$HOST_RESULT" | jq -r '.result[0].interfaces[0].ip // "N/A"' 2>/dev/null)

  if [ -z "$HOST_ID" ] || [ "$HOST_ID" = "null" ]; then
    echo -e "${RED}Host no encontrado: ${HOSTNAME}${NC}"
    read -p "Presione Enter para continuar..."
    return
  fi

  echo ""
  echo -e "${GREEN}Host encontrado:${NC}"
  echo "  Host ID: $HOST_ID | Nombre: $HOSTNAME | IP: $HOST_IP"
  echo ""
  echo -e "${YELLOW}PSK actual:${NC}"
  echo "$HOST_RESULT" | jq -r '.result[0] | "  Identity: \(.tls_psk_identity // "N/A")\n  Key: \(.tls_psk // "N/A")"' 2>/dev/null
  echo ""

  echo -ne "${BLUE}Ingrese nuevo PSK Identity (dejar vacio para mantener): ${NC}"
  read PSK_IDENTITY

  echo -ne "${BLUE}Ingrese nuevo PSK Key hex 32 bytes (dejar vacio para mantener): ${NC}"
  read PSK_KEY

  if [ -z "$PSK_IDENTITY" ] && [ -z "$PSK_KEY" ]; then
    echo -e "${RED}No se ingresaron nuevos valores${NC}"
    read -p "Presione Enter para continuar..."
    return
  fi

  # Construir JSON como string de una línea
  JSON_PARAMS="{\"hostid\":\"${HOST_ID}\",\"tls_connect\":2,\"tls_accept\":2"
  if [ -n "$PSK_IDENTITY" ]; then
    JSON_PARAMS="${JSON_PARAMS},\"tls_psk_identity\":\"${PSK_IDENTITY}\""
  fi
  if [ -n "$PSK_KEY" ]; then
    JSON_PARAMS="${JSON_PARAMS},\"tls_psk\":\"${PSK_KEY}\""
  fi
  JSON_PARAMS="${JSON_PARAMS}}"

  echo ""
  echo -ne "${YELLOW}¿Actualizar PSK del host? (y/N): ${NC}"
  read CONFIRM

  if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
    RESULT=$(zabbix_api_call "host.update" "$JSON_PARAMS")
    echo ""
    if echo "$RESULT" | grep -q '"result"'; then
      echo -e "${GREEN}PSK actualizado correctamente${NC}"
    else
      echo "$RESULT" | jq '.' 2>/dev/null || echo "$RESULT"
    fi
  else
    echo -e "${YELLOW}Actualizacion cancelada${NC}"
  fi

  echo ""
  read -p "Presione Enter para continuar..."
}

# ==============================================
# LISTADOS Y DETALLES
# ==============================================

listar_hosts() {
  echo ""
  echo -e "${YELLOW}Listando todos los hosts...${NC}"

  RESULT=$(zabbix_api_call "host.get" "{
        \"output\": [\"hostid\", \"name\", \"host\"],
        \"selectInterfaces\": [\"ip\", \"port\"],
        \"limit\": 50
    }")

  echo ""
  echo -e "${GREEN}Hosts encontrados:${NC}"
  echo "$RESULT" | jq -r '.result[] | "Host ID: \(.hostid) | Nombre: \(.name) | IP: \(.interfaces[0].ip // "N/A") | Puerto: \(.interfaces[0].port // "N/A")"' 2>/dev/null || echo "$RESULT"

  echo ""
  read -p "Presione Enter para continuar..."
}

ver_detalles_host() {
  echo ""
  echo -ne "${BLUE}Ingrese el nombre del host: ${NC}"
  read HOSTNAME

  echo ""
  echo -e "${YELLOW}Buscando host: ${HOSTNAME}...${NC}"

  RESULT=$(zabbix_api_call "host.get" "{
        \"filter\": {\"name\": \"${HOSTNAME}\"},
        \"output\": [\"hostid\", \"name\", \"host\", \"status\"],
        \"selectInterfaces\": [\"ip\", \"port\", \"type\"],
        \"selectTLS\": [\"tls_psk_identity\", \"tls_psk\"],
        \"selectParentTemplates\": [\"name\"],
        \"selectGroups\": [\"name\"]
    }")

  echo ""
  echo -e "${GREEN}Detalles del host:${NC}"
  echo "$RESULT" | jq '.' 2>/dev/null || echo "$RESULT"

  echo ""
  read -p "Presione Enter para continuar..."
}

# ==============================================
# MAIN
# ==============================================

# Verificar dependencias
if ! command -v jq &>/dev/null; then
  echo -e "${RED}Error: jq no esta instalado${NC}"
  echo "Instalar con: yum install jq -y  o  apt-get install jq -y"
  exit 1
fi

# Verificar openssl para generar PSK
if ! command -v openssl &>/dev/null; then
  echo -e "${RED}Error: openssl no esta instalado${NC}"
  echo "Instalar con: yum install openssl -y  o  apt-get install openssl -y"
  exit 1
fi

while true; do
  clear_screen
  show_menu
  read OPTION

  case $OPTION in
  1)
    buscar_host_por_nombre
    ;;
  2)
    buscar_host_por_ip
    ;;
  3)
    agregar_host
    ;;
  4)
    eliminar_host_por_nombre
    ;;
  5)
    eliminar_host_por_ip
    ;;
  6)
    cambiar_psk
    ;;
  7)
    listar_hosts
    ;;
  8)
    ver_detalles_host
    ;;
  0)
    echo -e "${GREEN}Saliendo...${NC}"
    exit 0
    ;;
  *)
    echo -e "${RED}Opcion invalida${NC}"
    sleep 1
    ;;
  esac
done
