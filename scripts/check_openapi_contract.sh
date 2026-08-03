#!/usr/bin/env bash
set -euo pipefail

origin="${1:?usage: check_openapi_contract.sh ORIGIN [IDENTITY]}"
identity="${2:-schemathesis@example.com}"

# Admin and MCP expose transport/operational routes whose generic discovery
# documents are not typed application contracts. Exercise the eight typed HTTP
# operations generated from endpoint declarations on the same real server used
# by the caller (Uvicorn or Workerd).
common_args=(
  "${origin}/openapi.json"
  --header "cf-access-authenticated-user-email: ${identity}"
  --mode positive
  --checks not_a_server_error,status_code_conformance,content_type_conformance,response_schema_conformance
  --generation-deterministic
  --no-color
)

uv run schemathesis run "${common_args[@]}" \
  --include-path-regex '^/(health|canonicalize|whoami|todos(?:/.*)?|uploads)$' \
  --phases examples,coverage \
  --max-examples 20

# Arbitrary multipart fields produced by generic fuzzing can terminate the
# local Workerd transport before the application returns a response. The upload
# contract still receives generated coverage above and an explicit real upload
# in both callers; retain full positive fuzzing for every non-multipart route.
uv run schemathesis run "${common_args[@]}" \
  --include-path-regex '^/(health|canonicalize|whoami|todos(?:/.*)?)$' \
  --phases fuzzing \
  --max-examples 20
