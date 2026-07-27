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
invalid_status="$(
  curl --silent --show-error --output /dev/null --write-out "%{http_code}" --max-time 10 \
    "${auth[@]}" \
    "http://127.0.0.1:${port}/todos/not-a-uuid"
)"
if [[ "${invalid_status}" != "400" ]]; then
  echo "expected malformed TODO UUID to return 400; got ${invalid_status}" >&2
  exit 1
fi

identity="$(
  curl --fail --silent --show-error --max-time 10 \
    "${auth[@]}" \
    "http://127.0.0.1:${port}/whoami"
)"
uv run python -c \
  'import json,sys; assert json.loads(sys.argv[1])["subject"] == "asgi@example.com"' \
  "${identity}"

admin_auth=(-H "cf-access-authenticated-user-email: developer@example.com")
admin_denied_status="$(
  curl --silent --show-error --output /dev/null --write-out "%{http_code}" --max-time 10 \
    -H "cf-access-authenticated-user-email: viewer@example.com" \
    "http://127.0.0.1:${port}/admin"
)"
if [[ "${admin_denied_status}" != "403" ]]; then
  echo "expected non-operator ASGI admin request to return 403; got ${admin_denied_status}" >&2
  exit 1
fi
admin_headers="$(mktemp)"
curl --fail --silent --show-error --max-time 10 \
  --dump-header "${admin_headers}" \
  --output /dev/null \
  -X POST "http://127.0.0.1:${port}/admin/todos/create" \
  "${admin_auth[@]}" \
  -H "origin: https://app.example.com" \
  -H "content-type: application/x-www-form-urlencoded" \
  --data "title=ASGI+golden+admin"
admin_location="$(awk 'tolower($1) == "location:" {print $2}' "${admin_headers}" | tr -d '\r')"
if [[ "${admin_location}" != /admin/todos/object/* ]]; then
  echo "ASGI admin create did not return an object redirect" >&2
  exit 1
fi
admin_list="$(
  curl --fail --silent --show-error --max-time 10 \
    "${admin_auth[@]}" \
    "http://127.0.0.1:${port}/admin/todos?q=golden"
)"
if [[ "${admin_list}" != *"ASGI golden admin"* ]]; then
  echo "ASGI admin list did not return its identity-scoped record" >&2
  exit 1
fi
admin_history="$(
  curl --fail --silent --show-error --max-time 10 \
    "${admin_auth[@]}" \
    "http://127.0.0.1:${port}${admin_location}/history"
)"
if [[ "${admin_history}" != *"resource:add"* || "${admin_history}" == *"ASGI golden admin"* ]]; then
  echo "ASGI admin history is missing redacted audit evidence" >&2
  exit 1
fi

openapi="$(
  curl --fail --silent --show-error --max-time 10 \
    "${auth[@]}" \
    "http://127.0.0.1:${port}/openapi.json"
)"
uv run python -c \
  'import json,sys; value=json.loads(sys.argv[1]); assert value["openapi"] == "3.1.1"; parameter=value["paths"]["/todos/{id}"]["get"]["parameters"][0]; assert parameter == {"name":"id","in":"path","required":True,"schema":{"type":"string","format":"uuid"}}; create=value["paths"]["/todos"]["post"]["responses"]["201"]["content"]["application/json"]["schema"]; assert create["properties"]["id"] == {"type":"string","format":"uuid"}; listing=value["paths"]["/todos"]["get"]["responses"]["200"]["content"]["application/json"]["schema"]; assert listing["type"] == "array"; assert listing["items"]["properties"]["id"] == {"type":"string","format":"uuid"}' \
  "${openapi}"
curl --fail --silent --show-error --max-time 10 \
  "${auth[@]}" \
  "http://127.0.0.1:${port}/docs" >/dev/null

uploaded="$(
  printf 'portable typed upload' |
    curl --fail --silent --show-error --max-time 10 \
      -X POST "http://127.0.0.1:${port}/uploads" \
      "${auth[@]}" \
      -F 'file=@-;filename=golden.txt;type=text/plain'
)"
uv run python -c \
  'import json,sys; value=json.loads(sys.argv[1]); assert value == {"name":"golden.txt","type":"text/plain","size":21,"sha256":"f173d53139adf5d1395cc0c4e3ff2334547b1482736b056c157b52ae951ad267"}' \
  "${uploaded}"

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
