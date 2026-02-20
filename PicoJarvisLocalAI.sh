#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
# 🧠 PICOCLAW LOCAL AI DEPLOYER - Llama.cpp + Qwen 2.5 + Picovoice
# Optimizado para Raspberry Pi 3B (1GB RAM, ARM64 sin GPU CUDA)
# ==============================================================================

trap 'echo -e "\n❌ ERROR: El script ha fallado en la línea $LINENO. Vuelve a ejecutarlo para reanudar desde el último paso completado." >&2' ERR

APP_USER="jarvis"
INSTALL_DIR="/home/$APP_USER/llamacpp"
MODEL_DIR="/home/$APP_USER/models"
MODEL_NAME="qwen2.5-0.5B-instruct-q4_k_m.gguf"
# URL extraída de un bucket GGUF confiable habitual en HuggingFace (Ej. mradermacher o Qwen oficial)
MODEL_URL="https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf"

STATE_FILE="/tmp/picojarvis_local_ai.state"
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

echo "===================================================="
echo "🧠 CONFIGURACIÓN DE IA LOCAL Y PICOVOICE (RPi 3B)"
echo "===================================================="
echo "Se usará Llama.cpp nativo en lugar de Ollama para ahorrar "
echo "recursos junto a Qwen 2.5 0.5B (Formato Q4_K_M de HuggingFace)."
read -p "🎤 Pega tu 'Access Key' gratuita de Picovoice (o pulsa enter si prefieres obviarlo por ahora): " PICOVOICE_KEY
echo "===================================================="

# 1. Dependencias Base
if ! check_step "dependencias"; then
    echo "📦 Instalando compiladores C/C++ y herramientas Python necesarias..."
    apt-get update
    apt-get install -y build-essential cmake pkg-config git curl wget python3 python3-pip python3-venv portaudio19-dev libasound2-dev
    mark_step "dependencias"
else
    echo "⏭️  Paso 1 (Dependencias) ya completado. Omitiendo..."
fi

# 2. Swap Crítico para Compilación Llama.cpp
if ! check_step "swap"; then
    echo "⚙️  Configurando Swap temporal de 2GB para compilar Llama.cpp..."
    systemctl stop llamacpp 2>/dev/null || true
    fallocate -l 2G /swapfile_llamacpp 2>/dev/null || true
    chmod 600 /swapfile_llamacpp 2>/dev/null || true
    mkswap /swapfile_llamacpp 2>/dev/null || true
    swapon /swapfile_llamacpp 2>/dev/null || true
    mark_step "swap"
else
    echo "⏭️  Paso 2 (Swap) ya completado. Omitiendo..."
fi

# 3. Compilación de Llama.cpp nativamente en ARM64 Libre
if ! check_step "compilacion_llamacpp"; then
    echo "🚀 Descargando y compilando Llama.cpp (Sin CUDA)..."
    rm -rf "$INSTALL_DIR"
    sudo -u "$APP_USER" git clone https://github.com/ggerganov/llama.cpp "$INSTALL_DIR"
    cd "$INSTALL_DIR" || exit 1
    # Compilar activando soporte nativo usando flags que maximicen CPU y Fast Math.
    sudo -u "$APP_USER" make LLAMA_FAST_MATH=1 -j4 || sudo -u "$APP_USER" make LLAMA_FAST_MATH=1 -j1 # Cae a j1 si la RAM revienta
    mark_step "compilacion_llamacpp"
else
    echo "⏭️  Paso 3 (Compilación Llama.cpp) ya completado. Omitiendo..."
    cd "$INSTALL_DIR" || exit 1
fi

# 4. Descarga del Modelo Cuantizado Qwen 0.5B GGUF
if ! check_step "descarga_modelo"; then
    echo "🤖 Descargando modelo Ultra-Ligero Qwen 2.5 0.5B (Q4_K)..."
    sudo -u "$APP_USER" mkdir -p "$MODEL_DIR"
    sudo -u "$APP_USER" wget --continue -O "$MODEL_DIR/$MODEL_NAME" "$MODEL_URL"
    mark_step "descarga_modelo"
else
    echo "⏭️  Paso 4 (Descarga Modelo GGUF) ya completado. Omitiendo..."
fi

# 5. Desmontar Swap
if ! check_step "desmontar_swap"; then
    echo "🧹 Desmontando Swap temporal..."
    swapoff /swapfile_llamacpp 2>/dev/null || true
    rm -f /swapfile_llamacpp 2>/dev/null || true
    mark_step "desmontar_swap"
fi

# 6. Servicio Systemd (Modo Servidor API compatible con OpenAI para PicoClaw)
if ! check_step "systemd_llamacpp"; then
    echo "⚙️  Creando servicio SystemD para el Servidor Inferencia Llama.cpp..."
    cat <<EOF > "/etc/systemd/system/llamacpp.service"
[Unit]
Description=Llama.cpp API Server (Local Qwen 2.5)
After=network.target network-online.target time-sync.target
Wants=network-online.target

[Service]
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$INSTALL_DIR
Environment="HOME=/home/$APP_USER"
# Hilo limitado (threads=3 en RPi3, context=1024, parallel=1) para no quemar la placa
ExecStart=$INSTALL_DIR/llama-server -m $MODEL_DIR/$MODEL_NAME -c 1024 --host 0.0.0.0 --port 11434 -t 3
Restart=always
RestartSec=10

ProtectSystem=full
PrivateTmp=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable llamacpp
    systemctl restart llamacpp
    mark_step "systemd_llamacpp"
else
    echo "⏭️  Paso 6 (Servicio Systemd API) ya completado. Omitiendo..."
fi

# 7. Picovoice (SDK de Audio)
if ! check_step "picovoice"; then
    if [ -n "$PICOVOICE_KEY" ]; then
        echo "🎤 Instalando Picovoice SDK en un entorno virtual..."
        VENV_DIR="/home/$APP_USER/picovoice_env"
        sudo -u "$APP_USER" python3 -m venv "$VENV_DIR"
        sudo -u "$APP_USER" bash -c "source $VENV_DIR/bin/activate && pip install --upgrade pip"
        sudo -u "$APP_USER" bash -c "source $VENV_DIR/bin/activate && pip install pvporcupine pvcheetah pvorca pvaudiodevice"
        
        # Guardar la Access Key para los scripts de PicoClaw en un archivo protegido
        echo "PICOVOICE_ACCESS_KEY='$PICOVOICE_KEY'" > "/home/$APP_USER/.picovoice.env"
        chown "$APP_USER:$APP_USER" "/home/$APP_USER/.picovoice.env"
        chmod 600 "/home/$APP_USER/.picovoice.env"
        
        echo "✅ Picovoice SDK instalado. (Key guardada en /home/$APP_USER/.picovoice.env)"
    else
        echo "⚠️  Picovoice SDK no instalado (No se proveyó la Access Key)."
    fi
    mark_step "picovoice"
else
    echo "⏭️  Paso 7 (Picovoice) ya completado. Omitiendo..."
fi

# 7.5. Configuración automática de Audio (ALSA)
if ! check_step "alsa_config"; then
    echo "🔈 Configurando subsistema ALSA para el micrófono y altavoz..."
    sudo -u "$APP_USER" tee "/home/$APP_USER/.asoundrc" > /dev/null <<EOF
pcm.!default {
  type asym
  playback.pcm "plug:hw:0,0"
  capture.pcm "plug:hw:1,0"
}
ctl.!default {
  type hw
  card 0
}
EOF
    mark_step "alsa_config"
else
    echo "⏭️  Paso 7.5 (ALSA Config) ya completado. Omitiendo..."
fi

# 8. Unir dependencias Systemd (PicoClaw -> Llama.cpp)
if ! check_step "dependencia_systemd"; then
    echo "🔗 Vinculando el bot al motor de Llama.cpp en Systemd..."
    if [ -f "/etc/systemd/system/picoclaw.service" ]; then
        if ! grep -q "Requires=llamacpp.service" /etc/systemd/system/picoclaw.service; then
            # Hacemos que PicoClaw dependa de Llama.cpp y arranque después
            sudo sed -i '/\[Unit\]/a Requires=llamacpp.service\nAfter=llamacpp.service' /etc/systemd/system/picoclaw.service
            sudo systemctl daemon-reload
            sudo systemctl restart picoclaw || true
        fi
    fi
    mark_step "dependencia_systemd"
else
    echo "⏭️  Paso 8 (Dependencia Systemd) ya completado. Omitiendo..."
fi

# 9. Verificación de Server
if ! check_step "verificacion_llamacpp"; then
    echo "🔍 Esperando a que el Llama.cpp server monte el modelo Qwen (puede tardar en la RPi)..."
    sleep 30  # La raspberry tarda bastante en leer el GGUF de la MicroSD a la RAM
    if systemctl is-active --quiet llamacpp; then
        echo "✅ El servicio Llama.cpp (Qwen 2.5 API) está corriendo y escuchando en el puerto 11434 (API nativa de Ollama/OpenAI)."
    else
        echo -e "\n❌ ERROR: Llama.cpp Server falló en el arranque. Consultando los logs de error:" >&2
        journalctl -u llamacpp -n 25 --no-pager >&2
        exit 1
    fi
    mark_step "verificacion_llamacpp"
fi

rm -f "$STATE_FILE"

echo "===================================================="
echo "🧠 ¡INSTALACIÓN DE IA LOCAL COMPLETADA CON ÉXITO!"
echo "Motor: llama.cpp (Nativo ARM64)"
echo "Modelo: Qwen 2.5 0.5B (GGUF 4 bits)"
echo "Endpoint expuesto listo para ser consumido por PicoClaw: http://localhost:11434/v1"
echo "===================================================="
