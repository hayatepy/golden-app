import pytest

from app import app
from tests.helpers import AUTH_HEADERS


def _multipart_file(payload: bytes, *, boundary: str = "golden-upload") -> bytes:
    return (
        (
            f"--{boundary}\r\n"
            'Content-Disposition: form-data; name="file"; filename="golden.txt"\r\n'
            "Content-Type: text/plain\r\n\r\n"
        ).encode()
        + payload
        + f"\r\n--{boundary}--\r\n".encode()
    )


@pytest.mark.asyncio
async def test_health_and_identity():
    health = await app.request("/health")
    assert health.status == 200
    assert await health.json() == {"status": "ok"}

    identity = await app.request("/whoami", headers=AUTH_HEADERS)
    assert identity.status == 200
    principal = await identity.json()
    assert isinstance(principal["subject"], str)


@pytest.mark.asyncio
async def test_todo_crud_is_scoped_to_the_request_identity():
    created = await app.request(
        "/todos",
        method="POST",
        headers=AUTH_HEADERS,
        json={"title": "ship the production path"},
    )
    assert created.status == 201
    todo = await created.json()

    rejected = await app.request(
        "/todos",
        method="POST",
        headers=AUTH_HEADERS,
        json={"title": "not in the contract", "owner": "other"},
    )
    assert rejected.status == 400

    invalid_path = await app.request("/todos/not-a-uuid", headers=AUTH_HEADERS)
    assert invalid_path.status == 400

    listed = await app.request("/todos", headers=AUTH_HEADERS)
    assert listed.status == 200
    assert todo in await listed.json()

    invalid_limit = await app.request("/todos?limit=101", headers=AUTH_HEADERS)
    assert invalid_limit.status == 400

    shown = await app.request(f"/todos/{todo['id']}", headers=AUTH_HEADERS)
    assert shown.status == 200
    assert await shown.json() == todo

    deleted = await app.request(
        f"/todos/{todo['id']}",
        method="DELETE",
        headers=AUTH_HEADERS,
    )
    assert deleted.status == 204

    missing = await app.request(f"/todos/{todo['id']}", headers=AUTH_HEADERS)
    assert missing.status == 404


@pytest.mark.asyncio
async def test_typed_upload_is_bounded_and_digest_checked():
    payload = b"portable typed upload"
    boundary = "golden-upload"
    uploaded = await app.request(
        "/uploads",
        method="POST",
        headers={
            **AUTH_HEADERS,
            "content-type": f"multipart/form-data; boundary={boundary}",
        },
        body=_multipart_file(payload, boundary=boundary),
    )
    assert uploaded.status == 201
    assert await uploaded.json() == {
        "name": "golden.txt",
        "type": "text/plain",
        "size": len(payload),
        "sha256": "f173d53139adf5d1395cc0c4e3ff2334547b1482736b056c157b52ae951ad267",
    }

    too_large = b"x" * ((512 * 1024) + 1)
    rejected = await app.request(
        "/uploads",
        method="POST",
        headers={
            **AUTH_HEADERS,
            "content-type": f"multipart/form-data; boundary={boundary}",
        },
        body=_multipart_file(too_large, boundary=boundary),
    )
    assert rejected.status == 413
    problem = await rejected.json()
    assert problem["title"] == "Payload Too Large"
