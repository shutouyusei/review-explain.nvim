# review-explain.nvim

On-demand, per-function AI code explanations for Neovim — cached, git-trackable, and shown right where you already look for docs (`K` / hover).

## Why

Claude (or another agent) can write code for you somewhere else — a terminal session, a remote-controlled session, whatever. When you come back to review it, you don't need a live AI session embedded in your editor: you need to understand *this specific function*, on demand, without re-explaining context every time.

review-explain.nvim does exactly that and nothing more:

- Select a range, ask for an explanation. It's generated once per function (by name + content hash) via the real `claude` CLI in non-interactive print mode (`claude -p`) — never an API key, never the Agent SDK, so it draws on your existing Claude subscription like any other `claude` CLI use.
- The explanation is cached in a small JSON file under `.nvim-review/`, meant to be committed to git — it accumulates like durable, code-attached documentation, not a throwaway chat log.
- Explained functions get a colored border and a sign-column marker so you can see at a glance what's already documented.
- Press `K` on an explained function and the explanation shows up alongside normal LSP hover — one floating window, not two competing ones.
- If the function's content changes after it was explained, the old explanation is still shown (it doesn't just vanish — it's still a useful starting point) but clearly flagged as possibly outdated, both in the hover window and the marker color.
- Works the same way inside [diffview.nvim](https://github.com/sindrets/diffview.nvim) panes as it does on the real file — explanations generated in either place are visible in both.

## Non-goals

- No embedded/live Claude session in the editor.
- No automatic diff summarization or risk flagging — that's what good commit messages are for.
- No auto-generation on hover, and no silent auto-refresh of a stale explanation. Every AI call is triggered explicitly by you.

## Requirements

- Neovim >= 0.10 (uses `vim.system`, `vim.fs.root`)
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) with parsers for the languages you want to explain
- The [`claude` CLI](https://claude.com/claude-code) installed and logged in

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "shutouyusei/review-explain.nvim",
  dependencies = { "nvim-treesitter/nvim-treesitter" },
  opts = {},
}
```

`opts = {}` calls `require("review_explain").setup({})` with all defaults. See Configuration below for what you can override.

## Usage

| Mapping | Mode | Action |
|---|---|---|
| `<leader>ce` | visual | Explain the selected range |
| `K` | normal | Show LSP hover + cached explanation for the function under the cursor (if any) |

That's the whole surface. Everything else — caching, staleness detection, the diffview bridge — happens automatically.

## Configuration

Defaults, shown with `opts = {}`:

```lua
{
  -- Model passed to `claude -p --model <model>`. nil = claude's own default.
  model = nil,

  -- Cache directory, relative to the resolved project root. Commit this.
  cache_dirname = ".nvim-review",

  -- Language the explanation text itself is written in. Any human-readable
  -- name works, not just these two examples.
  language = "English", -- or "Japanese", "日本語", "Spanish", ...

  keymaps = {
    explain = "<leader>ce", -- set to false to not register it
  },

  -- Whether review_explain registers its own K mapping. See "LazyVim +
  -- Snacks.nvim users" below for why you might want to set this to false.
  register_hover_keymap = true,

  -- Filetypes where review_explain never touches K or shows markers.
  excluded_filetypes = {
    help = true,
    man = true,
    qf = true,
    checkhealth = true,
    lazy = true,
    mason = true,
    lspinfo = true,
    query = true,
  },
}
```

### Japanese explanations

```lua
opts = {
  language = "Japanese",
}
```

### LazyVim + Snacks.nvim users

LazyVim's default LSP setup registers `K` → hover through `Snacks.nvim`, on a short debounce *after* `LspAttach` fires. That registration will overwrite a plain `FileType`-time `K` mapping set by any other plugin (this one included) on any LSP-attached buffer. If you notice `K` isn't showing cached explanations in real code buffers, set `register_hover_keymap = false` and instead add review-explain's handler to LazyVim's own `servers['*'].keys` list, so it goes through the same mechanism LazyVim's own hover key does (Snacks keeps the most-recently-registered mapping for a given key):

```lua
-- in your nvim-lspconfig.lua spec
opts = {
  servers = {
    ["*"] = {
      keys = {
        {
          "K",
          function()
            require("review_explain.recall").show(0)
          end,
          desc = "Hover / cached explanation",
        },
      },
    },
  },
},
```

`register_hover_keymap = false` still lets review-explain manage the explained-function markers (border + sign) on `FileType` — it only stops it from claiming `K` itself.

## Known limitations

- **Git worktrees**: the diffview.nvim cache-sharing bridge assumes the git directory is a plain `.git` folder directly under the project root. In a linked worktree it falls back to treating diffview panes and the real file as separate cache entries — not a crash, just not shared.
- **Anonymous functions nested in a table constructor** (`M.handlers = { onClick = function() ... end }`) can't be named reliably and are silently skipped, to avoid misattributing the explanation to the table's own variable name.
- Multi-target assignments (`local a, b = function() end, function() end`) aren't resolved.
- The explanation cache has no pruning — old revisions for a function accumulate indefinitely.

## Development

```bash
# run the test suite (requires plenary.nvim + nvim-treesitter installed
# via your plugin manager already)
for f in tests/review_explain/*_spec.lua; do
  nvim --headless -u tests/minimal_init.lua -c "lua require('plenary.busted').run('$f')" -c "qa!"
done
```

## License

MIT
