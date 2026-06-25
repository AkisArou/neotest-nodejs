---@diagnostic disable: undefined-field
local async = require("neotest.async")
local compat = require("neotest-nodejs.compat")
local lib = require("neotest.lib")
local logger = require("neotest.logging")
local util = require("neotest-nodejs.util")
local node_util = require("neotest-nodejs.node-util")
local types = require("neotest.types")

local ResultStatus = types.ResultStatus

---@class neotest-nodejs.NodeArgumentContext
---@field reporterPath string
---@field resultsPath string
---@field testNamePattern string

---@class neotest.NodejsOptions
---@field nodeCommand? string | fun(): string
---@field nodeArguments? fun(defaultArguments: string[], nodeArgsContext: neotest-nodejs.NodeArgumentContext): string[]
---@field env? table<string, string> | fun(): table<string, string>
---@field cwd? string | fun(): string
---@field strategy_config? table<string, unknown> | fun(): table<string, unknown>
---@field isTestFile async fun(file_path: string?): boolean

---@type neotest.Adapter
local adapter = { name = "neotest-nodejs" }

adapter.root = function(path)
  return lib.files.match_root_pattern("package.json")(path)
end

local getNodeCommand = node_util.getNodeCommand
local getNodeArguments = node_util.getNodeArguments
local isTestFile = node_util.defaultIsTestFile
local reporter_path =
  util.path.join(debug.getinfo(1, "S").source:sub(2):match("(.*/)"), "reporter.cjs")

local NODE_TEST_PARAMETER_TYPES = {
  "%%p",
  "%%s",
  "%%d",
  "%%i",
  "%%f",
  "%%j",
  "%%o",
  "%%#",
  "%%%%",
}

local NODE_TEST_NAMED_PARAMETER_REGEX = "\\$[%a%.]+"

---@param tree neotest.Tree
---@param pos neotest.Position
---@return boolean
local function is_position_parameterized(tree, pos)
  if pos.is_parameterized then
    return true
  end

  local parent = tree:parent()

  while parent do
    local parent_pos = parent:data()

    if parent_pos.is_parameterized then
      return true
    end

    parent = parent:parent()
  end

  return false
end

---@param name string
---@return string
local function replace_test_parameters_with_regex(name)
  for _, parameter_type in ipairs(NODE_TEST_PARAMETER_TYPES) do
    name = name:gsub(parameter_type, ".*")
  end

  return name:gsub(NODE_TEST_NAMED_PARAMETER_REGEX, ".*")
end

---@async
---@param file_path? string
---@return boolean
function adapter.is_test_file(file_path)
  return isTestFile(file_path)
end

function adapter.filter_dir(name)
  return name ~= "node_modules"
end

---@param captured_nodes TSNode[]
---@return ("test" | "namespace")?
local function get_match_type(captured_nodes)
  if captured_nodes["test.name"] then
    return "test"
  end
  if captured_nodes["namespace.name"] then
    return "namespace"
  end
end

-- Enrich `it.each` tests with metadata about TS node position
function adapter.build_position(file_path, source, captured_nodes)
  local match_type = get_match_type(captured_nodes)

  if not match_type then
    return
  end

  ---@type TSNode
  local node = captured_nodes[match_type .. ".name"]
  local name = vim.treesitter.get_node_text(node, source)
  local definition = captured_nodes[match_type .. ".definition"]
  local type = node:type()
  local nonStringNode = false

  if type == "string" then
    -- If the node is a string then strip the quotes from the name by getting
    -- it's first named child (string_fragment). This works for single- and
    -- double-quotes and is necessary since we match anything in the queries
    -- used in discover_positions
    local content = node:named_child(0)

    if content then
      name = vim.treesitter.get_node_text(content, source)
    end
  elseif type == "template_string" then
    -- If the node is a template string then concatenate its named children
    -- which is essentially the inner part of the backticks thus stripping
    -- backticks. This is necessary since we match anything in the queries used
    -- in discover_positions
    local new_name = {}

    for _, named_child in ipairs(node:named_children()) do
      table.insert(new_name, vim.treesitter.get_node_text(named_child, source))
    end

    name = table.concat(new_name, "")
  else
    nonStringNode = true
  end

  return {
    type = match_type,
    path = file_path,
    name = name,
    range = { definition:range() },
    -- Record the position of the line where the string name occurs
    test_name_range = match_type == "test" and { node:range() } or nil,
    is_parameterized = (captured_nodes["each_property"] or nonStringNode) and true or false,
  }
end

---@async
---@return neotest.Tree | nil
function adapter.discover_positions(path)
  -- NOTE: Combining queries with a second argument that can be either
  -- arrow_function, function_expression, or call_expression seems to
  -- change the order of the matches so that namespaces or listed after
  -- tests. When neotest builds the tree tests are not properly nested
  -- under their namespace. This might be because the range of a combined
  -- query can end later that a test, changing the order that matches are
  -- iterated
  local query = [[
    ; ##############
    ; # Namespaces #
    ; ##############

    ; Matches: `describe('context', () => {})`
    ;          `fdescribe('context', () => {})` (alias for describe.only)
    ;          `xdescribe('context', () => {})` (alias for describe.skip)
    ((call_expression
        function: (identifier) @func_name (#any-of? @func_name "describe" "fdescribe" "xdescribe")
          arguments: (arguments ((_) @namespace.name) (arrow_function))
    )) @namespace.definition

    ; Matches: `describe('context', function() {})`
    ;          `fdescribe('context', function() {})` (alias for describe.only)
    ;          `xdescribe('context', function() {})` (alias for describe.skip)
    ((call_expression
        function: (identifier) @func_name (#any-of? @func_name "describe" "fdescribe" "xdescribe")
          arguments: (arguments ((_) @namespace.name) (function_expression))
    )) @namespace.definition

    ; Matches: `describe('context', wrapper())`
    ;          `fdescribe('context', wrapper())`
    ;          `xdescribe('context', wrapper())`
    ((call_expression
        function: (identifier) @func_name (#any-of? @func_name "describe" "fdescribe" "xdescribe")
          arguments: (arguments ((_) @namespace.name) (call_expression))
    )) @namespace.definition

    ; Matches: `describe.only('context', () => {})`
    ((call_expression
        function: (member_expression) @func_name (
          #any-of? @func_name "describe.only" "describe.skip"
        )
        arguments: (arguments ((_) @namespace.name) (arrow_function))
    )) @namespace.definition

    ; Matches: `describe.only('context', function() {})`
    ((call_expression
        function: (member_expression) @func_name (
          #any-of? @func_name "describe.only" "describe.skip"
        )
        arguments: (arguments ((_) @namespace.name) (function_expression))
    )) @namespace.definition

    ; Matches: `describe.only('context', wrapper())`
    ((call_expression
        function: (member_expression) @func_name (
          #any-of? @func_name "describe.only" "describe.skip"
        )
        arguments: (arguments ((_) @namespace.name) (call_expression))
    )) @namespace.definition

    ; Matches: `describe.each(['data'])('context', () => {})`
    ((call_expression
      function: (call_expression
        function: (member_expression
          object: (identifier) @func_name (#eq? @func_name "describe")
          property: (property_identifier) @each_property (#eq? @each_property "each")
        )
      )
      arguments: (arguments ((_) @namespace.name) (arrow_function))
    )) @namespace.definition

    ; Matches: `describe.each(['data'])('context', function() {})`
    ((call_expression
      function: (call_expression
        function: (member_expression
          object: (identifier) @func_name (#eq? @func_name "describe")
          property: (property_identifier) @each_property (#eq? @each_property "each")
        )
      )
      arguments: (arguments ((_) @namespace.name) (function_expression))
    )) @namespace.definition

    ; Matches: `describe.each(['data'])('context', wrapper())`
    ((call_expression
      function: (call_expression
        function: (member_expression
          object: (identifier) @func_name (#eq? @func_name "describe")
        )
      )
      arguments: (arguments ((_) @namespace.name) (call_expression))
    )) @namespace.definition

    ; #########
    ; # Tests #
    ; #########

    ; Matches "it" "test" "xit" "xtest" "fit" with arrow functions
    ((call_expression
      function: (identifier) @func_name (#any-of? @func_name "it" "test" "xit" "xtest" "fit")
        arguments: (arguments ((_) @test.name) (arrow_function))
    )) @test.definition

    ; Matches "it" "test" "xit" "xtest" "fit" with function expressions
    ((call_expression
      function: (identifier) @func_name (#any-of? @func_name "it" "test" "xit" "xtest" "fit")
        arguments: (arguments ((_) @test.name) (function_expression))
    )) @test.definition

    ; Matches "it" "test" "xit" "xtest" "fit" with call expressions
    ((call_expression
      function: (identifier) @func_name (#any-of? @func_name "it" "test" "xit" "xtest" "fit")
        arguments: (arguments ((_) @test.name) (call_expression))
    )) @test.definition

    ; Matches different aliases with arrow functions
    ((call_expression
      function: (member_expression) @func_name (
        #any-of? @func_name
          "it.only"
          "it.failing"
          "it.concurrent"
          "it.only.failing"
          "it.skip.failing"
          "fit.failing"
          "xit.failing"
          "test.failing"
          "test.concurrent"
          "test.only"
          "test.only.failing"
          "test.skip.failing"
          "xtest.failing"
        )
      arguments: (arguments ((_) @test.name) (arrow_function))
    )) @test.definition

    ; Matches different aliases with function expressions
    ((call_expression
      function: (member_expression) @func_name (
        #any-of? @func_name
          "it.only"
          "it.failing"
          "it.concurrent"
          "it.only.failing"
          "it.skip.failing"
          "fit.failing"
          "xit.failing"
          "test.failing"
          "test.concurrent"
          "test.only"
          "test.only.failing"
          "test.skip.failing"
          "xtest.failing"
        )
      arguments: (arguments ((_) @test.name) (function_expression))
    )) @test.definition

    ; Matches different aliases with call expressions
    ((call_expression
      function: (member_expression) @func_name (
        #any-of? @func_name
          "it.only"
          "it.failing"
          "it.concurrent"
          "it.only.failing"
          "it.skip.failing"
          "fit.failing"
          "xit.failing"
          "test.failing"
          "test.concurrent"
          "test.only"
          "test.only.failing"
          "test.skip.failing"
          "xtest.failing"
        )
      arguments: (arguments ((_) @test.name) (call_expression))
    )) @test.definition

    ; Matches all test.each aliases with arrow functions
    ((call_expression
      function: (call_expression
        function: (member_expression) @func_name @each_property (
          #any-of? @func_name
          "it.each"
          "it.only.each"
          "it.failing.each"
          "it.skip.each"
          "it.concurrent.each"
          "it.concurrent.only.each"
          "it.concurrent.skip.each"
          "fit.each"
          "xit.each"
          "test.each"
          "test.only.each"
          "test.failing.each"
          "test.skip.each"
          "test.concurrent.each"
          "test.concurrent.only.each"
          "test.concurrent.skip.each"
          "xtest.each"
        )
      )
      arguments: (arguments ((_) @test.name) (arrow_function))
    )) @test.definition

    ; Matches all test.each aliases with function expressions
    ((call_expression
      function: (call_expression
        function: (member_expression) @func_name @each_property (
          #any-of? @func_name
          "it.each"
          "it.only.each"
          "it.failing.each"
          "it.skip.each"
          "it.concurrent.each"
          "it.concurrent.only.each"
          "it.concurrent.skip.each"
          "fit.each"
          "xit.each"
          "test.each"
          "test.only.each"
          "test.failing.each"
          "test.skip.each"
          "test.concurrent.each"
          "test.concurrent.only.each"
          "test.concurrent.skip.each"
          "xtest.each"
        )
      )
      arguments: (arguments ((_) @test.name) (function_expression))
    )) @test.definition

    ; Matches all test.each aliases with call expressions
    ((call_expression
      function: (call_expression
        function: (member_expression) @func_name @each_property (
          #any-of? @func_name
          "it.each"
          "it.only.each"
          "it.failing.each"
          "it.skip.each"
          "it.concurrent.each"
          "it.concurrent.only.each"
          "it.concurrent.skip.each"
          "fit.each"
          "xit.each"
          "test.each"
          "test.only.each"
          "test.failing.each"
          "test.skip.each"
          "test.concurrent.each"
          "test.concurrent.only.each"
          "test.concurrent.skip.each"
          "xtest.each"
        )
      )
      arguments: (arguments ((_) @test.name) (call_expression))
    )) @test.definition

    ; Matches all todo tests
    ((call_expression
      function: (member_expression) @func_name (
        #any-of? @func_name
          "it.todo"
          "test.todo"
        )
      arguments: (arguments ((_) @test.name))
    )) @test.definition
  ]]

  ---@diagnostic disable-next-line: missing-fields
  local positions = lib.treesitter.parse_positions(path, query, {
    nested_tests = false,
    ---@diagnostic disable-next-line: assign-type-mismatch
    build_position = 'require("neotest-nodejs").build_position',
  })

  return positions
end

local function get_default_strategy_config(strategy, command, cwd)
  local config = {
    dap = function()
      return {
        name = "Debug Node.js Tests",
        type = "pwa-node",
        request = "launch",
        args = { unpack(command, 2) },
        runtimeExecutable = command[1],
        console = "integratedTerminal",
        internalConsoleOptions = "neverOpen",
        rootPath = "${workspaceFolder}",
        cwd = cwd or "${workspaceFolder}",
      }
    end,
  }
  if config[strategy] then
    return config[strategy]()
  end
end

local function getEnv(specEnv)
  return specEnv
end

---@param path string
---@return string|nil
local function getCwd(path)
  return nil
end

local function getStrategyConfig(default_strategy_config, args)
  return default_strategy_config
end

local function read_node_test_events(data)
  local events = {}

  for line in data:gmatch("[^\r\n]+") do
    local ok, event = pcall(vim.json.decode, line, { luanil = { object = true } })

    if ok and event.type then
      table.insert(events, event)
    end
  end

  return events
end

local function node_error_message(err)
  if not err then
    return ""
  end

  if type(err) == "string" then
    return err
  end

  local cause = err.cause
  if type(cause) == "string" then
    return cause
  end

  if type(cause) == "table" then
    if cause.stack then
      return cause.stack
    end
    if cause.message then
      return cause.message
    end
  end

  return err.message or err.failureType or err.code or ""
end

local function node_result_file(file, target_file)
  if not target_file then
    return file
  end

  local real_target = compat.uv.fs_realpath(target_file)

  if real_target and vim.fs.normalize(file) == vim.fs.normalize(real_target) then
    return target_file
  end

  if vim.fs.normalize(file) == vim.fs.normalize(target_file) then
    return target_file
  end

  return file
end

local function parsed_node_events_to_results(events, consoleOut, target_file)
  local tests = {}
  local active = {}

  for _, event in ipairs(events) do
    local data = event.data or {}
    local details = data.details or {}
    local nesting = data.nesting or 0

    if event.type == "test:start" then
      active[nesting] = data.name
      for index = nesting + 1, #active do
        active[index] = nil
      end
    elseif
      (event.type == "test:pass" or event.type == "test:fail")
      and details.type == "test"
      and data.file
      and data.name ~= data.file
    then
      local keyid = node_result_file(data.file, target_file)

      for index = 0, nesting - 1 do
        if active[index] then
          keyid = keyid .. "::" .. active[index]
        end
      end

      keyid = keyid .. "::" .. data.name

      local status = event.type == "test:fail" and ResultStatus.failed or ResultStatus.passed

      if data.skip or data.todo or details.skip or details.todo then
        status = ResultStatus.skipped
      end

      tests[keyid] = {
        status = status,
        short = data.name .. ": " .. status,
        output = consoleOut,
        location = {
          line = data.line,
          column = data.column,
        },
      }

      if event.type == "test:fail" then
        local msg = node_error_message(details.error)
        tests[keyid].short = tests[keyid].short .. "\n" .. msg
        tests[keyid].errors = {
          {
            line = (data.line or 1) - 1,
            column = (data.column or 1) - 1,
            message = msg,
          },
        }
      end
    end
  end

  return tests
end

local function parsed_output_to_results(data, consoleOut, target_file)
  return parsed_node_events_to_results(read_node_test_events(data), consoleOut, target_file)
end

---@param args neotest.RunArgs
---@return neotest.RunSpec | nil
function adapter.build_spec(args)
  local tree = args.tree

  if not tree then
    return
  end

  local pos = tree:data()
  local testNamePattern = ".*"

  if pos.type == types.PositionType.test or pos.type == types.PositionType.namespace then
    local testName = pos.id

    testName, _ = testName:sub(pos.id:find("::") + 2):gsub("::", " ")
    testNamePattern = util.escapeTestPattern(testName)

    -- If the position or any of its enclosing blocks are parameterized, replace any
    -- test parameters with a match-all regex so we can run the test
    if is_position_parameterized(tree, pos) then
      testNamePattern = replace_test_parameters_with_regex(testNamePattern)
    end

    testNamePattern = "^" .. testNamePattern

    -- Node's test name pattern matches against the full test name so if we added
    -- '$' to a namespace position it would never match any tests
    if pos.type == types.PositionType.test then
      testNamePattern = testNamePattern .. "$"
    end
  end

  local binary = args.nodeCommand or getNodeCommand(pos.path)
  local command = vim.split(binary, "%s+")

  ---@type string
  local results_path = async.fn.tempname() .. ".json"

  local nodeArgsContext = {
    reporterPath = reporter_path,
    resultsPath = results_path,
    testNamePattern = testNamePattern,
  }

  local options =
    getNodeArguments(node_util.getNodeDefaultArguments(nodeArgsContext), nodeArgsContext)

  if compat.tbl_islist(options) then
    vim.list_extend(command, options)
  else
    vim.notify(
      ("Node arguments must be a list, got '%s'"):format(type(options)),
      vim.log.levels.ERROR
    )

    -- Add the default arguments to allow neotest to run
    vim.list_extend(command, node_util.getNodeDefaultArguments(nodeArgsContext))
  end

  if compat.tbl_islist(args.extra_args) then
    vim.list_extend(command, args.extra_args)
  elseif args.extra_args then
    vim.notify(
      ("Extra arguments must be a list, got '%s'"):format(type(options)),
      vim.log.levels.ERROR
    )
  end

  table.insert(command, vim.fs.normalize(pos.path))

  local cwd = getCwd(pos.path)

  -- Creating empty file for streaming results
  lib.files.write(results_path, "")
  local stream_data, stop_stream = util.stream(results_path)

  return {
    command = command,
    cwd = cwd,
    context = {
      results_path = results_path,
      file = pos.path,
      stop_stream = stop_stream,
    },
    stream = function()
      return function()
        local new_results = stream_data()

        if new_results == "" then
          return {}
        end

        return parsed_output_to_results(new_results, nil, pos.path)
      end
    end,
    strategy = getStrategyConfig(
      get_default_strategy_config(args.strategy, command, cwd) or {},
      args
    ),
    env = getEnv(args[2] and args[2].env or {}),
  }
end

---@async
---@param spec neotest.RunSpec
---@param result neotest.StrategyResult
---@param tree neotest.Tree
---@return table<string, neotest.Result>
function adapter.results(spec, result, tree)
  spec.context.stop_stream()

  local output_file = spec.context.results_path

  local success, data = pcall(lib.files.read, output_file)

  if not success then
    logger.error("No test output file found ", output_file)
    return {}
  end

  return parsed_output_to_results(data, result.output, spec.context.file)
end

---@generic T
---@param value T | fun(any): T
---@param default fun(any): T
---@param reject_value boolean?
---@return fun(any): T
local function resolve_config_option(value, default, reject_value)
  if util.is_callable(value) then
    return value
  elseif value and not reject_value then
    return function()
      return value
    end
  end

  return default
end

setmetatable(adapter, {
  ---@param opts neotest.NodejsOptions
  __call = function(_, opts)
    getNodeCommand = resolve_config_option(opts.nodeCommand, getNodeCommand)
    getNodeArguments = resolve_config_option(opts.nodeArguments, getNodeArguments, true)
    getCwd = resolve_config_option(opts.cwd, getCwd)
    getStrategyConfig = resolve_config_option(opts.strategy_config, getStrategyConfig)

    if util.is_callable(opts.env) then
      getEnv = opts.env
    elseif opts.env then
      getEnv = function(specEnv)
        return vim.tbl_extend("force", opts.env, specEnv)
      end
    end

    if util.is_callable(opts.isTestFile) then
      isTestFile = opts.isTestFile
    end

    return adapter
  end,
})

return adapter
