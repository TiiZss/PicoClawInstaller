#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
# 🚀 PICOCLAW ULTIMATE INSTALLER - VERSIÓN DEFINITIVA (2026)
# ==============================================================================
# Este script instala PicoClaw desde cero usando el método oficial 'make',
# configura el modelo Qwen 3 (vía Groq) y aplica el parche de personalidad.

trap 'echo -e "\n❌ ERROR: El script ha fallado en la línea $LINENO. Vuelve a ejecutarlo para reanudar desde el último paso completado." >&2' ERR

STATE_FILE="/tmp/picoclaw_installer.state"
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

APP_USER="jarvis"
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
echo "Puedes usar Groq (Nube) u Ollama (Local/Red)."
read -p "🔑 [Opcional] Pega tu API Key de Groq (deja en blanco si usas Ollama): " GROQ_KEY
read -p "🌐 [Opcional] IP/Puerto de Ollama (ej. http://192.0.2.12:11434/v1). Deja blanco para usar Groq: " OLLAMA_URL
read -p "💬 Pega tu Token de Telegram: " TELEGRAM_TOKEN
echo "===================================================="

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
    # Instalamos log2ram si estuviera disponible, o advertimos al usuario
    apt-get update && apt-get install -y make build-essential git wget
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
if ! check_step "compilacion"; then
    chown -R "$APP_USER:$APP_USER" "$INSTALL_DIR"
    sudo -u "$APP_USER" bash -c "export PATH=$PATH:/usr/local/go/bin && make deps && make build"
    mark_step "compilacion"
else
    echo "⏭️  Paso 3 (Compilación) ya completado. Omitiendo..."
fi

# 4. Creación de la Configuración Perfecta (La que finalmente funcionó)
if ! check_step "configuracion"; then
    mkdir -p "$CONFIG_DIR/workspace"

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

# 5. Configuración del Servicio Systemd con protecciones de seguridad
if ! check_step "systemd"; then
    cat <<EOF > "/etc/systemd/system/picoclaw.service"
[Unit]
Description=PicoClaw Jarvis Bot
After=network.target network-online.target time-sync.target
Wants=network-online.target systemd-time-wait-sync.service

[Service]
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$INSTALL_DIR
Environment="HOME=/home/$APP_USER"
ExecStart=$INSTALL_DIR/build/picoclaw-linux-arm64 gateway
Restart=always
RestartSec=10

# Hardening nativo de systemd
ProtectSystem=full
PrivateTmp=true
NoNewPrivileges=true
ProtectKernelTunables=true
ProtectControlGroups=true

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
rm -f "$STATE_FILE"

echo "===================================================="
echo "✅ ¡INSTALACIÓN COMPLETADA CON ÉXITO Y VERIFICADA!"
echo "Tu bot debería estar respondiendo en Telegram ahora mismo."
echo "▶️ NOTA: Ejecuta 'PicoJarvisHarden.sh' desde el menú para aplicar UUID Optimizations (ZRAM, Log2Ram, Watchdog)."
echo "Puedes ver el log del bot en tiempo real ejecutando: sudo journalctl -u picoclaw -f"
echo "===================================================="