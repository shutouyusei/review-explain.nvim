local prompt = require("review_explain.prompt")
local client = require("review_explain.client")
local parser = require("review_explain.parser")
local resolve = require("review_explain.resolve")
local cache = require("review_explain.cache")
local config = require("review_explain.config")

local M = {}

local ns = vim.api.nvim_create_namespace("review_explain")

-- Re-entrancy guard: tracks buffers with an in-flight `claude -p` call so a
-- repeated keypress doesn't fire overlapping requests that could race writing
-- to the same cache file.
---@type table<integer, boolean>
local in_flight = {}

---Explain every top-level function in the given (0-indexed, inclusive) range.
---@param bufnr integer
---@param start_lnum integer
---@param end_lnum integer
function M.run(bufnr, start_lnum, end_lnum)
	if in_flight[bufnr] then
		vim.notify("review-explain: a request is already in flight for this buffer", vim.log.levels.WARN)
		return
	end

	local filepath = vim.api.nvim_buf_get_name(bufnr)
	if filepath == "" then
		vim.notify("review-explain: buffer has no file path", vim.log.levels.ERROR)
		return
	end
	local filetype = vim.bo[bufnr].filetype
	local lines = vim.api.nvim_buf_get_lines(bufnr, start_lnum, end_lnum + 1, false)
	local code = table.concat(lines, "\n")

	vim.notify("review-explain: asking Claude...", vim.log.levels.INFO)

	in_flight[bufnr] = true
	client.run({
		system_prompt = prompt.build_system_prompt(config.language),
		user_message = prompt.build_user_message(code, filepath, filetype),
		model = config.model,
	}, function(ok, stdout_or_err)
		in_flight[bufnr] = nil

		if not ok then
			vim.notify("review-explain: " .. stdout_or_err, vim.log.levels.ERROR)
			return
		end

		if not vim.api.nvim_buf_is_valid(bufnr) then
			vim.notify("review-explain: buffer no longer valid, discarding result", vim.log.levels.WARN)
			return
		end

		local entries, err = parser.parse_cli_output(stdout_or_err)
		if not entries then
			vim.notify("review-explain: " .. err, vim.log.levels.ERROR)
			return
		end
		if #entries == 0 then
			vim.notify("review-explain: no functions found in selection", vim.log.levels.WARN)
			return
		end

		local body_hashes = {}
		local resolved_entries = {}
		local unresolved_count = 0
		for _, entry in ipairs(entries) do
			-- entry.start_line is 1-indexed relative to the selection; translate
			-- to an absolute 0-indexed buffer line to search from.
			local abs_lnum = start_lnum + entry.start_line - 1
			local found = resolve.find_enclosing_function(bufnr, abs_lnum)
			if found and resolve.names_corroborate(entry.name, found.name) then
				-- Key everything by resolve's canonical (treesitter-resolved) name,
				-- never by whatever name the LLM reported, so cache.merge and
				-- recall.show (which also keys by resolve's name) agree.
				body_hashes[found.name] = resolve.hash_node(bufnr, found.node)
				table.insert(resolved_entries, {
					name = found.name,
					start_line = found.start_line,
					end_line = found.end_line,
					explanation = entry.explanation,
				})
				vim.api.nvim_buf_set_extmark(bufnr, ns, found.start_line - 1, 0, {
					end_row = found.end_line - 1,
				})
			else
				unresolved_count = unresolved_count + 1
			end
		end

		if unresolved_count > 0 then
			vim.notify(
				string.format("review-explain: %d function(s) could not be resolved", unresolved_count),
				vim.log.levels.WARN
			)
		end

		if #resolved_entries == 0 then
			vim.notify("review-explain: no functions could be resolved in selection", vim.log.levels.WARN)
			return
		end

		local root = cache.resolve_root(bufnr)
		local cache_path = cache.cache_path(root .. "/" .. config.cache_dirname, filepath, root)
		cache.merge(cache_path, resolved_entries, body_hashes)
		require("review_explain.recall").highlight_buffer(bufnr)

		vim.notify(
			string.format("review-explain: explained %d function(s)", #resolved_entries),
			vim.log.levels.INFO
		)
	end)
end

return M
