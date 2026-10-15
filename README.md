# EasyGPU — Ollama + Open WebUI + OpenAI-compatible API

Portable, Docker Compose-based GPU inference stack.

Includes Ollama (GPU inference), Open WebUI (chat), LiteLLM (authenticated OpenAI-compatible API), and optional Caddy HTTPS.

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
