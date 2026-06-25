import assert from "node:assert/strict";
import test from "node:test";

test("top-level node:test works", () => {
  assert.deepEqual(
    ["node", "test", "runner"].filter((word) => word.length > 3),
    ["node", "test", "runner"],
  );
});
