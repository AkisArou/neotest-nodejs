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

  if not util.defaultTestFileMatcher(file_path) then
    return false
  end

  local lib = require("neotest.lib")
  local ok, content = pcall(lib.files.read, file_path)
  if not ok or not content:find("vitest", 1, true) then
    return true
  end

  local parsed, root, lang = pcall(lib.treesitter.get_parse_root, file_path, content, {})
  if not parsed or not vim.tbl_contains({ "javascript", "typescript", "tsx" }, lang) then
    return true
  end

  local query = vim.treesitter.query.parse(
    lang,
    [[
    (import_statement source: (string (string_fragment) @module)) @dependency
    (call_expression
      function: [(identifier) @function (import)]
      arguments: (arguments (string (string_fragment) @module))) @dependency
  ]]
  )
  for _, match in query:iter_matches(root, content, 0, -1) do
    local module, dependency, func
    for id, nodes in pairs(match) do
      local captured = nodes[1]
      local name = query.captures[id]
      if name == "module" then
        module = vim.treesitter.get_node_text(captured, content)
      elseif name == "dependency" then
        dependency = captured
      elseif name == "function" then
        func = vim.treesitter.get_node_text(captured, content)
      end
    end
    local type_only = false
    if dependency:type() == "import_statement" then
      for child in dependency:iter_children() do
        type_only = type_only or child:type() == "type"
        if child:type() == "import_clause" and child:named_child_count() == 1 then
          local bindings = child:named_child(0)
          if bindings:type() == "named_imports" then
            local all_types, has_bindings = true, false
            for binding in bindings:iter_children() do
              if binding:type() == "import_specifier" then
                has_bindings = true
                all_types = all_types and binding:child(0):type() == "type"
              end
            end
            type_only = type_only or (has_bindings and all_types)
          end
        end
      end
    end
    if module == "vitest" and not type_only and (not func or func == "require") then
      return false
    end
  end
  return true
end

return M
