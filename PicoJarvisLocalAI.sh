#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
# 🧠 PICOCLAW LOCAL AI DEPLOYER - Llama.cpp + SmolLM2 360M + Picovoice
# Optimizado para Raspberry Pi 3B (1GB RAM, ARM64 sin GPU CUDA)
# ==============================================================================

trap 'echo -e "\n❌ ERROR: El script ha fallado en la línea $LINENO. Vuelve a ejecutarlo para reanudar desde el último paso completado." >&2' ERR

# Reparación radical del hostname para evitar el aviso "unable to resolve host" de sudo que ensucia la consola
CURRENT_HOST=$(hostname | tr -d '[:space:]')
if ! grep -E -q "^127\.0\.1\.1[[:space:]]+$CURRENT_HOST" /etc/hosts; then
    sudo sed -i '/^127\.0\.1\.1/d' /etc/hosts 2>/dev/null || true
    sudo bash -c "echo -e '127.0.1.1\t$CURRENT_HOST' >> /etc/hosts" 2>/dev/null || true
fi

if sudo test -f "/root/.picoclaw_installer_vars.env" 2>/dev/null; then
    eval "$(sudo cat /root/.picoclaw_installer_vars.env 2>/dev/null)" || true
    # Extracción garantizada por grep para evitar dropouts de eval con variables largas (Ej. Picovoice)
    PICO_SAVED=$(sudo grep "^PICOVOICE_KEY=" /root/.picoclaw_installer_vars.env 2>/dev/null | cut -d'"' -f2 || true)
    if [ -n "$PICO_SAVED" ]; then
        PICOVOICE_KEY="$PICO_SAVED"
    fi
fi
VARS_FILE="/root/.picojarvis_config_vars.env"
if sudo test -f "$VARS_FILE" 2>/dev/null; then
    eval "$(sudo cat "$VARS_FILE" 2>/dev/null)" || true
fi
APP_USER=${APP_USER:-picojarvis}

INSTALL_DIR="/home/$APP_USER/llamacpp"
MODEL_DIR="/home/$APP_USER/models"
MODEL_NAME="smollm2-360m-instruct-q4_k_m.gguf"
# URL extraída de un bucket GGUF confiable habitual en HuggingFace (Ej. mradermacher o Qwen oficial)
MODEL_URL="https://huggingface.co/hugging-quants/SmolLM2-360M-Instruct-Q4_K_M-GGUF/resolve/main/smollm2-360m-instruct-q4_k_m.gguf"

STATE_FILE="/root/.picojarvis_local_ai.state"
sudo touch "$STATE_FILE" 2>/dev/null || true

function check_step() {
    sudo grep -q "^$1$" "$STATE_FILE" 2>/dev/null
}

function mark_step() {
    echo "$1" | sudo tee -a "$STATE_FILE" > /dev/null
}

if [ "$(id -u)" -ne 0 ]; then 
    echo "❌ ERROR: Este script debe ser ejecutado con privilegios de superusuario (sudo)." >&2
    exit 1
fi

echo "===================================================="
echo "🧠 CONFIGURACIÓN DE IA LOCAL Y PICOVOICE (RPi 3B)"
echo "===================================================="
echo "Se usará Llama.cpp nativo en lugar de Ollama para ahorrar "
echo "recursos junto a SmolLM2 360M (Formato Q4_K_M de HuggingFace)."
if [ -n "${PICOVOICE_KEY:-}" ]; then
    echo "Clave de Picovoice actual guardada: $PICOVOICE_KEY"
    read -p "🎤 Pega tu nueva 'Access Key' gratuita de Picovoice (o pulsa enter para mantener la actual): " INPUT_KEY
    if [ -n "$INPUT_KEY" ]; then
        PICOVOICE_KEY="$INPUT_KEY"
    fi
else
    read -p "🎤 Pega tu 'Access Key' gratuita de Picovoice (o pulsa enter si prefieres obviarlo por ahora): " PICOVOICE_KEY
fi
echo "===================================================="

# Guardar PICOVOICE_KEY en el vars de instalación global para persistencia entre reintentos
sudo sed -i '/^PICOVOICE_KEY=/d' /root/.picoclaw_installer_vars.env 2>/dev/null || true
if [ -n "$PICOVOICE_KEY" ]; then
    echo "PICOVOICE_KEY=\"$PICOVOICE_KEY\"" | sudo tee -a /root/.picoclaw_installer_vars.env >/dev/null
fi

# 1. Dependencias Base
# Verificamos si libssl-dev ya está para forzar reinstalación si venimos de versiones anteriores del script
if ! dpkg -l | grep -q libssl-dev; then
    sudo sed -i '/^dependencias$/d' "$STATE_FILE" 2>/dev/null || true
fi

if ! check_step "dependencias"; then
    echo "📦 Instalando compiladores C/C++ y herramientas Python necesarias..."
    if [ -z "$(find /root/.apt_updated -mmin -1440 2>/dev/null)" ]; then
        apt-get update
        touch /root/.apt_updated
    else
        echo "✅ Repositorios CACHEADOS (actualizados en las últimas 24h). Omitiendo apt update..."
    fi
    apt-get install -y build-essential cmake pkg-config git curl wget python3 portaudio19-dev libasound2-dev libssl-dev libcurl4-openssl-dev
    
    # Instalamos UV de Astral en lugar del obsoleto y lento pip/venv
    if ! command -v uv &> /dev/null; then
        echo "⚡ Instalando el gestor de paquetes Python ultrarrápido (uv)..."
        # NOTA DE SEGURIDAD: En entornos extremadamente seguros, descargar install.sh, 
        # verificar su hash (SHA256) contra la versión oficial, y luego ejecutarlo.
        # Aquí permitimos curl | sh por simplicidad y porque Astral lo mantiene actualizado.
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="$HOME/.local/bin:$PATH"
    fi
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
# Verificación de oro: Si el binario ya existe, forzamos el salto del paso para ahorrar 2 horas de CPU
if [ -f "$INSTALL_DIR/build/bin/llama-server" ]; then
    mark_step "compilacion_llamacpp"
fi

if ! check_step "compilacion_llamacpp"; then
    echo "🚀 Descargando y compilando Llama.cpp (Sin CUDA)..."
    if ! id "$APP_USER" &>/dev/null; then
        echo "⚙️  Creando usuario $APP_USER..."
        sudo useradd -m -s /bin/bash "$APP_USER" || true
    fi
    sudo mkdir -p "/home/$APP_USER"
    sudo chown "$APP_USER:$APP_USER" "/home/$APP_USER"
    if [ ! -d "$INSTALL_DIR/.git" ]; then
        sudo rm -rf "$INSTALL_DIR"
        sudo -u "$APP_USER" git clone https://github.com/ggerganov/llama.cpp "$INSTALL_DIR"
    else
        echo "♻️  Carpeta de código encontrada. Reanudando compilación previa para no perder el progreso..."
    fi
    cd "$INSTALL_DIR" || exit 1
    # Compilar activando soporte nativo usando CMake. Construimos solo el server para ahorrar memoria
    sudo -u "$APP_USER" cmake -B build -S . -DLLAMA_FAST_MATH=ON
    # Limitamos a -j 2 de forma estricta. picos de -j 4 pueden provocar apagones por Brownout (apagado térmico o falta de energía)
    sudo -u "$APP_USER" cmake --build build --config Release --target llama-server -j 2 || sudo -u "$APP_USER" cmake --build build --config Release --target llama-server -j 1 # Cae a j1 si la RAM revienta
    mark_step "compilacion_llamacpp"
else
    echo "⏭️  Paso 3 (Compilación Llama.cpp) ya completado. Omitiendo..."
    cd "$INSTALL_DIR" || exit 1
fi

# 4. Descarga del Modelo Cuantizado SmolLM2 360M GGUF
if ! check_step "descarga_modelo"; then
    echo "🤖 Descargando modelo Ultra-Ligero SmolLM2 360M (Q4_K_M)..."
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
Description=Llama.cpp API Server (Local SmolLM2 360M)
After=network.target network-online.target time-sync.target
Wants=network-online.target

[Service]
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$INSTALL_DIR
Environment="HOME=/home/$APP_USER"
# Hilo limitado (threads=3 en RPi3, context=2048, parallel=1) para no quemar la placa
ExecStart=$INSTALL_DIR/build/bin/llama-server -m $MODEL_DIR/$MODEL_NAME -c 2048 --host 0.0.0.0 --port 11434 -t 3
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
        # Aseguramos que uv esté en el PATH de superusuario provisionalmente
        export PATH="$HOME/.local/bin:$PATH"

        VENV_DIR="/home/$APP_USER/picovoice_env"
        sudo -u "$APP_USER" bash -c "export PATH=\"/home/$APP_USER/.local/bin:\$PATH\" && curl -LsSf https://astral.sh/uv/install.sh | sh"
        sudo -u "$APP_USER" bash -c "export PATH=\"/home/$APP_USER/.local/bin:\$PATH\" && uv venv \"$VENV_DIR\""
        
        #uv pip install en centésimas de segundo targeting the venv specifically
        sudo -u "$APP_USER" bash -c "export PATH=\"/home/$APP_USER/.local/bin:\$PATH\" && uv pip install --python \"$VENV_DIR\" pvporcupine pvcheetah pvorca pvrecorder pvkoala"
        
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
    echo "🔍 Esperando a que el Llama.cpp server monte el modelo SmolLM2 (puede tardar en la RPi)..."
    sleep 30  # La raspberry tarda bastante en leer el GGUF de la MicroSD a la RAM
    if systemctl is-active --quiet llamacpp; then
        echo "✅ El servicio Llama.cpp (SmolLM2 360M API) está corriendo y escuchando en el puerto 11434 (API nativa de Ollama/OpenAI)."
    else
        echo -e "\n❌ ERROR: Llama.cpp Server falló en el arranque. Consultando los logs de error:" >&2
        journalctl -u llamacpp -n 25 --no-pager >&2
        exit 1
    fi
    mark_step "verificacion_llamacpp"
fi

sudo rm -f "$STATE_FILE"

echo "===================================================="
echo "🧠 ¡INSTALACIÓN DE IA LOCAL COMPLETADA CON ÉXITO!"
echo "Motor: llama.cpp (Nativo ARM64)"
echo "Modelo: SmolLM2 360M (GGUF 4 bits)"
echo "Endpoint expuesto listo para ser consumido por PicoClaw: http://localhost:11434/v1"
echo "===================================================="
