local async = require("neotest.async").tests
local lib = require("neotest.lib")
local logger = require("neotest.logging")
local stub = require("luassert.stub")
local types = require("neotest.types")

describe("adapter.results", function()
  local spec
  local strategy_result = {
    output = "node spec reporter output",
  }

  local path = "/tmp/node.test.js"

  local function event(type, data)
    return vim.json.encode({ type = type, data = data })
  end

  local function node_output(lines)
    return table.concat(lines, "\n") .. "\n"
  end

  before_each(function()
    spec = {
      context = {
        results_path = "test_output.ndjson",
        file = path,
        stop_stream = function() end,
      },
    }

    stub(logger, "error")
  end)

  after_each(function()
    ---@diagnostic disable-next-line: undefined-field
    logger.error:revert()
  end)

  async.it("creates neotest results from node test events", function()
    package.loaded["neotest-nodejs"] = nil
    local adapter = require("neotest-nodejs")({})
    local output = node_output({
      event("test:start", {
        nesting = 0,
        name = "calculator",
        line = 3,
        column = 1,
        file = path,
      }),
      event("test:start", {
        nesting = 1,
        name = "add",
        line = 4,
        column = 3,
        file = path,
      }),
      event("test:pass", {
        nesting = 2,
        name = "adds numbers",
        line = 5,
        column = 5,
        file = path,
        details = { type = "test" },
      }),
      event("test:pass", {
        nesting = 0,
        name = "calculator",
        line = 3,
        column = 1,
        file = path,
        details = { type = "suite" },
      }),
    })

    stub(lib.files, "read", output)

    local results = adapter.results(spec, strategy_result, {
      data = function()
        return { path = path }
      end,
    })

    assert.are.same({
      [path .. "::calculator::add::adds numbers"] = {
        status = types.ResultStatus.passed,
        short = "adds numbers: passed",
        output = strategy_result.output,
        location = {
          line = 5,
          column = 5,
        },
      },
    }, results)

    ---@diagnostic disable-next-line: undefined-field
    lib.files.read:revert()
  end)

  async.it("creates failed results with errors", function()
    package.loaded["neotest-nodejs"] = nil
    local adapter = require("neotest-nodejs")({})
    local output = node_output({
      event("test:fail", {
        nesting = 0,
        name = "fails",
        line = 9,
        column = 3,
        file = path,
        details = {
          type = "test",
          error = {
            cause = {
              message = "expected values to be equal",
            },
          },
        },
      }),
    })

    stub(lib.files, "read", output)

    local results = adapter.results(spec, strategy_result, {
      data = function()
        return { path = path }
      end,
    })

    assert.are.same(types.ResultStatus.failed, results[path .. "::fails"].status)
    assert.are.same({
      {
        line = 8,
        column = 2,
        message = "expected values to be equal",
      },
    }, results[path .. "::fails"].errors)

    ---@diagnostic disable-next-line: undefined-field
    lib.files.read:revert()
  end)

  async.it("creates skipped results", function()
    package.loaded["neotest-nodejs"] = nil
    local adapter = require("neotest-nodejs")({})
    local output = node_output({
      event("test:pass", {
        nesting = 0,
        name = "skipped test",
        line = 12,
        column = 1,
        file = path,
        skip = true,
        details = { type = "test" },
      }),
    })

    stub(lib.files, "read", output)

    local results = adapter.results(spec, strategy_result, {
      data = function()
        return { path = path }
      end,
    })

    assert.are.same(types.ResultStatus.skipped, results[path .. "::skipped test"].status)

    ---@diagnostic disable-next-line: undefined-field
    lib.files.read:revert()
  end)

  async.it("creates todo results as skipped", function()
    package.loaded["neotest-nodejs"] = nil
    local adapter = require("neotest-nodejs")({})
    local output = node_output({
      event("test:pass", {
        nesting = 0,
        name = "todo test",
        line = 14,
        column = 1,
        file = path,
        todo = true,
        details = { type = "test" },
      }),
    })

    stub(lib.files, "read", output)

    local results = adapter.results(spec, strategy_result, {
      data = function()
        return { path = path }
      end,
    })

    assert.are.same(types.ResultStatus.skipped, results[path .. "::todo test"].status)

    ---@diagnostic disable-next-line: undefined-field
    lib.files.read:revert()
  end)

  async.it("adds diagnostics to matching test output", function()
    package.loaded["neotest-nodejs"] = nil
    local adapter = require("neotest-nodejs")({})
    local output = node_output({
      event("test:start", {
        nesting = 0,
        name = "diagnostic test",
        line = 16,
        column = 1,
        file = path,
      }),
      event("test:pass", {
        nesting = 0,
        name = "diagnostic test",
        line = 16,
        column = 1,
        file = path,
        details = { type = "test" },
      }),
      event("test:diagnostic", {
        nesting = 0,
        message = "created useful diagnostic",
        level = "info",
        line = 16,
        column = 1,
        file = path,
      }),
    })

    stub(lib.files, "read", output)

    local results = adapter.results(spec, strategy_result, {
      data = function()
        return { path = path }
      end,
    })

    assert.matches(
      "%[diagnostic%] created useful diagnostic",
      results[path .. "::diagnostic test"].short
    )

    ---@diagnostic disable-next-line: undefined-field
    lib.files.read:revert()
  end)

  async.it("adds stdout and stderr to file results", function()
    package.loaded["neotest-nodejs"] = nil
    local adapter = require("neotest-nodejs")({})
    local output = node_output({
      event("test:stdout", {
        file = path,
        message = "hello stdout\n",
      }),
      event("test:stderr", {
        file = path,
        message = "hello stderr\n",
      }),
      event("test:pass", {
        nesting = 0,
        name = "logs output",
        line = 18,
        column = 1,
        file = path,
        details = { type = "test" },
      }),
    })

    stub(lib.files, "read", output)

    local results = adapter.results(spec, strategy_result, {
      data = function()
        return { path = path }
      end,
    })

    assert.matches("%[stdout%] hello stdout", results[path .. "::logs output"].short)
    assert.matches("%[stderr%] hello stderr", results[path .. "::logs output"].short)

    ---@diagnostic disable-next-line: undefined-field
    lib.files.read:revert()
  end)
end)
