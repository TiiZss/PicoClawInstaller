#!/bin/bash

# ==============================================================================
# 🛡️ SCRIPT DE CONFIGURACIÓN INTEGRAL: PICOJARVIS SECURITY & VAULT
# ==============================================================================

# Colores para la salida
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}🚀 Iniciando configuración de PicoJarvis...${NC}"

# 1. REBRANDING DEL HOSTNAME
echo "🏷️ Configurando hostname a picojarvis..."
sudo hostnamectl set-hostname picojarvis
echo "picojarvis" | sudo tee /etc/hostname
sudo sed -i 's/jarvis/picojarvis/g' /etc/hosts

# 2. INSTALACIÓN DE DEPENDENCIAS
echo "📦 Instalando herramientas necesarias..."
sudo apt update -y && sudo apt install -y pass gpg curl util-linux pinentry-curses

# 3. CONFIGURACIÓN DEL GPG AGENT (Modo Loopback para scripts)
echo "🔐 Configurando GPG Agent para modo desatendido..."
mkdir -p /home/picojarvis/.gnupg
chmod 700 /home/picojarvis/.gnupg
echo "allow-loopback-pinentry" | sudo tee /home/picojarvis/.gnupg/gpg-agent.conf
echo "pinentry-program /usr/bin/pinentry-curses" | sudo tee -a /home/picojarvis/.gnupg/gpg-agent.conf
sudo chown -R picojarvis:picojarvis /home/picojarvis/.gnupg
sudo gpgconf --kill gpg-agent

# 4. CONFIGURACIÓN DE PERMISOS SUDOERS
echo "⚖️ Ajustando permisos de sudoers..."
sudo tee /etc/sudoers.d/picojarvis_security <<EOF
ALL ALL=(root) NOPASSWD: /usr/bin/cat /root/.gpg_pass
ALL ALL=(picojarvis) NOPASSWD: /usr/bin/gpg
EOF
sudo chmod 440 /etc/sudoers.d/picojarvis_security

# 5. CREACIÓN DEL SCRIPT DE ALERTA SSH
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
    IP_ORIGEN=$(who am i | awk '{print $NF}' | tr -d '()')
fi
[ -z "$IP_ORIGEN" ] && IP_ORIGEN=$(who | grep "$USER" | awk '{print $NF}' | tr -d '()' | head -n 1)

[ "$USER_LOGIN" = "root" ] && CABECERA="💀 *ALERTA: ACCESO COMO ROOT* 💀" || CABECERA="🚨 *Alerta de Seguridad SSH* 🚨"

MENSAJE="$CABECERA%0A%0A*Servidor:* $HOSTNAME%0A*Usuario:* $USER_LOGIN%0A*IP:* ${IP_ORIGEN:-Local}%0A*Fecha:* $FECHA"

curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
     -d "chat_id=$ID_CHAT" \
     -d "text=$MENSAJE" \
     -d "parse_mode=Markdown" > /dev/null 2>&1
EOF

sudo chmod 755 /usr/local/bin/ssh-alert.sh

# 6. ACTIVACIÓN EN EL LOGIN (Evitando duplicados)
echo "🔗 Activando script en el inicio de sesión..."
sudo sed -i '/ssh-alert.sh/d' /etc/bash.bashrc
echo "/usr/local/bin/ssh-alert.sh > /dev/null 2>&1 &" | sudo tee -a /etc/bash.bashrc

echo -e "${GREEN}✅ Configuración terminada. Por favor, reinicia con 'sudo reboot'.${NC}"