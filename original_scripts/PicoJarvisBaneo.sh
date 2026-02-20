#!/bin/bash

# =============================================================
# 🛡️ PICOJARVIS: VIGILANTE CON BANEO PROGRESIVO (FIBONACCI)
# =============================================================

GREEN='\033[0;32m'
NC='\033[0m'
PUERTO_SSH=2222

echo -e "${GREEN}🕵️ Configurando vigilancia activa y baneo progresivo...${NC}"

# 1. CREAR EL SCRIPT DE NOTIFICACIÓN PARA FAIL2BAN
echo "📝 Creando script de notificación Telegram para Fail2Ban..."
sudo tee /usr/local/bin/fail2ban-telegram.sh <<'EOF'
#!/bin/bash
# Extraer token del vault
TOKEN=$(sudo /usr/bin/cat "/root/.gpg_pass" | sudo -u picojarvis /usr/bin/gpg --quiet --batch --pinentry-mode loopback --passphrase-fd 0 --decrypt "/home/picojarvis/.password-store/telegram/token_jarvis.gpg" 2>/dev/null)
ID_CHAT="5530049"
IP=$1

MENSAJE="🚫 *PicoJarvis: IP Baneada*%0A%0A*IP:* $IP%0A*Motivo:* Ataque SSH detectado.%0A*Escalado:* Baneo progresivo aplicado."

curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" -d "chat_id=$ID_CHAT" -d "text=$MENSAJE" -d "parse_mode=Markdown" > /dev/null 2>&1
EOF

sudo chmod 755 /usr/local/bin/fail2ban-telegram.sh

# 2. DEFINIR LA ACCIÓN DE TELEGRAM EN FAIL2BAN
echo "⚙️ Configurando acción de baneo en Fail2Ban..."
sudo tee /etc/fail2ban/action.d/telegram.conf <<EOF
[Definition]
actionban = /usr/local/bin/fail2ban-telegram.sh <ip>
actionunban = 
EOF

# 3. CONFIGURAR EL BANEO PROGRESIVO (Lógica Fibonacci)
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

# 4. REINICIAR EL SERVICIO
echo "🔄 Reiniciando Fail2Ban para activar el centinela..."
sudo systemctl restart fail2ban

echo -e "${GREEN}✅ ¡Listo! PicoJarvis ahora banea con progresión Fibonacci y te avisa al móvil.${NC}"