#!/bin/bash
set -euo pipefail

# ==============================================================================
# 🚀 PICOCLAW INSTALLER MENU (2026)
# Este script facilita la ejecución ordenada de la suite de instalación.
# ==============================================================================

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Directorio base (asumimos que los scripts están al lado de este menú)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

function mostrar_menu() {
    clear
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${GREEN}      🤖 ASISTENTE DE DESPLIEGUE PICOJARVIS (RPi 3B) 🤖     ${NC}"
    echo -e "${CYAN}================================================================${NC}"
    echo -e "El orden recomendado de ejecución es secuencial (Paso 1 al Paso 5)."
    echo ""
    echo -e "${YELLOW}1.${NC} 🛡️  Hardenizar Sistema (SSH, Sysctl, UFW. ${RED}Cuidado: Desactiva contraseñas${NC})"
    echo -e "${YELLOW}2.${NC} 🚫 Configurar Baneo Progresivo (Fail2Ban con Fibonacci y Telegram)"
    echo -e "${YELLOW}3.${NC} 🧠 Instalar Llama.cpp + Qwen 2.5 + Picovoice SDK ${YELLOW}[NUEVO]${NC}"
    echo -e "${YELLOW}4.${NC} 💻 Instalar PicoClaw (Requiere Sudo. Configura IA y Systemd)"
    echo -e "${YELLOW}5.${NC} 👤 Configurar Entorno Secreto (Vault, Nombres, Permisos GPG)"
    echo -e "${YELLOW}6.${NC} 🔄 Cambiar de Modelo de IA (Groq / Llama.cpp / Ollama Red)"
    echo -e "${YELLOW}7.${NC} 🩺 Diagnóstico del Sistema (Comprobar Salud y Servicios)"
    echo -e "${YELLOW}0.${NC} 🧹 Salir del Menú"
    echo -e "${CYAN}================================================================${NC}"
    echo -n -e "Elige una opción ${YELLOW}[0-7]${NC}: "
}

function ejecutar_script() {
    local script="$1"
    local requiere_sudo="$2"

    if [ ! -f "$DIR/$script" ]; then
        echo -e "\n${RED}❌ ERROR: No se encuentra el script $script en $DIR.${NC}"
        read -p "Presiona Enter para continuar..."
        return
    fi
    
    chmod +x "$DIR/$script"

    echo -e "\n${GREEN}🚀 Ejecutando $script...${NC}\n"
    
    if [ "$requiere_sudo" == "yes" ]; then
        if [ "$(id -u)" -ne 0 ]; then
            sudo bash "$DIR/$script"
        else
            bash "$DIR/$script"
        fi
    else
        bash "$DIR/$script"
    fi

    echo -e "\n${CYAN}================================================================${NC}"
    echo -e "${GREEN}✅ Ejecución de $script finalizada.${NC}"
    read -p "Presiona Enter para volver al menú principal..."
}


# Bucle de opciones
while true; do
    mostrar_menu
    read opcion
    case $opcion in
        1)
            # Hardening requiere tocar sshd y kernel
            ejecutar_script "PicoJarvisHarden.sh" "no"
            ;;
        2)
            # Baneo por Fail2ban
            ejecutar_script "PicoJarvisBaneo.sh" "no"
            ;;
        3)
            # Motor IA Local y SDK de voz
            ejecutar_script "PicoJarvisLocalAI.sh" "yes"
            ;;
        4)
            # El instalador comprueba internamente el id -u, usamos sudo
            ejecutar_script "PicoClawRPIInstaller.sh" "yes"
            ;;
        5)
            # La config confidencial asume permisos de usuario (Fortificar bot)
            ejecutar_script "PicoJarvisConfiguration.sh" "no"
            ;;
        6)
            # Cambiador de IA en caliente
            ejecutar_script "PicoJarvisAISwitch.sh" "yes"
            ;;
        7)
            # Herramienta de Diagnóstico del Sistema
            ejecutar_script "PicoJarvisDiagnostic.sh" "yes"
            ;;
        0)
            echo -e "\n${GREEN}👋 ¡Hasta la próxima!${NC}"
            exit 0
            ;;
        *)
            echo -e "\n${RED}⚠️  Opción no válida. Por favor, selecciona un número del 0 al 7.${NC}"
            sleep 2
            ;;
    esac
done
