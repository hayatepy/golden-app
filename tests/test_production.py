import json
import re
import tomllib
from pathlib import Path
from types import SimpleNamespace

import pytest
from hayate import HTTPException
from hayate.middleware import current_request_id

from app import app
from feature_observability import request_log
from feature_production import _platform_controls
from release_metadata import release_metadata
from tests.helpers import AUTH_HEADERS


def test_application_version_sources_do_not_drift():
    project = tomllib.loads(Path("pyproject.toml").read_text(encoding="utf-8"))
    expected = project["project"]["version"]

    for config_path in ("wrangler.toml", "wrangler.global.toml"):
        wrangler = tomllib.loads(Path(config_path).read_text(encoding="utf-8"))
        assert wrangler["vars"]["APP_VERSION"] == expected
        assert wrangler["env"]["production"]["vars"]["APP_VERSION"] == expected
        assert wrangler["version_metadata"]["binding"] == "CF_VERSION_METADATA"
        assert wrangler["env"]["production"]["version_metadata"]["binding"] == (
            "CF_VERSION_METADATA"
        )
    assert expected == app._env.APP_VERSION


@pytest.mark.asyncio
async def test_production_headers_and_local_cors_policy():
    response = await app.request(
        "/whoami",
        headers={**AUTH_HEADERS, "Origin": "http://localhost:3000"},
    )
    assert response.status == 200
    assert response.headers.get("access-control-allow-origin") == "http://localhost:3000"
    assert response.headers.get("x-content-type-options") == "nosniff"
    assert response.headers.get("referrer-policy") == "no-referrer"
    assert "default-src 'none'" in response.headers.get("content-security-policy")
    assert response.headers.get("x-app-version") == "0.1.0"
    assert response.headers.get("x-worker-version") is None
    exposed = response.headers.get("access-control-expose-headers")
    assert exposed is not None
    assert {value.strip() for value in exposed.split(",")} == {
        "x-app-version",
        "x-request-id",
        "x-worker-version",
    }


@pytest.mark.asyncio
async def test_unlisted_cors_origin_is_not_reflected():
    response = await app.request(
        "/whoami",
        headers={**AUTH_HEADERS, "Origin": "https://attacker.example"},
    )
    assert response.status == 200
    assert response.headers.get("access-control-allow-origin") is None


@pytest.mark.asyncio
async def test_production_health_and_cors_preflight_do_not_require_app_identity(monkeypatch):
    monkeypatch.setattr(
        app,
        "_env",
        SimpleNamespace(
            ENVIRONMENT="production",
            APP_VERSION="2026.07.0",
            CF_VERSION_METADATA=SimpleNamespace(id="worker-version-123"),
            CORS_ORIGINS="https://app.example.com",
        ),
    )

    health = await app.request("/health")
    assert health.status == 200
    assert health.headers.get("x-app-version") == "2026.07.0"
    assert health.headers.get("x-worker-version") == "worker-version-123"

    preflight = await app.request(
        "/todos",
        method="OPTIONS",
        headers={
            "Origin": "https://app.example.com",
            "Access-Control-Request-Method": "GET",
        },
    )
    assert preflight.status == 204
    assert preflight.headers.get("access-control-allow-origin") == "https://app.example.com"


def test_release_metadata_accepts_mapping_and_attribute_bindings():
    assert release_metadata(
        {
            "APP_VERSION": "2026.07.0",
            "CF_VERSION_METADATA": {
                "id": "mapping-version",
                "tag": "not-exposed",
            },
        }
    ) == ("2026.07.0", "mapping-version")
    assert release_metadata(
        SimpleNamespace(
            APP_VERSION="2026.07.1",
            CF_VERSION_METADATA=SimpleNamespace(id="attribute-version"),
        )
    ) == ("2026.07.1", "attribute-version")


def test_release_metadata_rejects_unbounded_or_header_unsafe_values():
    assert release_metadata(
        SimpleNamespace(
            APP_VERSION="2026.07.0\r\nx-injected: yes",
            CF_VERSION_METADATA=SimpleNamespace(id="x" * 129),
        )
    ) == (None, None)


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("env", "title"),
    [
        (
            SimpleNamespace(
                ENVIRONMENT="production",
                CF_VERSION_METADATA=SimpleNamespace(id="worker-version-123"),
            ),
            "Application version is not configured",
        ),
        (
            SimpleNamespace(
                ENVIRONMENT="production",
                APP_VERSION="2026.07.0",
            ),
            "Worker version metadata is not configured",
        ),
    ],
)
async def test_protected_production_requests_fail_closed_without_release_metadata(env, title):
    context = SimpleNamespace(
        req=SimpleNamespace(
            method="GET",
            url=SimpleNamespace(pathname="/todos"),
        ),
        env=env,
    )
    with pytest.raises(HTTPException) as captured:
        await _platform_controls(context, pytest.fail)
    assert captured.value.status == 503
    assert captured.value.title == title


@pytest.mark.asyncio
async def test_access_logs_are_correlated_structured_and_query_free(
    caplog: pytest.LogCaptureFixture,
):
    request_log.addHandler(caplog.handler)
    try:
        response = await app.request(
            "/whoami?access_token=must-not-be-logged",
            headers={
                **AUTH_HEADERS,
                "x-request-id": "golden:request-42",
            },
        )
    finally:
        request_log.removeHandler(caplog.handler)

    assert response.status == 200
    assert response.headers.get("x-request-id") == "golden:request-42"
    assert response.headers.get("x-app-version") == "0.1.0"
    record = next(record for record in caplog.records if record.name == request_log.name)
    event = json.loads(record.getMessage())
    duration_ms = event.pop("duration_ms")
    assert event == {
        "event": "http_request",
        "method": "GET",
        "path": "/whoami",
        "status": 200,
        "request_id": "golden:request-42",
    }
    assert isinstance(duration_ms, float)
    assert duration_ms >= 0
    assert record.__dict__["request_id"] == "golden:request-42"
    assert "must-not-be-logged" not in record.getMessage()
    assert current_request_id() is None


@pytest.mark.asyncio
async def test_access_logs_cover_replaced_ids_not_found_and_handled_errors(
    caplog: pytest.LogCaptureFixture,
    monkeypatch: pytest.MonkeyPatch,
):
    request_log.addHandler(caplog.handler)
    try:
        unauthorized = await app.request(
            "/whoami",
            headers={"x-request-id": "golden:unauthorized"},
        )
        missing = await app.request(
            "/missing?secret=must-not-be-logged",
            headers={
                **AUTH_HEADERS,
                "x-request-id": "invalid request id",
            },
        )
        monkeypatch.setattr(
            app,
            "_env",
            SimpleNamespace(ENVIRONMENT="production"),
        )
        failed = await app.request(
            "/whoami",
            headers={
                **AUTH_HEADERS,
                "x-request-id": "golden:configuration-error",
            },
        )
    finally:
        request_log.removeHandler(caplog.handler)

    assert unauthorized.status == 401
    assert unauthorized.headers.get("x-request-id") == "golden:unauthorized"
    assert unauthorized.headers.get("x-app-version") == "0.1.0"
    assert missing.status == 404
    assert missing.headers.get("x-app-version") == "0.1.0"
    replacement = missing.headers.get("x-request-id")
    assert replacement is not None
    assert replacement != "invalid request id"
    assert re.fullmatch(r"[A-Za-z0-9._:+-]+", replacement)
    assert failed.status == 500
    assert failed.headers.get("x-request-id") == "golden:configuration-error"
    assert failed.headers.get("x-app-version") is None

    events = [
        json.loads(record.getMessage())
        for record in caplog.records
        if record.name == request_log.name
    ]
    assert [(event["path"], event["status"], event["request_id"]) for event in events] == [
        ("/whoami", 401, "golden:unauthorized"),
        ("/missing", 404, replacement),
        ("/whoami", 500, "golden:configuration-error"),
    ]
    assert all("must-not-be-logged" not in json.dumps(event) for event in events)
    assert current_request_id() is None
