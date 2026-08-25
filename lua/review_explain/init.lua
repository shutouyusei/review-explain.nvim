local config = require("review_explain.config")

local M = {}

---@param opts table|nil overrides for review_explain.config's defaults;
---  deep-merged, so e.g. `{ excluded_filetypes = { markdown = true } }`
---  only adds to the default exclusions rather than replacing the table.
local function merge_config(opts)
	local merged = vim.tbl_deep_extend("force", config, opts or {})
	for k in pairs(config) do
		config[k] = nil
	end
	for k, v in pairs(merged) do
		config[k] = v
	end
end

-- Explicit, non-linked colors so they're visible under any colorscheme,
-- including a transparent-background one: several commonly-linked groups
-- (e.g. Folded) carry no `bg` at all in that case. Box groups set `bg`
-- only so the underlying syntax color still shows through; sign groups
-- set `fg` only since sign-column glyphs have no separate syntax color to
-- combine with.
local function apply_highlights()
	if vim.o.background == "light" then
		vim.api.nvim_set_hl(0, "ReviewExplainExplained", { bg = "#cfe0ff" })
		vim.api.nvim_set_hl(0, "ReviewExplainStale", { bg = "#ffe3b3" })
		vim.api.nvim_set_hl(0, "ReviewExplainExplainedSign", { fg = "#1a3a6b" })
		vim.api.nvim_set_hl(0, "ReviewExplainStaleSign", { fg = "#6b4a1a" })
		vim.api.nvim_set_hl(0, "ReviewExplainHighlightBox", { fg = "#7a4fb5" })
	else
		vim.api.nvim_set_hl(0, "ReviewExplainExplained", { bg = "#2d3f6b" })
		vim.api.nvim_set_hl(0, "ReviewExplainStale", { bg = "#6b4a1a" })
		vim.api.nvim_set_hl(0, "ReviewExplainExplainedSign", { fg = "#bcd4ff" })
		vim.api.nvim_set_hl(0, "ReviewExplainStaleSign", { fg = "#ffd699" })
		vim.api.nvim_set_hl(0, "ReviewExplainHighlightBox", { fg = "#c9a6ff" })
	end
end

---@param opts table|nil see lua/review_explain/config.lua for the full
---  list of options and their defaults.
function M.setup(opts)
	merge_config(opts)

	apply_highlights()
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("review_explain_colors", { clear = true }),
		callback = apply_highlights,
	})

	local generate = require("review_explain.generate")
	local recall = require("review_explain.recall")
	local review_map = require("review_explain.review_map")

	vim.api.nvim_create_user_command("ReviewOpen", function(args)
		review_map.open(args.args)
	end, {
		nargs = 1,
		desc = "Open a /review-handoff review map's diff (diffview.nvim) and quickfix list",
	})

	if config.keymaps.review_toggle then
		vim.keymap.set("n", config.keymaps.review_toggle, function()
			review_map.toggle()
		end, { desc = "Toggle the most recently opened :ReviewOpen review" })
	end

	if config.keymaps.explain then
		vim.keymap.set("x", config.keymaps.explain, function()
			vim.cmd("normal! \27") -- exit visual mode so '< '> marks are set
			local start_lnum = vim.api.nvim_buf_get_mark(0, "<")[1] - 1
			local end_lnum = vim.api.nvim_buf_get_mark(0, ">")[1] - 1
			generate.run(0, start_lnum, end_lnum)
		end, { desc = "Explain selection with Claude" })
	end

	vim.api.nvim_create_autocmd("FileType", {
		group = vim.api.nvim_create_augroup("review_explain_filetype", { clear = true }),
		callback = function(args)
			if config.excluded_filetypes[args.match] then
				return
			end

			if config.register_hover_keymap then
				vim.keymap.set("n", "K", function()
					recall.show(args.buf)
				end, { buffer = args.buf, desc = "Hover / cached explanation" })
			end

			if config.disable_folding then
				vim.wo.foldenable = false
			end

			recall.highlight_buffer(args.buf)
		end,
	})
end

return M
