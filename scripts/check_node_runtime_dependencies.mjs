import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const packageJson = JSON.parse(await readFile("package.json", "utf8"));
const packageLock = JSON.parse(await readFile("package-lock.json", "utf8"));

assert.equal(packageJson.dependencies, undefined, "package.json must have no runtime dependencies");
assert.equal(
  packageLock.packages[""].dependencies,
  undefined,
  "package-lock.json must have no runtime dependencies",
);

process.stdout.write("Verified zero JavaScript runtime dependencies.\n");
