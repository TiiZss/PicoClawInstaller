#!/bin/bash
set -euo pipefail

# =============================================================
# 🩺 DIAGNÓSTICO INTEGRAL DE PICOJARVIS
# =============================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}================================================================${NC}"
echo -e "${CYAN}        🩺 INICIANDO DIAGNÓSTICO DEL SISTEMA PICOJARVIS         ${NC}"
echo -e "${CYAN}================================================================${NC}"

# Variables
APP_USER=${APP_USER:-picojarvis}
ERRORES=0

function check_service() {
    local service=$1
    local name=$2
    if systemctl is-active --quiet "$service"; then
        echo -e "${GREEN}[OK]${NC} Servicio $name ($service) está CORRIENDO."
    else
        echo -e "${RED}[FAIL]${NC} Servicio $name ($service) está DETENIDO o FALLANDO."
        ERRORES=$((ERRORES+1))
    fi
}

function check_oneshot() {
    local service=$1
    local name=$2
    local result=$(systemctl show -p Result --value "$service" 2>/dev/null || echo "unknown")
    if systemctl is-active --quiet "$service" || [ "$result" == "success" ]; then
        echo -e "${GREEN}[OK]${NC} Servicio $name ($service) se ejecutó CORRECTAMENTE."
    else
        echo -e "${RED}[FAIL]${NC} Servicio $name ($service) FALLÓ en su ejecución."
        ERRORES=$((ERRORES+1))
    fi
}

function check_port() {
    local port=$1
    local name=$2
    if ss -tuln | grep -q ":$port "; then
        echo -e "${GREEN}[OK]${NC} Puerto $name ($port) está a la escucha."
    else
        echo -e "${YELLOW}[WARN]${NC} El puerto $name ($port) NO está activo."
    fi
}

echo -e "\n${YELLOW}--- 1. ESTADO DE LOS SERVICIOS CRÍTICOS (SYSTEMD) ---${NC}"
check_service "fail2ban" "Baneo Progresivo"
check_service "ufw" "Cortafuegos UFW"
check_service "ssh" "Servidor SSH"
if [ -f "/etc/systemd/system/cpu-performance.service" ]; then
    check_oneshot "cpu-performance" "Acelerador CPU Performance"
fi
if [ -f "/etc/systemd/system/llamacpp.service" ]; then
    check_service "llamacpp" "Motor IA Local (Llama.cpp)"
else
    echo -e "${YELLOW}[INFO]${NC} Motor IA Local no detectado (Probablemente usas IA remota)."
fi
if [ -f "/etc/systemd/system/picoclaw.service" ]; then
    check_service "picoclaw" "Cerebro del Bot (PicoClaw)"
else
    echo -e "${RED}[FAIL]${NC} El servicio PicoClaw no existe. ¿Has ejecutado el Paso 4?"
    ERRORES=$((ERRORES+1))
fi

echo -e "\n${YELLOW}--- 2. CONECTIVIDAD Y PUERTOS DE RED ---${NC}"
check_port "2222" "SSH Hardenizado"
check_port "11434" "LLM API Local (Ollama/Llama.cpp)"
check_port "18790" "PicoClaw Gateway"

echo -e "\n${YELLOW}--- 3. OPTIMIZACIONES DE MEMORIA Y HARDWARE ---${NC}"
if grep -q "/dev/zram" /proc/swaps; then
    ZRAM_SIZE=$(grep "/dev/zram" /proc/swaps | awk '{print $3}' | head -n 1)
    if [ -n "$ZRAM_SIZE" ]; then
        # Convertimos KB a MB para mejor legibilidad
        ZRAM_MB=$((ZRAM_SIZE / 1024))
        echo -e "${GREEN}[OK]${NC} ZRAM (Compresión RAM) está ACTIVO y estructurando ${ZRAM_MB}MB en el núcleo."
    else
        echo -e "${RED}[FAIL]${NC} ZRAM está montado pero reporta tamaño 0."
        ERRORES=$((ERRORES+1))
    fi
else
    echo -e "${RED}[FAIL]${NC} El bloque /dev/zram0 no se encuentra activo en el kernel (/proc/swaps)."
    ERRORES=$((ERRORES+1))
fi

if grep -q "/run/shm" /proc/mounts; then
    echo -e "${GREEN}[OK]${NC} Memoria compartida (/run/shm) está BLOQUEADA (Segura)."
else
    echo -e "${RED}[FAIL]${NC} Memoria compartida (/run/shm) no está protegida por fstab."
fi

echo -e "\n${YELLOW}--- 4. SALUD DEL BANEO CONTINUO ---${NC}"
if command -v fail2ban-client &>/dev/null; then
    SSH_BANS=$(sudo fail2ban-client status sshd 2>/dev/null | grep "Currently banned" | awk '{print $4}' || echo "0")
    echo -e "${GREEN}[OK]${NC} Antenas de vigilancia activas. Atacantes bloqueados actualmente: $SSH_BANS"
else
    echo -e "${YELLOW}[WARN]${NC} Fail2Ban no instalado o CLI indisponible."
fi

echo -e "\n${CYAN}================================================================${NC}"
if [ $ERRORES -eq 0 ]; then
    echo -e "${GREEN}✅ ¡DIAGNÓSTICO PERFECTO! Tu PicoClaw está fortificado, optimizado y operando al 100%.${NC}"
else
    echo -e "${RED}❌ El diagnóstico encontró $ERRORES problema(s). Revisa los mensajes en rojo y reejecuta los pasos del menú que correspondan.${NC}"
fi
echo -e "${CYAN}================================================================${NC}"
