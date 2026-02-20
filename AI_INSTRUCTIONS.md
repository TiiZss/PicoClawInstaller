# AI Instructions for PicoClawInstaller

This project consists of a suite of bash scripts designed to deploy, configure, and secure a PicoClaw (Jarvis) AI assistant on a Linux environment (such as a Raspberry Pi).

## Project Overview
1. **PicoClawRPIInstaller.sh**: Compiles and installs the PicoClaw bot, configures its systemd service, and sets up its Groq/Telegram integration.
2. **PicoJarvisConfiguration.sh**: Handles host renaming (`picojarvis`), sets up `pass` for secret management, and creates SSH login alerts.
3. **PicoJarvisHarden.sh**: Secures the server by changing the SSH port to 2222, disabling Root login, enabling UFW, and configuring basic Fail2Ban.
4. **PicoJarvisBaneo.sh**: Implements an advanced Fail2Ban configuration with a Fibonacci-based progressive ban strategy and Telegram notifications.

## Rules for AI Agents
1. **Encoding Protocol**: ALL files (both scripts and documentation) MUST ALWAYS be encoded in **UTF-8 (without BOM)**. This is a strict requirement to avoid execution issues in Linux environments.
2. **Language**: The scripts use Spanish for comments, echo outputs, and Telegram notifications. Maintain Spanish for user-facing text and comments within the scripts.
3. **Idempotency**: When modifying installation scripts, aim to keep operations idempotent (e.g., checking if a service exists before creating it, or safe overwrites).
4. **Security First**: 
   - Never hardcode sensitive tokens or passwords in the scripts. Standardize using `pass` or environment variables when prompted dynamically.
   - Maintain strict permissions on sensitive files (e.g., `chmod 600` on configuration files).
5. **Script Standards**:
   - Begin bash scripts with `#!/bin/bash`.
   - Use clear sections with separated comments.
   - Ensure color variables (like `GREEN` and `NC`) are used consistently for terminal outputs.
