local M = {}

---Build the system prompt sent to `claude -p`.
---@param language string|nil human-readable language name for the
---  explanation text (e.g. "English", "Japanese", "日本語"). Defaults to
---  English when nil, empty, or already "english".
---@param long_function_lines integer|nil a function at or above this many
---  lines must get highlights breaking down its processing, even if
---  nothing in it is individually surprising. Defaults to 20.
---@return string
function M.build_system_prompt(language, long_function_lines)
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
- "highlights": an array of notable internal points worth calling out
  on their own -- a non-obvious branch, a validation step, a loop with
  a subtle invariant, a workaround. Each has "about" (a short label
  for the block/line being described, e.g. "input validation" or
  "retry loop"), "note" (1-2 sentences explaining what it does and, if
  relevant, why), and "start_line"/"end_line" (1-indexed line numbers,
  relative to the same snippet as the function's own start_line/
  end_line, spanning exactly the block of code the highlight
  describes -- a few lines, not the whole function).
  - For a function spanning %d lines (end_line - start_line + 1) or
    more: highlights are REQUIRED, not optional. Break its processing
    down into consecutive blocks (3-6 typically) covering the whole
    body, even if no single block is individually surprising -- a long
    function benefits from a step-by-step walkthrough on its own
    merits, not only when something's worth flagging.
  - For a function below that length: omit highlights entirely (empty
    array) unless something specific actually stands out, rather than
    restating the summary in different words in bullet form.
%s
Respond with ONLY a single fenced code block containing a JSON array,
and nothing else before or after it. Each element must have this exact
shape:

{"name": string, "start_line": integer, "end_line": integer, "summary": string, "highlights": [{"about": string, "note": string, "start_line": integer, "end_line": integer}]}

start_line and end_line (both the function's own and each highlight's)
are 1-indexed line numbers relative to the snippet you were given (the
first line of the snippet is line 1).
If the snippet contains no top-level function/method, return an empty
JSON array: []
]],
		long_function_lines or 20,
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
