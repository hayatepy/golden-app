import assert from "node:assert/strict";

import { createHayateClient } from "./api-client.js";

const baseUrl = process.env.HAYATE_API_BASE_URL;
assert(baseUrl, "HAYATE_API_BASE_URL is required");

const client = createHayateClient({
  baseUrl,
  headers: {
    "cf-access-authenticated-user-email": "typescript-client@example.com",
  },
});

const createdResponse = await client.createTodo({
  json: { title: "First-party TypeScript client" },
});
assert.equal(createdResponse.status, 201);
const created = await createdResponse.json();
assert.equal(created.title, "First-party TypeScript client");
assert.match(created.id, /^[0-9a-f-]{36}$/u);

const listResponse = await client.listTodos({ query: { limit: 1 } });
assert.equal(listResponse.status, 200);
const todos = await listResponse.json();
assert.deepEqual(todos, [created]);

const getResponse = await client.getTodo({ path: { id: created.id } });
assert.equal(getResponse.status, 200);
assert.deepEqual(await getResponse.json(), created);

const uploadResponse = await client.digestUpload({
  form: {
    file: new File(["first-party typed upload"], "typed-client.txt", {
      type: "text/plain",
    }),
  },
});
assert.equal(uploadResponse.status, 201);
assert.deepEqual(await uploadResponse.json(), {
  name: "typed-client.txt",
  type: "text/plain",
  size: 24,
  sha256: "280e1024b7a58d6f41e141105f4066541d2a64dda0e78cb731a48c71f6e7c126",
});

const deleteResponse = await client.deleteTodo({ path: { id: created.id } });
assert.equal(deleteResponse.status, 204);

const missingResponse = await client.getTodo({ path: { id: created.id } });
assert.equal(missingResponse.status, 404);

process.stdout.write(
  `First-party TypeScript client passed: todo=${created.id} upload=typed-client.txt\n`,
);
