"""Explicit local defaults; Workers replaces them with platform bindings."""

from types import SimpleNamespace

LOCAL_ENV = SimpleNamespace(
    ENVIRONMENT="local",
    APP_VERSION="0.1.0",
    CORS_ORIGINS="http://localhost:3000",
    ADMIN_EMAILS="developer@example.com",
)
