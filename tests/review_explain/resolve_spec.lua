local resolve = require("review_explain.resolve")

local function make_lua_buffer(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].filetype = "lua"
  return bufnr
end

describe("review_explain.resolve.find_enclosing_function", function()
  it("finds a local function containing the given line", function()
    local bufnr = make_lua_buffer({
      "local function calculate_reward(x)",
      "  local y = x * 2",
      "  return y",
      "end",
    })
    local found = resolve.find_enclosing_function(bufnr, 1) -- inside the body
    assert.is_table(found)
    assert.equal("calculate_reward", found.name)
    assert.equal(1, found.start_line)
    assert.equal(4, found.end_line)
  end)

  it("finds a dot-indexed function (function M.foo() end)", function()
    local bufnr = make_lua_buffer({
      "function M.find_enclosing_function(bufnr, lnum)",
      "  local node = get_node(bufnr, lnum)",
      "  return node",
      "end",
    })
    local found = resolve.find_enclosing_function(bufnr, 1)
    assert.is_table(found)
    assert.equal("find_enclosing_function", found.name)
  end)

  it("finds a method-indexed function (function M:method() end)", function()
    local bufnr = make_lua_buffer({
      "function Parser:parse(source)",
      "  local tree = self:build_tree(source)",
      "  return tree",
      "end",
    })
    local found = resolve.find_enclosing_function(bufnr, 1)
    assert.is_table(found)
    assert.equal("parse", found.name)
  end)

  it("finds an assignment-style anonymous function (M.foo = function() end)", function()
    local bufnr = make_lua_buffer({
      "M.process = function(data)",
      "  return data * 2",
      "end",
    })
    local found = resolve.find_enclosing_function(bufnr, 1)
    assert.is_table(found)
    assert.equal("process", found.name)
  end)

  it("resolves to the innermost function, not a parent function", function()
    local bufnr = make_lua_buffer({
      "local function outer()",
      "  M.inner = function()",
      "    local y = 42",
      "  end",
      "end",
    })
    -- lnum 2 is inside the inner function body (the "local y = 42" line)
    local found = resolve.find_enclosing_function(bufnr, 2)
    assert.is_table(found)
    assert.equal("inner", found.name)
    assert.is_not.equal("outer", found.name)
  end)

  it("does not misattribute functions nested in table constructors", function()
    local bufnr = make_lua_buffer({
      "M.handlers = {",
      "  onClick = function()",
      "    local x = 1",
      "  end,",
      "}",
    })
    -- lnum 2 is inside the onClick function body
    local found = resolve.find_enclosing_function(bufnr, 2)
    -- The function is nested inside a table, not directly assigned, so should not be "handlers"
    if found then
      assert.is_not.equal("handlers", found.name)
    end
    -- If found, it should be nil since the function has no direct name (anonymous in table)
    assert.is_nil(found)
  end)

  it("resolves an indented function signature line (e.g. nested inside a do block)", function()
    local bufnr = make_lua_buffer({
      "do",
      "  local function indented_helper(x)",
      "    return x + 1",
      "  end",
      "end",
    })
    -- lnum 1 is the indented function signature line itself, probed at column 0
    -- would land on whitespace outside the function node.
    local found = resolve.find_enclosing_function(bufnr, 1)
    assert.is_table(found)
    assert.equal("indented_helper", found.name)
    assert.equal(2, found.start_line)
    assert.equal(4, found.end_line)
  end)

  it("returns nil when the line is outside any function", function()
    local bufnr = make_lua_buffer({
      "local x = 1",
      "local y = 2",
    })
    assert.is_nil(resolve.find_enclosing_function(bufnr, 0))
  end)
end)

describe("review_explain.resolve.find_all_functions", function()
  it("finds every top-level function in the buffer", function()
    local bufnr = make_lua_buffer({
      "local function foo()",
      "  return 1",
      "end",
      "",
      "function M.bar()",
      "  return 2",
      "end",
    })
    local found = resolve.find_all_functions(bufnr)
    local names = {}
    for _, f in ipairs(found) do
      table.insert(names, f.name)
    end
    table.sort(names)
    assert.same({ "bar", "foo" }, names)
  end)

  it("also finds nested functions, not just top-level ones", function()
    local bufnr = make_lua_buffer({
      "local function outer()",
      "  M.inner = function()",
      "    return 1",
      "  end",
      "end",
    })
    local found = resolve.find_all_functions(bufnr)
    local names = {}
    for _, f in ipairs(found) do
      table.insert(names, f.name)
    end
    table.sort(names)
    assert.same({ "inner", "outer" }, names)
  end)

  it("returns an empty list when there are no functions", function()
    local bufnr = make_lua_buffer({ "local x = 1" })
    assert.same({}, resolve.find_all_functions(bufnr))
  end)
end)

describe("review_explain.resolve.hash_node", function()
  it("produces the same hash for identical function bodies", function()
    local buf_a = make_lua_buffer({ "local function f()", "  return 1", "end" })
    local buf_b = make_lua_buffer({ "local function f()", "  return 1", "end" })
    local node_a = resolve.find_enclosing_function(buf_a, 1).node
    local node_b = resolve.find_enclosing_function(buf_b, 1).node
    assert.equal(resolve.hash_node(buf_a, node_a), resolve.hash_node(buf_b, node_b))
  end)

  it("produces a different hash when the body changes", function()
    local buf_a = make_lua_buffer({ "local function f()", "  return 1", "end" })
    local buf_b = make_lua_buffer({ "local function f()", "  return 2", "end" })
    local node_a = resolve.find_enclosing_function(buf_a, 1).node
    local node_b = resolve.find_enclosing_function(buf_b, 1).node
    assert.is_not.equal(resolve.hash_node(buf_a, node_a), resolve.hash_node(buf_b, node_b))
  end)
end)
