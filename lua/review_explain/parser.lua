local M = {}

---Extract the contents of the first fenced code block in `text`.
---@param text string
---@return string|nil
function M.extract_fenced_block(text)
	return text:match("```[%w]*\n(.-)\n```")
end

local REQUIRED_FIELDS = { "name", "start_line", "end_line" }

---@param highlights any
---@return boolean
local function is_valid_highlights(highlights)
	if highlights == nil then
		return true
	end
	if type(highlights) ~= "table" then
		return false
	end
	for _, h in ipairs(highlights) do
		if
			type(h) ~= "table"
			or type(h.about) ~= "string"
			or type(h.note) ~= "string"
			or type(h.start_line) ~= "number"
			or type(h.end_line) ~= "number"
		then
			return false
		end
	end
	return true
end

---An entry is valid with either the legacy `explanation` string field, or
---the newer `summary` string field (optionally paired with `highlights`,
---an array of {about, note} internal-block notes). Both shapes may coexist
---in an old cache, so recall.lua must handle either at display time.
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
	if type(entry.name) ~= "string" or type(entry.start_line) ~= "number" or type(entry.end_line) ~= "number" then
		return false
	end
	local has_explanation = type(entry.explanation) == "string"
	local has_summary = type(entry.summary) == "string"
	if not (has_explanation or has_summary) then
		return false
	end
	return is_valid_highlights(entry.highlights)
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
