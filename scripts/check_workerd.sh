#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
entrypoint="${1:-class}"
log_file="${test_dir}.${entrypoint}.workerd.log"
dry_run_log="${test_dir}.${entrypoint}.dry-run.log"
bundle_dir="${test_dir}/${entrypoint}-bundle"
port="${WORKERD_PORT:-8796}"
server_pid=""

if [[ "${entrypoint}" == "global" ]]; then
  config_file="wrangler.global.toml"
elif [[ "${entrypoint}" != "class" ]]; then
  echo "expected class or global entrypoint; got ${entrypoint}" >&2
  exit 2
else
  config_file=""
fi

run_workers() {
  if [[ -n "${config_file}" ]]; then
    uv run python manage_workers.py "$@" --config "${config_file}"
  else
    uv run python manage_workers.py "$@"
  fi
}

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
if [[ "${entrypoint}" == "class" ]]; then
  if ! grep -q 'Default = to_workers(app)' "${root}/src/entry.py"; then
    echo "the golden reference must retain the feature-complete class entrypoint" >&2
    exit 1
  fi
elif ! grep -q 'on_fetch = to_workers_global(app)' "${root}/src/entry_global.py"; then
  echo "the global golden reference must use Hayate's explicit compatibility entrypoint" >&2
  exit 1
fi

(
  cd "${root}"
  run_workers d1 migrations apply DB --local
  run_workers deploy --dry-run --outdir "${bundle_dir}" >"${dry_run_log}" 2>&1
  run_workers dev --port "${port}"
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
for admin_module in hayate_admin/site.py hayate_htmx/request.py; do
  if [[ ! -f "${bundle_dir}/${admin_module}" ]]; then
    echo "vendored admin module is absent from the workerd bundle: ${admin_module}" >&2
    exit 1
  fi
done

auth=(-H "cf-access-authenticated-user-email: workerd@example.com")
created="$(
  curl --fail --silent --show-error --max-time 10 \
    -X POST "http://127.0.0.1:${port}/todos" \
    "${auth[@]}" \
    -H "content-type: application/json" \
    --data '{"title":"D1 golden todo"}'
)"
todo_id="$(uv run python -c 'import json,sys; value=json.loads(sys.argv[1]); assert value["title"] == "D1 golden todo"; print(value["id"])' "${created}")"
invalid_status="$(
  curl --silent --show-error --output /dev/null --write-out "%{http_code}" --max-time 10 \
    "${auth[@]}" \
    "http://127.0.0.1:${port}/todos/not-a-uuid"
)"
if [[ "${invalid_status}" != "400" ]]; then
  echo "expected malformed TODO UUID to return 400; got ${invalid_status}" >&2
  exit 1
fi
invalid_limit_status="$(
  curl --silent --show-error --output /dev/null --write-out "%{http_code}" --max-time 10 \
    "${auth[@]}" \
    "http://127.0.0.1:${port}/todos?limit=101"
)"
if [[ "${invalid_limit_status}" != "400" ]]; then
  echo "expected constrained TODO limit to return 400; got ${invalid_limit_status}" >&2
  exit 1
fi

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
  'import json,sys; value=json.loads(sys.argv[1]); assert value["openapi"] == "3.1.1"; limit=value["paths"]["/todos"]["get"]["parameters"][0]; assert limit == {"name":"limit","in":"query","required":False,"schema":{"type":"integer","minimum":1,"maximum":100,"default":25}}; parameter=value["paths"]["/todos/{id}"]["get"]["parameters"][0]; assert parameter == {"name":"id","in":"path","required":True,"schema":{"type":"string","format":"uuid"}}; create=value["paths"]["/todos"]["post"]["responses"]["201"]["content"]["application/json"]["schema"]; assert create["properties"]["id"] == {"type":"string","format":"uuid"}; listing=value["paths"]["/todos"]["get"]["responses"]["200"]["content"]["application/json"]["schema"]; assert listing["type"] == "array"; assert listing["items"]["properties"]["id"] == {"type":"string","format":"uuid"}' \
  "${openapi}"

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

terminate_tree "${server_pid}"
wait "${server_pid}" 2>/dev/null || true
server_pid=""
(
  cd "${root}"
  run_workers dev --port "${port}"
) >>"${log_file}" 2>&1 &
server_pid=$!

admin_auth=(-H "cf-access-authenticated-user-email: developer@example.com")
admin_ready=false
for _ in {1..60}; do
  if curl --fail --silent --max-time 2 \
    "${admin_auth[@]}" \
    "http://127.0.0.1:${port}/admin" >/dev/null; then
    admin_ready=true
    break
  fi
  if ! kill -0 "${server_pid}" 2>/dev/null; then
    cat "${log_file}"
    exit 1
  fi
  sleep 1
done
if [[ "${admin_ready}" != true ]]; then
  cat "${log_file}"
  exit 1
fi

admin_denied_status="$(
  curl --silent --show-error --output /dev/null --write-out "%{http_code}" --max-time 10 \
    -H "cf-access-authenticated-user-email: viewer@example.com" \
    "http://127.0.0.1:${port}/admin"
)"
if [[ "${admin_denied_status}" != "403" ]]; then
  echo "expected non-operator workerd admin request to return 403; got ${admin_denied_status}" >&2
  exit 1
fi
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
  echo "workerd admin home is missing its branding and accessibility contract" >&2
  exit 1
fi
if ! grep -qiF "style-src 'sha256-" "${admin_home_headers}" \
  || grep -qiF "'unsafe-inline'" "${admin_home_headers}"; then
  echo "workerd admin home is missing its hashed style CSP" >&2
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
  --data "title=D1+golden+admin"
admin_location="$(awk 'tolower($1) == "location:" {print $2}' "${admin_headers}" | tr -d '\r')"
if [[ "${admin_location}" != /admin/todos/object/* ]]; then
  echo "workerd admin create did not return an object redirect" >&2
  exit 1
fi
admin_list="$(
  curl --fail --silent --show-error --max-time 10 \
    "${admin_auth[@]}" \
    "http://127.0.0.1:${port}/admin/todos?view=title-a-z&q=golden"
)"
if [[ "${admin_list}" != *"D1 golden admin"* \
  || "${admin_list}" != *'aria-current="page">Title A-Z'* ]]; then
  echo "workerd admin list did not apply its identity-scoped saved view" >&2
  exit 1
fi
admin_csv="$(
  curl --fail --silent --show-error --max-time 10 \
    "${admin_auth[@]}" \
    "http://127.0.0.1:${port}/admin/todos/export.csv?view=title-a-z&q=golden"
)"
if [[ "${admin_csv}" != *"D1 golden admin"* ]]; then
  echo "workerd admin CSV did not return its bounded identity-scoped record" >&2
  exit 1
fi
admin_history="$(
  curl --fail --silent --show-error --max-time 10 \
    "${admin_auth[@]}" \
    "http://127.0.0.1:${port}${admin_location}/history"
)"
if [[ "${admin_history}" != *"Add record"* || "${admin_history}" == *"D1 golden admin"* ]]; then
  echo "workerd admin history is missing localized, redacted audit evidence" >&2
  exit 1
fi

echo "workerd ${entrypoint} golden flow passed: ${upload} todo_id=${todo_id}"
