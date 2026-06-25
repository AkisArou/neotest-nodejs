# Contributing

Please raise a PR if you are interested in adding new functionality or fixing any bugs. When submitting a bug, please try to include some minimal reproduction code that can be tested.

To run the tests and styling:

1. Fork this repository.
2. Make changes.
3. Make sure tests and styling checks are passing.
   * Run tests by running `./scripts/test` in the root directory. Running the tests requires [`plenary.nvim`](https://github.com/nvim-lua/plenary.nvim), [`neotest`](https://github.com/nvim-neotest/neotest), [`nvim-nio`](https://github.com/nvim-neotest/nvim-nio), and [`nvim-treesitter`](https://github.com/nvim-treesitter/nvim-treesitter). You may need to update `./tests/minimal_init.lua` to point to your local installation.
   * Run the Node.js fixture with `cd node-test-fixture && npm test`.
   * If you are testing a new feature that requires running tests, open a file under `node-test-fixture/test/` and verify Neotest behavior manually.
   * Install [stylua](https://github.com/JohnnyMorganz/StyLua) and check styling using `stylua --check lua/ tests/`. Omit `--check` in order to fix styling.
4. Submit a pull request.
5. Get it approved.
