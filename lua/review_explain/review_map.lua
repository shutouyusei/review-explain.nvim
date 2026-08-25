local cache = require("review_explain.cache")
local config = require("review_explain.config")

local M = {}

---@param item table one review-map item ({kind, note, check, checked, ...})
---@return string
local function format_item_text(item)
	local prefix = item.checked and "[x] " or "[ ] "
	return prefix .. item.kind .. ": " .. item.note .. " -- check: " .. item.check
end

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

	vim.cmd("DiffviewOpen " .. map.base)

	vim.fn.setqflist({}, " ", { title = "review-handoff: " .. name, items = M.build_qf_items(root, map) })
	vim.cmd("copen")

	local qf_bufnr = vim.api.nvim_get_current_buf()
	vim.b[qf_bufnr].review_explain_map_path = map_path
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

---`:ReviewOpen <name>` again (or the `<leader>ao` keymap with no name):
---close the review if it's currently open, otherwise open it.
---@param name string|nil defaults to the most recently opened review
function M.toggle(name)
	name = name or (M._last and M._last.name)
	if not name then
		vim.notify("review-explain: no review to toggle; run :ReviewOpen <name> first", vim.log.levels.WARN)
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
