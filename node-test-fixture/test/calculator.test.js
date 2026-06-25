import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { add, divide, doubleLater } from "../src/calculator.js";

describe("calculator", () => {
  describe("add", () => {
    test("adds positive numbers", () => {
      assert.equal(add(2, 3), 5);
    });

    test("adds negative numbers", () => {
      assert.equal(add(-2, -3), -5);
    });
  });

  describe("divide", () => {
    test("divides two numbers", () => {
      assert.equal(divide(8, 2), 4);
    });

    test("throws when dividing by zero", () => {
      assert.throws(() => divide(8, 0), /Cannot divide by zero/);
    });
  });

  describe("async work", () => {
    test("resolves doubled value", async () => {
      assert.equal(await doubleLater(21), 42);
    });
  });

  test("skipped example", { skip: true }, () => {
    assert.fail("This skipped test should not run");
  });
});
