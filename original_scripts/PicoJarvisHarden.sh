#!/bin/bash

# ==============================================================================
# 🛡️ SCRIPT DE FORTIFICACIÓN PARA PICOJARVIS
# ==============================================================================

GREEN='\033[0;32m'
NC='\033[0m'
PUERTO_SSH=2222

echo -e "${GREEN}🛡️ Iniciando fortificación de picojarvis en el puerto $PUERTO_SSH...${NC}"

# 1. ACTUALIZACIÓN INICIAL
echo "🔄 Actualizando repositorios..."
sudo apt update -y

# 2. INSTALACIÓN DE HERRAMIENTAS DE SEGURIDAD
echo "📦 Instalando UFW, Fail2Ban y Unattended-Upgrades..."
sudo apt install -y ufw fail2ban unattended-upgrades

# 3. CONFIGURACIÓN DE SSH (Puerto 2222 y prohibir Root)
echo "🔑 Asegurando SSH..."
sudo sed -i "s/^#Port 22/Port $PUERTO_SSH/" /etc/ssh/sshd_config
sudo sed -i "s/^Port 22/Port $PUERTO_SSH/" /etc/ssh/sshd_config
sudo sed -i "s/^#PermitRootLogin.*/PermitRootLogin no/" /etc/ssh/sshd_config
sudo sed -i "s/^PermitRootLogin.*/PermitRootLogin no/" /etc/ssh/sshd_config

# 4. CONFIGURACIÓN DEL CORTAFUEGOS (UFW)
echo "🧱 Configurando Firewall (UFW)..."
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow $PUERTO_SSH/tcp
echo "y" | sudo ufw enable

# 5. CONFIGURACIÓN DE FAIL2BAN
echo "🚫 Configurando Fail2Ban para el puerto $PUERTO_SSH..."
sudo tee /etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
port = $PUERTO_SSH
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
findtime = 600
bantime = 24h
EOF

# 6. ACTUALIZACIONES AUTOMÁTICAS DE SEGURIDAD
echo "📅 Activando actualizaciones desatendidas..."
sudo dpkg-reconfigure -plow unattended-upgrades

# 7. REINICIO DE SERVICIOS
echo "🔄 Reiniciando servicios..."
sudo systemctl restart ssh
sudo systemctl restart fail2ban

echo -e "${GREEN}✅ Fortificación completada con éxito.${NC}"
echo -e "⚠️  RECUERDA: A partir de ahora debes entrar con: ${GREEN}ssh -p $PUERTO_SSH usuario@picojarvis.local${NC}"