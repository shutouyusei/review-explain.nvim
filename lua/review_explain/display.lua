local M = {}

---Bounds for the floating popup. Width is capped to a fairly narrow
---fraction of the screen on purpose -- a tall/narrow box reads more like a
---hover doc; height then grows to fit whatever that width wraps to,
---instead of the box growing wide to fit its longest line.
local MIN_WIDTH = 40
local MAX_WIDTH_RATIO = 0.4
local MIN_HEIGHT = 10
local MAX_HEIGHT_RATIO = 0.7

---Compute a width/height for `lines`, capped to MAX_WIDTH_RATIO of the
---screen for width; height is derived from how many screen rows `lines`
---wraps to at that width (so a long line adds height, not width), capped
---to MAX_HEIGHT_RATIO of the screen.
---@param lines string[]
---@return integer width
---@return integer height
local function compute_size(lines)
	local max_line_width = 0
	for _, line in ipairs(lines) do
		max_line_width = math.max(max_line_width, vim.fn.strdisplaywidth(line))
	end

	local width = math.min(max_line_width + 2, math.floor(vim.o.columns * MAX_WIDTH_RATIO))
	width = math.max(MIN_WIDTH, width)

	local wrapped_rows = 0
	for _, line in ipairs(lines) do
		wrapped_rows = wrapped_rows + math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / (width - 2)))
	end

	local height = math.max(MIN_HEIGHT, wrapped_rows)
	height = math.min(height, math.floor(vim.o.lines * MAX_HEIGHT_RATIO))

	return width, height
end

---Screen row/col (0-indexed, editor-relative) of the cursor in the
---current window, plus that window's screen column and width -- used to
---anchor the popup just past the window's right edge instead of at the
---cursor's own (possibly narrow) window.
---@return integer row
---@return integer win_right_col
local function cursor_row_and_win_right_edge()
	local win_pos = vim.fn.win_screenpos(0) -- {row, col}, 1-indexed
	local row = win_pos[1] - 1 + vim.fn.winline() - 1
	local win_right_col = win_pos[2] - 1 + vim.api.nvim_win_get_width(0)
	return row, win_right_col
end

---Show `lines` in a floating window styled like LSP hover, anchored just
---to the right of the current window's edge (editor-relative) rather than
---confined to the current window's bounds. This lets the popup spill over
---neighboring windows (e.g. a narrow quickfix list) instead of being
---clipped by vim.lsp.util.open_floating_preview to whatever space is left
---in the window under the cursor -- that function always positions
---relative to the cursor's own window even when told `relative = "editor"`,
---so a wide/tall popup gets shrunk to fit the quickfix list. We open the
---floating window ourselves instead, computing editor-absolute coordinates.
---@param lines string[]
---@param opts table|nil extra options: `border` may be overridden;
---  `close_events` overrides the autocmd events that auto-close the popup
---  (default: CursorMoved, CursorMovedI, InsertCharPre, BufLeave, WinLeave
---  in the buffer that was current when `show` was called) -- pass `false`
---  to skip wiring auto-close entirely (e.g. a caller managing its own).
---@return integer bufnr
---@return integer winnr
function M.show(lines, opts)
	opts = opts or {}
	local source_bufnr = vim.api.nvim_get_current_buf()
	local width, height = compute_size(lines)

	local row, col = cursor_row_and_win_right_edge()
	-- Leave room for the border (2 rows) below the popup; if it doesn't
	-- fit under the cursor, anchor it above instead.
	if row + height + 2 > vim.o.lines then
		row = math.max(0, row - height - 2)
	end
	-- Clamp so the popup's right edge stays on-screen.
	col = math.min(col, math.max(0, vim.o.columns - width - 2))

	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.bo[bufnr].modifiable = true
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.bo[bufnr].modifiable = false
	-- Set `syntax`, not `filetype`: filetype fires the FileType autocmd,
	-- which can pull in the user's markdown config (folding, LSP, etc.)
	-- for this throwaway scratch buffer -- a folded buffer collapses to
	-- an empty-looking box, which is how this bug actually surfaced.
	vim.bo[bufnr].syntax = "markdown"
	vim.bo[bufnr].bufhidden = "wipe"

	local winnr = vim.api.nvim_open_win(bufnr, false, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = opts.border or "rounded",
		focusable = opts.focusable == true,
		zindex = 50,
	})
	vim.wo[winnr].wrap = true
	vim.wo[winnr].foldenable = false

	if opts.close_events ~= false then
		vim.api.nvim_create_autocmd(opts.close_events or { "CursorMoved", "CursorMovedI", "InsertCharPre", "BufLeave", "WinLeave" }, {
			group = vim.api.nvim_create_augroup("review_explain_popup_close_" .. winnr, { clear = true }),
			buffer = source_bufnr,
			once = true,
			callback = function()
				if vim.api.nvim_win_is_valid(winnr) then
					vim.api.nvim_win_close(winnr, true)
				end
			end,
		})
	end

	return bufnr, winnr
end

return M
