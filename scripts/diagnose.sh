#!/usr/bin/env bash
set -u
cd "$(dirname "$(realpath "$0")")/.."
echo '== GPU =='; nvidia-smi -L 2>&1 || true
echo '== Docker =='; docker info --format '{{.ServerVersion}}' 2>&1 || true
echo '== Compose =='; docker compose version 2>&1 || true
echo '== Services =='; docker compose ps 2>&1 || true
echo '== Models =='; docker compose exec -T ollama ollama list 2>&1 || true
echo '== API local status (no key disclosed) =='; curl -sS -o /dev/null -w 'HTTP %{http_code}\n' http://127.0.0.1:4000/v1/models || true
echo '== Gateway logs =='; docker compose logs --tail=30 litellm 2>&1 || true
