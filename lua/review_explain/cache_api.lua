local resolve = require("review_explain.resolve")
local cache = require("review_explain.cache")
local config = require("review_explain.config")

local M = {}

---Load (or reuse) a listed buffer for `filepath`, with filetype detection
---run so treesitter parsing works -- matching how a real edited buffer
---looks to resolve.lua. Unlike generate.lua's callers, there's no
---already-open buffer to rely on here: this is meant to be invoked from a
---headless `nvim --headless -c "lua ..."` process with no buffers open yet.
---@param filepath string absolute path
---@return integer|nil bufnr
---@return string|nil err
local function open_buffer(filepath)
	if vim.fn.filereadable(filepath) == 0 then
		return nil, "file not readable: " .. filepath
	end
	local bufnr = vim.fn.bufadd(filepath)
	vim.fn.bufload(bufnr)
	return bufnr, nil
end

---Find the function in `bufnr` matching `name`, preferring an exact match
---over the qualified-name tolerance generate.lua also uses (so an exact
---match always wins if both exist, e.g. an inner and outer function that
---happen to satisfy the tolerant check against each other).
---@param bufnr integer
---@param name string
---@return {name:string, start_line:integer, end_line:integer, node:userdata}|nil
local function find_matching_function(bufnr, name)
	local candidates = resolve.find_all_functions(bufnr)
	for _, found in ipairs(candidates) do
		if found.name == name then
			return found
		end
	end
	for _, found in ipairs(candidates) do
		if resolve.names_corroborate(name, found.name) then
			return found
		end
	end
	return nil
end

---Write an explanation into the same cache format generate.lua produces,
---without going through `claude -p` -- the explanation text is supplied by
---the caller (namely `/review-handoff`, pre-attaching explanations for
---complex-but-not-doubtful functions). Meant to be called from a headless
---`nvim --headless -c "lua require('review_explain.cache_api').write(...)"`
---process.
---@param filepath string absolute path to the source file
---@param name string function name (as resolve.lua would report it, e.g. "M.foo")
---@param explanation string
---@return boolean ok
---@return string|nil err
function M.write(filepath, name, explanation)
	local bufnr, open_err = open_buffer(filepath)
	if not bufnr then
		return false, open_err
	end

	local found = find_matching_function(bufnr, name)
	if not found then
		return false, string.format("no function matching '%s' found in %s", name, filepath)
	end

	local hash = resolve.hash_node(bufnr, found.node)
	local root = cache.resolve_root(bufnr)
	local cache_path = cache.cache_path(root .. "/" .. config.cache_dirname, filepath, root)

	cache.merge(cache_path, {
		{ name = found.name, start_line = found.start_line, end_line = found.end_line, explanation = explanation },
	}, { [found.name] = hash })

	return true, nil
end

return M
