#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# =============================================================
# 🛡️ PICOJARVIS: VIGILANTE CON BANEO PROGRESIVO (FIBONACCI)
# =============================================================

GREEN='\033[0;32m'
NC='\033[0m'
PUERTO_SSH=2222

trap 'echo -e "\n❌ ERROR: El script ha fallado en la línea $LINENO. Vuelve a ejecutarlo para reanudar desde el último paso completado." >&2' ERR

STATE_FILE="/tmp/picojarvis_baneo.state"
touch "$STATE_FILE"

function check_step() {
    grep -q "^$1$" "$STATE_FILE" 2>/dev/null
}

function mark_step() {
    echo "$1" >> "$STATE_FILE"
}

echo -e "${GREEN}🕵️ Configurando vigilancia activa y baneo progresivo...${NC}"

# 1. CREAR EL SCRIPT DE NOTIFICACIÓN PARA FAIL2BAN
if ! check_step "script_notificacion"; then
    echo "📝 Creando script de notificación Telegram para Fail2Ban..."
    sudo tee /usr/local/bin/fail2ban-telegram.sh <<'EOF'
#!/bin/bash
# Extraer token del vault
TOKEN=$(sudo /usr/bin/cat "/root/.gpg_pass" | sudo -u picojarvis /usr/bin/gpg --quiet --batch --pinentry-mode loopback --passphrase-fd 0 --decrypt "/home/picojarvis/.password-store/telegram/token_jarvis.gpg" 2>/dev/null || true)
if [ -z "$TOKEN" ]; then exit 0; fi

ID_CHAT="5530049"
IP="$1"

MENSAJE="🚫 *PicoJarvis: IP Baneada*%0A%0A*IP:* $IP%0A*Motivo:* Ataque SSH detectado.%0A*Escalado:* Baneo progresivo aplicado."

curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" -d "chat_id=$ID_CHAT" -d "text=$MENSAJE" -d "parse_mode=Markdown" > /dev/null 2>&1 || true
EOF

    sudo chmod 755 /usr/local/bin/fail2ban-telegram.sh
    mark_step "script_notificacion"
else
    echo "⏭️  Paso 1 (Notificación Tlgrm) ya completado. Omitiendo..."
fi

# 2. DEFINIR LA ACCIÓN DE TELEGRAM EN FAIL2BAN
if ! check_step "accion_fail2ban"; then
    echo "⚙️ Configurando acción de baneo en Fail2Ban..."
    sudo tee /etc/fail2ban/action.d/telegram.conf <<EOF
[Definition]
actionban = /usr/local/bin/fail2ban-telegram.sh <ip>
actionunban = 
EOF
    mark_step "accion_fail2ban"
else
    echo "⏭️  Paso 2 (Acción Fail2Ban) ya completado. Omitiendo..."
fi

# 3. CONFIGURAR EL BANEO PROGRESIVO (Lógica Fibonacci)
if ! check_step "baneo_progresivo"; then
    echo "📈 Aplicando lógica de baneo incremental..."
    sudo tee /etc/fail2ban/jail.local <<EOF
[DEFAULT]
# Mantener el historial de reincidentes para que el escalado funcione
dbpurgeage = 2d

[sshd]
enabled = true
port = $PUERTO_SSH
filter = sshd
logpath = /var/log/auth.log
maxretry = 3

# LÓGICA DE TIEMPO PROGRESIVO
bantime = 1m
bantime.increment = true
bantime.factor = 1
# La fórmula usa 1.618 para imitar la secuencia de Fibonacci
bantime.formula = ban.time * (1.618034 ** ban.count)
bantime.maxtime = 24h

action = iptables-multiport[name=sshd, port="$PUERTO_SSH", protocol=tcp]
         telegram
EOF
    mark_step "baneo_progresivo"
else
    echo "⏭️  Paso 3 (Baneo Progresivo) ya completado. Omitiendo..."
fi

# 4. REINICIAR EL SERVICIO
if ! check_step "reinicio"; then
    echo "🔄 Reiniciando Fail2Ban para activar el centinela..."
    sudo systemctl restart fail2ban
    mark_step "reinicio"
fi

rm -f "$STATE_FILE"
echo -e "${GREEN}✅ ¡Listo! PicoJarvis ahora banea con progresión Fibonacci y te avisa al móvil.${NC}"