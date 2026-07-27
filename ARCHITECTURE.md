# Architecture and trust boundaries

## Derivation

The repository is synchronized with public `create-hayate==0.6.0` using the
Workers production preset. Future changes should remain expressible as either
an upstream scaffold improvement or a clearly documented reference-only
addition. `golden-app.toml` records the generator and protocol lines.

## One core, two adapters

`src/app.py` owns routes and application behavior. It does not import ASGI,
Cloudflare Workers, SQLite, or D1 adapters directly.

```text
                 ┌───────────────────────┐
HTTP / MCP ─────▶│ src/app.py + features│
                 └───────────┬───────────┘
                             │ request Context
               ┌─────────────┴─────────────┐
               │                           │
        ASGI + SQLite              workerd + D1
```

Runtime resources enter through the Hayate request context. `src/storage.py`
selects D1 only when the `DB` binding is present; otherwise it uses local
SQLite. HTTP and MCP call that same storage module with the same principal.

`schemas.TodoResponse` is the source for HTTP response validation and UUID
serialization, OpenAPI response schemas, and the MCP output schema. The
explicit create-body JSON Schema remains only for string-length constraints
that plain standard-library types do not express.

## Identity

Local mode trusts `Cf-Access-Authenticated-User-Email` only because
`.dev.vars` explicitly sets `ENVIRONMENT=local`. `.dev.vars` is ignored and
must be created from the public example after clone.

Every deploy configuration defaults to `ENVIRONMENT=production`. Production
verifies Cloudflare Access RS256 signatures through the tenancy JWKS and
checks token type, issuer, audience, issued/not-before/expiry times, subject,
and email. Protected requests fail closed when configuration is absent.

## Public and protected paths

`/health` is the only application-public route. CORS preflights bypass
application identity and rate limiting but still pass through the exact-origin
CORS policy. API data, schema/docs, and MCP require identity.

## Workers entrypoint

The default class entrypoint preserves the full Workers contract, including
named RPC methods and class handlers. The optional global entrypoint is an
explicit HTTP-only compatibility mode. The reference app deliberately keeps
the class default.

## Data and migrations

SQL files are the source of truth. `hayate-sql` compiles four explicit
cardinality contracts against the complete D1/SQLite migration history and
generates `src/queries.py`. Production migrations are always a separate
operator action. Local bootstrap is restart-safe but never implies automatic
production migration.

## Evidence

- Direct tests execute application contracts without a server.
- ASGI E2E starts a real Uvicorn process after direct tests, exercising the
  restart boundary and SQLite persistence.
- workerd E2E applies a real local D1 migration and uses the real Workers
  adapter.
- OpenAPI JSON, TypeScript types, compatibility Markdown, and compatibility
  JSON are checked artifacts regenerated in CI.
