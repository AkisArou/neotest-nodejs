local node_util = require("neotest-nodejs.node-util")

describe("node-util", function()
  describe("getNodeCommand", function()
    it("returns node", function()
      assert.are.same(node_util.getNodeCommand("./spec"), "node")
    end)
  end)

  describe("getNodeDefaultArguments", function()
    it("builds node test runner arguments", function()
      assert.are.same(
        node_util.getNodeDefaultArguments({
          reporterPath = "/tmp/reporter.cjs",
          resultsPath = "/tmp/results.ndjson",
          testNamePattern = "^suite test$",
        }),
        {
          "--test",
          "--test-reporter=/tmp/reporter.cjs",
          "--test-reporter=spec",
          "--test-reporter-destination=/tmp/results.ndjson",
          "--test-reporter-destination=stdout",
          "--test-name-pattern=^suite test$",
        }
      )
    end)
  end)
end)
