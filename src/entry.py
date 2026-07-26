"""Cloudflare Python Workers entry: the same app, exposed through the adapter."""

from hayate.adapters.workers import to_workers

from app import app

Default = to_workers(app)
