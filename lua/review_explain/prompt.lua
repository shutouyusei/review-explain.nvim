local M = {}

---Build the system prompt sent to `claude -p`.
---@param language string|nil human-readable language name for the
---  explanation text (e.g. "English", "Japanese", "日本語"). Defaults to
---  English when nil, empty, or already "english".
---@return string
function M.build_system_prompt(language)
	local language_line = ""
	if language and language ~= "" and language:lower() ~= "english" then
		language_line = '\nWrite the "explanation" field in ' .. language .. ".\n"
	end

	return string.format(
		[[
You are a code explanation assistant embedded in a Neovim plugin.
You will be given a snippet of source code from a file.
Identify each top-level function or method defined in the snippet.
For each one, produce:
- "summary": a concise explanation (2-4 sentences, no code repetition)
  of what the function does overall.
- "highlights": an array of 0-4 notable internal points worth calling
  out on their own -- a non-obvious branch, a validation step, a loop
  with a subtle invariant, a workaround. Each has "about" (a short
  label for the block/line being described, e.g. "input validation" or
  "retry loop") and "note" (1-2 sentences explaining what it does and,
  if relevant, why). Omit trivial functions' highlights entirely
  (empty array) rather than restating the summary in different words.
%s
Respond with ONLY a single fenced code block containing a JSON array,
and nothing else before or after it. Each element must have this exact
shape:

{"name": string, "start_line": integer, "end_line": integer, "summary": string, "highlights": [{"about": string, "note": string}]}

start_line and end_line are 1-indexed line numbers relative to the
snippet you were given (the first line of the snippet is line 1).
If the snippet contains no top-level function/method, return an empty
JSON array: []
]],
		language_line
	)
end

---Build the per-call user message sent to `claude -p`.
---@param code string the selected source code
---@param filepath string absolute or relative path of the source file
---@param filetype string neovim filetype, used as the fence language
---@return string
function M.build_user_message(code, filepath, filetype)
	return string.format("File: %s\nLanguage: %s\n\n```%s\n%s\n```", filepath, filetype, filetype, code)
end

return M
