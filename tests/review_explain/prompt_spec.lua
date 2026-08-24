local prompt = require("review_explain.prompt")

describe("review_explain.prompt", function()
  it("embeds the file path, language, and code in the user message", function()
    local msg = prompt.build_user_message("local x = 1", "/tmp/foo.lua", "lua")
    assert.truthy(msg:find("/tmp/foo.lua", 1, true))
    assert.truthy(msg:find("lua", 1, true))
    assert.truthy(msg:find("local x = 1", 1, true))
  end)

  it("builds a non-empty system prompt that demands fenced JSON output", function()
    local sys = prompt.build_system_prompt(nil)
    assert.is_string(sys)
    assert.truthy(sys:find("JSON", 1, true))
    assert.truthy(sys:find("start_line", 1, true))
  end)

  it("defaults to no language directive when language is nil, empty, or English", function()
    for _, lang in ipairs({ nil, "", "English", "english" }) do
      local sys = prompt.build_system_prompt(lang)
      assert.falsy(sys:find("Write the", 1, true))
    end
  end)

  it("adds a language directive when a non-English language is given", function()
    local sys = prompt.build_system_prompt("Japanese")
    assert.truthy(sys:find("Japanese", 1, true))
    assert.truthy(sys:find("Write the", 1, true))
  end)
end)
