#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
mkdir -p data/native/logs data/native/run
if [[ "${1:-}" == "--help" ]]; then
  echo "Usage: bash scripts/native.sh [install|start|stop|status]"
  exit 0
fi
ACTION="${1:-install}"
if [[ ! "$ACTION" =~ ^(install|start|stop|status)$ ]]; then
  echo "Unknown action $ACTION" >&2; exit 2
fi
ollama_ready() { curl -fsS --max-time 3 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; }
port_live() { (echo >/dev/tcp/127.0.0.1/"$1") >/dev/null 2>&1; }
process_stop() {
  local name="$1" pid_file="$ROOT/data/native/run/$1.pid" pid
  if [[ -f "$pid_file" ]]; then
    read -r pid < "$pid_file"
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" || true
      echo "Stopped $name ($pid)"
    fi
    rm -f "$pid_file"
  fi
}
process_start() {
  local name="$1" port="$2"; shift 2
  if port_live "$port"; then
    echo "Port $port is already in use; reusing existing $name only if it is your intended service."
    return 0
  fi
  nohup "$@" > "$ROOT/data/native/logs/$name.log" 2>&1 < /dev/null &
  echo "$!" > "$ROOT/data/native/run/$name.pid"
  echo "Started $name (PID $!, port $port)"
}
if [[ "$ACTION" == "stop" ]]; then
  process_stop litellm
  process_stop open-webui
  # Do not stop Ollama: it may have been running before installation.
  exit 0
fi
if [[ "$ACTION" == "status" ]]; then
  for port in 11434 8080 4000; do
    if port_live "$port"; then echo "Port $port: listening"; else echo "Port $port: not listening"; fi
  done
  echo "Logs: $ROOT/data/native/logs/"
  exit 0
fi
if [[ "$ACTION" == "install" ]]; then
  if ! command -v curl >/dev/null || ! command -v openssl >/dev/null; then
    echo "curl and openssl required (apt-get install curl openssl)" >&2; exit 1
  fi
  if ! command -v python3 >/dev/null; then
    echo "Python 3 required; install Python 3.11 or 3.12 and venv." >&2; exit 1
  fi
  if ! command -v ollama >/dev/null; then
    echo "Installing Ollama with official installer..."
    curl -fsSL https://ollama.com/install.sh | sh
  fi
  if [[ ! -f .env ]]; then
    umask 077
    {
      printf 'LITELLM_MASTER_KEY=sk-%s\n' "$(openssl rand -hex 32)"
      printf 'WEBUI_SECRET_KEY=%s\n' "$(openssl rand -hex 32)"
    } > .env
    echo "Generated local .env with API secrets"
  else
    echo "Reusing .env, preserving existing API key"
  fi
  if [[ ! -x data/native/venv/bin/python ]]; then
    python3 -m venv data/native/venv || {
      echo "venv unavailable. Try apt-get install python3-venv." >&2; exit 1;
    }
  fi
  data/native/venv/bin/python -m pip install --upgrade pip
  data/native/venv/bin/python -m pip install 'litellm[proxy]' open-webui
fi
[[ -f .env ]] || { echo ".env is missing, run bash install.sh --native" >&2; exit 1; }
[[ -x data/native/venv/bin/python ]] || { echo "Native environment missing, install first" >&2; exit 1; }
set -a
# File is generated locally, not accepted from untrusted input.
source .env
set +a
[[ -n "${LITELLM_MASTER_KEY:-}" && -n "${WEBUI_SECRET_KEY:-}" ]] || {
  echo "LITELLM_MASTER_KEY and WEBUI_SECRET_KEY must be set in .env" >&2; exit 1;
}
if ! ollama_ready; then
  if port_live 11434; then
    echo "Port 11434 is in use but Ollama API is not responding." >&2; exit 1
  fi
  export OLLAMA_HOST=127.0.0.1:11434
  process_start ollama 11434 ollama serve
fi
for i in $(seq 1 30); do
  if ollama_ready; then break; fi
  sleep 1
done
ollama_ready || { echo "Ollama did not start; inspect data/native/logs/ollama.log" >&2; exit 1; }
if [[ "$ACTION" == "install" ]]; then
  echo "Pulling default models (may take several minutes)"
  ollama pull qwen3.5:9b
  ollama pull huihui_ai/qwen3-abliterated:8b
fi
export ENABLE_SIGNUP=True
export WEBUI_AUTH=True
export OLLAMA_BASE_URL=http://127.0.0.1:11434
export DATA_DIR="$ROOT/data/native/open-webui"
mkdir -p "$DATA_DIR"
process_start open-webui 8080 "$ROOT/data/native/venv/bin/open-webui" serve --host 127.0.0.1 --port 8080
process_start litellm 4000 "$ROOT/data/native/venv/bin/litellm" --config "$ROOT/config/litellm-native.yaml" --host 127.0.0.1 --port 4000
cat <<EOF
Native services launched. They may take up to a minute to become ready.
Open WebUI (local): http://127.0.0.1:8080
LiteLLM API (local): http://127.0.0.1:4000/v1
API key: stored in $ROOT/.env
Diagnose: bash scripts/native.sh status
Logs: tail -f data/native/logs/litellm.log
SSH forwarding from Windows: ssh -N -L 4000:127.0.0.1:4000 -L 8080:127.0.0.1:8080 -p PORT root@HOST
EOF
