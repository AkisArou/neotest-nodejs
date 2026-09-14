local adapter = require("neotest-nodejs")({ nodeCommand = "node" })
local async = require("nio").tests
local util = require("neotest-nodejs.util")

require("neotest-nodejs.test-utils").prepare_vim_treesitter()

describe("adapter.is_test_file", function()
  async.it("matches node test files", function()
    assert.True(adapter.is_test_file("./spec/tests/basic.test.ts"))
    assert.True(adapter.is_test_file("./spec/tests/__tests__/some.test.ts"))
  end)

  async.it("does not match nil or plain js/ts files", function()
    assert.False(adapter.is_test_file(nil))
    assert.False(adapter.is_test_file("./index.js"))
    assert.False(adapter.is_test_file("./index.ts"))
  end)

  async.it("matches all supported extensions", function()
    for _, extension in ipairs(util.getDefaultTestExtensions()) do
      local path = "./spec/file." .. extension[1] .. "." .. extension[2]
      local result = adapter.is_test_file(path)

      if not result then
        vim.print(path)
      end

      assert.True(result)
    end
  end)

  describe("Vitest imports", function()
    local directory
    before_each(function()
      directory = vim.fn.tempname()
      vim.fn.mkdir(directory, "p")
      vim.fn.writefile({ '{"devDependencies":{"vitest":"^5.0.0"}}' }, directory .. "/package.json")
    end)
    after_each(function()
      vim.fn.delete(directory, "rf")
    end)
    local function write_test(name, content)
      local path = directory .. "/" .. name
      vim.fn.writefile(vim.split(content, "\n", { plain = true }), path)
      return path
    end
    async.it("excludes named, namespace, side-effect, and multiline Vitest imports", function()
      for _, content in ipairs({
        [[import { describe, it } from 'vitest';]],
        [[import * as vitest from "vitest";]],
        [[import 'vitest';]],
        [[import {} from 'vitest';]],
        [[import {
          it as test,
        } from 'vitest';]],
      }) do
        assert.False(adapter.is_test_file(write_test("vitest.spec.ts", content)))
      end
    end)
    async.it("excludes require and dynamic import of Vitest", function()
      assert.False(
        adapter.is_test_file(write_test("vitest.test.js", [[const { it } = require("vitest");]]))
      )
      assert.False(
        adapter.is_test_file(
          write_test("vitest.test.ts", [[const { it } = await import("vitest");]])
        )
      )
    end)
    async.it("keeps native Node tests alongside Vitest tests", function()
      local native = write_test("native.test.ts", [[import { test } from 'node:test';]])
      local vitest = write_test("vitest.test.ts", [[import { test } from 'vitest';]])
      assert.True(adapter.is_test_file(native))
      assert.False(adapter.is_test_file(vitest))
    end)
    async.it("ignores Vitest mentions in comments, strings, and unrelated calls", function()
      local path = write_test(
        "native.test.js",
        [=[
        // import { it } from 'vitest';
        /* const { it } = require('vitest'); */
        const example = "import { it } from 'vitest';";
        const label = lookup('vitest');
        import { test } from 'node:test';
      ]=]
      )
      assert.True(adapter.is_test_file(path))
    end)
    async.it("keeps type-only Vitest imports", function()
      assert.True(
        adapter.is_test_file(write_test("native.test.ts", [[import type { Test } from 'vitest';]]))
      )
    end)
    async.it("keeps inline type-only imports but excludes mixed value imports", function()
      assert.True(
        adapter.is_test_file(write_test("native.test.ts", [[import { type Test } from 'vitest';]]))
      )
      assert.False(
        adapter.is_test_file(
          write_test("vitest.test.ts", [[import { type Test, it } from 'vitest';]])
        )
      )
    end)
    async.it("keeps the filename fallback for other languages", function()
      vim.fn.mkdir(directory .. "/__tests__", "p")
      local path = write_test("__tests__/example.lua", [[local example = "vitest"]])
      assert.True(adapter.is_test_file(path))
    end)
    async.it("allows isTestFile to override Vitest exclusion", function()
      local custom = require("neotest-nodejs")({
        isTestFile = function()
          return true
        end,
      })
      assert.True(
        custom.is_test_file(write_test("vitest.test.ts", [[import { it } from 'vitest';]]))
      )
    end)
  end)

  async.it("uses isTestFile option if given", function()
    local _adapter = require("neotest-nodejs")({
      nodeCommand = "node",
      isTestFile = function(file_path)
        if not file_path then
          return false
        end

        return vim.fn.fnamemodify(file_path, ":e:e") == "testy.js"
      end,
    })

    assert.False(_adapter.is_test_file(nil))
    assert.False(_adapter.is_test_file("./spec/tests/basic.test.ts"))
    assert.False(_adapter.is_test_file("./spec/tests/__tests__/some.test.ts"))
    assert.False(_adapter.is_test_file("./spec/tests/test.test.ts"))
    assert.True(_adapter.is_test_file("./spec/test.testy.js"))
  end)
end)
