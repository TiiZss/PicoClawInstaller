# Changelog

All notable changes to this project will be documented in this file.

## [1.1.4] - 2026-10-04

### Changed
- The Ollama network server prompt no longer pre-fills a specific LAN address; it uses your saved `OLLAMA_NETWORK_URL` or a placeholder. Example IPs use the documentation range.

## [1.1.3] - 2026-02-22
### Changed
- **AI/Cognitive Optimizations for RPi 3B**:
  - `PicoClawRPIInstaller.sh`: Limited `max_tokens` from 8192 to 1024 to prevent 1-hour generation thermal runaways.
  - `PicoClawRPIInstaller.sh`: Softened `system_prompt` default to allow JSON/XML parsing, enabling Agentic behaviors.
  - `PicoJarvisLocalAI.sh`: Drastically reduced local `-c context` from 4096 to 2048 to save ~200MB of static RAM and prevent memory swaps.
  - `PicoJarvisAISwitch.sh`: Automatically stops/starts the `llamacpp` systemd service when switching between Cloud and Local, fully releasing local RAM when not in use.

## [1.1.2] - 2026-02-22
### Changed
- Fixed Race Condition zero-day vulnerabilities in file creations across all scripts avoiding token leakage on `/tmp` and other temp files.

## [1.1.1] - 2026-02-22
### Changed
- Improved overall security mechanisms by patching input injections in IPs and subnet masks, reducing UFW attack surface, and restricting `gpg` sudoers rules to only root.

## [1.1.0] - 2026-02-22
### Added
- `PicoClawMenu.sh`: Interactive execution menu to guide users safely through the deployment process in the optimal order.
- `PicoJarvisLocalAI.sh`: Optional installer exclusively focused on local AI inferences. Natively compiles `llama.cpp` for CPU inference, downloads the `Qwen 2.5 0.5B` GGUF model, configures it as a SystemD API endpoint compatible with OpenAI, and installs the offline audio SDK `Picovoice`.
- `PicoClawRPIInstaller.sh`: Core installer script that handles dependencies, swapping, building PicoClaw from source, creating the configuration for Groq, Ollama and Telegram, and setting up the systemd service. **Now auto-creates `/workspace/memory/MEMORY.md` to prevent bot read errors.**
- `PicoJarvisConfiguration.sh`: Configuration script to change hostname to `picojarvis`, setup GPG and `pass` for secrets management, and trigger Telegram alerts on SSH logins.
- `PicoJarvisHarden.sh`: Security hardening script that changes SSH port to 2222, removes root & password login access, configures UFW firewall, Fail2Ban, unattended upgrades, and applies Sysctl network mitigations.
- `PicoJarvisBaneo.sh`: Advanced Fail2Ban script implementing progressive ban times using a Fibonacci-like sequence and Telegram notifications for banned IPs.
- `AI_INSTRUCTIONS.md`: Guidelines and context for AI agents working on this project.

### Changed
- **Extreme Hardware Micro-Optimizations added**:
  - `PicoJarvisHarden.sh` imposes a 40M limit on `SystemMaxUse` in `journald` to rescue RAM from runaway logs.
  - `PicoJarvisHarden.sh` locks `/run/shm` in `fstab` via `noexec,nosuid,nodev` to restrict shared-memory privileges.
  - `PicoJarvisHarden.sh` permanently disables unneeded OS services (`bluetooth`, `avahi-daemon`, `triggerhappy`) to reclaim highly valuable RAM.
  - `PicoJarvisLocalAI.sh` forces `make LLAMA_FAST_MATH=1` when compiling `llama.cpp` to squeeze every possible token/s from the RPi CPU.
  - `PicoClawRPIInstaller.sh` and `PicoJarvisLocalAI.sh` both now wait for NTP `time-sync.target` via `systemd-time-wait-sync`, ensuring no TLS/SSL cert failures happen post-reboot.
- **Advanced RPi 3B Optimizations added to scripts**:
  - `PicoJarvisHarden.sh` now auto-installs and configures **ZRAM** (100% lz4), **Log2Ram**, **cpufrequtils** (performance governor), and the Broadcom **Hardware Watchdog**.
  - `PicoJarvisLocalAI.sh` now dynamically injects a `Requires=llamacpp.service` into PicoClaw's systemd to ensure safe boot order.
  - `PicoJarvisLocalAI.sh` auto-configures a generic `~/.asoundrc` for ALSA to handle USB mics and Picovoice more reliably.
- All scripts now apply strict failure handling with `set -euo pipefail`.
- Added **Resume/Checkpoint capability** to all scripts: Execution utilizes `/tmp/*.state` files to safely resume operations from the last successful step instead of starting over.
- Added **Functional Verification**: The installer now waits and verifies that the `picoclaw` systemd service runs without errors before concluding the installation.
- Systemd service configurations improved with `ProtectSystem` and similar isolation features.
- All files ensured to use strictly UTF-8 (No BOM).
