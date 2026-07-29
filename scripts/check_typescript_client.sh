#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="$(mktemp -d)"
log_file="$(mktemp)"
port="${TYPESCRIPT_CLIENT_PORT:-8796}"
server_pid=""

cleanup() {
  local status=$?
  if [[ "${status}" -ne 0 ]]; then
    cat "${log_file}"
  fi
  if [[ -n "${server_pid}" ]] && kill -0 "${server_pid}" 2>/dev/null; then
    kill "${server_pid}" 2>/dev/null || true
    wait "${server_pid}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

cd "${root}"
npm run client:check
./node_modules/.bin/tsc \
  --noEmit false \
  --outDir "${build_dir}" \
  --declaration false \
  --sourceMap false

uv run uvicorn app:app --app-dir src --host 127.0.0.1 --port "${port}" \
  >"${log_file}" 2>&1 &
server_pid=$!

ready=false
for _ in {1..30}; do
  if curl --fail --silent --max-time 2 "http://127.0.0.1:${port}/health" >/dev/null; then
    ready=true
    break
  fi
  if ! kill -0 "${server_pid}" 2>/dev/null; then
    cat "${log_file}"
    exit 1
  fi
  sleep 1
done
if [[ "${ready}" != true ]]; then
  cat "${log_file}"
  exit 1
fi

HAYATE_API_BASE_URL="http://127.0.0.1:${port}" \
  node "${build_dir}/check-api-client.js"
