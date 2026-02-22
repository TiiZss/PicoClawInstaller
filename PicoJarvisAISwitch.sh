#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
# 🧠 SCRIPT CAMBIO DE IA: INTERCAMBIA ENTRE GROQ Y LOCAL
# ==============================================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# Reparación silenciosa del hostname si sudo está roto por culpa de /etc/hosts desincronizada
CURRENT_HOST=$(hostname | tr -d '[:space:]')
if ! grep -E -q "^127\.0\.1\.1[[:space:]]+$CURRENT_HOST" /etc/hosts; then
    sudo sed -i '/^127\.0\.1\.1/d' /etc/hosts 2>/dev/null || true
    sudo bash -c "echo -e '127.0.1.1\t$CURRENT_HOST' >> /etc/hosts" 2>/dev/null || true
fi

if sudo test -f "/root/.picoclaw_installer_vars.env" 2>/dev/null; then
    eval "$(sudo cat /root/.picoclaw_installer_vars.env 2>/dev/null)"
fi
VARS_FILE="/root/.picojarvis_config_vars.env"
if sudo test -f "$VARS_FILE" 2>/dev/null; then
    eval "$(sudo cat "$VARS_FILE" 2>/dev/null)"
fi

# 1. Recuperar el usuario maestro real leyendo el servicio preinstalado
if [ -f "/etc/systemd/system/picoclaw.service" ]; then
    APP_USER=$(grep "^User=" /etc/systemd/system/picoclaw.service | cut -d'=' -f2)
else
    APP_USER="picojarvis"
fi

CONFIG_FILE="/home/$APP_USER/.picoclaw/config.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}❌ ERROR: No se ha encontrado la configuración principal en $CONFIG_FILE.${NC}"
    echo "Asegúrate de haber completado el Paso 1 al menos una vez para generar el archivo."
    exit 1
fi

echo -e "${CYAN}================================================================${NC}"
echo -e "${GREEN}🔄 CAMBIO RÁPIDO DE MOTOR DE IA${NC}"
echo -e "${CYAN}================================================================${NC}"
echo "Elige qué motor quieres que utilice PicoClaw desde ahora:"
echo ""
echo -e "${YELLOW}1.${NC} ☁️  Groq (Ultra-rápido, requiere internet)"
echo -e "${YELLOW}2.${NC} 🧠 Llama.cpp Local (Raspberry Pi - SmolLM2 360M)"
echo -e "${YELLOW}3.${NC} 🌐 Red Local (Servidor Ollama Externo)"
echo -e "${CYAN}================================================================${NC}"
read -p "Opción [1-3]: " OPCION_IA

case $OPCION_IA in
    1)
        read -e -i "${GROQ_KEY:-}" -p "🔑 Pega tu API Key de Groq: " NUEVO_GROQ
        PICO_MODEL="qwen-2.5-32b-it" # O el modelo estándar de Groq preferido
        PICO_PROVIDER="groq"
        PICO_URL="https://api.groq.com/openai/v1"
        PICO_KEY="$NUEVO_GROQ"
        DISABLE_TOOLS="false"
        
        # Detener IA Local para liberar RAM si estuviese corriendo
        sudo systemctl stop llamacpp 2>/dev/null || true
        
        # Actualizamos la memoria
        sudo sed -i '/^GROQ_KEY=/d' /root/.picoclaw_installer_vars.env 2>/dev/null || true
        echo "GROQ_KEY=\"$NUEVO_GROQ\"" | sudo tee -a /root/.picoclaw_installer_vars.env >/dev/null
        ;;
    2)
        read -e -i "${OLLAMA_URL:-http://127.0.1.1:11434/v1}" -p "🌐 URL de la API Local (Enter para $APP_USER): " NUEVO_URL
        PICO_MODEL="smollm2"
        PICO_PROVIDER="openai" # Llama.cpp usa el formato compatible con openai
        PICO_URL="$NUEVO_URL"
        PICO_KEY="local-key-no-necesaria"
        DISABLE_TOOLS="true"
        
        # Arrancar IA Local si estaba detenida
        sudo systemctl start llamacpp 2>/dev/null || true
        
        # Actualizamos la memoria
        sudo sed -i '/^OLLAMA_URL=/d' /root/.picoclaw_installer_vars.env 2>/dev/null || true
        echo "OLLAMA_URL=\"$NUEVO_URL\"" | sudo tee -a /root/.picoclaw_installer_vars.env >/dev/null
        ;;
    3)
        read -e -i "${OLLAMA_NETWORK_URL:-http://IP_DEL_SERVIDOR:11434/v1}" -p "🌐 URL de tu Servidor Ollama: " NUEVO_URL_RED
        read -e -i "${OLLAMA_NETWORK_MODEL:-ollama/qwen2.5-coder:32b}" -p "🤖 Modelo en tu servidor (ej. ollama/qwen2.5-coder:32b): " NUEVO_MODELO_RED
        PICO_MODEL="$NUEVO_MODELO_RED"
        PICO_PROVIDER="ollama" 
        PICO_URL="$NUEVO_URL_RED"
        PICO_KEY="ollama"
        DISABLE_TOOLS="false"
        
        # Actualizamos la memoria
        sudo sed -i '/^OLLAMA_NETWORK_URL=/d' /root/.picoclaw_installer_vars.env 2>/dev/null || true
        sudo sed -i '/^OLLAMA_NETWORK_MODEL=/d' /root/.picoclaw_installer_vars.env 2>/dev/null || true
        echo "OLLAMA_NETWORK_URL=\"$NUEVO_URL_RED\"" | sudo tee -a /root/.picoclaw_installer_vars.env >/dev/null
        echo "OLLAMA_NETWORK_MODEL=\"$NUEVO_MODELO_RED\"" | sudo tee -a /root/.picoclaw_installer_vars.env >/dev/null
        ;;
    *)
        echo -e "${RED}Opción inválida. Saliendo sin hacer cambios.${NC}"
        exit 1
        ;;
esac

echo -e "\n⏳ Inyectando nueva configuración en el JSON del bot..."

# Inyectar configuración temporal en un directorio seguro y no en /tmp/
sudo -u "$APP_USER" bash -c "touch \"$CONFIG_FILE.tmp\" && chmod 600 \"$CONFIG_FILE.tmp\""
sudo -u "$APP_USER" bash -c "jq '.agents.defaults.model = \"$PICO_MODEL\" | .agents.defaults.disable_tools = $DISABLE_TOOLS | .providers.$PICO_PROVIDER.api_base = \"$PICO_URL\" | .providers.$PICO_PROVIDER.api_key = \"$PICO_KEY\" | .providers.default = \"$PICO_PROVIDER\" | .model_list[0].model_name = \"$PICO_MODEL\" | .model_list[0].model = \"$PICO_MODEL\" | .model_list[0].api_key = \"$PICO_PROVIDER\" | .model_list[0].api_base = \"$PICO_URL\"' \"$CONFIG_FILE\" > \"$CONFIG_FILE.tmp\""

if [ $? -eq 0 ]; then
    sudo mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    sudo chown "$APP_USER:$APP_USER" "$CONFIG_FILE"
    sudo chmod 600 "$CONFIG_FILE"
    echo -e "${GREEN}✅ Configuración inyectada con éxito.${NC}"
    
    echo "🔄 Reiniciando el servicio de PicoClaw para aplicar los cambios..."
    sudo systemctl restart picoclaw 2>/dev/null || true
    echo -e "${GREEN}¡Todo listo! PicoClaw ahora está usando el nuevo cerebro.${NC}"
else
    echo -e "${RED}❌ Ocurrió un error al intentar parchear config.json con jq.${NC}"
    exit 1
fi
