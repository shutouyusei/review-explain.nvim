local client = require("review_explain.client")

describe("review_explain.client.build_cmd", function()
  it("builds the base claude -p command with print/json flags", function()
    local cmd = client.build_cmd({ system_prompt = "sys", user_message = "hello" })
    assert.same({ "claude", "-p", "hello", "--output-format", "json", "--system-prompt", "sys" }, cmd)
  end)

  it("appends --model when provided", function()
    local cmd = client.build_cmd({ system_prompt = "sys", user_message = "hello", model = "haiku" })
    assert.same(
      { "claude", "-p", "hello", "--output-format", "json", "--system-prompt", "sys", "--model", "haiku" },
      cmd
    )
  end)
end)

describe("review_explain.client.run", function()
  it("calls on_done(true, stdout) when the fake runner exits 0", function()
    local fake_runner = function(_cmd, _run_opts, cb)
      cb({ code = 0, stdout = '{"result":"ok"}', stderr = "" })
    end
    local got_ok, got_out
    client.run({ system_prompt = "s", user_message = "u" }, function(ok, out)
      got_ok, got_out = ok, out
    end, fake_runner)
    vim.wait(100, function() return got_ok ~= nil end)
    assert.is_true(got_ok)
    assert.equal('{"result":"ok"}', got_out)
  end)

  it("calls on_done(false, stderr) when the fake runner exits non-zero", function()
    local fake_runner = function(_cmd, _run_opts, cb)
      cb({ code = 1, stdout = "", stderr = "boom" })
    end
    local got_ok, got_out
    client.run({ system_prompt = "s", user_message = "u" }, function(ok, out)
      got_ok, got_out = ok, out
    end, fake_runner)
    vim.wait(100, function() return got_ok ~= nil end)
    assert.is_false(got_ok)
    assert.equal("boom", got_out)
  end)
end)
