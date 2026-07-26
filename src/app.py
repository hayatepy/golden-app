"""golden-app: one Hayate application core for every supported runtime."""

from hayate import URL, Context, Hayate, HTTPException

from contracts import describe, validated
from generated_features import register_features
from identity import principal, subject
from runtime import LOCAL_ENV
from schemas import PRINCIPAL_SCHEMA, TODO_CREATE_SCHEMA, TODO_SCHEMA
from storage import create_todo, delete_todo, get_todo, list_todos

app = Hayate(env=LOCAL_ENV)


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
@describe(
    summary="List todos",
    response={"type": "array", "items": TODO_SCHEMA},
    operation_id="listTodos",
)
async def todos_index(c: Context):
    return c.json(await list_todos(c, subject(c)))


@app.post("/todos", validated("json", TODO_CREATE_SCHEMA))
@describe(
    summary="Create a todo",
    status=201,
    response=TODO_SCHEMA,
    responses={400: None},
    operation_id="createTodo",
)
async def todos_create(c: Context):
    data = c.req.valid("json")
    if not isinstance(data, dict) or set(data) != {"title"}:
        raise HTTPException(400, title="request body must contain only title")
    title = data.get("title") if isinstance(data, dict) else None
    if not isinstance(title, str) or not title.strip() or len(title) > 200:
        raise HTTPException(400, title="title must be a non-empty string up to 200 characters")
    todo = await create_todo(c, subject(c), title.strip())
    return c.json(todo, status=201)


@app.get("/todos/:id")
@describe(
    summary="Get a todo",
    response=TODO_SCHEMA,
    responses={404: None},
    operation_id="getTodo",
)
async def todos_show(c: Context):
    todo = await get_todo(c, subject(c), c.req.param("id"))
    if todo is None:
        raise HTTPException(404, title="Todo not found")
    return c.json(todo)


@app.delete("/todos/:id")
@describe(summary="Delete a todo", status=204, responses={404: None}, operation_id="deleteTodo")
async def todos_delete(c: Context):
    if not await delete_todo(c, subject(c), c.req.param("id")):
        raise HTTPException(404, title="Todo not found")
    return c.body(None, status=204)


register_features(app)
