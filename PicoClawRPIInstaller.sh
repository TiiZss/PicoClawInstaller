#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
# 🚀 PICOCLAW ULTIMATE INSTALLER - VERSIÓN DEFINITIVA (2026)
# ==============================================================================
# Este script instala PicoClaw desde cero usando el método oficial 'make',
# configura el modelo Qwen 3 (vía Groq) y aplica el parche de personalidad.

trap 'echo -e "\n❌ ERROR: El script ha fallado en la línea $LINENO. Vuelve a ejecutarlo para reanudar desde el último paso completado." >&2' ERR

STATE_FILE="/root/.picoclaw_installer.state"
touch "$STATE_FILE"

function check_step() {
    grep -q "^$1$" "$STATE_FILE" 2>/dev/null
}

function mark_step() {
    echo "$1" >> "$STATE_FILE"
}

if [ "$(id -u)" -ne 0 ]; then 
    echo "❌ ERROR: Este script debe ser ejecutado con privilegios de superusuario (sudo)." >&2
    exit 1
fi

VARS_FILE="/root/.picoclaw_installer_vars.env"
[ -f "$VARS_FILE" ] && source "$VARS_FILE"

echo "===================================================="
echo "🤖 CONFIGURACIÓN DE TU ASISTENTE"
echo "===================================================="
read -e -i "${APP_USER:-picojarvis}" -p "👤 Introduce el nombre de usuario de sistema para el bot: " APP_USER
APP_USER=$(echo "$APP_USER" | tr -d '[:space:]')

# Crear usuario si no existe
if ! id "$APP_USER" &>/dev/null; then
    echo "⚙️  Creando usuario $APP_USER..."
    useradd -m -s /bin/bash "$APP_USER"
fi

INSTALL_DIR="/home/$APP_USER/picoclaw"
REPO_URL="https://github.com/sipeed/picoclaw.git"
CONFIG_DIR="/home/$APP_USER/.picoclaw"
CONFIG_FILE="$CONFIG_DIR/config.json"
GROQ_URL="https://api.groq.com/openai/v1"

echo "===================================================="
echo "🤖 CONFIGURACIÓN DE TU ASISTENTE JARVIS"
echo "===================================================="
echo "Puedes usar Groq (Velocidad Nube) o tu propia IA Local."
echo "💡 NOTA: Si vas a instalar la IA Local integrada en la Raspberry"
echo "   usando el Paso 5 del menú, usa la siguiente URL local:"
echo "   http://127.0.1.1:11434/v1"
echo "----------------------------------------------------"
read -e -i "${GROQ_KEY:-}" -p "🔑 [Opcional] Pega tu API Key de Groq (deja en blanco si usas IA Local): " GROQ_KEY
read -e -i "${OLLAMA_URL:-}" -p "🌐 [Opcional] Introduce la URL de tu IA (Ej. http://127.0.1.1:11434/v1): " OLLAMA_URL
read -e -i "${TELEGRAM_TOKEN:-}" -p "💬 Pega tu Token de Telegram: " TELEGRAM_TOKEN
echo "===================================================="

# Guardar respuestas para reanudaciones en caso de fallo
cat <<EOF > "$VARS_FILE"
APP_USER="$APP_USER"
GROQ_KEY="$GROQ_KEY"
OLLAMA_URL="$OLLAMA_URL"
TELEGRAM_TOKEN="$TELEGRAM_TOKEN"
EOF

# 1. Limpieza total y preparación de RAM (Crítico para compilación RPi 3B)
if ! check_step "limpieza"; then
    systemctl stop picoclaw 2>/dev/null || true
    rm -rf "$INSTALL_DIR"
    rm -rf "$CONFIG_DIR"

    echo "⚙️ Configurando Swap temporal de 2GB (necesario para compilar en 1GB RAM)..."
    fallocate -l 2G /swapfile_build 2>/dev/null || true
    chmod 600 /swapfile_build 2>/dev/null || true
    mkswap /swapfile_build 2>/dev/null || true
    swapon /swapfile_build 2>/dev/null || true
    mark_step "limpieza"
else
    echo "⏭️  Paso 1 (Limpieza) ya completado. Omitiendo..."
fi

# 2. Descarga y Parche de Compilación
if ! check_step "descarga"; then
    # Instalamos dependencias básicas para compilar PicoClaw y gestionar JSON
    if [ -z "$(find /root/.apt_updated -mmin -1440 2>/dev/null)" ]; then
        apt-get update
        touch /root/.apt_updated
    else
        echo "✅ Repositorios CACHEADOS (actualizados en las últimas 24h). Omitiendo apt update..."
    fi
    apt-get install -y make build-essential git wget curl jq

    sudo -u "$APP_USER" git clone "$REPO_URL" "$INSTALL_DIR"
    cd "$INSTALL_DIR" || exit 1

    # Arreglo del error 'pattern workspace: no matching files found'
    echo "📁 Preparando workspace..."
    mkdir -p cmd/picoclaw/workspace
    if [ -d "workspace" ]; then
        cp -r workspace/* cmd/picoclaw/workspace/ 2>/dev/null || true
    fi
    mark_step "descarga"
else
    echo "⏭️  Paso 2 (Descarga) ya completado. Omitiendo..."
    cd "$INSTALL_DIR" || exit 1
fi

# 3. Compilación oficial
# Verificación de oro: Si el binario compilado ya existe, forzamos el salto de paso
if [ -f "$INSTALL_DIR/build/picoclaw-linux-arm64" ]; then
    mark_step "compilacion"
fi

if ! check_step "compilacion"; then
    # Instalamos Go si no está instalado (Lo hacemos aquí por si se reanuda la instalación)
    if [ ! -x /usr/local/go/bin/go ]; then
        echo "🐹 Instalando Go (Golang)..."
        wget -qO go.tar.gz "https://go.dev/dl/go1.22.5.linux-arm64.tar.gz"
        tar -C /usr/local -xzf go.tar.gz
        rm go.tar.gz
    fi

    chown -R "$APP_USER:$APP_USER" "$INSTALL_DIR"
    # SOLUCIÓN: Desviar la memoria temporal '$WORK' y Cache estructurándola en la SD Física (128GB) en vez del límite de RAM de `/tmp`
    sudo -u "$APP_USER" mkdir -p "$INSTALL_DIR/.go_tmp"
    sudo -u "$APP_USER" mkdir -p "$INSTALL_DIR/.go_cache"
    sudo -u "$APP_USER" bash -c "export PATH=\$PATH:/usr/local/go/bin && export GOTMPDIR=\"$INSTALL_DIR/.go_tmp\" && export GOCACHE=\"$INSTALL_DIR/.go_cache\" && make deps && make build"
    # Limpiar basura gigante post-compilación
    sudo rm -rf "$INSTALL_DIR/.go_tmp" 2>/dev/null || true
    mark_step "compilacion"
else
    echo "⏭️  Paso 3 (Compilación) ya completado. Omitiendo..."
fi

# 4. Creación de la Configuración Perfecta (La que finalmente funcionó)
if ! check_step "configuracion"; then
    mkdir -p "$CONFIG_DIR/workspace/memory"
    
    # Crear un archivo MEMORY.md inicial para evitar el error de archivo inexistente
    if [ ! -f "$CONFIG_DIR/workspace/memory/MEMORY.md" ]; then
        echo "# Memoria Histórica de Jarvis" > "$CONFIG_DIR/workspace/memory/MEMORY.md"
        echo "Contexto de interacciones importantes y directrices operativas." >> "$CONFIG_DIR/workspace/memory/MEMORY.md"
        echo "- Idioma: Español." >> "$CONFIG_DIR/workspace/memory/MEMORY.md"
        echo "- Personalidad: Asistente pragmático, directo y experto en Linux." >> "$CONFIG_DIR/workspace/memory/MEMORY.md"
    fi

    # Determinar el proveedor y modelo principal según el input del usuario
    if [ -n "$OLLAMA_URL" ]; then
        MODELO_POR_DEFECTO="ollama/llama3.2" # O el modelo ligero que prefieras en Ollama
        API_KEY_USAR="ollama"
        API_BASE_USAR="$OLLAMA_URL"
    else
        MODELO_POR_DEFECTO="qwen/qwen3-32b"
        API_KEY_USAR="$GROQ_KEY"
        API_BASE_USAR="$GROQ_URL"
    fi

    cat <<EOF > "$CONFIG_FILE"
{
  "agents": {
    "defaults": {
      "workspace": "~/.picoclaw/workspace",
      "model": "$MODELO_POR_DEFECTO",
      "system_prompt": "Responde SIEMPRE en texto plano y directo en español. NUNCA uses formato JSON, XML ni etiquetas como <message>. Actúa como un asistente humano natural.",
      "max_tokens": 8192,
      "temperature": 0.7,
      "max_tool_iterations": 20
    }
  },
  "model_list": [
    {
      "model_name": "$MODELO_POR_DEFECTO",
      "model": "$MODELO_POR_DEFECTO",
      "api_key": "$API_KEY_USAR",
      "api_base": "$API_BASE_USAR"
    }
  ],
  "providers": {
    "ollama": {
      "api_key": "ollama",
      "api_base": "$OLLAMA_URL"
    },
    "openai": {
      "api_key": "$API_KEY_USAR",
      "api_base": "$API_BASE_USAR"
    }
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "token": "$TELEGRAM_TOKEN"
    }
  },
  "gateway": {
    "host": "0.0.0.0",
    "port": 18790
  }
}
EOF
    chown -R "$APP_USER:$APP_USER" "$CONFIG_DIR"
    chmod 600 "$CONFIG_FILE"
    mark_step "configuracion"
else
    echo "⏭️  Paso 4 (Configuración Groq/Ollama) ya completado. Omitiendo..."
fi

# 5. Configuración del Servicio Systemd con la ruta correcta
if ! check_step "systemd"; then
    echo "⚙️ Configurando el auto-arranque (Systemd)..."
    cat <<EOF > "/etc/systemd/system/picoclaw.service"
[Unit]
Description=PicoClaw Jarvis Bot
After=network.target

[Service]
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$INSTALL_DIR
Environment="HOME=/home/$APP_USER"
ExecStart=$INSTALL_DIR/build/picoclaw-linux-arm64 gateway
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    mark_step "systemd"
else
    echo "⏭️  Paso 5 (Servicio Systemd) ya completado. Omitiendo..."
fi

# 6. Arranque final
if ! check_step "arranque"; then
    systemctl daemon-reload
    systemctl enable picoclaw
    systemctl restart picoclaw

    # Limpieza estricta de RAM/Swap después de compilar
    echo "🧹 Desmontando y limpiando Swap temporal..."
    swapoff /swapfile_build 2>/dev/null || true
    rm -f /swapfile_build || true
    mark_step "arranque"
fi

# 7. Verificación de Funcionamiento
if ! check_step "verificacion"; then
    echo "🔍 Esperando a que PicoClaw inicie completamente para verificar..."
    sleep 5
    
    if systemctl is-active --quiet picoclaw; then
        echo "✅ El servicio PicoClaw está ACTIVO y corriendo sin fallos críticos en Systemd."
    else
        echo -e "\n❌ ERROR: El servicio PicoClaw no arrancó correctamente. Mostrando logs de error:" >&2
        journalctl -u picoclaw -n 25 --no-pager >&2
        exit 1
    fi
    mark_step "verificacion"
fi

# Al finalizar con éxito absoluto, limpiamos el estado
sudo rm -f "$STATE_FILE"
sudo rm -f "$VARS_FILE"

echo "===================================================="
echo "✅ ¡INSTALACIÓN COMPLETADA CON ÉXITO Y VERIFICADA!"
echo "Tu bot debería estar respondiendo en Telegram ahora mismo."
echo "▶️ NOTA: Ejecuta 'PicoJarvisHarden.sh' desde el menú para aplicar UUID Optimizations (ZRAM, Log2Ram, Watchdog)."
echo "Puedes ver el log del bot en tiempo real ejecutando: sudo journalctl -u picoclaw -f"
echo "===================================================="