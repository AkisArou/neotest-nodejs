local M = {}

local util = require("neotest-nodejs.util")

---@param path string
---@return string
function M.getNodeCommand(path)
  return "node"
end

---@param context neotest-nodejs.NodeArgumentContext
---@return string[]
function M.getNodeDefaultArguments(context)
  return {
    "--test",
    "--test-reporter=" .. context.reporterPath,
    "--test-reporter=spec",
    "--test-reporter-destination=" .. context.resultsPath,
    "--test-reporter-destination=stdout",
    "--test-name-pattern=" .. context.testNamePattern,
  }
end

---@param defaultArguments string[]
---@param context neotest-nodejs.NodeArgumentContext
---@return string[]
---@diagnostic disable-next-line: unused-local
function M.getNodeArguments(defaultArguments, context)
  return defaultArguments
end

---@async
---@param file_path string?
---@return boolean
function M.defaultIsTestFile(file_path)
  if not file_path then
    return false
  end

  return util.defaultTestFileMatcher(file_path)
end

return M
