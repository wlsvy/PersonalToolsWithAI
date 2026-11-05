# Folo AI summary and translation (AI)

요약: [ai.md](ai.md)

Status: implemented.

## Files
- `lua/folo/ai.lua` (new): only module that runs Claude or touches summary files. Owns queue and job state.
- `lua/folo/ui.lua`: child rows, keys. `load_view` extracted from the preview chain and shared as the AI source.
- `tests/ai_test.lua`, `tests/fake_claude.sh` (new).

## Config
```lua
ai = {
  cmd = { "claude" },
  config_dir = "~/.claude-clip",  -- CLAUDE_CONFIG_DIR, shared with native-host
  models = { summary = "sonnet", translation = "sonnet" },
  prompts = {},                   -- { summary=path, translation=path }; default native-host/prompts/*.md
  concurrency = 3,
  timeout_ms = { summary = 600000, translation = 1800000 },
  confirm_over = 10,
  dir = nil,                      -- default stdpath("cache")/folo/summaries
},
keymaps.list += { summarize = "s", translate = "t", delete_summary = "x" }
```

## Invocation (same as `native-host/clip_host.mjs`)
`claude -p --model <m> --system-prompt <file contents> --tools '' --no-session-persistence`; article on stdin; `cwd` = OS temp dir; env `CLAUDE_CONFIG_DIR`. `--tools ''` is required: the input is untrusted web text. Do not use `--bare` (breaks subscription login).

## Storage
- `<dir>/<sha256(entry id)>.md`; hashed because ids come from the network. Written via temp file + rename.
- Layout: `# title`, url, feed + date, blank, summary. Translation append: blank, `<!-- folo:translation -->`, blank, `---`, blank, `## 번역`, blank, text.
- Marker line decides "has translation". A false positive only blocks a re-translation; `x` clears it.
- Displayed with `nvim_buf_set_lines` in the scratch preview, never `:edit`: LLM output must not reach modelines or autocmds.

## Queue rules
- FIFO; at most `concurrency` jobs, counting the source load. One job per entry at a time.
- `s`: skip when summary exists or is busy. `t`: skip when translation exists or is busy; without a summary, queue summary then translation; while summary is queued/running, set the follow-up flag.
- Failure sets `error`, drops the follow-up, writes nothing; pressing the key again retries.
- Source gate: no article and body shorter than `article.thin_chars` → fail without calling Claude.
- Empty stdout, non-zero exit, timeout (code 124), missing prompt, missing executable → failure. Login-related text adds a login hint.
- `VimLeavePre` kills running processes. Jobs outlive closed lists.

## UI
- `state[buf].rows`: flattened `{entry=, child=bool}`; `items` keeps paging data. Redraw keeps the cursor on the same row.
- Child row exists when a file, job, or error exists: `   └ summary`, `+ translation`, `queued`/`running` states, `failed: <reason>`.
- Cursor on child previews the file with a progress footer; live update on job change. `<CR>` marks read and focuses preview. `m`, `gx`, `<Tab>` on a child apply to its parent; `<Tab>` skips child rows moving down.
- `s`/`t` target selection else current; selection clears after queueing; confirm above `confirm_over`.
- `x` confirms, deletes the file, refuses while busy.

## Verify
```sh
NVIM_LOG_FILE="$TMPDIR/nvim.log" nvim --headless -i NONE -u NONE --cmd "set rtp+=folo/nvim" -l folo/nvim/tests/ai_test.lua
```
Manual, by the user (sandbox denies `~/.claude-clip` and network): `s`, `t` on real entries.

## Out of scope
Cancel, chunked translation, other AI providers, sharing results with the extension.
