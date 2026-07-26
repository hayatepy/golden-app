#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
log_file="$(mktemp)"
port="${ASGI_PORT:-8795}"
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

(
  cd "${root}"
  uv run uvicorn app:app --app-dir src --host 127.0.0.1 --port "${port}"
) >"${log_file}" 2>&1 &
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

auth=(-H "cf-access-authenticated-user-email: asgi@example.com")
created="$(
  curl --fail --silent --show-error --max-time 10 \
    -X POST "http://127.0.0.1:${port}/todos" \
    "${auth[@]}" \
    -H "content-type: application/json" \
    --data '{"title":"ASGI golden todo"}'
)"
todo_id="$(uv run python -c 'import json,sys; value=json.loads(sys.argv[1]); assert value["title"] == "ASGI golden todo"; print(value["id"])' "${created}")"

identity="$(
  curl --fail --silent --show-error --max-time 10 \
    "${auth[@]}" \
    "http://127.0.0.1:${port}/whoami"
)"
uv run python -c \
  'import json,sys; assert json.loads(sys.argv[1])["subject"] == "asgi@example.com"' \
  "${identity}"

openapi="$(
  curl --fail --silent --show-error --max-time 10 \
    "${auth[@]}" \
    "http://127.0.0.1:${port}/openapi.json"
)"
uv run python -c \
  'import json,sys; value=json.loads(sys.argv[1]); assert value["openapi"] == "3.1.1"; assert "/todos" in value["paths"]' \
  "${openapi}"
curl --fail --silent --show-error --max-time 10 \
  "${auth[@]}" \
  "http://127.0.0.1:${port}/docs" >/dev/null

initialized="$(
  curl --fail --silent --show-error --max-time 10 \
    -X POST "http://127.0.0.1:${port}/mcp" \
    "${auth[@]}" \
    -H "accept: application/json, text/event-stream" \
    -H "content-type: application/json" \
    --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"golden-asgi","version":"1.0.0"}}}'
)"
uv run python -c \
  'import json,sys; assert json.loads(sys.argv[1])["result"]["protocolVersion"] == "2025-11-25"' \
  "${initialized}"

called="$(
  curl --fail --silent --show-error --max-time 10 \
    -X POST "http://127.0.0.1:${port}/mcp" \
    "${auth[@]}" \
    -H "accept: application/json, text/event-stream" \
    -H "content-type: application/json" \
    -H "mcp-protocol-version: 2025-11-25" \
    --data '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_todos","arguments":{}}}'
)"
uv run python -c \
  'import json,sys; result=json.loads(sys.argv[1])["result"]["structuredContent"]; assert result["subject"] == "asgi@example.com"; assert sys.argv[2] in {todo["id"] for todo in result["todos"]}' \
  "${called}" \
  "${todo_id}"

echo "ASGI golden flow passed: identity=${identity} todo_id=${todo_id}"
