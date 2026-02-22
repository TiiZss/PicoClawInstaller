#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
# 🛡️ SCRIPT DE CONFIGURACIÓN INTEGRAL: PICOJARVIS SECURITY & VAULT
# ==============================================================================

# Colores para la salida
# Colores para la salida
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

trap 'echo -e "\n❌ ERROR: El script ha fallado en la línea $LINENO. Vuelve a ejecutarlo para reanudar desde el último paso completado." >&2' ERR

# Reparación radical del hostname para evitar el aviso "unable to resolve host" de sudo que ensucia la consola
CURRENT_HOST=$(hostname | tr -d '[:space:]')
if ! grep -E -q "^127\.0\.1\.1[[:space:]]+$CURRENT_HOST" /etc/hosts; then
    sudo sed -i '/^127\.0\.1\.1/d' /etc/hosts 2>/dev/null || true
    sudo bash -c "echo -e '127.0.1.1\t$CURRENT_HOST' >> /etc/hosts" 2>/dev/null || true
fi

STATE_FILE="/root/.picojarvis_config.state"
sudo touch "$STATE_FILE" 2>/dev/null || true

function check_step() {
    sudo grep -q "^$1$" "$STATE_FILE" 2>/dev/null
}

function mark_step() {
    echo "$1" | sudo tee -a "$STATE_FILE" > /dev/null
}

echo -e "${GREEN}🚀 Iniciando configuración de PicoJarvis...${NC}"

# SEGURIDAD: Prevenir el error "sudo: unable to resolve host {tu_host}" si el paso 1 falló anteriormente
if sudo test -f "/root/.picoclaw_installer_vars.env" 2>/dev/null; then
    eval "$(sudo cat /root/.picoclaw_installer_vars.env 2>/dev/null)"
fi
VARS_FILE="/root/.picojarvis_config_vars.env"
if sudo test -f "$VARS_FILE" 2>/dev/null; then
    eval "$(sudo cat "$VARS_FILE" 2>/dev/null)"
fi

read -e -i "${APP_USER:-picojarvis}" -p "👤 Introduce el nombre de usuario de sistema para el bot (el mismo que en el Paso 1): " APP_USER
APP_USER=$(echo "$APP_USER" | tr -d '[:space:]')

# Si corren este script sin haber hecho el Paso 1, el usuario no existe y 'chown' fallará. Lo creamos por si acaso.
if ! id "$APP_USER" &>/dev/null; then
    echo "⚠️  El usuario $APP_USER no existe en el sistema. Creándolo..."
    sudo useradd -m -s /bin/bash "$APP_USER"
fi

read -e -i "${HOSTNAME_USAR:-$APP_USER}" -p "🏷️ Introduce el nombre de máquina (hostname) deseado: " HOSTNAME_USAR
HOSTNAME_USAR=$(echo "$HOSTNAME_USAR" | tr -d '[:space:]')

if ! grep -q "$HOSTNAME_USAR" /etc/hosts; then
    sudo sed -i '/^127\.0\.1\.1/d' /etc/hosts 2>/dev/null || true
    printf "127.0.1.1\t%s\n" "$HOSTNAME_USAR" | sudo tee -a /etc/hosts >/dev/null 2>&1
fi

# 0. CONFIGURACIÓN DE IP ESTÁTICA
if ! check_step "ip_estatica"; then
    echo -e "\n${GREEN}🌐 Configuración de Red${NC}"
    read -e -i "${CONFIG_IP:-N}" -p "¿Deseas configurar una IP estática para la Raspberry Pi? (s/N): " CONFIG_IP
    if [[ "$CONFIG_IP" =~ ^[SsYy]$ ]]; then
        while [[ -z "${IP_FIJA:-}" ]] || ! [[ "$IP_FIJA" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; do
            read -e -i "${IP_FIJA:-}" -p "Introduce la IP estática (ej. 192.0.2.11): " IP_FIJA
            if ! [[ "$IP_FIJA" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                echo -e "${RED}⚠️  Formato de IP inválido. Usa formato X.X.X.X${NC}"
                IP_FIJA=""
            fi
        done

        while [[ -z "${MASCARA:-}" ]] || ! [[ "$MASCARA" =~ ^[0-9]+$ ]] || [ "$MASCARA" -lt 1 ] || [ "$MASCARA" -gt 32 ]; do
            read -e -i "${MASCARA:-24}" -p "Introduce la máscara de red en bits (ej. 24): " MASCARA
            if ! [[ "$MASCARA" =~ ^[0-9]+$ ]] || [ "$MASCARA" -lt 1 ] || [ "$MASCARA" -gt 32 ]; then
                echo -e "${RED}⚠️  La máscara debe ser un número entre 1 y 32.${NC}"
                MASCARA=""
            fi
        done

        # Intentamos obtener la puerta de enlace actual (gateway)
        DEFAULT_GW=$(ip route | grep default | awk '{print $3}' | head -n 1)

        while [[ -z "${GATEWAY:-}" ]]; do
            read -e -i "${GATEWAY:-$DEFAULT_GW}" -p "Introduce la puerta de enlace / router (ej. 192.0.2.10): " GATEWAY
        done
        
        while [[ -z "${DNS_SERVERS:-}" ]]; do
            read -e -i "${DNS_SERVERS:-8.8.8.8 8.8.4.4}" -p "Introduce los DNS separados por espacio (ej. 8.8.8.8 8.8.4.4): " DNS_SERVERS
        done
        
        # Guardar respuestas para futuras re-ejecuciones
        sudo tee "$VARS_FILE" >/dev/null 2>&1 <<EOF
APP_USER="$APP_USER"
HOSTNAME_USAR="$HOSTNAME_USAR"
CONFIG_IP="$CONFIG_IP"
IP_FIJA="$IP_FIJA"
MASCARA="$MASCARA"
GATEWAY="$GATEWAY"
DNS_SERVERS="$DNS_SERVERS"
EOF

        INTERFACE=$(ip route | awk '/default/ {print $5}' | head -n 1)
        [ -z "$INTERFACE" ] && INTERFACE="eth0"
        
        echo "🔧 Aplicando IP estática $IP_FIJA/$MASCARA en la interfaz $INTERFACE..."
        
        if command -v nmcli &> /dev/null; then
            echo "Detectado NetworkManager..."
            CON_NAME=$(nmcli -t -f NAME,DEVICE con show --active | grep -m 1 ":$INTERFACE$" | cut -d: -f1)
            if [ -n "$CON_NAME" ]; then
                sudo nmcli con mod "$CON_NAME" ipv4.addresses "$IP_FIJA/$MASCARA" ipv4.gateway "$GATEWAY" ipv4.dns "$DNS_SERVERS" ipv4.method manual 2>/dev/null || true
                echo -e "\n${YELLOW}⚠️  ATENCIÓN: Al aplicar la nueva IP estática ($IP_FIJA), tu conexión SSH actual SE CORTARÁ.${NC}"
                echo -e "${YELLOW}Deberás volver a conectarte usando la nueva IP: ssh $USER@$IP_FIJA${NC}"
                read -p "Presiona Enter para aplicar los cambios y desconectar..."
                
                # Ejecutar en deamon para no colgar el script si SSH muere inmediatamente
                nohup sudo sh -c "nmcli con up '$CON_NAME'" > /dev/null 2>&1 &
                
                echo -e "${GREEN}✅ IP Estática configurada. Desconectando...${NC}"
                mark_step "ip_estatica"
                exit 0
            else
                echo "⚠️ No se encontró conexión activa de NetworkManager. Prueba con dhcpcd."
            fi
            echo "No se detectó NetworkManager. Probando con dhcpcd..."
            sudo sed -i "/^interface $INTERFACE/d" /etc/dhcpcd.conf 2>/dev/null || true
            sudo tee -a /etc/dhcpcd.conf >/dev/null 2>&1 <<EOF

interface $INTERFACE
static ip_address=$IP_FIJA/$MASCARA
static routers=$GATEWAY
static domain_name_servers=$DNS_SERVERS
EOF
            echo -e "\n${YELLOW}⚠️  ATENCIÓN: Al aplicar la nueva IP estática ($IP_FIJA), tu conexión SSH actual SE CORTARÁ.${NC}"
            echo -e "${YELLOW}Deberás volver a conectarte usando la nueva IP: ssh $USER@$IP_FIJA${NC}"
            read -p "Presiona Enter para aplicar los cambios y desconectar..."
            
            # Reiniciamos asícronamente para que el comando llegue a ejecutarse aunque se pierda el túnel
            nohup sudo systemctl restart dhcpcd > /dev/null 2>&1 &
            
            echo -e "${GREEN}✅ IP Estática configurada. Desconectando...${NC}"
            mark_step "ip_estatica"
            exit 0
        else
            echo "⚠️ No se detectó NetworkManager ni dhcpcd. La configuración no se aplicó."
        fi
        # Si llegamos aquí sin salir, es que falló
    else
        echo "➡️ Manteniendo IP dinámica."
    fi
    mark_step "ip_estatica"
else
    echo "⏭️  Paso 0 (IP Estática) ya completado. Omitiendo..."
fi

# 1. REBRANDING DEL HOSTNAME
if ! check_step "hostname"; then
    echo "🏷️ Configurando hostname a $HOSTNAME_USAR..."
    CURRENT_HOSTNAME=$(hostname)
    sudo hostnamectl set-hostname "$HOSTNAME_USAR"
    echo "$HOSTNAME_USAR" | sudo tee /etc/hostname
    sudo sed -i "s/$CURRENT_HOSTNAME/$HOSTNAME_USAR/g" /etc/hosts || true
    sudo sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t$HOSTNAME_USAR/g" /etc/hosts || true
    mark_step "hostname"
else
    echo "⏭️  Paso 1 (Hostname) ya completado. Omitiendo..."
fi

# 2. INSTALACIÓN DE DEPENDENCIAS
if ! check_step "dependencias"; then
    echo "📦 Instalando herramientas necesarias..."
    if [ -z "$(find /root/.apt_updated -mmin -1440 2>/dev/null)" ]; then
        sudo apt update -y
        sudo touch /root/.apt_updated
    else
        echo "✅ Repositorios CACHEADOS (actualizados en las últimas 24h). Omitiendo apt update..."
    fi
    sudo apt install -y pass gpg curl util-linux pinentry-curses
    mark_step "dependencias"
else
    echo "⏭️  Paso 2 (Dependencias) ya completado. Omitiendo..."
fi

# 3. CONFIGURACIÓN DEL GPG AGENT (Modo Loopback para scripts)
if ! check_step "gpg"; then
    echo "🔐 Configurando GPG Agent y asegurando permisos para vault..."
    sudo mkdir -p /home/$APP_USER/.gnupg /home/$APP_USER/.password-store
    sudo chmod 700 /home/$APP_USER/.gnupg
    sudo chmod 700 /home/$APP_USER/.password-store

    echo "allow-loopback-pinentry" | sudo tee /home/$APP_USER/.gnupg/gpg-agent.conf
    echo "pinentry-program /usr/bin/pinentry-curses" | sudo tee -a /home/$APP_USER/.gnupg/gpg-agent.conf
    sudo chown -R $APP_USER:$APP_USER /home/$APP_USER/.gnupg /home/$APP_USER/.password-store

    # Limpieza estricta de gpg-agent para forzar lectura de configuración
    sudo -u $APP_USER gpgconf --kill gpg-agent || true
    mark_step "gpg"
else
    echo "⏭️  Paso 3 (GPG Agent) ya completado. Omitiendo..."
fi

# 4. CONFIGURACIÓN DE PERMISOS SUDOERS
if ! check_step "sudoers"; then
    echo "⚖️ Ajustando permisos de sudoers..."
    sudo tee /etc/sudoers.d/picojarvis_security <<EOF
root ALL=(root) NOPASSWD: /usr/bin/cat /root/.gpg_pass
root ALL=($APP_USER) NOPASSWD: /usr/bin/gpg
$APP_USER ALL=(root) NOPASSWD: /usr/bin/cat /root/.gpg_pass
$APP_USER ALL=($APP_USER) NOPASSWD: /usr/bin/gpg
EOF
    sudo chmod 440 /etc/sudoers.d/picojarvis_security
    mark_step "sudoers"
else
    echo "⏭️  Paso 4 (Sudoers) ya completado. Omitiendo..."
fi

# 5. CREACIÓN DEL SCRIPT DE ALERTA SSH
if ! check_step "ssh_alert"; then
    echo -e "\n${GREEN}🚨 Configuración de Alertas SSH${NC}"
    while [[ -z "${TELEGRAM_CHAT_ID:-}" ]] || ! [[ "$TELEGRAM_CHAT_ID" =~ ^-?[0-9]+$ ]]; do
        read -e -i "${TELEGRAM_CHAT_ID:-}" -p "💬 Introduce tu CHAT_ID de Telegram para recibir alertas de login: " TELEGRAM_CHAT_ID
        if ! [[ "$TELEGRAM_CHAT_ID" =~ ^-?[0-9]+$ ]]; then
            echo -e "${RED}⚠️  El CHAT_ID debe ser un número (puede incluir un signo menos).${NC}"
            TELEGRAM_CHAT_ID=""
        fi
    done
    
    # Guardar para futuras ejecuciones
    sudo sed -i '/^TELEGRAM_CHAT_ID=/d' /root/.picoclaw_installer_vars.env 2>/dev/null || true
    echo "TELEGRAM_CHAT_ID=\"$TELEGRAM_CHAT_ID\"" | sudo tee -a /root/.picoclaw_installer_vars.env >/dev/null

    echo "🚨 Creando script de alerta /usr/local/bin/ssh-alert.sh..."
    sudo tee /usr/local/bin/ssh-alert.sh <<EOF
#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
APP_USER="picojarvis"
GPG_PASS_FILE="/root/.gpg_pass"
VAULT_FILE="/home/\$APP_USER/.password-store/telegram/token_jarvis.gpg"
ID_CHAT="$TELEGRAM_CHAT_ID"

# Obtención del Token vía Vault Cifrado
TOKEN=\$(sudo /usr/bin/cat "\$GPG_PASS_FILE" | sudo -u \$APP_USER /usr/bin/gpg --quiet --batch --pinentry-mode loopback --passphrase-fd 0 --decrypt "\$VAULT_FILE" 2>/dev/null)
EOF

    sudo tee -a /usr/local/bin/ssh-alert.sh <<'EOF'
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

    sudo chmod 700 /usr/local/bin/ssh-alert.sh
    echo "ALL ALL=(root) NOPASSWD: /usr/local/bin/ssh-alert.sh" | sudo tee /etc/sudoers.d/ssh_alert > /dev/null
    sudo chmod 440 /etc/sudoers.d/ssh_alert
    mark_step "ssh_alert"
else
    echo "⏭️  Paso 5 (Script SSH Alert) ya completado. Omitiendo..."
fi

# 6. ACTIVACIÓN EN EL LOGIN (Evitando duplicados)
if ! check_step "login_alert"; then
    echo "🔗 Activando script en el inicio de sesión..."
    sudo sed -i '/ssh-alert.sh/d' /etc/bash.bashrc || true
    echo "sudo /usr/local/bin/ssh-alert.sh > /dev/null 2>&1 &" | sudo tee -a /etc/bash.bashrc
    mark_step "login_alert"
else
    echo "⏭️  Paso 6 (Activación Login Alert) ya completado. Omitiendo..."
fi

sudo rm -f "$STATE_FILE"
sudo rm -f "$VARS_FILE"
echo -e "${GREEN}✅ Configuración terminada. Por favor, reinicia con 'sudo reboot'.${NC}"