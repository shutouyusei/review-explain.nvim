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
    assert.truthy(text:find("**AI explanation**", 1, true))
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
end)
