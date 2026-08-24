local parser = require("review_explain.parser")

describe("review_explain.parser.extract_fenced_block", function()
  it("returns the contents between the first fence pair", function()
    local text = "here you go:\n```json\n[1,2,3]\n```\nhope that helps"
    assert.equal("[1,2,3]", parser.extract_fenced_block(text))
  end)

  it("returns nil when there is no fence", function()
    assert.is_nil(parser.extract_fenced_block("no fences here"))
  end)
end)

describe("review_explain.parser.parse_cli_output", function()
  it("parses a well-formed envelope with a fenced JSON array", function()
    local envelope = vim.json.encode({
      is_error = false,
      result = '```json\n[{"name":"foo","start_line":1,"end_line":3,"explanation":"does a thing"}]\n```',
    })
    local entries, err = parser.parse_cli_output(envelope)
    assert.is_nil(err)
    assert.equal(1, #entries)
    assert.equal("foo", entries[1].name)
    assert.equal(1, entries[1].start_line)
    assert.equal(3, entries[1].end_line)
    assert.equal("does a thing", entries[1].explanation)
  end)

  it("also accepts an unfenced JSON array in result", function()
    local envelope = vim.json.encode({
      is_error = false,
      result = '[{"name":"foo","start_line":1,"end_line":2,"explanation":"x"}]',
    })
    local entries, err = parser.parse_cli_output(envelope)
    assert.is_nil(err)
    assert.equal(1, #entries)
  end)

  it("returns an error when the top-level JSON is invalid", function()
    local entries, err = parser.parse_cli_output("not json at all")
    assert.is_nil(entries)
    assert.is_string(err)
  end)

  it("returns an error when is_error is true", function()
    local envelope = vim.json.encode({ is_error = true, result = "boom" })
    local entries, err = parser.parse_cli_output(envelope)
    assert.is_nil(entries)
    assert.is_string(err)
  end)

  it("returns an error when an entry is missing a required field", function()
    local envelope = vim.json.encode({
      is_error = false,
      result = '```json\n[{"name":"foo","start_line":1}]\n```',
    })
    local entries, err = parser.parse_cli_output(envelope)
    assert.is_nil(entries)
    assert.is_string(err)
  end)
end)
