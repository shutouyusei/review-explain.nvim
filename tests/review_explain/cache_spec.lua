local cache = require("review_explain.cache")

local function tmp_dir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  return dir
end

describe("review_explain.cache.cache_path", function()
  it("mirrors the file's path relative to cwd, under the cache root, with .json appended", function()
    local path = cache.cache_path("/proj/.nvim-review", "/proj/src/foo.lua", "/proj")
    assert.equal("/proj/.nvim-review/src/foo.lua.json", path)
  end)

  it("maps a diffview.nvim virtual buffer name to the same path as the real file", function()
    -- Real diffview.nvim buffer names, confirmed against the installed
    -- plugin: diffview://<root>/<git-dir-name>/<rev>/<path>. <git-dir-name>
    -- is typically ".git"; <rev> is an abbreviated hash or a stage marker.
    local real = cache.cache_path("/proj/.nvim-review", "/proj/src/foo.lua", "/proj")
    local diffview_commit = cache.cache_path(
      "/proj/.nvim-review",
      "diffview:///proj/.git/a1b2c3d4e5f/src/foo.lua",
      "/proj"
    )
    local diffview_stage = cache.cache_path("/proj/.nvim-review", "diffview:///proj/.git/:0:/src/foo.lua", "/proj")
    assert.equal(real, diffview_commit)
    assert.equal(real, diffview_stage)
  end)

  it("leaves a diffview path under a different root unchanged (falls through)", function()
    local other = "diffview:///other-root/abc/src/foo.lua"
    local path = cache.cache_path("/proj/.nvim-review", other, "/proj")
    assert.equal("/proj/.nvim-review/" .. other .. ".json", path)
  end)
end)

describe("review_explain.cache.resolve_root", function()
  it("extracts the root directly from a diffview buffer name, regardless of cwd", function()
    -- vim.fs.root() cannot resolve "diffview://" names (they aren't real
    -- filesystem paths) and falls back to getcwd(), which is unreliable --
    -- this must work correctly even when cwd is something else entirely.
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_name(bufnr, "diffview:///some/project/.git/abc123/src/foo.lua")
    assert.equal("/some/project", cache.resolve_root(bufnr))
  end)

  it("matches the root a real file buffer under the same project would resolve to", function()
    local dir = tmp_dir()
    vim.fn.system({ "git", "init", "-q", dir })
    local real_bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_name(real_bufnr, dir .. "/src/foo.lua")
    local dv_bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_name(dv_bufnr, "diffview://" .. dir .. "/.git/abc123/src/foo.lua")

    assert.equal(cache.resolve_root(real_bufnr), cache.resolve_root(dv_bufnr))
  end)
end)

describe("review_explain.cache read/write/merge", function()
  it("read returns an empty table when the file does not exist", function()
    local dir = tmp_dir()
    local got, decode_failed = cache.read(dir .. "/nope.json")
    assert.same({}, got)
    assert.is_false(decode_failed)
  end)

  it("write then read round-trips the data", function()
    local dir = tmp_dir()
    local path = dir .. "/sub/foo.lua.json"
    cache.write(path, { foo = { explanation = "does a thing" } })
    local got = cache.read(path)
    assert.equal("does a thing", got.foo.explanation)
  end)

  it("read signals decode_failed on a corrupt file instead of silently returning {}", function()
    local dir = tmp_dir()
    local path = dir .. "/corrupt.json"
    local f = assert(io.open(path, "w"))
    f:write("<<<<<<< HEAD\n{\"foo\": 1}\n=======\n{\"foo\": 2}\n>>>>>>> branch\n")
    f:close()
    local got, decode_failed = cache.read(path)
    assert.same({}, got)
    assert.is_true(decode_failed)
  end)

  it("merge adds new entries as a single-element revision list, most recent first", function()
    local dir = tmp_dir()
    local path = dir .. "/foo.lua.json"
    local entries = {
      { name = "foo", start_line = 1, end_line = 3, explanation = "does a thing" },
    }
    local result = cache.merge(path, entries, { foo = "abc123" })
    assert.equal(1, #result.foo)
    assert.equal(1, result.foo[1].start_line)
    assert.equal(3, result.foo[1].end_line)
    assert.equal("abc123", result.foo[1].body_hash)
    assert.equal("does a thing", result.foo[1].explanation)
    assert.is_string(result.foo[1].generated_at)
  end)

  it("merge preserves existing entries not touched by this call", function()
    local dir = tmp_dir()
    local path = dir .. "/foo.lua.json"
    cache.write(path, { bar = { { explanation = "old", body_hash = "b1" } } })
    cache.merge(path, {
      { name = "foo", start_line = 1, end_line = 2, explanation = "new" },
    }, { foo = "h" })
    local got = cache.read(path)
    assert.equal("old", got.bar[1].explanation)
    assert.equal("new", got.foo[1].explanation)
  end)

  it("merge prepends a new revision when the same name gets a different body_hash", function()
    local dir = tmp_dir()
    local path = dir .. "/foo.lua.json"
    cache.merge(path, {
      { name = "foo", start_line = 1, end_line = 2, explanation = "v1" },
    }, { foo = "hash1" })
    local result = cache.merge(path, {
      { name = "foo", start_line = 1, end_line = 3, explanation = "v2" },
    }, { foo = "hash2" })
    assert.equal(2, #result.foo)
    assert.equal("v2", result.foo[1].explanation)
    assert.equal("hash2", result.foo[1].body_hash)
    assert.equal("v1", result.foo[2].explanation)
    assert.equal("hash1", result.foo[2].body_hash)
  end)

  it("merge does not duplicate a revision when the same body_hash reappears", function()
    local dir = tmp_dir()
    local path = dir .. "/foo.lua.json"
    cache.merge(path, {
      { name = "foo", start_line = 1, end_line = 2, explanation = "v1" },
    }, { foo = "hash1" })
    local result = cache.merge(path, {
      { name = "foo", start_line = 1, end_line = 2, explanation = "v1-regenerated" },
    }, { foo = "hash1" })
    assert.equal(1, #result.foo)
    assert.equal("v1-regenerated", result.foo[1].explanation)
  end)

  it("write backs up a previously-corrupt file to <path>.bak before overwriting", function()
    local dir = tmp_dir()
    local path = dir .. "/foo.lua.json"
    local corrupt_content = "<<<<<<< HEAD\nnot json\n"
    local f = assert(io.open(path, "w"))
    f:write(corrupt_content)
    f:close()

    cache.merge(path, {
      { name = "foo", start_line = 1, end_line = 2, explanation = "new" },
    }, { foo = "h" })

    local bak = assert(io.open(path .. ".bak", "r"))
    local bak_content = bak:read("*a")
    bak:close()
    assert.equal(corrupt_content, bak_content)

    -- and the real path now holds valid, decodable JSON
    local got = cache.read(path)
    assert.equal("new", got.foo[1].explanation)
  end)

  it("produces output with a stable, sorted top-level key order regardless of merge order", function()
    local dir_a = tmp_dir()
    local path_a = dir_a .. "/foo.lua.json"
    cache.merge(path_a, {
      { name = "zeta", start_line = 1, end_line = 2, explanation = "z" },
    }, { zeta = "hz" })
    cache.merge(path_a, {
      { name = "alpha", start_line = 3, end_line = 4, explanation = "a" },
    }, { alpha = "ha" })

    local dir_b = tmp_dir()
    local path_b = dir_b .. "/foo.lua.json"
    cache.merge(path_b, {
      { name = "alpha", start_line = 3, end_line = 4, explanation = "a" },
    }, { alpha = "ha" })
    cache.merge(path_b, {
      { name = "zeta", start_line = 1, end_line = 2, explanation = "z" },
    }, { zeta = "hz" })

    local function read_raw(path)
      local f = assert(io.open(path, "r"))
      local content = f:read("*a")
      f:close()
      -- generated_at timestamps will differ by call order in real time but
      -- are the same across these two runs since they execute back-to-back
      -- within the same second in practice; strip them to avoid flakiness.
      return (content:gsub('"generated_at": "[^"]*"', '"generated_at": "STRIPPED"'))
    end

    assert.equal(read_raw(path_a), read_raw(path_b))

    local raw = read_raw(path_a)
    local alpha_pos = raw:find('"alpha"')
    local zeta_pos = raw:find('"zeta"')
    assert.is_true(alpha_pos < zeta_pos)
  end)

  it("write output is multi-line (not a single-line blob)", function()
    local dir = tmp_dir()
    local path = dir .. "/foo.lua.json"
    cache.merge(path, {
      { name = "foo", start_line = 1, end_line = 2, explanation = "x" },
    }, { foo = "h" })
    local f = assert(io.open(path, "r"))
    local content = f:read("*a")
    f:close()
    local _, newline_count = content:gsub("\n", "\n")
    assert.is_true(newline_count > 1)
  end)
end)
