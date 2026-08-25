-- Test harness bootstrap. Requires plenary.nvim, nvim-treesitter, and
-- diffview.nvim to already be installed via your plugin manager (this
-- only adds them to the runtimepath for the test run, it doesn't install
-- anything).
local function find_plugin_dir(name)
	local candidates = {
		vim.fn.stdpath("data") .. "/lazy/" .. name,
		vim.fn.stdpath("data") .. "/site/pack/packer/start/" .. name,
		vim.fn.stdpath("data") .. "/site/pack/packer/opt/" .. name,
	}
	for _, path in ipairs(candidates) do
		if vim.fn.isdirectory(path) == 1 then
			return path
		end
	end
	error(
		string.format(
			"review-explain.nvim tests: could not find '%s' under any known plugin manager install path. "
				.. "Install it via your plugin manager first.",
			name
		)
	)
end

vim.opt.rtp:append(find_plugin_dir("plenary.nvim"))
vim.opt.rtp:append(find_plugin_dir("nvim-treesitter"))
vim.opt.rtp:append(find_plugin_dir("diffview.nvim"))
-- Prepend (not append): Neovim's default runtimepath already includes
-- stdpath("config") (~/.config/nvim), which may itself contain a
-- lua/review_explain/ (e.g. this plugin embedded in a dotfiles repo,
-- pre-extraction) that would otherwise shadow this checkout's copy.
vim.opt.rtp:prepend(vim.fn.getcwd())

vim.cmd("runtime plugin/plenary.vim")
require("plenary.busted")
