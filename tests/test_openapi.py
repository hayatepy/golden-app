import pytest

from app import app
from tests.helpers import AUTH_HEADERS


@pytest.mark.asyncio
async def test_openapi_and_scalar_come_from_the_registered_routes():
    response = await app.request("/openapi.json", headers=AUTH_HEADERS)
    assert response.status == 200
    document = await response.json()
    assert document["openapi"] == "3.1.1"
    assert "/todos" in document["paths"]
    create = document["paths"]["/todos"]["post"]
    assert create["operationId"] == "createTodo"
    request_schema = create["requestBody"]["content"]["application/json"]["schema"]
    assert request_schema["required"] == ["title"]
    assert request_schema["properties"]["title"]["maxLength"] == 200
    create_response = create["responses"]["201"]["content"]["application/json"]["schema"]
    assert create_response["properties"]["id"] == {"type": "string", "format": "uuid"}
    assert set(create_response["required"]) == {"id", "title", "done"}
    list_response = document["paths"]["/todos"]["get"]["responses"]["200"]["content"][
        "application/json"
    ]["schema"]
    assert list_response["type"] == "array"
    assert list_response["items"]["properties"]["id"] == {
        "type": "string",
        "format": "uuid",
    }
    path_parameter = document["paths"]["/todos/{id}"]["get"]["parameters"][0]
    assert path_parameter["name"] == "id"
    assert path_parameter["in"] == "path"
    assert path_parameter["required"] is True
    assert path_parameter["schema"] == {"type": "string", "format": "uuid"}
    assert document["security"] == [{"CloudflareAccess": []}]
    assert document["components"]["securitySchemes"]["CloudflareAccess"] == {
        "type": "apiKey",
        "in": "cookie",
        "name": "CF_Authorization",
        "description": (
            "Cloudflare Access application token. Browser sessions send this "
            "cookie through the Access proxy; service clients authenticate to "
            "Access before the request reaches this application."
        ),
    }
    assert document["paths"]["/health"]["get"]["security"] == []

    docs = await app.request("/docs", headers=AUTH_HEADERS)
    assert docs.status == 200
    assert "content-security-policy" in docs.headers
