local resolve = require("review_explain.resolve")
local cache = require("review_explain.cache")
local display = require("review_explain.display")
local config = require("review_explain.config")

local M = {}

local highlight_ns = vim.api.nvim_create_namespace("review_explain_highlight")

---@param bufnr integer
---@return string cache_path
local function cache_path_for_buffer(bufnr)
	local filepath = vim.api.nvim_buf_get_name(bufnr)
	local root = cache.resolve_root(bufnr)
	return cache.cache_path(root .. "/" .. config.cache_dirname, filepath, root)
end

---Look up the best available cached explanation for a resolved function:
---the revision matching its current content if one exists, otherwise the
---most recent revision on record (marked stale) so an explanation stays
---available -- and visibly flagged as possibly outdated -- instead of
---disappearing the moment the function is edited.
---@param bufnr integer
---@param found {name:string, node:userdata}
---@return {explanation:string, stale:boolean}|nil
local function find_best_revision(bufnr, found)
	local entries = cache.read(cache_path_for_buffer(bufnr))
	local revisions = entries[found.name]
	if not revisions or #revisions == 0 then
		return nil
	end

	local current_hash = resolve.hash_node(bufnr, found.node)
	for _, revision in ipairs(revisions) do
		if revision.body_hash == current_hash then
			return { explanation = revision.explanation, stale = false }
		end
	end

	-- No exact match: revisions are stored most-recent-first (cache.merge),
	-- so [1] is the closest thing we have.
	return { explanation = revisions[1].explanation, stale = true }
end

---Request LSP hover for the cursor position and return its markdown lines.
---Calls back with an empty table if there's no LSP client or no hover info.
---@param bufnr integer
---@param callback fun(lines: string[])
local function request_hover(bufnr, callback)
	local clients = vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/hover" })
	if #clients == 0 then
		callback({})
		return
	end
	local params = vim.lsp.util.make_position_params(0, clients[1].offset_encoding)
	vim.lsp.buf_request_all(bufnr, "textDocument/hover", params, function(results)
		local lines = {}
		for _, resp in pairs(results) do
			local result = resp.result
			if result and result.contents then
				vim.list_extend(lines, vim.lsp.util.convert_input_to_markdown_lines(result.contents))
			end
		end
		callback(lines)
	end)
end

---Show LSP hover and any cached explanation for the function under the
---cursor together in one floating window, instead of one replacing the
---other.
---@param bufnr integer
function M.show(bufnr)
	local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
	local found = resolve.find_enclosing_function(bufnr, lnum)
	local best = found and find_best_revision(bufnr, found) or nil

	request_hover(bufnr, function(hover_lines)
		local lines = {}
		vim.list_extend(lines, hover_lines)

		if best then
			if #lines > 0 then
				table.insert(lines, "---")
			end
			if best.stale then
				table.insert(lines, "**AI explanation (⚠️ code changed since this was written):**")
			else
				table.insert(lines, "**AI explanation:**")
			end
			vim.list_extend(lines, vim.split(best.explanation, "\n"))
		end

		if #lines == 0 then
			vim.notify("No information available", vim.log.levels.INFO)
			return
		end

		display.show(lines)
	end)
end

---Mark a range [start_row, end_row] (0-indexed, inclusive) as a bounded
---region with a top/bottom border drawn as `virt_lines` -- whole synthetic
---lines inserted before/after the range, never touching an existing
---line's own content, so this has no interaction with LSP inlay hints
---(which insert eol/inline virt_text into the real lines themselves).
---@param bufnr integer
---@param ns integer
---@param start_row integer
---@param end_row integer
---@param hl_group string
local function highlight_box(bufnr, ns, start_row, end_row, hl_group)
	local lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)

	local max_width = 0
	for _, line in ipairs(lines) do
		max_width = math.max(max_width, vim.fn.strdisplaywidth(line))
	end
	max_width = math.max(max_width, 1)

	vim.api.nvim_buf_set_extmark(bufnr, ns, start_row, 0, {
		virt_lines = { { { "╭" .. string.rep("─", max_width) .. "╮", hl_group } } },
		virt_lines_above = true,
	})
	vim.api.nvim_buf_set_extmark(bufnr, ns, end_row, 0, {
		virt_lines = { { { "╰" .. string.rep("─", max_width) .. "╯", hl_group } } },
	})
end

---Highlight every function in the buffer that has a cached explanation,
---so explained functions are visible at a glance without pressing K on
---each one. Functions whose content matches the cached revision exactly
---get one color; functions whose content has since changed (a stale
---revision is all that's on record) get a different one.
---@param bufnr integer
function M.highlight_buffer(bufnr)
	vim.api.nvim_buf_clear_namespace(bufnr, highlight_ns, 0, -1)

	if vim.api.nvim_buf_get_name(bufnr) == "" then
		return
	end

	local entries = cache.read(cache_path_for_buffer(bufnr))
	if vim.tbl_isempty(entries) then
		return
	end

	for _, fn in ipairs(resolve.find_all_functions(bufnr)) do
		local best = find_best_revision(bufnr, fn)
		if best then
			local box_group = best.stale and "ReviewExplainStale" or "ReviewExplainExplained"
			local sign_group = best.stale and "ReviewExplainStaleSign" or "ReviewExplainExplainedSign"
			highlight_box(bufnr, highlight_ns, fn.start_line - 1, fn.end_line - 1, box_group)
			for row = fn.start_line - 1, fn.end_line - 1 do
				vim.api.nvim_buf_set_extmark(bufnr, highlight_ns, row, 0, {
					-- Not a vertical bar: hlchunk's indent guides already use
					-- that shape, and using it here too would read as the
					-- same kind of marker.
					sign_text = "●",
					sign_hl_group = sign_group,
				})
			end
		end
	end
end

return M
