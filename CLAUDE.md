# url-picker — project notes

## Names

- Assistant: **Skronk**
- Human: **Chebulldozer**

## What this is

A herdr plugin: `<prefix>u` → fzf over the URLs in the current pane → open the
chosen one in the default browser.

## Architecture decisions

- **Action + popup, two stages.** An action's stdout is *captured* by herdr, so
  it has no TTY and cannot run fzf. The interactive picker therefore lives in a
  `[[panes]]` entry with `placement = "popup"` (a real PTY). `pick.sh` (action)
  is just a launcher that captures the origin pane and opens the popup.
- **Origin pane id is passed explicitly** via `--env URL_PICKER_SOURCE_PANE`.
  The popup builds its *own* invocation context at open time, so it can't be
  trusted to still know which pane the user came from. `pick.sh` reads
  `focused_pane_id` from `HERDR_PLUGIN_CONTEXT_JSON` and hands it over.
- **Neovim buffers are snapshotted before opening the popup.** A modal can
  close transient preview windows, so querying Neovim from `picker.sh` is too
  late. `pick.sh` detects `--listen` or `NVIM_LISTEN_ADDRESS`, writes the
  current tab's buffers to a private temporary file, and passes its path to the
  popup. `picker.sh` consumes and removes it.
- **`herdr pane read --source recent-unwrapped --format text`** is the input.
  `--format text` returns *raw plain text* (no JSON envelope, no ANSI), so it
  pipes straight into the extractor. `recent-unwrapped` rejoins soft-wrapped
  lines so column-wrapped URLs come back whole.
- **`extract-urls.sh` is a pure stdin→stdout transform**, deliberately split
  from all herdr/fzf I/O so it can be unit-tested (`test/extract-urls.test.sh`).
  It emits URLs newest-first, de-duplicated, with trailing punctuation, `\`
  (shell line-continuation), and `…` (TUI truncation) stripped. Trailing `/` is
  preserved (significant). `www.` gets an `https://` prefix so `open` treats it
  as a URL, not a file path.
- **No `tac`** — macOS doesn't ship it. Reverse+dedup is done with a POSIX
  `awk` one-liner instead.
- **No `pipefail` in `extract-urls.sh`** — `grep` exiting 1 on "no matches" is a
  valid empty result, not a failure.
- **Delimiter-aware matching.** Terminal output embeds URLs in JSON/quotes
  (`"https://x","next":…`), so a URL runs until a delimiter that can't appear
  mid-URL (quotes, backtick, `<>{}|^`, whitespace) rather than just whitespace.
  Query-string chars (`?&=+`) and balanced `()` survive; trailing punctuation is
  stripped afterward.
- **Scheme filtering.** Default `https?|ftp`; `file://` is off by default (build
  tools spew `file://` node_modules paths). User config lives in a `.env` in
  `HERDR_PLUGIN_CONFIG_DIR`, sourced by `picker.sh` with `set -a` so the child
  `extract-urls.sh` inherits it. `URL_PICKER_INCLUDE_FILES=1` is the friendly
  flag; `URL_PICKER_SCHEMES` is the advanced override (wins over the flag). The
  flag→scheme translation lives in `extract-urls.sh` so it's unit-tested.

## herdr gotchas learned here

- Commands are argv, never a shell — no pipes/globs/`$VAR` in the manifest.
- Keybindings are NOT declared by the plugin; the user adds `[[keys.command]]`
  with `type = "plugin_action"` in their herdr `config.toml`. (Chebu's prefix is
  `ctrl+a`.)
- Read the `warnings` array after `herdr plugin link` — unknown event names
  link *successfully* but silently never fire.
- Plugin stdout/stderr is captured; `herdr plugin log list` is the only place
  it surfaces.

## Testing status

- `test/extract-urls.test.sh` — unit tests, all passing. Also verified the
  read→extract path against live panes (`herdr pane read | extract-urls.sh`).
- `test/neovim-snapshot.test.sh` — regression test for pre-popup Neovim
  capture, snapshot handoff, selection, opening, and cleanup.
- **Interactive path (popup + fzf + browser open) is NOT auto-tested** — it
  needs a human to drive fzf. Test by binding the key and pressing it, or:
  `herdr plugin action invoke url-picker.pick`.
