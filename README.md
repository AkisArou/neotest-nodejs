# neotest-nodejs

A [Neotest](https://github.com/rcarriga/neotest) adapter for Node.js' built-in
[`node:test`](https://nodejs.org/api/test.html) runner.

This adapter targets Node.js' built-in test runner directly.

It is based on
[nvim-neotest/neotest-jest](https://github.com/nvim-neotest/neotest-jest),
with the Jest-specific runner integration replaced by Node.js test runner
support.

## Requirements

- Neovim 0.10 or newer
- Neotest 4.0.0 or newer
- Node.js with the built-in test runner
- Tree-sitter parsers for the languages you test, usually `javascript`,
  `typescript`, and `tsx`

## Installation

With `vim.pack` while developing from this checkout:

```lua
vim.opt.rtp:prepend("/path/to/neotest-nodejs")
```

Then configure Neotest:

```lua
require("neotest").setup({
  adapters = {
    require("neotest-nodejs")({
      nodeCommand = "node",
    }),
  },
})
```

## Configuration

### `nodeCommand`

Type: `string | fun(path: string): string`

The command used to run tests. Defaults to `node`.

Examples:

```lua
nodeCommand = "node"
nodeCommand = "NODE_OPTIONS='--import tsx' node"
```

### `nodeArguments`

Type:

```lua
fun(defaultArguments: string[], context: neotest-nodejs.NodeArgumentContext): string[]
```

Override the arguments passed to Node. The test file path is appended
automatically after these arguments.

The context table contains:

- `reporterPath`: adapter JSON reporter path
- `resultsPath`: JSON event output file used by Neotest
- `testNamePattern`: pattern passed to `--test-name-pattern`

Default arguments:

```text
--test
--test-reporter=<adapter JSON reporter>
--test-reporter=spec
--test-reporter-destination=<results file>
--test-reporter-destination=stdout
--test-name-pattern=<pattern>
```

The custom reporter writes machine-readable events for Neotest. The `spec`
reporter writes human-readable output so `neotest.output.open()` is useful.

### `env`

Type: `table<string, string> | fun(): table<string, string>`

Environment variables for the test process.

### `cwd`

Type: `string | fun(path: string): string`

Working directory for the test process.

### `strategy_config`

Custom strategy configuration, for example for `nvim-dap`.

### `isTestFile`

Type: `async fun(file_path: string?): boolean`

Override test file detection. The default matcher checks common test filename
patterns such as `*.test.js`, `*.spec.ts`, and files under `__tests__`.

## Project-specific configuration

Each `require("neotest-nodejs")({...})` call creates an independent adapter
instance. This means you can keep a global default adapter and configure a
different adapter for a specific project without the options overwriting each
other.

Use Neotest's `setup_project()` for project-local Node flags:

```lua
local project_root = "/path/to/project"
local polyfills_path = project_root .. "/polyfills/index.ts"

require("neotest").setup_project(project_root, {
  adapters = {
    require("neotest-nodejs")({
      nodeCommand = "node",
      nodeArguments = function(default_args)
        return vim.list_extend({
          "--experimental-transform-types",
          "--no-warnings=ExperimentalWarning",
          "--import=" .. polyfills_path,
        }, default_args)
      end,
    }),
  },
})
```

This is preferable to mutating adapter options after `neotest.setup()`, because
Neotest stores configured adapter instances per project.

## TypeScript

This adapter runs `node --test` directly. TypeScript support depends on your
Node.js setup. For example:

```lua
require("neotest-nodejs")({
  nodeCommand = "node",
  nodeArguments = function(default_args)
    return vim.list_extend({ "--import", "tsx" }, default_args)
  end,
})
```

Runtime-expanded parameterized test discovery is intentionally not implemented.
Source-level `test.each` / `describe.each` positions are still discovered and
use a broader test-name pattern when run.
