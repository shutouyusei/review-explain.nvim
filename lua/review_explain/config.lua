local M = {
	-- Model passed to `claude -p --model <model>`. nil uses claude's own
	-- default model for the current session.
	model = nil,

	-- Directory (relative to the resolved project root) the explanation
	-- cache is stored under. Meant to be git-tracked.
	cache_dirname = ".nvim-review",

	-- Human-readable language name the "explanation" text is written in,
	-- e.g. "English", "Japanese", "日本語". Any value other than nil, "",
	-- or "english" (case-insensitive) is passed straight into the prompt.
	language = "English",

	keymaps = {
		-- Visual-mode mapping that explains the selected range. Set to
		-- false to not register it.
		explain = "<leader>ce",

		-- Normal-mode mapping, registered only in the quickfix buffer a
		-- :ReviewOpen call populates, that toggles `checked` on the review
		-- item under the cursor. Set to false to not register it.
		review_check = "<leader>cx",

		-- Normal-mode mapping (global) that toggles the most recently
		-- opened :ReviewOpen review closed/open. Set to false to not
		-- register it.
		review_toggle = "<leader>ro",
	},

	-- If true, review_explain registers its own buffer-local `K` mapping
	-- on FileType (falling back to vim.lsp.buf.hover() when there's no
	-- cached explanation for the position). Set to false if you'd rather
	-- wire recall.show() into your own hover keymap -- e.g. LazyVim users
	-- may want to add it to `opts.servers['*'].keys` in their nvim-lspconfig
	-- spec instead, since Snacks.nvim's own K registration can otherwise
	-- overwrite a plain FileType-time mapping on LSP-attached buffers. See
	-- the README for that setup.
	register_hover_keymap = true,

	-- Filetypes where review_explain never claims `K` (register_hover_keymap)
	-- or shows explained-function markers, so buffers like :help or :Man
	-- keep their own default K behavior.
	excluded_filetypes = {
		help = true,
		man = true,
		qf = true,
		checkhealth = true,
		lazy = true,
		mason = true,
		lspinfo = true,
		query = true,
	},
}

return M
