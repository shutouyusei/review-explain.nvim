local recall = require("review_explain.recall")

describe("review_explain.recall._format_explanation", function()
  it("renders summary and highlights as markdown with a heading and bullets", function()
    local lines = recall._format_explanation({
      stale = false,
      summary = "Does a thing overall.",
      highlights = {
        { about = "validation", note = "checks the input shape" },
        { about = "retry loop", note = "backs off on failure" },
      },
    })
    local text = table.concat(lines, "\n")
    assert.truthy(text:find("**AI explanation — Does a thing overall.**", 1, true))
    assert.truthy(text:find("Does a thing overall.", 1, true))
    assert.truthy(text:find("**Inside this function:**", 1, true))
    assert.truthy(text:find("**validation** — checks the input shape", 1, true))
    assert.truthy(text:find("**retry loop** — backs off on failure", 1, true))
  end)

  it("omits the highlights section when there are none", function()
    local lines = recall._format_explanation({ stale = false, summary = "Just a summary." })
    local text = table.concat(lines, "\n")
    assert.falsy(text:find("Inside this function", 1, true))
  end)

  it("falls back to the legacy explanation string when summary is absent", function()
    local lines = recall._format_explanation({ stale = false, explanation = "legacy text" })
    local text = table.concat(lines, "\n")
    assert.truthy(text:find("legacy text", 1, true))
  end)

  it("marks stale revisions with a warning", function()
    local lines = recall._format_explanation({ stale = true, summary = "x" })
    local text = table.concat(lines, "\n")
    assert.truthy(text:find("code changed since this was written", 1, true))
  end)

  it("leads with the highlight covering the cursor line, marked in the bullet list too", function()
    local lines = recall._format_explanation({
      stale = false,
      summary = "Does a thing overall.",
      highlights = {
        { about = "validation", note = "checks the input shape", start_line = 10, end_line = 12 },
        { about = "retry loop", note = "backs off on failure", start_line = 20, end_line = 25 },
      },
    }, 22)
    local text = table.concat(lines, "\n")
    assert.truthy(text:find("**AI explanation — retry loop**", 1, true))
    assert.truthy(text:find("▶ **retry loop** — backs off on failure", 1, true))
    assert.falsy(text:find("▶ **validation**", 1, true))
  end)

  it("titles the main heading with a truncated summary, same mechanism as a highlight's own heading", function()
    local long_summary = string.rep("あ", 80) .. "。 second sentence stays out of the title."
    local lines = recall._format_explanation({ stale = false, summary = long_summary })
    local text = table.concat(lines, "\n")
    assert.truthy(text:find("**AI explanation — " .. string.rep("あ", 25), 1, true))
    assert.truthy(text:find("…**", 1, true))
    -- the full summary still appears in full below the (truncated) heading
    assert.truthy(text:find(long_summary, 1, true))
  end)

  it("does not lead with any highlight when the cursor is outside every range", function()
    local lines = recall._format_explanation({
      stale = false,
      summary = "Does a thing overall.",
      highlights = { { about = "validation", note = "checks input", start_line = 10, end_line = 12 } },
    }, 50)
    local text = table.concat(lines, "\n")
    assert.falsy(text:find("AI explanation — validation", 1, true))
  end)
end)
