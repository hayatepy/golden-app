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

release_headers="$(
  curl --fail --silent --head --max-time 10 \
    "http://127.0.0.1:${port}/health"
)"
if ! grep -qiF "x-app-version: 0.1.0" <<<"${release_headers}"; then
  echo "ASGI response is missing its semantic application version" >&2
  exit 1
fi
if grep -qiF "x-worker-version:" <<<"${release_headers}"; then
  echo "portable ASGI response claimed a Cloudflare Worker version" >&2
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
    -H "x-request-id: asgi-golden-smoke" \
    "http://127.0.0.1:${port}/whoami?access_token=must-not-be-logged"
)"
uv run python -c \
  'import json,sys; assert json.loads(sys.argv[1])["subject"] == "asgi@example.com"' \
  "${identity}"
request_log_line="$(grep -F '"request_id":"asgi-golden-smoke"' "${log_file}" | tail -1)"
if [[ -z "${request_log_line}" || "${request_log_line}" == *"must-not-be-logged"* ]]; then
  echo "ASGI request log is missing correlation or exposed the query string" >&2
  exit 1
fi

admin_auth=(-H "cf-access-authenticated-user-email: developer@example.com")
admin_home_headers="$(mktemp)"
admin_home="$(
  curl --fail --silent --show-error --max-time 10 \
    --dump-header "${admin_home_headers}" \
    "${admin_auth[@]}" \
    "http://127.0.0.1:${port}/admin"
)"
if [[ "${admin_home}" != *"golden-app Operations"* \
  || "${admin_home}" != *'class="skip-link"'* \
  || "${admin_home}" != *"@media(prefers-reduced-motion:reduce)"* ]]; then
  echo "ASGI admin home is missing its branding and accessibility contract" >&2
  exit 1
fi
if ! grep -qiF "style-src 'sha256-" "${admin_home_headers}" \
  || grep -qiF "'unsafe-inline'" "${admin_home_headers}"; then
  echo "ASGI admin home is missing its hashed style CSP" >&2
  exit 1
fi
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
    "http://127.0.0.1:${port}/admin/todos?view=title-a-z&q=golden"
)"
if [[ "${admin_list}" != *"ASGI golden admin"* \
  || "${admin_list}" != *'aria-current="page">Title A-Z'* ]]; then
  echo "ASGI admin list did not apply its identity-scoped saved view" >&2
  exit 1
fi
admin_csv="$(
  curl --fail --silent --show-error --max-time 10 \
    "${admin_auth[@]}" \
    "http://127.0.0.1:${port}/admin/todos/export.csv?view=title-a-z&q=golden"
)"
if [[ "${admin_csv}" != *"ASGI golden admin"* ]]; then
  echo "ASGI admin CSV did not return its bounded identity-scoped record" >&2
  exit 1
fi
admin_history="$(
  curl --fail --silent --show-error --max-time 10 \
    "${admin_auth[@]}" \
    "http://127.0.0.1:${port}${admin_location}/history"
)"
if [[ "${admin_history}" != *"Add record"* || "${admin_history}" == *"ASGI golden admin"* ]]; then
  echo "ASGI admin history is missing localized, redacted audit evidence" >&2
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

discovered="$(
  curl --fail --silent --show-error --max-time 10 \
    -X POST "http://127.0.0.1:${port}/mcp" \
    "${auth[@]}" \
    -H "accept: application/json, text/event-stream" \
    -H "content-type: application/json" \
    -H "mcp-protocol-version: 2026-07-28" \
    -H "mcp-method: server/discover" \
    --data '{"jsonrpc":"2.0","id":1,"method":"server/discover","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{},"io.modelcontextprotocol/clientInfo":{"name":"golden-asgi","version":"1.0.0"}}}}'
)"
uv run python -c \
  'import json,sys; result=json.loads(sys.argv[1])["result"]; assert result["supportedVersions"] == ["2026-07-28"]; assert result["resultType"] == "complete"; assert "tools" in result["capabilities"]' \
  "${discovered}"

called="$(
  curl --fail --silent --show-error --max-time 10 \
    -X POST "http://127.0.0.1:${port}/mcp" \
    "${auth[@]}" \
    -H "accept: application/json, text/event-stream" \
    -H "content-type: application/json" \
    -H "mcp-protocol-version: 2026-07-28" \
    -H "mcp-method: tools/call" \
    -H "mcp-name: list_todos" \
    --data '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{},"io.modelcontextprotocol/clientInfo":{"name":"golden-asgi","version":"1.0.0"}},"name":"list_todos","arguments":{}}}'
)"
uv run python -c \
  'import json,sys; envelope=json.loads(sys.argv[1])["result"]; assert envelope["resultType"] == "complete"; result=envelope["structuredContent"]; assert result["subject"] == "asgi@example.com"; assert sys.argv[2] in {todo["id"] for todo in result["todos"]}' \
  "${called}" \
  "${todo_id}"

echo "ASGI golden flow passed: identity=${identity} todo_id=${todo_id}"
