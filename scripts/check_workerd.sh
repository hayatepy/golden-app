#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
log_file="${test_dir}.workerd.log"
dry_run_log="${test_dir}.dry-run.log"
bundle_dir="${test_dir}/bundle"
port="${WORKERD_PORT:-8796}"
server_pid=""

terminate_tree() {
  local parent_pid="$1"
  local child_pid
  while read -r child_pid; do
    if [[ -n "${child_pid}" ]]; then
      terminate_tree "${child_pid}"
    fi
  done < <(pgrep -P "${parent_pid}" 2>/dev/null || true)
  kill "${parent_pid}" 2>/dev/null || true
}

cleanup() {
  local status=$?
  if [[ "${status}" -ne 0 ]]; then
    cat "${dry_run_log}" 2>/dev/null || true
    cat "${log_file}" 2>/dev/null || true
  fi
  if [[ -n "${server_pid}" ]] && kill -0 "${server_pid}" 2>/dev/null; then
    terminate_tree "${server_pid}"
    wait "${server_pid}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if [[ ! -f "${root}/.dev.vars" ]]; then
  echo "copy .dev.vars.example to .dev.vars before running the workerd flow" >&2
  exit 2
fi
if [[ "$(node --version)" != v24.* ]]; then
  echo "the golden workerd flow requires Node.js 24" >&2
  exit 2
fi
if ! grep -q 'Default = to_workers(app)' "${root}/src/entry.py"; then
  echo "the golden reference must retain the feature-complete class entrypoint" >&2
  exit 1
fi

(
  cd "${root}"
  uv run python manage_workers.py d1 migrations apply DB --local
  uv run python manage_workers.py deploy --dry-run --outdir "${bundle_dir}" \
    >"${dry_run_log}" 2>&1
  uv run python manage_workers.py dev --port "${port}"
) >"${log_file}" 2>&1 &
server_pid=$!

ready=false
for _ in {1..60}; do
  if curl --fail --silent --max-time 2 "http://127.0.0.1:${port}/health" >/dev/null; then
    ready=true
    break
  fi
  if ! kill -0 "${server_pid}" 2>/dev/null; then
    cat "${dry_run_log}" 2>/dev/null || true
    cat "${log_file}"
    exit 1
  fi
  sleep 1
done
if [[ "${ready}" != true ]]; then
  cat "${log_file}"
  exit 1
fi

upload="$(grep -F "Total Upload:" "${dry_run_log}" | tail -1)"
if [[ -z "${upload}" ]]; then
  cat "${dry_run_log}"
  exit 1
fi

auth=(-H "cf-access-authenticated-user-email: workerd@example.com")
created="$(
  curl --fail --silent --show-error --max-time 10 \
    -X POST "http://127.0.0.1:${port}/todos" \
    "${auth[@]}" \
    -H "content-type: application/json" \
    --data '{"title":"D1 golden todo"}'
)"
todo_id="$(uv run python -c 'import json,sys; value=json.loads(sys.argv[1]); assert value["title"] == "D1 golden todo"; print(value["id"])' "${created}")"

identity="$(
  curl --fail --silent --show-error --max-time 10 \
    "${auth[@]}" \
    "http://127.0.0.1:${port}/whoami"
)"
uv run python -c \
  'import json,sys; assert json.loads(sys.argv[1])["subject"] == "workerd@example.com"' \
  "${identity}"

openapi="$(
  curl --fail --silent --show-error --max-time 10 \
    "${auth[@]}" \
    "http://127.0.0.1:${port}/openapi.json"
)"
uv run python -c \
  'import json,sys; value=json.loads(sys.argv[1]); assert value["openapi"] == "3.1.1"; assert "/todos" in value["paths"]' \
  "${openapi}"

initialized="$(
  curl --fail --silent --show-error --max-time 10 \
    -X POST "http://127.0.0.1:${port}/mcp" \
    "${auth[@]}" \
    -H "accept: application/json, text/event-stream" \
    -H "content-type: application/json" \
    --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"golden-workerd","version":"1.0.0"}}}'
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
  'import json,sys; result=json.loads(sys.argv[1])["result"]["structuredContent"]; assert result["subject"] == "workerd@example.com"; assert sys.argv[2] in {todo["id"] for todo in result["todos"]}' \
  "${called}" \
  "${todo_id}"

echo "workerd golden flow passed: ${upload} todo_id=${todo_id}"
