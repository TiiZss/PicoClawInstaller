#!/bin/bash

# ==============================================================================
# 🚀 PICOCLAW ULTIMATE INSTALLER - VERSIÓN DEFINITIVA (2026)
# ==============================================================================
# Este script instala PicoClaw desde cero usando el método oficial 'make',
# configura el modelo Qwen 3 (vía Groq) y aplica el parche de personalidad.

if [ "$(id -u)" -ne 0 ]; then echo "❌ ERROR: Ejecuta con sudo."; exit 1; fi

APP_USER="jarvis"
INSTALL_DIR="/home/$APP_USER/picoclaw"
REPO_URL="https://github.com/sipeed/picoclaw.git"
CONFIG_DIR="/home/$APP_USER/.picoclaw"
CONFIG_FILE="$CONFIG_DIR/config.json"
GROQ_URL="https://api.groq.com/openai/v1"

echo "===================================================="
echo "🤖 CONFIGURACIÓN DE TU ASISTENTE JARVIS"
echo "===================================================="
read -p "🔑 Pega tu API Key de Groq: " GROQ_KEY
read -p "💬 Pega tu Token de Telegram: " TELEGRAM_TOKEN
echo "===================================================="

# 1. Limpieza total y preparación de RAM
systemctl stop picoclaw 2>/dev/null
rm -rf "$INSTALL_DIR"
rm -rf "$CONFIG_DIR"

fallocate -l 2G /swapfile_build 2>/dev/null
chmod 600 /swapfile_build 2>/dev/null
mkswap /swapfile_build 2>/dev/null
swapon /swapfile_build 2>/dev/null

# 2. Descarga y Parche de Compilación
apt-get update && apt-get install -y make build-essential git
sudo -u "$APP_USER" git clone "$REPO_URL" "$INSTALL_DIR"
cd "$INSTALL_DIR" || exit 1

# Arreglo del error 'pattern workspace: no matching files found'
mkdir -p cmd/picoclaw/workspace
cp -r workspace/* cmd/picoclaw/workspace/ 2>/dev/null

# 3. Compilación oficial
chown -R "$APP_USER:$APP_USER" "$INSTALL_DIR"
sudo -u "$APP_USER" bash -c "export PATH=$PATH:/usr/local/go/bin && make deps && make build"

# 4. Creación de la Configuración Perfecta (La que finalmente funcionó)
mkdir -p "$CONFIG_DIR/workspace"
cat <<EOF > "$CONFIG_FILE"
{
  "agents": {
    "defaults": {
      "workspace": "~/.picoclaw/workspace",
      "model": "qwen/qwen3-32b",
      "system_prompt": "Responde SIEMPRE en texto plano y directo en español. NUNCA uses formato JSON, XML ni etiquetas como <message>. Actúa como un asistente humano natural.",
      "max_tokens": 8192,
      "temperature": 0.7,
      "max_tool_iterations": 20
    }
  },
  "providers": {
    "groq": {
      "api_key": "$GROQ_KEY",
      "api_base": ""
    },
    "openai": {
      "api_key": "$GROQ_KEY",
      "api_base": "$GROQ_URL"
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

# 5. Configuración del Servicio Systemd con la ruta correcta
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

# 6. Arranque final
systemctl daemon-reload
systemctl enable picoclaw
systemctl start picoclaw

# Limpieza de RAM
swapoff /swapfile_build 2>/dev/null
rm -f /swapfile_build

echo "===================================================="
echo "✅ ¡INSTALACIÓN COMPLETADA!"
echo "Tu bot debería estar respondiendo en Telegram ahora mismo."
echo "Si quieres ver lo que piensa el bot, usa: sudo journalctl -u picoclaw -f"
echo "===================================================="