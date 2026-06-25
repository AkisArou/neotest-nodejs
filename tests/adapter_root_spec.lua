local adapter = require("neotest-nodejs")({ nodeCommand = "node" })
local async = require("nio").tests

describe("adapter.root", function()
  async.it("recognises root", function()
    assert.Not.Nil(adapter.root("./spec"))
    assert.Nil(adapter.root(".."))
  end)
end)
