local cache = require("review_explain.cache")
local config = require("review_explain.config")
local display = require("review_explain.display")

local M = {}

---Max length of the note shown in a single quickfix line before it's
---truncated with an ellipsis; the full text is available in the
---CursorHold popup (format_item_detail).
local QF_NOTE_SUMMARY_LEN = 60

---@param note string
---@return string
local function summarize_note(note)
	local first_line = note:match("^[^\n]*") or note
	-- Truncate by display width via strcharpart, not byte count via
	-- string.sub/#: the latter can split a multibyte UTF-8 character (e.g.
	-- Japanese text) mid-byte, corrupting the quickfix line.
	if vim.fn.strdisplaywidth(first_line) <= QF_NOTE_SUMMARY_LEN then
		return first_line
	end

	local nchars = vim.fn.strchars(first_line)
	local lo, hi = 0, nchars
	while lo < hi do
		local mid = math.ceil((lo + hi) / 2)
		if vim.fn.strdisplaywidth(vim.fn.strcharpart(first_line, 0, mid)) <= QF_NOTE_SUMMARY_LEN then
			lo = mid
		else
			hi = mid - 1
		end
	end
	return vim.fn.strcharpart(first_line, 0, lo) .. "…"
end

---@param item table one review-map item ({kind, note, check, checked, ...})
---@return string
local function format_item_text(item)
	local prefix = item.checked and "[x] " or "[ ] "
	return prefix .. item.kind .. ": " .. summarize_note(item.note)
end

---Build the markdown lines shown in the CursorHold popup for one review
---item -- the full note/check text that the single-line quickfix entry
---(format_item_text) truncates for width.
---@param item table one review-map item ({kind, note, check, checked, ...})
---@return string[]
local function format_item_detail(item)
	local status = item.checked and "✅ checked" or "⬜ unchecked"
	return {
		string.format("**%s** _(%s)_", item.kind, status),
		"",
		item.note,
		"",
		"**check:** " .. item.check,
	}
end
M._format_item_detail = format_item_detail

---Build the quickfix-list entries for a review map, one per item, in order.
---@param root string absolute project root, items' `file` paths are relative to this
---@param map table decoded review map ({base, items, ...})
---@return table[] quickfix items (see :h setqflist)
function M.build_qf_items(root, map)
	local qf_items = {}
	for _, item in ipairs(map.items) do
		table.insert(qf_items, {
			filename = root .. "/" .. item.file,
			lnum = item.line,
			text = format_item_text(item),
		})
	end
	return qf_items
end

---Toggle `checked` on the item at `index` (1-based, matching both
---map.items and the quickfix list built from it) and persist the change.
---@param map_path string
---@param index integer
---@return table|nil item the updated item
---@return string|nil err
function M.toggle_checked(map_path, index)
	local map, decode_failed = cache.read(map_path)
	if decode_failed or not map.items or not map.items[index] then
		return nil, "no review item at index " .. tostring(index) .. " in " .. map_path
	end

	local item = map.items[index]
	item.checked = not item.checked
	cache.write(map_path, map)
	return item, nil
end

---`<leader>cx`: toggle the review item under the cursor in a quickfix
---buffer populated by M.open, and reflect the change in the quickfix list
---display immediately, without removing the item from the list.
function M.toggle_checked_at_cursor()
	local bufnr = vim.api.nvim_get_current_buf()
	local map_path = vim.b[bufnr].review_explain_map_path
	if not map_path then
		vim.notify("review-explain: not in a :ReviewOpen review list", vim.log.levels.WARN)
		return
	end

	local index = vim.fn.line(".")
	local item, err = M.toggle_checked(map_path, index)
	if not item then
		vim.notify("review-explain: " .. err, vim.log.levels.ERROR)
		return
	end

	local qf_list = vim.fn.getqflist()
	if qf_list[index] then
		qf_list[index].text = format_item_text(item)
		vim.fn.setqflist(qf_list, "r")
	end
end

---Wire up a CursorHold popup in a quickfix buffer showing the review item
---under the cursor's full note/check text, since the single-line quickfix
---entry truncates it. Closes on cursor move / leaving the buffer so it
---never lingers over a different item.
---@param qf_bufnr integer
---@param map table decoded review map ({items, ...})
local function attach_item_popup(qf_bufnr, map)
	local group = vim.api.nvim_create_augroup("review_explain_qf_popup_" .. qf_bufnr, { clear = true })
	local popup_winnr = nil

	local function close_popup()
		if popup_winnr and vim.api.nvim_win_is_valid(popup_winnr) then
			vim.api.nvim_win_close(popup_winnr, true)
		end
		popup_winnr = nil
	end

	vim.api.nvim_create_autocmd("CursorHold", {
		group = group,
		buffer = qf_bufnr,
		callback = function()
			local item = map.items[vim.fn.line(".")]
			if not item then
				return
			end
			local _, winnr = display.show(format_item_detail(item))
			popup_winnr = winnr
		end,
	})

	vim.api.nvim_create_autocmd({ "CursorMoved", "BufLeave", "WinLeave" }, {
		group = group,
		buffer = qf_bufnr,
		callback = close_popup,
	})
end

---Keep diffview.nvim's diff pair in sync when the user jumps to a review
---item's file from the quickfix list (`<CR>`, `]q`/`[q`, `gf`, ...): a
---plain quickfix jump only replaces the buffer in whichever diff pane last
---had focus, so the *other* pane (and diffview's file panel) is left
---showing the previous file's diff. Watching for the resulting BufWinEnter
---and re-selecting the file through diffview's own API keeps both panes
---paired correctly.
---@param root string absolute project root, matched against entered buffers
local function attach_diffview_sync(root)
	local group = vim.api.nvim_create_augroup("review_explain_diffview_sync", { clear = true })
	local prefix = root .. "/"
	local syncing = false

	vim.api.nvim_create_autocmd("BufWinEnter", {
		group = group,
		callback = function(args)
			if syncing or vim.bo[args.buf].buftype ~= "" then
				return
			end

			local name = vim.api.nvim_buf_get_name(args.buf)
			if name:sub(1, #prefix) ~= prefix then
				return
			end

			local ok, lib = pcall(require, "diffview.lib")
			local view = ok and lib.get_current_view()
			if not view then
				return
			end

			local rel_path = name:sub(#prefix + 1)
			local cur_file = view.panel and view.panel.cur_file
			if cur_file and cur_file.path == rel_path then
				return
			end

			syncing = true
			view:set_file_by_path(rel_path, false)
			vim.schedule(function()
				syncing = false
			end)
		end,
	})
end

---`:ReviewOpen <name>`: open the diff against the review map's recorded
---base in diffview.nvim, and populate the quickfix list with its items so
---`]q` / `[q` navigation is immediate.
---@param name string
function M.open(name)
	local root = vim.fs.root(0, { ".git" }) or vim.fn.getcwd()
	local map_path = root .. "/" .. config.cache_dirname .. "/reviews/" .. name .. ".json"

	if vim.fn.filereadable(map_path) == 0 then
		vim.notify("review-explain: no review map found at " .. map_path, vim.log.levels.ERROR)
		return
	end

	local map, decode_failed = cache.read(map_path)
	if decode_failed or not map.items or not map.base then
		vim.notify("review-explain: could not decode review map: " .. map_path, vim.log.levels.ERROR)
		return
	end

	-- Table form, not string concatenation: `map.base` comes from a JSON
	-- file on disk, and passing it as a literal Ex-command argument (rather
	-- than interpolating it into a command string) means a stray `|` or
	-- other Ex-command metacharacter in it can't be parsed as anything but
	-- a literal revision argument.
	vim.cmd({ cmd = "DiffviewOpen", args = { map.base } })
	attach_diffview_sync(root)

	vim.fn.setqflist({}, " ", { title = "review-handoff: " .. name, items = M.build_qf_items(root, map) })
	vim.cmd("copen")

	local qf_bufnr = vim.api.nvim_get_current_buf()
	vim.b[qf_bufnr].review_explain_map_path = map_path
	attach_item_popup(qf_bufnr, map)
	if config.keymaps.review_check then
		vim.keymap.set(
			"n",
			config.keymaps.review_check,
			M.toggle_checked_at_cursor,
			{ buffer = qf_bufnr, desc = "Toggle checked for review item under cursor" }
		)
	end

	M._last = { name = name, qf_bufnr = qf_bufnr }
end

---The review map name /review-handoff derives for the current branch:
---the branch name itself, with `/` replaced by `-` (see its "Derive the
---review map name" step).
---@return string|nil nil if the current directory isn't inside a git repo
---  with a checked-out branch (e.g. detached HEAD)
local function branch_review_name()
	local branch = vim.fn.systemlist("git rev-parse --abbrev-ref HEAD")[1]
	if vim.v.shell_error ~= 0 or not branch or branch == "" or branch == "HEAD" then
		return nil
	end
	return (branch:gsub("/", "-"))
end

---`:ReviewOpen <name>` again (or the `<leader>ao` keymap with no name):
---close the review if it's currently open, otherwise open it. With no
---name, defaults to the most recently opened review, falling back to the
---current git branch's review map name.
---@param name string|nil
function M.toggle(name)
	name = name or (M._last and M._last.name) or branch_review_name()
	if not name then
		vim.notify("review-explain: could not determine a review name (not on a git branch?)", vim.log.levels.WARN)
		return
	end

	if M._last and M._last.name == name and vim.api.nvim_buf_is_valid(M._last.qf_bufnr) then
		vim.cmd("DiffviewClose")
		vim.cmd("cclose")
		M._last = nil
		return
	end

	M.open(name)
end

return M
