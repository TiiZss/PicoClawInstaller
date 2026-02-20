#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
# 🛡️ SCRIPT DE CONFIGURACIÓN INTEGRAL: PICOJARVIS SECURITY & VAULT
# ==============================================================================

# Colores para la salida
GREEN='\033[0;32m'
NC='\033[0m'

trap 'echo -e "\n❌ ERROR: El script ha fallado en la línea $LINENO. Vuelve a ejecutarlo para reanudar desde el último paso completado." >&2' ERR

STATE_FILE="/tmp/picojarvis_config.state"
touch "$STATE_FILE"

function check_step() {
    grep -q "^$1$" "$STATE_FILE" 2>/dev/null
}

function mark_step() {
    echo "$1" >> "$STATE_FILE"
}

echo -e "${GREEN}🚀 Iniciando configuración de PicoJarvis...${NC}"

# 1. REBRANDING DEL HOSTNAME
if ! check_step "hostname"; then
    echo "🏷️ Configurando hostname a picojarvis..."
    sudo hostnamectl set-hostname picojarvis
    echo "picojarvis" | sudo tee /etc/hostname
    sudo sed -i 's/jarvis/picojarvis/g' /etc/hosts || true
    mark_step "hostname"
else
    echo "⏭️  Paso 1 (Hostname) ya completado. Omitiendo..."
fi

# 2. INSTALACIÓN DE DEPENDENCIAS
if ! check_step "dependencias"; then
    echo "📦 Instalando herramientas necesarias..."
    sudo apt update -y && sudo apt install -y pass gpg curl util-linux pinentry-curses
    mark_step "dependencias"
else
    echo "⏭️  Paso 2 (Dependencias) ya completado. Omitiendo..."
fi

# 3. CONFIGURACIÓN DEL GPG AGENT (Modo Loopback para scripts)
if ! check_step "gpg"; then
    echo "🔐 Configurando GPG Agent y asegurando permisos para vault..."
    mkdir -p /home/picojarvis/.gnupg /home/picojarvis/.password-store
    chmod 700 /home/picojarvis/.gnupg
    chmod 700 /home/picojarvis/.password-store

    echo "allow-loopback-pinentry" | sudo tee /home/picojarvis/.gnupg/gpg-agent.conf
    echo "pinentry-program /usr/bin/pinentry-curses" | sudo tee -a /home/picojarvis/.gnupg/gpg-agent.conf
    sudo chown -R picojarvis:picojarvis /home/picojarvis/.gnupg /home/picojarvis/.password-store

    # Limpieza estricta de gpg-agent para forzar lectura de configuración
    sudo -u picojarvis gpgconf --kill gpg-agent || true
    mark_step "gpg"
else
    echo "⏭️  Paso 3 (GPG Agent) ya completado. Omitiendo..."
fi

# 4. CONFIGURACIÓN DE PERMISOS SUDOERS
if ! check_step "sudoers"; then
    echo "⚖️ Ajustando permisos de sudoers..."
    sudo tee /etc/sudoers.d/picojarvis_security <<EOF
ALL ALL=(root) NOPASSWD: /usr/bin/cat /root/.gpg_pass
ALL ALL=(picojarvis) NOPASSWD: /usr/bin/gpg
EOF
    sudo chmod 440 /etc/sudoers.d/picojarvis_security
    mark_step "sudoers"
else
    echo "⏭️  Paso 4 (Sudoers) ya completado. Omitiendo..."
fi

# 5. CREACIÓN DEL SCRIPT DE ALERTA SSH
if ! check_step "ssh_alert"; then
    echo "🚨 Creando script de alerta /usr/local/bin/ssh-alert.sh..."
    sudo tee /usr/local/bin/ssh-alert.sh <<'EOF'
#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
GPG_PASS_FILE="/root/.gpg_pass"
VAULT_FILE="/home/picojarvis/.password-store/telegram/token_jarvis.gpg"
ID_CHAT="5530049"

# Obtención del Token vía Vault Cifrado
TOKEN=$(sudo /usr/bin/cat "$GPG_PASS_FILE" | sudo -u picojarvis /usr/bin/gpg --quiet --batch --pinentry-mode loopback --passphrase-fd 0 --decrypt "$VAULT_FILE" 2>/dev/null)

if [ -z "$TOKEN" ]; then exit 0; fi

HOSTNAME=$(hostname)
FECHA=$(date '+%d/%m/%Y %H:%M:%S')
USER_LOGIN=$USER
IP_ORIGEN=$(echo $SSH_CLIENT | awk '{print $1}')

# Detección de IP para sudo -i
if [ -z "$IP_ORIGEN" ]; then
    IP_ORIGEN=$(who am i | awk '{print $NF}' | tr -d '()' || true)
fi
[ -z "$IP_ORIGEN" ] && IP_ORIGEN=$(who | grep "$USER" | awk '{print $NF}' | tr -d '()' | head -n 1 || true)
[ -z "$IP_ORIGEN" ] && IP_ORIGEN="Desconocida/Local"

[ "$USER_LOGIN" = "root" ] && CABECERA="💀 *ALERTA: ACCESO COMO ROOT* 💀" || CABECERA="🚨 *Alerta de Seguridad SSH* 🚨"

MENSAJE="$CABECERA%0A%0A*Servidor:* $HOSTNAME%0A*Usuario:* $USER_LOGIN%0A*IP:* ${IP_ORIGEN:-Local}%0A*Fecha:* $FECHA"

curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
     -d "chat_id=$ID_CHAT" \
     -d "text=$MENSAJE" \
     -d "parse_mode=Markdown" > /dev/null 2>&1 || true
EOF

    sudo chmod 755 /usr/local/bin/ssh-alert.sh
    mark_step "ssh_alert"
else
    echo "⏭️  Paso 5 (Script SSH Alert) ya completado. Omitiendo..."
fi

# 6. ACTIVACIÓN EN EL LOGIN (Evitando duplicados)
if ! check_step "login_alert"; then
    echo "🔗 Activando script en el inicio de sesión..."
    sudo sed -i '/ssh-alert.sh/d' /etc/bash.bashrc || true
    echo "/usr/local/bin/ssh-alert.sh > /dev/null 2>&1 &" | sudo tee -a /etc/bash.bashrc
    mark_step "login_alert"
else
    echo "⏭️  Paso 6 (Activación Login Alert) ya completado. Omitiendo..."
fi

rm -f "$STATE_FILE"
echo -e "${GREEN}✅ Configuración terminada. Por favor, reinicia con 'sudo reboot'.${NC}"