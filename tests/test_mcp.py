import pytest

from app import app
from tests.helpers import AUTH_HEADERS

MCP_HEADERS = {
    **AUTH_HEADERS,
    "Accept": "application/json, text/event-stream",
    "Content-Type": "application/json",
}
MCP_VERSION = "2026-07-28"
MCP_META = {
    "io.modelcontextprotocol/protocolVersion": MCP_VERSION,
    "io.modelcontextprotocol/clientCapabilities": {},
    "io.modelcontextprotocol/clientInfo": {
        "name": "golden-test",
        "version": "1.0.0",
    },
}


@pytest.mark.asyncio
async def test_mcp_2026_07_28_uses_request_identity_and_application_storage():
    discovered = await app.request(
        "/mcp",
        method="POST",
        headers={
            **MCP_HEADERS,
            "MCP-Protocol-Version": MCP_VERSION,
            "Mcp-Method": "server/discover",
        },
        json={
            "jsonrpc": "2.0",
            "id": 1,
            "method": "server/discover",
            "params": {"_meta": MCP_META},
        },
    )
    assert discovered.status == 200
    assert discovered.headers.get("Mcp-Session-Id") is None
    discovery = (await discovered.json())["result"]
    assert discovery["supportedVersions"] == [MCP_VERSION]
    assert discovery["resultType"] == "complete"
    assert "tools" in discovery["capabilities"]

    listed_tools = await app.request(
        "/mcp",
        method="POST",
        headers={
            **MCP_HEADERS,
            "MCP-Protocol-Version": MCP_VERSION,
            "Mcp-Method": "tools/list",
        },
        json={
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/list",
            "params": {"_meta": MCP_META},
        },
    )
    assert listed_tools.status == 200
    list_result = (await listed_tools.json())["result"]
    assert list_result["resultType"] == "complete"
    tool = list_result["tools"][0]
    todo_schema = tool["outputSchema"]["properties"]["todos"]["items"]
    assert todo_schema["properties"]["id"] == {"type": "string", "format": "uuid"}

    created = await app.request(
        "/todos",
        method="POST",
        headers=AUTH_HEADERS,
        json={"title": "visible through MCP"},
    )
    assert created.status == 201

    called = await app.request(
        "/mcp",
        method="POST",
        headers={
            **MCP_HEADERS,
            "MCP-Protocol-Version": MCP_VERSION,
            "Mcp-Method": "tools/call",
            "Mcp-Name": "list_todos",
        },
        json={
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {
                "_meta": MCP_META,
                "name": "list_todos",
                "arguments": {},
            },
        },
    )
    assert called.status == 200
    call_result = (await called.json())["result"]
    assert call_result["resultType"] == "complete"
    structured = call_result["structuredContent"]
    assert structured["subject"]
    assert any(todo["title"] == "visible through MCP" for todo in structured["todos"])


@pytest.mark.asyncio
async def test_mcp_2025_11_25_client_remains_compatible():
    initialized = await app.request(
        "/mcp",
        method="POST",
        headers=MCP_HEADERS,
        json={
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2025-11-25",
                "capabilities": {},
                "clientInfo": {"name": "golden-legacy-test", "version": "1.0.0"},
            },
        },
    )

    assert initialized.status == 200
    assert (await initialized.json())["result"]["protocolVersion"] == "2025-11-25"
