local M = {}

---@class ReviewExplainClientOpts
---@field system_prompt string
---@field user_message string
---@field model string|nil

---Build the argv for a one-shot `claude -p` call.
---@param opts ReviewExplainClientOpts
---@return string[]
function M.build_cmd(opts)
	local cmd = { "claude", "-p", opts.user_message, "--output-format", "json", "--system-prompt", opts.system_prompt }
	if opts.model then
		vim.list_extend(cmd, { "--model", opts.model })
	end
	return cmd
end

---Run `claude -p` asynchronously and report the result.
---@param opts ReviewExplainClientOpts
---@param on_done fun(ok: boolean, stdout_or_err: string)
---@param runner fun(cmd: string[], run_opts: table, cb: fun(obj: table))|nil defaults to vim.system
function M.run(opts, on_done, runner)
	local using_default_runner = runner == nil
	runner = runner or function(cmd, run_opts, cb)
		vim.system(cmd, run_opts, cb)
	end
	local cmd = M.build_cmd(opts)
	local run_opts = { text = true, timeout = 60000 }

	local function handle_result(obj)
		vim.schedule(function()
			if obj.code ~= 0 then
				on_done(false, (obj.stderr and obj.stderr ~= "") and obj.stderr or ("claude exited with code " .. obj.code))
				return
			end
			on_done(true, obj.stdout)
		end)
	end

	if using_default_runner then
		-- vim.system raises an uncaught error (rather than failing the
		-- callback) if the binary isn't found on PATH; wrap it so that
		-- becomes a clean on_done(false, ...) notification instead.
		local ok, err = pcall(runner, cmd, run_opts, handle_result)
		if not ok then
			vim.schedule(function()
				on_done(false, "claude CLI not found: " .. tostring(err))
			end)
		end
	else
		runner(cmd, run_opts, handle_result)
	end
end

return M
