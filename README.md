# EasyGPU — Ollama + Open WebUI + OpenAI-compatible API

Portable, Docker Compose-based GPU inference stack.

Includes Ollama (GPU inference), Open WebUI (chat), LiteLLM (authenticated OpenAI-compatible API), and optional Caddy HTTPS.

## Windows one-click launcher

Download [easygpu-windows.bat](easygpu-windows.bat) from this repository and double-click it on Windows 10/11 (OpenSSH Client required).

It prompts for the rental host, SSH port and username (defaults: `relay.gridshare.in`, `30001`, `root`). Use:
- **1** for first-time install/repair (SSH, Git clone/pull, native installer, tunnel).
- **2** for subsequent starts (native services, tunnel and browser).
- **3** to open the private SSH tunnel only.
- **4** to check remote status.

The tunnel maps your Windows `http://127.0.0.1:8080` to remote Open WebUI and `http://127.0.0.1:4000/v1` to the authenticated LiteLLM API. Leave the separate tunnel terminal open. The SSH password may be requested once for setup and again for the tunnel; SSH keys avoid repeat prompts. For a new GPU rental, update the hostname and SSH port when prompted. Cloning a private GitHub repository on a *new* GPU host requires GitHub authentication on that host; prefer a fine-grained read-only token or SSH deploy key.

The launcher does not make the API publicly accessible; it only forwards connections to your Windows PC. Local port conflicts will prevent the tunnel from starting. No remote passwords or API keys are stored by the launcher. The GPU server's own `.env` retains the key.

## Native installation for GridShare / rented GPU containers (no Docker)

If `docker info` cannot connect to a Docker daemon, use **native mode**:

```bash
cd ~/easygpu
git pull origin main
bash install.sh --native
```

This installs Python services in `data/native/venv`, reuses an existing Ollama installation, generates/reuses the `.env` API key, and serves all services on localhost by default. Existing Ollama models are reused; the installer will pull missing default models. Python 3.11/3.12 recommended; ensure `python3-venv` is installed. The host/container must allow Python packages and locally launched processes.

Check or restart services:

```bash
bash scripts/native.sh status
bash scripts/native.sh start
bash scripts/native.sh stop
tail -n 100 data/native/logs/litellm.log
```

From **Windows PowerShell**, forward the two UI/API ports:

```powershell
ssh -N -L 4000:127.0.0.1:4000 -L 8080:127.0.0.1:8080 -p 30001 root@relay.gridshare.in
```

Then open Open WebUI at `http://127.0.0.1:8080`, and connect VS Code / OpenAI SDK to `http://127.0.0.1:4000/v1` with the key in `.env`. In native mode **WebUI is on 8080, not 3000**. Do not expose 4000 or 11434 publicly without access controls, TLS and rate limiting.

Note: Docker mode and native mode are mutually alternative deployments; if you have existing services on ports 8080/4000, stop them before starting native mode. This has not yet been verified on the specific GridShare container; test with `bash scripts/native.sh status` and review logs.

## Requirements

A Linux NVIDIA GPU VM with Docker daemon access, Docker Compose v2, NVIDIA Container Toolkit, curl, and openssl. **Container-only GPU rentals may not support Docker-in-Docker.** This installer cannot bypass that restriction.

## Install

```bash
git clone https://github.com/jeevanandham572/easygpu.git
cd easygpu
bash install.sh
```

Options: `--skip-models`, `--no-docker-install`, `--domain ai.example.com`.

Default models: `qwen3.5:9b` (API alias `coding-ai`) and `huihui_ai/qwen3-abliterated:8b` (alias `uncensored-ai`).

## Access and test

Private endpoints on the GPU machine:
- API: `http://127.0.0.1:4000/v1`
- Open WebUI: `http://127.0.0.1:3000`
- API key: `grep '^LITELLM_MASTER_KEY=' .env` (keep it secret).

On Windows, keep this SSH tunnel open, replacing the host and port with your rental details:

```powershell
ssh -N -L 4000:127.0.0.1:4000 -L 3000:127.0.0.1:3000 -p YOUR_SSH_PORT root@YOUR_RENTAL_HOST
```

Then use Open WebUI at `http://127.0.0.1:3000` and the OpenAI-compatible API at `http://127.0.0.1:4000/v1`.

```bash
set -a; source .env; set +a
curl -f http://127.0.0.1:4000/v1/models -H "Authorization: Bearer $LITELLM_MASTER_KEY"
curl -f http://127.0.0.1:4000/v1/chat/completions -H "Authorization: Bearer $LITELLM_MASTER_KEY" -H "Content-Type: application/json" -d '{"model":"coding-ai","messages":[{"role":"user","content":"Hello"}]}'
```

VS Code Cline / Roo Code: use OpenAI-compatible provider, API base URL `http://127.0.0.1:4000/v1`, key from `.env`, and `coding-ai`. Some Roo LiteLLM provider versions expect `http://127.0.0.1:4000` without `/v1`.

## HTTPS option

`bash install.sh --domain ai.example.com` enables Caddy with TLS if DNS points to your public VM and inbound ports 80/443 are open. API: `https://ai.example.com/v1`; WebUI: `https://ai.example.com/`. Relay-only GPU services may not support this.

## Operations

```bash
docker compose ps
docker compose logs -f --tail=100
docker compose exec ollama ollama list
bash scripts/diagnose.sh
docker compose down
```

Models and state persist in `data/`; credentials persist in excluded `.env`. Never commit secrets or embed a master key in websites or Android apps. Use your own authenticated backend for public user-facing apps. First WebUI signup should be admin; disable further signups afterward.

This project hasn't been deployment-tested on your particular GPU host. Docker daemon and NVIDIA runtime prerequisites must be met.
