"""golden-app: one Hayate application core for every supported runtime."""

from hashlib import sha256
from typing import Annotated
from uuid import UUID

from hayate import URL, Context, File, FormDataLimits, Hayate, HTTPException
from hayate_openapi import Constraints, Form, Path, Query, StdlibProvider, endpoint

from contracts import describe, validated
from generated_features import register_features
from identity import principal, subject
from runtime import LOCAL_ENV
from schemas import PRINCIPAL_SCHEMA, TODO_CREATE_SCHEMA, TodoResponse, UploadResponse
from storage import Todo, create_todo, delete_todo, get_todo, list_todos

app = Hayate(env=LOCAL_ENV)
_PROVIDERS = [StdlibProvider()]
_UPLOAD_LIMITS = FormDataLimits(
    max_body_bytes=(1024 * 1024) + (16 * 1024),
    max_file_bytes=512 * 1024,
    max_field_bytes=1024,
    max_parts=1,
    max_header_bytes=8 * 1024,
    file_memory_bytes=64 * 1024,
)


def _todo_response(todo: Todo) -> TodoResponse:
    return {
        "id": UUID(todo["id"]),
        "title": todo["title"],
        "done": todo["done"],
    }


@app.get("/health")
@describe(
    summary="Health check",
    response={
        "type": "object",
        "properties": {"status": {"type": "string", "const": "ok"}},
        "required": ["status"],
        "additionalProperties": False,
    },
    operation_id="health",
    security=[],
)
async def health(c: Context):
    return c.json({"status": "ok"})


@app.get("/canonicalize")
@describe(
    summary="Canonicalize an international hostname",
    response={
        "type": "object",
        "properties": {"hostname": {"type": "string"}},
        "required": ["hostname"],
        "additionalProperties": False,
    },
    operation_id="canonicalize",
)
async def canonicalize(c: Context):
    return c.json({"hostname": URL("https://日本語.example/").hostname})


@app.get("/whoami")
@describe(summary="Current request identity", response=PRINCIPAL_SCHEMA, operation_id="whoami")
async def whoami(c: Context):
    return c.json(principal(c))


@app.get("/todos")
@endpoint(
    summary="List todos",
    operation_id="listTodos",
    providers=_PROVIDERS,
)
async def todos_index(
    c: Context,
    limit: Annotated[int, Constraints(ge=1, le=100), Query()] = 25,
) -> list[TodoResponse]:
    todos = await list_todos(c, subject(c))
    return [_todo_response(todo) for todo in todos[:limit]]


@app.post("/todos", validated("json", TODO_CREATE_SCHEMA))
@endpoint(
    summary="Create a todo",
    status=201,
    responses={400: None},
    operation_id="createTodo",
    providers=_PROVIDERS,
)
async def todos_create(c: Context) -> TodoResponse:
    data = c.req.valid("json")
    if not isinstance(data, dict) or set(data) != {"title"}:
        raise HTTPException(400, title="request body must contain only title")
    title = data.get("title") if isinstance(data, dict) else None
    if not isinstance(title, str) or not title.strip() or len(title) > 200:
        raise HTTPException(400, title="title must be a non-empty string up to 200 characters")
    todo = await create_todo(c, subject(c), title.strip())
    return _todo_response(todo)


@app.get("/todos/:id")
@endpoint(
    summary="Get a todo",
    responses={404: None},
    operation_id="getTodo",
    providers=_PROVIDERS,
)
async def todos_show(
    c: Context,
    todo_id: Annotated[UUID, Path(alias="id")],
) -> TodoResponse:
    todo = await get_todo(c, subject(c), str(todo_id))
    if todo is None:
        raise HTTPException(404, title="Todo not found")
    return _todo_response(todo)


@app.delete("/todos/:id")
@endpoint(
    summary="Delete a todo",
    status=204,
    responses={404: None},
    operation_id="deleteTodo",
    providers=_PROVIDERS,
)
async def todos_delete(
    c: Context,
    todo_id: Annotated[UUID, Path(alias="id")],
) -> None:
    if not await delete_todo(c, subject(c), str(todo_id)):
        raise HTTPException(404, title="Todo not found")


@app.post("/uploads")
@endpoint(
    summary="Digest a bounded uploaded file",
    status=201,
    operation_id="digestUpload",
    providers=_PROVIDERS,
)
async def uploads_create(
    file: Annotated[
        File,
        Form(media_type="multipart/form-data", limits=_UPLOAD_LIMITS),
    ],
) -> UploadResponse:
    digest = sha256()
    async for chunk in file.stream():
        digest.update(chunk)
    return {
        "name": file.name,
        "type": file.type,
        "size": file.size,
        "sha256": digest.hexdigest(),
    }


register_features(app)
