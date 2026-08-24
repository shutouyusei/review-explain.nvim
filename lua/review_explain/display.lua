local M = {}

---Show `lines` in a floating window styled like LSP hover.
---@param lines string[]
---@param opts table|nil extra options merged into vim.lsp.util.open_floating_preview's opts
---@return integer bufnr
---@return integer winnr
function M.show(lines, opts)
	opts = opts or {}
	return vim.lsp.util.open_floating_preview(lines, "markdown", vim.tbl_extend("force", {
		border = "rounded",
		focusable = false,
	}, opts))
end

return M
