# Hayate production golden app

[![CI](https://github.com/hayatepy/golden-app/actions/workflows/ci.yml/badge.svg)](https://github.com/hayatepy/golden-app/actions/workflows/ci.yml)

> **Hayate ecosystem:** [Start here](https://github.com/hayatepy/.github/blob/main/docs/START.md)
> · [Production path](https://github.com/hayatepy/.github/blob/main/docs/PRODUCTION.md)
> · [Tested compatibility](https://github.com/hayatepy/.github/blob/main/docs/COMPATIBILITY.md)

This is the public, executable reference for the
[Hayate ecosystem](https://github.com/hayatepy). It is generated from
`create-hayate==0.4.0` and contains one application core that runs unchanged
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
suite covers identity-scoped CRUD, OpenAPI, MCP, production middleware, SQL
contracts, and restart-safe local database bootstrap.

Run the complete ASGI path:

```sh
bash scripts/check_asgi.sh
```

Run the complete local workerd path with Node.js 24:

```sh
bash scripts/check_workerd.sh class
bash scripts/check_workerd.sh global
```

Both paths create a TODO through authenticated HTTP and read the same
identity-scoped data through an MCP 2025-11-25 `tools/call`.

## What is integrated

| Boundary | Verified behavior |
|---|---|
| Application | One `src/app.py`, WHATWG Request/Response, identity-scoped CRUD |
| API contract | OpenAPI 3.1.1, hardened Scalar, pinned TypeScript generation |
| Agent protocol | MCP 2025-11-25 initialize and structured tool result |
| Identity | Explicit local identity; fail-closed Cloudflare Access JWT/JWKS in production |
| Data | Checked SQL contracts; SQLite on ASGI, D1 binding on Workers |
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
- `GET /openapi.json`, `GET /docs` — authenticated schema and docs.
- `POST /mcp` — MCP Streamable HTTP.

## Production use

This repository is a reference, not a deploy-with-placeholders artifact.
Complete every item in [PRODUCTION.md](PRODUCTION.md), including replacing
the Access audience/domain, D1 IDs, CORS origins, rate-limit namespaces,
observability policy, and rollout ownership.

The design and trust boundaries are explained in
[ARCHITECTURE.md](ARCHITECTURE.md). Report vulnerabilities according to
[SECURITY.md](SECURITY.md).
