# review-handoff: fast pre-run review for AI-authored experiment code

Status: design approved, spec written, not yet implemented.
Date: 2026-08-25. Revised 2026-08-25 (Stage A/B split, severity, batched
explanation writes — see "Revision: cost-aware Stage A/B split" below).

## Problem

Reviewing AI-authored research code commit-by-commit is slower than the AI that
wrote it. A concrete incident motivated this: in `lerobot-il`, an experiment's
image-loading code took a 480x640 frame and sliced `[:240, :320]` — a top-left
**crop**, not a resize. Every USB/spike cell computed since (calibration, main
measurements, a robustness cell meant to rule out a "weak vision proxy"
explanation) ran on frames missing the object of interest. It read fine
function-by-function; nobody looked at what the model actually saw until asked
directly. Reading source is not the bottleneck for this user — building the habit
and the tooling to look at the right things, at the right grain, before an
experiment runs, is.

## Goals

- Review happens once per coherent round of experiment-code writing, covering
  everything since the last reviewed round — not once per commit (too slow to
  keep pace with AI-authored volume) and not only at the end of an experiment
  (too late — GPU time already spent on possibly-wrong code).
- The review surface is a diff (`merge-base(main, HEAD)` vs working tree) opened
  in diffview.nvim, with a curated list of "things worth doubting" as a
  jumpable quickfix list next to it — not a full narration of the diff.
- Complex-but-not-suspicious code gets an explanation pre-attached (via the
  existing review-explain.nvim cache) so the human isn't stuck re-deriving it
  under time pressure.
- Nothing runs until every doubt item is checked off.
- No new "ask a question" UI in the plugin — the user already has a live Claude
  Code session reachable from Neovim (`<leader>ac`, review-explain.nvim's
  companion keymap) for anything a review item or explanation doesn't resolve.

## Non-goals

- Not a general static analyzer or linter — the doubt items come from an LLM
  review pass reading the diff, not from fixed rules.
- Not a replacement for the existing `experiment-transparency.md` independent
  post-run audit (evidence tier) — that still runs after results exist; this
  runs before the run.
- Not a live/embedded AI session in the editor (review-explain.nvim's existing
  non-goal, unchanged).
- Not responsible for enforcing the merge-cadence rule itself (see Companion
  repo-rule change) — that's a human/CLAUDE.md discipline, not something this
  tooling can gate on its own.

## Companion repo-rule change (already made, global)

`~/.claude/rules/repo-layout-research.md` was updated the same day this spec was
written: experiment branches now merge to the default branch after every
review-passed round (write -> review -> run -> record result -> merge), not only
once at claim-lock. The branch is never deleted after a merge and only ever
ff-merges into the default branch, so it stays strictly ahead. This is what
lets `base = merge-base(default, HEAD)` be computed fresh every time with no
extra state: it always equals "the last point this branch was reviewed and
merged," automatically, because merges never happen except right after a
review passes.

## Revision: cost-aware Stage A/B split

The original Half 1 (below) always spawns one fresh-context agent that reads
the full diff and full file contents, for every round. Two problems in
practice: (1) a fresh agent has no access to the round's actual intent
beyond what's stuffed into its prompt, so it can only catch surface-level
doubts, not "this deviates from what was intended"; (2) every round pays the
same fixed agent cost regardless of how small or clean it is.

Revised split:

- **Stage A (main session, no subagent call)**: the session that wrote the
  round already has the intent loaded — primarily the branch's own commit
  messages (`git log base..HEAD`), secondarily this session's conversation.
  It traces each changed input→output path in **one pass**, producing
  `doubts` (tagged `low`/`medium`/`high`) and `explanations` together — the
  alignment check and the trace are the same read, not two passes. No
  subagent is spawned for this; the intent is already in context, so a fresh
  agent would only pay cost to rediscover what this session already knows.
  Thin/absent commit messages that block intent-checking become a doubt
  themselves (`kind: intent-unclear`), which forces better commit hygiene
  over time rather than working around it.
- **Stage B (fresh subagent, `high`-severity doubts only)**: this is the one
  place freshness is actually load-bearing — a reader who does *not* know
  the stated intent, so they can't rationalize away a real bug as "expected
  because...". Scoped to just the flagged item and a tight excerpt, not the
  full diff/files. Zero agent calls when Stage A finds no `high` doubts.
- **Explanation writes are batched**: one `nvim --headless` invocation
  writing all `explanations` in a Lua loop, not one process per entry.
- **Trigger context generalized**: still invoked manually once a round is
  ready, but "ready" means different things per branch kind — experiment
  branches gate before running (correctness/reproducibility), development
  branches gate before merging to main (after the code has actually been
  exercised), since main must stay always-audited and the branch/main diff
  is itself the merge justification. The command's mechanics don't change
  between the two; only when a human chooses to invoke it does.

The review-map schema gains a `severity` field (`low|medium|high`) and a
`verified` field (`null` for un-escalated items, `true|false` for `high`
items after Stage B). See the updated schema below. Half 2 (the plugin) is
unaffected by this revision — `:ReviewOpen` and `<leader>cx` just carry the
two new fields through unmodified.

## Two halves

### Half 1 — `/review-handoff` (a Claude Code slash command, lives in the
research-session tooling, not in this plugin)

Invoked with no arguments once a round of experiment code is written and the
author (the Claude Code session) believes it's ready to run.

1. Compute `base = git merge-base main HEAD` (or the repo's actual default
   branch name).
2. Derive `name` from the current branch name (the experiment folder slug) plus
   a short suffix if a review map for this exact `(branch, base)` pair already
   exists (rare — only if a previous round's map was abandoned without being
   completed).
3. Spawn a **fresh-context** review agent (no memory of writing the code) with:
   - `git diff base -- <tracked dirs>` (respecting the repo's normal
     experiment/src/paper/scripts/tests scope, per `repo-layout-research.md`
     rule 6)
   - full contents of every changed file (not just the diff hunks) so the
     agent can see e.g. a native resolution defined 40 lines above the crop
   - Prior context already in the parent session's window that's directly
     load-bearing (the experiment's claim, what this round was trying to add) —
     passed explicitly in the prompt, not implied
   - Instructions: **doubt, don't narrate.** For each changed file, look
     specifically for: data boundary changes (resolution/shape, units, channel
     order, crop-vs-resize, dtype/range), time alignment, how a control
     condition is constructed or broken, train/test or fold-split leakage,
     cache-key completeness (does the key include everything that changes the
     cached value?), sign/index conventions. Return ONLY items that are
     actually worth doubting — an empty list for a clean small change is the
     correct, common output, not a failure to find something.
   - Output schema (JSON, matches the review-map schema below): one entry per
     doubt, each with `file`, `line` (in the working-tree version, since diff
     right-side = working tree per the Goals), `kind`, `note` (what's in
     question, in one sentence), `check` (one concrete thing the human can run
     or look at to resolve it — a command, or "look at the saved frames in
     outputs/.../inspect/").
   - A soft cap (20 items) on the list, applied by the agent itself: if more
     than 20 genuine doubts exist, that's a signal the round should have been
     split smaller, and the command should say so rather than silently
     truncating.
4. Separately (same agent call or a second pass — implementation's choice),
   identify functions in the diff that are **complex but not doubtful** — dense
   numeric code, multi-step bootstrap/statistics, anything where a reader would
   benefit from a plain-language walkthrough but where nothing is actually in
   question. For each, write an explanation directly into the review-explain
   cache via the headless API (Half 2) — this reuses the *existing* explanation
   mechanism and cache format; `/review-handoff` does not invent a second
   explanation store.
5. Write the review map to `.nvim-review/reviews/<name>.json` (schema below).
   This file is git-tracked, per review-explain.nvim's existing convention for
   `.nvim-review/` (durable, diffable record of what was reviewed and why).
6. Reply to the user: `Review map written: <name> (<n> items). Open with
   :ReviewOpen <name> in the branch's working tree.` — and stop. Does not run
   anything, does not merge anything, until the user has gone through the map.

### Half 2 — review-explain.nvim additions

**`lua/review_explain/cache_api.lua`** (new module) — a small, headless-callable
API that lets an external process (namely `/review-handoff`, via `nvim
--headless`) write an explanation into the same cache format `generate.lua`
produces, without going through `claude -p` itself (the explanation text is
supplied by the caller).

```lua
---@param filepath string absolute path to the source file
---@param name string function name (as resolve.lua would report it, e.g. "M.foo")
---@param explanation string
---@return boolean ok
---@return string|nil err
function M.write(filepath, name, explanation)
```

Implementation: open (or reuse) a buffer for `filepath`, run
`resolve.find_all_functions(bufnr)` to locate the node matching `name`
(exact match, then the same qualified-name tolerance `generate.lua` already
uses), compute `resolve.hash_node`, and call `cache.merge` with a single
synthetic entry — same code path `generate.lua` uses after parsing a real
`claude -p` response, just skipping the parse/CLI step. If no matching function
is found, return `false` and a message identifying the file/name — the caller
logs it and moves on (a missed pre-attached explanation is not fatal; `K` still
falls back to on-demand `<leader>ce` generation).

Exposed to shell/headless callers as:

```sh
nvim --headless \
  -c "lua require('review_explain.cache_api').write([[<file>]], [[<name>]], [[<explanation>]])" \
  -c "qa"
```

`/review-handoff` shells out to this once per pre-attached explanation.

**`:ReviewOpen <name>` command** (new, in `init.lua` or a new `review_map.lua`
module):

1. Read `.nvim-review/reviews/<name>.json`.
2. Open diffview.nvim against `map.base` (`:DiffviewOpen <base>`) — right side
   is working tree, matching the approved design.
3. Populate the quickfix list from `map.items` (`vim.fn.setqflist`), one entry
   per item: `{filename, lnum, text = kind .. ": " .. note .. " -- check: " .. check}`.
   Skip (or visually distinguish, e.g. a different sign) items already
   `checked: true` from a partial prior pass, but still list them — resuming a
   review shouldn't hide what was already confirmed.
4. Open the quickfix window so `]q` / `[q` navigation is immediate.
5. `K` continues to work exactly as before (recall.show) inside the diffview
   panes, including any explanations `/review-handoff` pre-attached via
   `cache_api.write` — no change needed here since diffview cache-path
   resolution (`cache.lua`'s `parse_diffview_path`) already handles this.

**`<leader>cx` keymap** (new, active only in a quickfix-list buffer populated by
`:ReviewOpen`, or globally scoped to check "is there a current review map for
this quickfix entry" — implementation's choice, but must not interfere with
`<leader>cx` in unrelated quickfix lists from other plugins): marks the item
under the cursor `checked: true`, writes it back to the JSON file (reusing
`cache.write`'s atomic temp-file-then-rename pattern, not `cache.merge`'s
revision-list semantics — this is a flat field update on one item, not an
explanation-revision merge), and updates the quickfix entry's display (e.g.
prefix with `[x]`) without removing it from the list — leaving a checked trail
visible is the point, not narrowing the list.

## Data formats

### Review map — `.nvim-review/reviews/<name>.json`

```json
{
  "name": "usable-info-fullframe",
  "base": "57ca4b0",
  "created": "2026-08-25T14:00:00Z",
  "items": [
    {
      "file": "experiments/usable-info-beta/run.py",
      "line": 88,
      "kind": "boundary",
      "severity": "high",
      "note": "480x640 -> 240x320: crop or resize?",
      "check": "python experiments/usable-info-beta/run.py --dataset usb --inspect",
      "verified": true,
      "checked": false
    }
  ]
}
```

- `kind` in `{boundary, align, control, split, cache, unit, intent-unclear,
  other}` (open set — Stage A is not restricted to only these, but should
  prefer one of them when it fits, for scannability).
- `severity` in `{low, medium, high}`, assigned by Stage A. Only `high`
  items go through Stage B.
- `verified` is `null` for `low`/`medium` items (Stage B never ran) and
  `true`/`false` for `high` items per Stage B's blind verdict.
- `base` is recorded for provenance/debugging even though `:ReviewOpen` could
  in principle recompute `merge-base(main, HEAD)` itself — recording what was
  actually diffed at review time is more honest than trusting it stays
  reproducible (branch history could move between review and later reading).
- No `session_id` field, no question/answer log — dropped from the design when
  the user decided the in-plugin question feature was unnecessary (existing
  `<leader>ac` float covers it). If a future iteration wants a durable record
  of Q&A that happened during a review, that would be a separate addition, not
  assumed here.

### Explanation cache — unchanged

`cache_api.write` produces entries in the exact same shape
`review_explain/cache.lua`'s `M.merge` already writes (see existing
`.nvim-review/<relpath>.json` format) — no schema change, no new file per
pre-attached explanation.

## Open implementation questions (for the plan, not blocking this spec)

1. Where does `/review-handoff` itself live — a Claude Code slash command file
   in `~/.claude/commands/`, or repo-scoped? Given it's meant to work "across
   all research repos" per the companion rule change, it should probably be a
   global command, parameterized only by the current repo's default branch
   name (detect via `git symbolic-ref refs/remotes/origin/HEAD` or fall back to
   `main`).
2. Exact prompt text for the reviewer agent's "doubt, don't narrate" framing —
   draft in the plan, refine after seeing real output on the `lerobot-il`
   crop-bug-fix round as a test case.
3. Whether `/review-handoff`'s explanation pre-attachment pass is the same
   agent call as the doubt-item pass (one prompt, two output sections) or a
   second call — affects cost/latency; default to one call unless testing
   shows the model conflates the two tasks.
4. Test coverage for `cache_api.lua` and the new quickfix/`<leader>cx` code
   follows the existing plenary.nvim pattern already used for
   `cache_spec.lua`, `resolve_spec.lua`, etc.

## Testing

- `cache_api_spec.lua`: write() finds an existing function by name, computes
  the same hash `resolve.hash_node` would, merges correctly; write() on a
  missing function name returns `false` with a message; write() on a function
  whose body changed since is treated as a new revision (matches `cache.merge`
  existing behavior — no special-casing needed, `cache_api` calls `cache.merge`
  directly).
- `review_map_spec.lua` (or similar): reading a review map populates the
  expected quickfix entries; `<leader>cx` toggles `checked` and persists it
  (round-trip through a temp file, same pattern `cache_spec.lua` already uses
  for `cache.lua`).
- `/review-handoff` itself (the slash command / prompt) is not unit-testable
  the way the plugin is — validate it empirically against the `lerobot-il`
  crop-bug fix as a real first case once implemented.
