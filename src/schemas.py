"""JSON Schema contracts shared by HTTP, OpenAPI, and MCP."""

TODO_SCHEMA = {
    "type": "object",
    "properties": {
        "id": {"type": "string"},
        "title": {"type": "string"},
        "done": {"type": "boolean"},
    },
    "required": ["id", "title", "done"],
    "additionalProperties": False,
}

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

TODO_ID_SCHEMA = {
    "type": "object",
    "properties": {"id": {"type": "string", "format": "uuid"}},
    "required": ["id"],
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

__all__ = ["PRINCIPAL_SCHEMA", "TODO_CREATE_SCHEMA", "TODO_ID_SCHEMA", "TODO_SCHEMA"]
