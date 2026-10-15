#!/usr/bin/env bash
# Container-friendly native mode (no Docker daemon required).
if [[ "${1:-}" == "--native" ]]; then
  shift
  exec bash "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/scripts/native.sh" install "$@"
fi

set -Eeuo pipefail
cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

usage() {
  cat <<'HELP'
Usage: bash install.sh [--domain ai.example.com] [--skip-models] [--no-docker-install]

Default: private-only services bound to localhost. Access via SSH forwarding.
--domain: enable public HTTPS (DNS points to this server, ports 80/443 open).
--skip-models: skip initial model downloads (helpful for fast deployment).
--no-docker-install: fail instead of attempting Docker installation.
HELP
}
DOMAIN_ARG=""
SKIP_MODELS=0
NO_DOCKER_INSTALL=0
while (($#)); do
  case "$1" in
    --domain) [[ $# -ge 2 ]] || { echo 'Missing domain' >&2; exit 2; }; DOMAIN_ARG="$2"; shift 2;;
    --skip-models) SKIP_MODELS=1; shift;;
    --no-docker-install) NO_DOCKER_INSTALL=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2;;
  esac
done

if [[ -n "$DOMAIN_ARG" && ! "$DOMAIN_ARG" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$ ]]; then
  echo 'Invalid domain name' >&2; exit 2
fi

if ! command -v openssl >/dev/null; then
  echo 'openssl required. Install it using apt-get install openssl.' >&2; exit 1
fi
if ! command -v docker >/dev/null; then
  if ((NO_DOCKER_INSTALL)); then echo 'Docker not installed.' >&2; exit 1; fi
  if [[ "$(id -u)" -ne 0 ]]; then
    echo 'Install Docker first or rerun installer as root to attempt auto-install.' >&2; exit 1
  fi
  if ! command -v curl >/dev/null; then echo 'curl is required to install Docker.' >&2; exit 1; fi
  echo 'Docker is missing. Installing with the official Docker convenience script (review before production use)...'
  tmp_script="$(mktemp)"
  trap 'rm -f "${tmp_script:-}"' EXIT
  curl -fsSL https://get.docker.com -o "$tmp_script"
  sh "$tmp_script"
  rm -f "$tmp_script"
  trap - EXIT
fi
if ! docker info >/dev/null 2>&1; then
  echo 'Docker daemon is inaccessible. This is common inside rented GPU containers.' >&2
  echo 'Use a GPU VM with Docker daemon or a GPU provider that supports nested Docker, then rerun.' >&2
  exit 1
fi
if ! docker compose version >/dev/null 2>&1; then
  echo 'Docker Compose v2 is required. Install the docker-compose-plugin package.' >&2; exit 1
fi
if ! command -v nvidia-smi >/dev/null 2>&1; then
  echo 'Warning: nvidia-smi is missing on host; GPU passthrough may fail.' >&2
fi

if [[ ! -f .env ]]; then
  umask 077
  cat > .env <<ENV
LITELLM_MASTER_KEY=sk-$(openssl rand -hex 32)
WEBUI_SECRET_KEY=$(openssl rand -hex 32)
DOMAIN=unused.example.com
API_PORT=4000
WEBUI_PORT=3000
OLLAMA_TAG=latest
WEBUI_TAG=main
LITELLM_IMAGE=docker.litellm.ai/berriai/litellm:main-stable
OLLAMA_KEEP_ALIVE=5m
ENV
  echo 'Created .env with random API and WebUI secrets.'
else
  echo 'Reusing existing .env and API key (no rotation).'
fi
if [[ -n "$DOMAIN_ARG" ]]; then
  sed -i "s/^DOMAIN=.*/DOMAIN=$DOMAIN_ARG/" .env
fi
mkdir -p data/ollama data/open-webui data/caddy_data data/caddy_config
chmod 700 data 2>/dev/null || true

COMPOSE=(docker compose -f docker-compose.yml)
if [[ -n "$DOMAIN_ARG" ]]; then COMPOSE+=(--profile public); fi
if ! "${COMPOSE[@]}" config --quiet; then echo 'Invalid Compose config.' >&2; exit 1; fi

echo 'Starting containers (this may download several GB)...'
if ! "${COMPOSE[@]}" up -d; then
  echo 'Container startup failed. If GPU unavailable inside Docker, install/configure NVIDIA Container Toolkit on host.' >&2
  echo 'Inspect: docker compose logs --tail=100 ollama litellm open-webui' >&2
  exit 1
fi
if (( ! SKIP_MODELS )); then
  echo 'Downloading models; large downloads can take several minutes...'
  for model in qwen3.5:9b huihui_ai/qwen3-abliterated:8b; do
    if ! "${COMPOSE[@]}" exec -T ollama ollama pull "$model"; then
      echo "Warning: could not download $model; retry: docker compose exec ollama ollama pull $model" >&2
    fi
  done
fi
cat <<'DONE'

Installation launched.
Private endpoints on the GPU machine:
  API:        http://127.0.0.1:4000/v1
  Open WebUI: http://127.0.0.1:3000
  Models:     coding-ai, uncensored-ai

API key: read from .env with: grep '^LITELLM_MASTER_KEY=' .env
Security: do not share the key or put it in browser/mobile client code.
On Windows, make an SSH tunnel: ssh -N -L 4000:127.0.0.1:4000 -L 3000:127.0.0.1:3000 -p YOUR_PORT root@YOUR_HOST
Check status: docker compose ps
See logs: docker compose logs -f --tail=100
DONE
if [[ -n "$DOMAIN_ARG" ]]; then
  echo "Public HTTPS API: https://$DOMAIN_ARG/v1"
  echo "Public Open WebUI: https://$DOMAIN_ARG/"
  echo 'HTTPS requires a working public IP, DNS A/AAAA record, and inbound ports 80/443.'
fi
