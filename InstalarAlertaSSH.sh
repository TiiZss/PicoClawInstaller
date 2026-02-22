#!/bin/bash
set -euo pipefail

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}🚀 Instalador Autónomo: Alerta SSH por Telegram${NC}"
echo -e "Este script configurará una alerta para avisarte por Telegram cada vez que alguien inicie sesión por SSH.\n"

if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}❌ ERROR: Este script debe ejecutarse con sudo o como root.${NC}"
    exit 1
fi

read -p "💬 Introduce el Token de tu Bot de Telegram: " TOKEN
read -p "💬 Introduce tu CHAT_ID de Telegram: " CHAT_ID

if [ -z "$TOKEN" ] || [ -z "$CHAT_ID" ]; then
    echo -e "${RED}❌ ERROR: El Token y el CHAT_ID son obligatorios.${NC}"
    exit 1
fi

SCRIPT_PATH="/usr/local/bin/ssh-alert.sh"

echo -e "\n📝 Creando script de alerta en $SCRIPT_PATH..."

touch "$SCRIPT_PATH"
chmod 700 "$SCRIPT_PATH"

cat <<EOF > "$SCRIPT_PATH"
#!/bin/bash
TOKEN="$TOKEN"
ID_CHAT="$CHAT_ID"

HOSTNAME=\$(hostname)
FECHA=\$(date '+%d/%m/%Y %H:%M:%S')
USER_LOGIN=\$USER
IP_ORIGEN=\$(echo \$SSH_CLIENT | awk '{print \$1}')

# Detección de IP para sudo -i
if [ -z "\$IP_ORIGEN" ]; then
    IP_ORIGEN=\$(who am i | awk '{print \$NF}' | tr -d '()' || true)
fi
[ -z "\$IP_ORIGEN" ] && IP_ORIGEN=\$(who | grep "\$USER" | awk '{print \$NF}' | tr -d '()' | head -n 1 || true)
[ -z "\$IP_ORIGEN" ] && IP_ORIGEN="Desconocida/Local"

[ "\$USER_LOGIN" = "root" ] && CABECERA="💀 *ALERTA: ACCESO COMO ROOT* 💀" || CABECERA="🚨 *Alerta de Seguridad SSH* 🚨"

MENSAJE="\$CABECERA%0A%0A*Servidor:* \$HOSTNAME%0A*Usuario:* \$USER_LOGIN%0A*IP:* \${IP_ORIGEN:-Local}%0A*Fecha:* \$FECHA"

curl -s -X POST "https://api.telegram.org/bot\$TOKEN/sendMessage" \\
     -d "chat_id=\$ID_CHAT" \\
     -d "text=\$MENSAJE" \\
     -d "parse_mode=Markdown" > /dev/null 2>&1 || true
EOF

echo "ALL ALL=(root) NOPASSWD: $SCRIPT_PATH" > /etc/sudoers.d/ssh_alert
chmod 440 /etc/sudoers.d/ssh_alert

echo "🔗 Activando script en el inicio de sesión global..."
sed -i '/ssh-alert.sh/d' /etc/bash.bashrc || true
echo "sudo $SCRIPT_PATH > /dev/null 2>&1 &" >> /etc/bash.bashrc

echo -e "\n${GREEN}✅ Configuración completada con éxito. Recibirás un mensaje en Telegram en el próximo inicio de sesión SSH.${NC}"
