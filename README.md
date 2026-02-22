<div align="center">

# 🤖 PicoClawInstaller 🤖

[![Version](https://img.shields.io/badge/version-1.1.3-blue.svg)](https://github.com/TiiZss/PicoClawInstaller/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash Shell](https://img.shields.io/badge/language-bash-4EAA25.svg?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-Raspberry_Pi_3B-C51A4A?logo=raspberry-pi&logoColor=white)](https://www.raspberrypi.org/)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy_Me_A_Coffee-FFDD00?style=flat&logo=buy-me-a-coffee&logoColor=black)](https://www.buymeacoffee.com/TiiZss)

**The Ultimate Offline AI & Deployment Suite for Raspberry Pi 3B**

[English](#english) • [Español](#español)

</div>

---

<a name="english"></a>
## 🇬🇧 English

### 📖 Short Description
PicoClawInstaller is a highly optimized, modular Bash deployment suite designed specifically for the Raspberry Pi 3B (1GB RAM). It automatically installs, fortifies, and configures the **PicoClaw** Telegram bot, integrating it with either cloud APIs (Groq) or a completely offline, natively compiled `llama.cpp` inference engine running the **Qwen 2.5 0.5B** or **SmolLM2 360M** LLM alongside **Picovoice** for Wake-Word and STT capabilities.

### ⚡ Key Features (Extreme RPi 3B Optimizations)
*   **Interactive Menu**: (`PicoClawMenu.sh`) A guided, step-by-step CLI interface.
*   **100% Offline AI**: Natively compiles `llama.cpp` for ARM64 CPU (no CUDA needed) with `Fast Math` enabled, running a 4-bit quantized Qwen 2.5 0.5B or SmolLM2 360M model.
*   **Memory & CPU Mastery**: Automatically deploys **ZRAM** (LZ4 compression), limits system logs (`journald`), locks shared memory (`/run/shm`), forces CPU `performance` governor, and disables GUI/Bluetooth bloatware.
*   **Maximum Security**: Implements `Fail2Ban` with progressive Fibonacci bans, UFW firewall, Ed25519 SSH-Key-Only access (Port 2222), and GPG Vault for API/Token secrets.
*   **Resilience**: Scripts use `set -euo pipefail` and maintain `/tmp/*.state` checkpoints to safely resume from interruptions. Features Broadcom Hardware Watchdog integration for auto-rebooting frozen systems.

### 🚀 Usage
Clone the repository and execute the interactive menu:
```bash
git clone https://github.com/TiiZss/PicoClawInstaller.git
cd PicoClawInstaller
chmod +x PicoClawMenu.sh
./PicoClawMenu.sh
```

---

<a name="español"></a>
## 🇪🇸 Español

### 📖 Descripción Corta
PicoClawInstaller es una suite de despliegue en Bash, modular y altamente optimizada, diseñada expresamente para exprimir la Raspberry Pi 3B (1GB RAM). Instala, fortifica y configura el bot de Telegram **PicoClaw**, integrándolo con APIs en la nube (Groq) o con un motor de inferencia local 100% offline (`llama.cpp` compilado nativamente) corriendo el LLM **Qwen 2.5 0.5B** o **SmolLM2 360M** y **Picovoice** para capacidades de voz.

### ⚡ Características (Optimizaciones Extremas RPi 3B)
*   **Menú Interactivo**: (`PicoClawMenu.sh`) Una interfaz CLI guiada paso a paso.
*   **IA 100% Offline**: Compila nativamente `llama.cpp` para CPU ARM64 (sin CUDA) con `Fast Math` activado, ejecutando un modelo Qwen 2.5 0.5B o SmolLM2 360M cuantizado a 4 bits.
*   **Maestría de CPU y Memoria**: Despliega automáticamente **ZRAM** (compresión LZ4), limita los logs del sistema (`journald`), bloquea la memoria compartida (`/run/shm`), fuerza el governor de CPU a `performance` y desactiva el bloatware del SO (Bluetooth/GUI).
*   **Seguridad Máxima**: Implementa `Fail2Ban` con baneos progresivos de Fibonacci, cortafuegos UFW, acceso SSH exclusivo por clave Ed25519 (Puerto 2222) y una bóveda GPG para los tokens y APIs.
*   **Resiliencia**: Los scripts operan bajo modo estricto (`set -euo pipefail`) y mantienen puntos de control (checkpoints `.state`) para reanudar operaciones interrumpidas. Integra Watchdog por hardware para auto-reiniciar placas congeladas.

### 🚀 Uso
Clona el repositorio y ejecuta el menú interactivo:
```bash
git clone https://github.com/TiiZss/PicoClawInstaller.git
cd PicoClawInstaller
chmod +x PicoClawMenu.sh
./PicoClawMenu.sh
```

El menú te guiará por el siguiente flujo recomendado:
1.  **Hardenizar Sistema**: Desactiva el acceso por contraseña y asegura SSH.
2.  **Configurar Baneo Progresivo**: Despliega Fail2Ban para repeler ataques.
3.  **Instalar IA Local y SDK**: Compila Llama.cpp y prepara el motor de voz Picovoice.
4.  **Instalar PicoClaw**: Despliega el bot y el servicio Systemd.
5.  **Configurar Entorno (Vault)**: Protege las claves GPG del bot post-instalación.
6.  **Cambiar IA**: Alterna entre nube (Groq) e IA local al instante.
7.  **Diagnóstico del Sistema**: Comprueba la salud del SO, puertos y servicios.

---

## 🙏 Acknowledgments & Credits

This project stands on the shoulders of giants. Massive thanks to the brilliant minds and communities behind:

*   **[PicoClaw](https://github.com/sipeed/picoclaw)** / **[OpenClaw](https://github.com/sipeed/openclaw)**: For creating the core Telegram Bot framework capable of reasoning and executing tools.
*   **[ggerganov/llama.cpp](https://github.com/ggerganov/llama.cpp)**: For democratizing local AI and making the impossible (running LLMs on a 1GB Raspberry Pi CPU) a reality.
*   **[Ollama](https://github.com/ollama/ollama)**: For providing an open API standard that bridges so many toolchains together.
*   **[Qwen](https://qwenlm.github.io/)**: For engineering insanely capable, tiny LLMs like Qwen 2.5 0.5B.
*   **[Raspberry Pi Foundation](https://www.raspberrypi.org/)**: For creating the legendary RPi 3B that powered this entire optimization challenge.
