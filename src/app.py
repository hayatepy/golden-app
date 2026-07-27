"""golden-app: one Hayate application core for every supported runtime."""

from typing import Annotated
from uuid import UUID

from hayate import URL, Context, Hayate, HTTPException
from hayate_openapi import Path, StdlibProvider, endpoint

from contracts import describe, validated
from generated_features import register_features
from identity import principal, subject
from runtime import LOCAL_ENV
from schemas import PRINCIPAL_SCHEMA, TODO_CREATE_SCHEMA, TodoResponse
from storage import Todo, create_todo, delete_todo, get_todo, list_todos

app = Hayate(env=LOCAL_ENV)
_PROVIDERS = [StdlibProvider()]


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
async def todos_index(c: Context) -> list[TodoResponse]:
    return [_todo_response(todo) for todo in await list_todos(c, subject(c))]


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


register_features(app)
