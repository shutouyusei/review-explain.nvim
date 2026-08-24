local M = {}

---Extract the contents of the first fenced code block in `text`.
---@param text string
---@return string|nil
function M.extract_fenced_block(text)
	return text:match("```[%w]*\n(.-)\n```")
end

local REQUIRED_FIELDS = { "name", "start_line", "end_line", "explanation" }

---@param entry table
---@return boolean
local function is_valid_entry(entry)
	if type(entry) ~= "table" then
		return false
	end
	for _, field in ipairs(REQUIRED_FIELDS) do
		if entry[field] == nil then
			return false
		end
	end
	return type(entry.name) == "string"
		and type(entry.start_line) == "number"
		and type(entry.end_line) == "number"
		and type(entry.explanation) == "string"
end

---Parse the full stdout of `claude -p ... --output-format json`.
---@param stdout string
---@return table[]|nil entries
---@return string|nil err
function M.parse_cli_output(stdout)
	local ok, envelope = pcall(vim.json.decode, stdout)
	if not ok then
		return nil, "invalid top-level JSON from claude -p: " .. tostring(envelope)
	end
	if envelope.is_error then
		return nil, "claude -p reported is_error=true"
	end
	if type(envelope.result) ~= "string" then
		return nil, "missing string 'result' field in claude -p output"
	end

	local fenced = M.extract_fenced_block(envelope.result)
	local json_text = fenced or envelope.result

	local ok2, entries = pcall(vim.json.decode, json_text)
	if not ok2 then
		return nil, "could not parse explanation JSON: " .. tostring(entries)
	end
	if type(entries) ~= "table" then
		return nil, "explanation JSON was not an array"
	end

	for _, entry in ipairs(entries) do
		if not is_valid_entry(entry) then
			return nil, "an explanation entry was missing a required field"
		end
	end

	return entries, nil
end

return M
