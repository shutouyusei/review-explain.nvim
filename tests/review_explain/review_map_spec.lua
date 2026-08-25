local review_map = require("review_explain.review_map")
local cache = require("review_explain.cache")

local function tmp_project()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  return dir
end

local function write_map(map_path, map)
  cache.write(map_path, map)
end

local function sample_map()
  return {
    name = "usable-info-fullframe",
    base = "57ca4b0",
    created = "2026-08-25T14:00:00Z",
    items = {
      {
        file = "src/run.py",
        line = 88,
        kind = "boundary",
        note = "480x640 -> 240x320: crop or resize?",
        check = "python src/run.py --inspect",
        checked = false,
      },
      {
        file = "src/run.py",
        line = 120,
        kind = "cache",
        note = "cache key omits dataset version",
        check = "grep cache_key src/run.py",
        checked = true,
      },
    },
  }
end

describe("review_explain.review_map.build_qf_items", function()
  it("builds one quickfix entry per item, filename rooted, text carrying kind/note/check", function()
    local qf_items = review_map.build_qf_items("/proj", sample_map())
    assert.equal(2, #qf_items)
    assert.equal("/proj/src/run.py", qf_items[1].filename)
    assert.equal(88, qf_items[1].lnum)
    assert.equal(
      "[ ] boundary: 480x640 -> 240x320: crop or resize? -- check: python src/run.py --inspect",
      qf_items[1].text
    )
  end)

  it("prefixes an already-checked item's text with [x] instead of dropping it from the list", function()
    local qf_items = review_map.build_qf_items("/proj", sample_map())
    assert.equal(
      "[x] cache: cache key omits dataset version -- check: grep cache_key src/run.py",
      qf_items[2].text
    )
  end)
end)

describe("review_explain.review_map.toggle_checked", function()
  it("flips checked false -> true and persists it (round-trips through the file)", function()
    local dir = tmp_project()
    local map_path = dir .. "/review.json"
    write_map(map_path, sample_map())

    local item, err = review_map.toggle_checked(map_path, 1)
    assert.is_nil(err)
    assert.is_true(item.checked)

    local reread = cache.read(map_path)
    assert.is_true(reread.items[1].checked)
  end)

  it("flips checked true -> false", function()
    local dir = tmp_project()
    local map_path = dir .. "/review.json"
    write_map(map_path, sample_map())

    local item = review_map.toggle_checked(map_path, 2)
    assert.is_false(item.checked)

    local reread = cache.read(map_path)
    assert.is_false(reread.items[2].checked)
  end)

  it("leaves other items untouched", function()
    local dir = tmp_project()
    local map_path = dir .. "/review.json"
    write_map(map_path, sample_map())

    review_map.toggle_checked(map_path, 1)

    local reread = cache.read(map_path)
    assert.is_true(reread.items[2].checked)
  end)

  it("returns nil with an error for an out-of-range index", function()
    local dir = tmp_project()
    local map_path = dir .. "/review.json"
    write_map(map_path, sample_map())

    local item, err = review_map.toggle_checked(map_path, 99)
    assert.is_nil(item)
    assert.is_string(err)
  end)
end)

describe("review_explain.review_map.open", function()
  it("opens diffview against map.base and populates the quickfix list from the map's items", function()
    local dir = tmp_project()
    vim.fn.system({ "git", "init", "-q", dir })
    vim.fn.system({ "git", "-C", dir, "config", "user.email", "t@example.com" })
    vim.fn.system({ "git", "-C", dir, "config", "user.name", "t" })

    vim.fn.mkdir(dir .. "/src", "p")
    vim.fn.writefile({ "x = 1" }, dir .. "/src/run.py")
    vim.fn.system({ "git", "-C", dir, "add", "-A" })
    vim.fn.system({ "git", "-C", dir, "commit", "-q", "-m", "init" })
    local base = vim.fn.system({ "git", "-C", dir, "rev-parse", "HEAD" }):gsub("%s+$", "")

    vim.fn.writefile({ "x = 1", "y = 2" }, dir .. "/src/run.py")

    local map = sample_map()
    map.base = base
    map.items = { map.items[1] }
    vim.fn.mkdir(dir .. "/.nvim-review/reviews", "p")
    write_map(dir .. "/.nvim-review/reviews/test-map.json", map)

    local bufnr = vim.fn.bufadd(dir .. "/src/run.py")
    vim.fn.bufload(bufnr)
    vim.api.nvim_set_current_buf(bufnr)

    review_map.open("test-map")

    local qf = vim.fn.getqflist()
    assert.equal(1, #qf)
    assert.truthy(qf[1].text:find("boundary", 1, true))

    local qf_bufnr = vim.api.nvim_get_current_buf()
    assert.equal(dir .. "/.nvim-review/reviews/test-map.json", vim.b[qf_bufnr].review_explain_map_path)

    vim.cmd("only!")
  end)

  it("notifies and does not throw when no review map exists for the given name", function()
    local dir = tmp_project()
    vim.fn.system({ "git", "init", "-q", dir })
    vim.fn.mkdir(dir .. "/src", "p")
    vim.fn.writefile({ "x = 1" }, dir .. "/src/run.py")
    local bufnr = vim.fn.bufadd(dir .. "/src/run.py")
    vim.fn.bufload(bufnr)
    vim.api.nvim_set_current_buf(bufnr)

    local ok = pcall(review_map.open, "does-not-exist")
    assert.is_true(ok)
  end)
end)

describe("review_explain.review_map._format_item_detail", function()
  it("renders kind, checked status, note, and check as markdown lines", function()
    local lines = review_map._format_item_detail(sample_map().items[1])
    local text = table.concat(lines, "\n")
    assert.truthy(text:find("boundary", 1, true))
    assert.truthy(text:find("unchecked", 1, true))
    assert.truthy(text:find("480x640 -> 240x320: crop or resize?", 1, true))
    assert.truthy(text:find("**check:** python src/run.py --inspect", 1, true))
  end)

  it("shows checked status when the item is checked", function()
    local item = sample_map().items[1]
    item.checked = true
    local text = table.concat(review_map._format_item_detail(item), "\n")
    assert.truthy(text:find("checked", 1, true))
    assert.falsy(text:find("unchecked", 1, true))
  end)
end)
