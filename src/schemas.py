"""Typed contracts shared by HTTP, OpenAPI, and MCP."""

from typing import TypedDict
from uuid import UUID

from hayate_openapi import StdlibProvider


class TodoResponse(TypedDict):
    id: UUID
    title: str
    done: bool


class UploadResponse(TypedDict):
    name: str
    type: str
    size: int
    sha256: str


TODO_SCHEMA, _TODO_DEFINITIONS = StdlibProvider().schema(TodoResponse)

TODO_CREATE_SCHEMA = {
    "type": "object",
    "properties": {
        "title": {
            "type": "string",
            "minLength": 1,
            "maxLength": 200,
            "description": "Todo title; surrounding whitespace is removed.",
        },
    },
    "required": ["title"],
    "additionalProperties": False,
}

PRINCIPAL_SCHEMA = {
    "type": "object",
    "properties": {
        "subject": {"type": "string"},
        "email": {"type": ["string", "null"]},
        "credential_type": {"type": "string"},
    },
    "required": ["subject", "email", "credential_type"],
    "additionalProperties": False,
}

__all__ = [
    "PRINCIPAL_SCHEMA",
    "TODO_CREATE_SCHEMA",
    "TODO_SCHEMA",
    "TodoResponse",
    "UploadResponse",
]
