local M = {}

---@type table<string, boolean>
local FUNCTION_NODE_TYPES = {
	function_declaration = true,
	function_definition = true,
}

---@type table<string, boolean>
local NAME_NODE_TYPES = {
	identifier = true,
	name = true,
	property_identifier = true,
}

---Extract the rightmost identifier from a dot_index_expression or method_index_expression.
---@param bufnr integer
---@param expr_node userdata
---@return string|nil
local function extract_index_name(bufnr, expr_node)
	-- For dot_index_expression (M.foo) or method_index_expression (M:method),
	-- iterate to find the rightmost identifier
	local rightmost_id = nil
	for child in expr_node:iter_children() do
		if child:type() == "identifier" or child:type() == "property_identifier" then
			rightmost_id = vim.treesitter.get_node_text(child, bufnr)
		end
	end
	return rightmost_id
end

---Check if a function node is the direct RHS value of an assignment (not nested inside a table/other expr).
---@param func_node userdata the function_definition node
---@param assign_node userdata the assignment_statement node
---@return boolean true if func_node is directly the RHS of assign_node
local function is_direct_rhs_of_assignment(func_node, assign_node)
	-- Walk up from func_node to find if we hit assign_node with expression_list as the only intermediate
	local current = func_node:parent()

	-- Direct case: func_definition -> expression_list -> assignment_statement
	if current and current:type() == "expression_list" then
		local grandparent = current:parent()
		if grandparent == assign_node then
			return true
		end
	end

	-- If we hit a table constructor, field, or other expression before reaching assignment, it's not direct
	return false
end

---Extract the function name from an assignment LHS (e.g., M.foo in "M.foo = function() end").
---Only applies if the function is the direct RHS value, not nested in table/other structures.
---@param bufnr integer
---@param assign_node userdata
---@param func_node userdata the function_definition node being checked
---@return string|nil
local function extract_assignment_name(bufnr, assign_node, func_node)
	-- Only extract the assignment name if the function is the *direct* RHS value
	if not is_direct_rhs_of_assignment(func_node, assign_node) then
		return nil
	end

	-- The assignment statement has children: (variable_list, "=", expression_list)
	-- The variable_list contains the LHS; we want the rightmost identifier in it
	local var_list = nil
	for child in assign_node:iter_children() do
		if child:type() == "variable_list" then
			var_list = child
			break
		end
	end

	if not var_list then
		return nil
	end

	-- Within the variable_list, look for a field (dot_index_expression, method_index_expression, identifier, etc.)
	local rightmost_id = nil
	for child in var_list:iter_children() do
		if child:type() == "dot_index_expression" or child:type() == "method_index_expression" then
			-- Extract the rightmost identifier from the index expression
			rightmost_id = extract_index_name(bufnr, child)
		elseif child:type() == "identifier" or child:type() == "property_identifier" then
			rightmost_id = vim.treesitter.get_node_text(child, bufnr)
		end
	end
	return rightmost_id
end

---Resolve the name of a function-like treesitter node.
---Handles: local function foo(), function M.foo(), function M:method(), and M.foo = function().
---@param bufnr integer
---@param node userdata (must be a function node type)
---@return string|nil
local function node_name(bufnr, node)
	-- Try direct children first (for simple cases like "local function foo()" where the first
	-- identifier child is the name)
	for child in node:iter_children() do
		if NAME_NODE_TYPES[child:type()] then
			return vim.treesitter.get_node_text(child, bufnr)
		end
	end

	-- Try to find a dot_index_expression or method_index_expression child (for "function M.foo()" or "function M:method()")
	for child in node:iter_children() do
		if child:type() == "dot_index_expression" or child:type() == "method_index_expression" then
			return extract_index_name(bufnr, child)
		end
	end

	-- If the function node has no name-bearing child, check if an ancestor is an assignment_statement
	-- (for "M.foo = function()" style). The function_definition is inside expression_list which is
	-- inside assignment_statement. Only extract the assignment name if the function is the direct RHS.
	local parent = node:parent()
	while parent do
		if parent:type() == "assignment_statement" then
			return extract_assignment_name(bufnr, parent, node)
		end
		parent = parent:parent()
	end

	return nil
end

---Find the smallest function-like treesitter node containing `lnum`.
---@param bufnr integer
---@param lnum integer 0-indexed line number
---@return {name:string, start_line:integer, end_line:integer, node:userdata}|nil
function M.find_enclosing_function(bufnr, lnum)
	local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
	if not ok or not parser then
		return nil
	end
	local tree = parser:parse()[1]
	if not tree then
		return nil
	end
	local root = tree:root()

	-- Probe at the first non-blank column of the line rather than column 0:
	-- on an indented line (e.g. a method inside a class, a function nested in
	-- a do/if block) column 0 is whitespace, outside the function node, so
	-- resolution would otherwise fail on the function's own signature line --
	-- exactly the line the LLM usually reports as start_line.
	local col = 0
	local line_text = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]
	if line_text then
		local first_non_blank = line_text:find("%S")
		if first_non_blank then
			col = first_non_blank - 1
		end
	end

	local node = root:named_descendant_for_range(lnum, col, lnum, col)
	while node do
		if FUNCTION_NODE_TYPES[node:type()] then
			local name = node_name(bufnr, node)
			if name then
				local srow, _, erow, _ = node:range()
				return { name = name, start_line = srow + 1, end_line = erow + 1, node = node }
			end
		end
		node = node:parent()
	end
	return nil
end

---Find every function-like node in the buffer, each with its resolved name.
---Used to scan a whole buffer (e.g. for highlighting explained functions),
---as opposed to find_enclosing_function's single-position lookup.
---@param bufnr integer
---@return {name:string, start_line:integer, end_line:integer, node:userdata}[]
function M.find_all_functions(bufnr)
	local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
	if not ok or not parser then
		return {}
	end
	local tree = parser:parse()[1]
	if not tree then
		return {}
	end

	local results = {}
	local function walk(node)
		if FUNCTION_NODE_TYPES[node:type()] then
			local name = node_name(bufnr, node)
			if name then
				local srow, _, erow, _ = node:range()
				table.insert(results, { name = name, start_line = srow + 1, end_line = erow + 1, node = node })
			end
		end
		for child in node:iter_children() do
			walk(child)
		end
	end
	walk(tree:root())

	return results
end

---@param bufnr integer
---@param node userdata
---@return string sha256 hex digest of the node's source text
function M.hash_node(bufnr, node)
	local text = vim.treesitter.get_node_text(node, bufnr)
	return vim.fn.sha256(text)
end

return M
