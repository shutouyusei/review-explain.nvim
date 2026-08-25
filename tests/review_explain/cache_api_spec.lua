local cache_api = require("review_explain.cache_api")
local resolve = require("review_explain.resolve")
local cache = require("review_explain.cache")

local function tmp_project()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  vim.fn.system({ "git", "init", "-q", dir })
  return dir
end

local function write_file(path, lines)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile(lines, path)
end

describe("review_explain.cache_api.write", function()
  it("finds an existing function by exact name and merges it into the cache with the matching body_hash", function()
    local dir = tmp_project()
    local filepath = dir .. "/src/foo.lua"
    write_file(filepath, {
      "local function calculate(x)",
      "  return x * 2",
      "end",
    })

    local ok, err = cache_api.write(filepath, "calculate", "Doubles the input.")
    assert.is_true(ok)
    assert.is_nil(err)

    local cache_path = dir .. "/.nvim-review/src/foo.lua.json"
    local entries = cache.read(cache_path)
    assert.is_table(entries.calculate)
    assert.equal(1, #entries.calculate)
    assert.equal("Doubles the input.", entries.calculate[1].explanation)

    local bufnr = vim.fn.bufadd(filepath)
    vim.fn.bufload(bufnr)
    local found = resolve.find_enclosing_function(bufnr, 0)
    assert.equal(resolve.hash_node(bufnr, found.node), entries.calculate[1].body_hash)
  end)

  it("matches a qualified name against a bare resolved name, the same tolerance generate.lua uses", function()
    local dir = tmp_project()
    local filepath = dir .. "/src/foo.lua"
    write_file(filepath, {
      "local function calculate(x)",
      "  return x * 2",
      "end",
    })

    local ok = cache_api.write(filepath, "M.calculate", "Doubles the input.")
    assert.is_true(ok)

    local entries = cache.read(dir .. "/.nvim-review/src/foo.lua.json")
    assert.is_table(entries.calculate)
  end)

  it("returns false with a message identifying the file/name when no function matches", function()
    local dir = tmp_project()
    local filepath = dir .. "/src/foo.lua"
    write_file(filepath, {
      "local function calculate(x)",
      "  return x * 2",
      "end",
    })

    local ok, err = cache_api.write(filepath, "not_here", "explanation")
    assert.is_false(ok)
    assert.is_string(err)
    assert.truthy(err:find("not_here", 1, true))
    assert.truthy(err:find(filepath, 1, true))
  end)

  it("returns false with a message when the file does not exist", function()
    local dir = tmp_project()
    local ok, err = cache_api.write(dir .. "/src/missing.lua", "calculate", "explanation")
    assert.is_false(ok)
    assert.is_string(err)
  end)

  it("adds a new revision (does not overwrite) when the function body changed since a prior write", function()
    local dir = tmp_project()
    local filepath = dir .. "/src/foo.lua"
    write_file(filepath, {
      "local function calculate(x)",
      "  return x * 2",
      "end",
    })
    cache_api.write(filepath, "calculate", "Doubles the input.")

    write_file(filepath, {
      "local function calculate(x)",
      "  return x * 3",
      "end",
    })
    -- Force review-explain to see the new file content rather than the
    -- buffer left over from the first write() call.
    local bufnr = vim.fn.bufadd(filepath)
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd("edit!")
    end)

    cache_api.write(filepath, "calculate", "Triples the input.")

    local entries = cache.read(dir .. "/.nvim-review/src/foo.lua.json")
    assert.equal(2, #entries.calculate)
    assert.equal("Triples the input.", entries.calculate[1].explanation)
    assert.equal("Doubles the input.", entries.calculate[2].explanation)
  end)
end)
