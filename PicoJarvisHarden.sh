#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
# 🛡️ SCRIPT DE FORTIFICACIÓN PARA PICOJARVIS
# ==============================================================================

GREEN='\033[0;32m'
NC='\033[0m'
PUERTO_SSH=2222

trap 'echo -e "\n❌ ERROR: El script ha fallado en la línea $LINENO. Vuelve a ejecutarlo para reanudar desde el último paso completado." >&2' ERR

# Reparación radical del hostname para evitar el aviso "unable to resolve host" de sudo que ensucia la consola
CURRENT_HOST=$(hostname | tr -d '[:space:]')
if ! grep -E -q "^127\.0\.1\.1[[:space:]]+$CURRENT_HOST" /etc/hosts; then
    sudo sed -i '/^127\.0\.1\.1/d' /etc/hosts 2>/dev/null || true
    sudo bash -c "echo -e '127.0.1.1\t$CURRENT_HOST' >> /etc/hosts" 2>/dev/null || true
fi

STATE_FILE="/root/.picojarvis_harden.state"
sudo touch "$STATE_FILE" 2>/dev/null || true

function check_step() {
    sudo grep -q "^$1$" "$STATE_FILE" 2>/dev/null
}

function mark_step() {
    echo "$1" | sudo tee -a "$STATE_FILE" > /dev/null
}

if sudo test -f "/root/.picoclaw_installer_vars.env" 2>/dev/null; then
    eval "$(sudo cat /root/.picoclaw_installer_vars.env 2>/dev/null)"
fi
VARS_FILE="/root/.picojarvis_config_vars.env"
if sudo test -f "$VARS_FILE" 2>/dev/null; then
    eval "$(sudo cat "$VARS_FILE" 2>/dev/null)"
fi

# Opciones por defecto si se lanza este script suelto
HOSTNAME_USAR=${HOSTNAME_USAR:-picojarvis}

echo -e "${GREEN}🛡️ Iniciando fortificación de $HOSTNAME_USAR en el puerto $PUERTO_SSH...${NC}"

# 1. ACTUALIZACIÓN INICIAL
if ! check_step "actualizacion"; then
    echo "🔄 Actualizando repositorios..."
    if [ -z "$(find /root/.apt_updated -mmin -1440 2>/dev/null)" ]; then
        sudo apt update -y
        sudo touch /root/.apt_updated
    else
        echo "✅ Repositorios CACHEADOS (actualizados en las últimas 24h). Omitiendo apt update..."
    fi
    mark_step "actualizacion"
else
    echo "⏭️  Paso 1 (Actualización inicial) ya completado. Omitiendo..."
fi

# 2. INSTALACIÓN DE HERRAMIENTAS DE SEGURIDAD
if ! check_step "herramientas"; then
    echo "📦 Instalando UFW, Fail2Ban y Unattended-Upgrades..."
    sudo apt install -y ufw fail2ban unattended-upgrades
    mark_step "herramientas"
else
    echo "⏭️  Paso 2 (Herramientas de seguridad) ya completado. Omitiendo..."
fi

# 2.1. ZRAM, CPU FREQ, LOG2RAM (OPTIMIZACIONES RPI 3B)
if ! check_step "optimizaciones"; then
    echo "⚡ Instalando optimizaciones RPi 3B (Zram, CPUFreq, Log2Ram, Watchdog)..."
    
    # Instalar clave y repositorio para Log2Ram
    echo "deb [signed-by=/usr/share/keyrings/azlux-archive-keyring.gpg] http://packages.azlux.fr/debian/ bookworm main" | sudo tee /etc/apt/sources.list.d/azlux.list
    sudo wget -qO /usr/share/keyrings/azlux-archive-keyring.gpg https://azlux.fr/repo.gpg
    sudo apt update -y
    
    sudo apt install -y zram-tools log2ram

    echo "⚙️ Configurando ZRAM (100% de la RAM en intercambio comprimido)..."
    sudo tee /etc/default/zramswap <<EOF >/dev/null
ALGO=lz4
PERCENT=100
EOF
    sudo systemctl restart zramswap 2>/dev/null || true

    echo "🔥 Fijando la CPU a máxima frecuencia (Performance)..."
    for cpu in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor; do
        if [ -f "$cpu" ]; then
            echo "performance" | sudo tee "$cpu" >/dev/null
        fi
    done
    
    # Hacerlo persistente instalando un servicio systemd minúsculo
    sudo tee /etc/systemd/system/cpu-performance.service >/dev/null <<EOF
[Unit]
Description=Set CPU governor to performance
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'for cpu in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor; do echo performance > \$cpu; done'

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable cpu-performance.service || true
    sudo systemctl start cpu-performance.service || true

    echo "🐶 Activando Watchdog de hardware anticuelgues..."
    echo "dtparam=watchdog=on" | sudo tee -a /boot/firmware/config.txt || true
    sudo sed -i 's/.*RuntimeWatchdogSec.*/RuntimeWatchdogSec=10s/' /etc/systemd/system.conf || true

    mark_step "optimizaciones"
else
    echo "⏭️  Paso 2.1 (Optimizaciones Hardware) ya completado. Omitiendo..."
fi

# 2.2. DIETA DE RAM, LIMITACIÓN DE LOGS Y MEMORIA COMPARTIDA SEGURA
if ! check_step "micro_optimizaciones"; then
    echo "🗜️ Aplicando dieta de RAM y bloqueos del Kernel..."
    
    # Desactivar servicios devoradores de RAM sin uso
    sudo systemctl disable bluetooth.service 2>/dev/null || true
    sudo systemctl disable hciuart.service 2>/dev/null || true
    sudo systemctl disable avahi-daemon.service 2>/dev/null || true
    sudo systemctl disable triggerhappy.service 2>/dev/null || true

    # Límite férreo a los Logs de Journald (Para no reventar Log2Ram ni la RAM física)
    sudo sed -i 's/.*SystemMaxUse.*/SystemMaxUse=40M/' /etc/systemd/journald.conf || true
    sudo systemctl restart systemd-journald || true

    # Bloqueo de memoria compartida (SHM)
    if ! grep -q "/run/shm" /etc/fstab; then
        echo "tmpfs /run/shm tmpfs defaults,noexec,nosuid,nodev 0 0" | sudo tee -a /etc/fstab
        sudo mount -o remount /run/shm || true
    fi

    mark_step "micro_optimizaciones"
else
    echo "⏭️  Paso 2.2 (Micro-Optimizaciones) ya completado. Omitiendo..."
fi

# 3. CONFIGURACIÓN DE SSH (Puerto 2222, prohibir Root y obligar Claves)
if ! check_step "ssh"; then
    echo "🔑 Asegurando SSH..."
    # Limpiar posibles inyecciones previas fallidas al final del archivo
    sudo sed -i '/^Port 2222/d' /etc/ssh/sshd_config || true
    sudo sed -i '/^PermitRootLogin no/d' /etc/ssh/sshd_config || true
    sudo sed -i '/^PasswordAuthentication yes/d' /etc/ssh/sshd_config || true

    # Reemplazar in-place en el mismo sitio original para no romper los bloques "Match" del final
    sudo sed -i "s/^#\?Port .*/Port $PUERTO_SSH/" /etc/ssh/sshd_config || true
    sudo sed -i "s/^#\?PermitRootLogin .*/PermitRootLogin no/" /etc/ssh/sshd_config || true
    sudo sed -i "s/^#\?PasswordAuthentication .*/PasswordAuthentication yes/" /etc/ssh/sshd_config || true
    
    # Si por algún casual el archivo venía vacío o sin las directivas base, inyectarlas de forma segura al PRINCIPIO
    if ! grep -q "^Port $PUERTO_SSH" /etc/ssh/sshd_config; then
        echo -e "Port $PUERTO_SSH\nPermitRootLogin no\nPasswordAuthentication yes\n$(sudo cat /etc/ssh/sshd_config)" | sudo tee /etc/ssh/sshd_config >/dev/null
    fi
    mark_step "ssh"
else
    echo "⏭️  Paso 3 (Configuración SSH) ya completado. Omitiendo..."
fi

# 3.5. HARDENING DEL KERNEL (Sysctl de Red)
if ! check_step "sysctl"; then
    echo "🛡️ Aplicando protecciones de red al Kernel (Sysctl)..."
    sudo tee /etc/sysctl.d/99-${HOSTNAME_USAR}-security.conf <<EOF
# Desactivación estricta de IPv6
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1

# Mitigación contra SYN flood y Smurf attacks
net.ipv4.tcp_syncookies = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Prevenir IP spoofing y source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
EOF
    sudo sysctl --system
    mark_step "sysctl"
else
    echo "⏭️  Paso 3.5 (Hardening de Sysctl) ya completado. Omitiendo..."
fi

# 4. CONFIGURACIÓN DEL CORTAFUEGOS (UFW)
if ! check_step "ufw"; then
    echo "🧱 Configurando Firewall (UFW)..."
    sudo ufw default deny incoming || true
    sudo ufw default allow outgoing || true
    sudo ufw allow $PUERTO_SSH/tcp || true
    # Bloquear explícitamente el acceso externo a las APIs locales por seguridad zero-trust
    sudo ufw deny 11434/tcp || true
    sudo ufw deny 18790/tcp || true
    echo "y" | sudo ufw enable
    mark_step "ufw"
else
    echo "⏭️  Paso 4 (Cortafuegos) ya completado. Omitiendo..."
fi

# 5. CONFIGURACIÓN DE FAIL2BAN
if ! check_step "fail2ban"; then
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
    mark_step "fail2ban"
else
    echo "⏭️  Paso 5 (Fail2Ban) ya completado. Omitiendo..."
fi

# 6. ACTUALIZACIONES AUTOMÁTICAS DE SEGURIDAD
if ! check_step "unattended"; then
    echo "📅 Activando actualizaciones desatendidas..."
    sudo dpkg-reconfigure -plow unattended-upgrades
    mark_step "unattended"
else
    echo "⏭️  Paso 6 (Últimas actualizaciones) ya completado. Omitiendo..."
fi

# 7. REINICIO DE SERVICIOS
if ! check_step "reinicio"; then
    echo "🔄 Reiniciando servicios..."
    if ! sudo systemctl restart ssh; then echo -e "${RED}❌ Falla crítica al reiniciar SSH${NC}"; exit 1; fi
    if ! sudo systemctl restart fail2ban; then echo -e "${RED}❌ Falla crítica al reiniciar Fail2Ban${NC}"; exit 1; fi
    mark_step "reinicio"
fi

sudo rm -f "$STATE_FILE"
echo -e "${GREEN}✅ Fortificación completada con éxito.${NC}"
echo -e "⚠️  RECUERDA: A partir de ahora debes entrar con: ${GREEN}ssh -p $PUERTO_SSH usuario@${HOSTNAME_USAR}.local${NC}"
echo -e "⚠️  RECUERDA: Las contraseñas están deshabilitadas. Asegúrate de tener tu clave SSH intercambiada."