"""HTTP-only Cloudflare global-handler entry for compatibility verification."""

from hayate.adapters.workers import to_workers_global

from app import app

on_fetch = to_workers_global(app)
