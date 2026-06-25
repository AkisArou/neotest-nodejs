local compat = {}

compat.uv = vim.uv or vim.loop

---@param tbl table
---@return table
function compat.tbl_flatten(tbl)
  return vim.iter(tbl):flatten():totable()
end

---@param tbl table
---@return boolean
function compat.tbl_islist(tbl)
  return vim.islist(tbl)
end

return compat
