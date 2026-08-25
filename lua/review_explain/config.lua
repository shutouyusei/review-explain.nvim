local M = {
	-- Model passed to `claude -p --model <model>` (an alias like "sonnet",
	-- "opus", "haiku", or a full model id). nil falls back to claude's own
	-- default model for the current session instead of forcing one.
	model = "sonnet",

	-- Directory (relative to the resolved project root) the explanation
	-- cache is stored under. Meant to be git-tracked.
	cache_dirname = ".nvim-review",

	-- A function at or above this many lines must get highlights (a
	-- per-processing-block breakdown) even if nothing in it is individually
	-- surprising -- long functions benefit from a step-by-step walkthrough
	-- on their own merits, not just when something's worth doubting.
	-- Shorter functions still only get highlights when something actually
	-- stands out.
	long_function_lines = 20,

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
		review_toggle = "<leader>ao",
	},

	-- If true, review_explain disables real vim folding (`foldenable`) on
	-- buffers it manages, via the same FileType autocmd that registers `K`
	-- -- code buffers otherwise start with functions collapsed under
	-- whatever foldmethod the user's config sets up (e.g. treesitter fold
	-- with foldlevel 0), which fights with reading a function's AI
	-- explanation next to its (folded-away) body. Set to false to leave
	-- folding alone.
	disable_folding = true,

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
