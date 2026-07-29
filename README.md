# Hayate production golden app

[![CI](https://github.com/hayatepy/golden-app/actions/workflows/ci.yml/badge.svg)](https://github.com/hayatepy/golden-app/actions/workflows/ci.yml)

> **Hayate ecosystem:** [Start here](https://github.com/hayatepy/.github/blob/main/docs/START.md)
> · [Production path](https://github.com/hayatepy/.github/blob/main/docs/PRODUCTION.md)
> · [Tested compatibility](https://github.com/hayatepy/.github/blob/main/docs/COMPATIBILITY.md)

This is the public, executable reference for the
[Hayate ecosystem](https://github.com/hayatepy). It is generated from
`create-hayate==0.12.0` and contains one application core that runs unchanged
on ASGI with SQLite and Cloudflare Python Workers with D1.

The app intentionally uses a generic TODO model. It contains no FolioMCP
source, data model, credentials, tenant policy, or product-specific behavior.

## Start here

After cloning the repository, run:

```sh
uv sync --locked
cp .dev.vars.example .dev.vars
uv run pytest
uv run python scripts/check_sql_contracts.py
```

Every executable command block in this README runs in CI. The direct test
suite covers identity-scoped CRUD, bounded typed multipart uploads, OpenAPI,
MCP, production middleware, explicit operational admin, SQL contracts,
persistent redacted audit history, and restart-safe local database bootstrap.

Run the complete ASGI path:

```sh
bash scripts/check_asgi.sh
```

Run the complete local workerd path with Node.js 24:

```sh
bash scripts/check_workerd.sh class
bash scripts/check_workerd.sh global
```

Both paths create a TODO and digest a bounded upload through authenticated
HTTP, then read the same identity-scoped data through a stateless MCP
2026-07-28 `tools/call`.

## What is integrated

| Boundary | Verified behavior |
|---|---|
| Application | One `src/app.py`, WHATWG Request/Response, identity-scoped CRUD |
| API contract | Typed UUID and binary-file validation, bounded multipart parsing, OpenAPI 3.1.1, hardened Scalar, pinned TypeScript generation |
| Agent protocol | MCP 2026-07-28 discovery and structured complete result; 2025-11-25 compatibility |
| Identity | Explicit local identity; fail-closed Cloudflare Access JWT/JWKS in production |
| Data | Checked SQL contracts; SQLite on ASGI, D1 binding on Workers |
| Operations | Explicit TODO admin; operator allowlist, owner scope, exact Origin, cursor paging, saved views, bounded CSV, redacted localized history, safe branding |
| Observability | Validated request IDs and compact query-free JSON access events across ASGI and Workers |
| Production | Exact-origin CORS, security headers, 1 MiB body limit, native rate limiting |
| Supply chain | Locked dependencies, dependency audit, workflow audit, pinned actions |

Regenerate and verify the checked artifacts:

```sh
uv run python scripts/export_compatibility.py --check
sh scripts/export_api.sh
git diff --exit-code -- COMPATIBILITY.md compatibility.json openapi.json client/api-types.ts
```

The generated [compatibility table](COMPATIBILITY.md) and
[machine-readable JSON](compatibility.json) come from `uv.lock`,
`golden-app.toml`, and `wrangler.toml`; CI fails when they drift.

## Runtime modes

The reference uses Hayate's default `WorkerEntrypoint` class. This is the
feature-complete mode for HTTP plus named RPC methods and class handlers such
as `scheduled`.

Hayate also exposes an explicit global-handler compatibility mode. It has
slightly less dispatch overhead but is HTTP-only: it must not be presented as
supporting RPC methods or scheduled class handlers. Generate that shape with
`create-hayate --workers-entrypoint global` only when the service contract is
strictly HTTP.

## Routes

- `GET /health` — public liveness.
- `GET /canonicalize` — a WHATWG URL/IDNA contract.
- `GET /whoami` — the current request principal.
- `GET|POST /todos`, `GET|DELETE /todos/:id` — identity-scoped data.
- `POST /uploads` — bounded multipart file streaming with a typed digest response.
- `GET /openapi.json`, `GET /docs` — authenticated schema and docs.
- `POST /mcp` — MCP Streamable HTTP.
- `GET|POST /admin/*` — separately allowlisted operational TODO administration.

## Operations admin

The reference enables create-hayate's opt-in `admin` profile. Local requests
to `/admin` require the `developer@example.com` Cloudflare Access identity;
production uses the placeholder `operator@example.com` until the deployment
owner replaces it. There is no anonymous mode, default superuser, reflected
table access, or generic SQL endpoint.

Records and audit history are scoped to the Access subject. List controls use
bounded checked-SQL search/sort/cursor contracts, static saved views, and a
separately authorized CSV export with hard row and byte ceilings. Mutations
require an exact configured Origin, and persistent audit rows deliberately
omit submitted values. Branding is escaped plain text with contrast-checked
theme tokens and a hashed style CSP; the page includes semantic landmarks,
visible focus, reduced-motion handling, and application-scoped localization.
The reviewed vendored source commits and MIT licenses live under `admin/`.

Run the optional real-browser gate after installing Chromium:

```sh
uv run playwright install chromium
HAYATE_ADMIN_BROWSER_TESTS=1 uv run pytest -m browser -q
```

## Production use

This repository is a reference, not a deploy-with-placeholders artifact.
Complete every item in [PRODUCTION.md](PRODUCTION.md), including replacing
the Access audience/domain, D1 IDs, CORS origins, rate-limit namespaces,
observability policy, and rollout ownership.

The design and trust boundaries are explained in
[ARCHITECTURE.md](ARCHITECTURE.md). Report vulnerabilities according to
[SECURITY.md](SECURITY.md).
