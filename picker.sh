#!/usr/bin/env bash
# Pane entrypoint. Runs inside the picker popup (a real PTY).
#
# Reads the source pane's scrollback, extracts the URLs, lets the user filter
# and pick one with fzf, and opens the choice in the default browser. The popup
# closes when this script exits.
set -uo pipefail

herdr="${HERDR_BIN_PATH:-herdr}"
here="$(cd "$(dirname "$0")" && pwd)"
pane_id="${URL_PICKER_SOURCE_PANE:-}"
snapshot="${URL_PICKER_NVIM_SNAPSHOT:-}"
trap '[ -z "$snapshot" ] || rm -f "$snapshot"' EXIT

# Load user config, if present (see .env.example). `set -a` exports every
# setting so the child extract-urls.sh inherits the URL_PICKER_* vars too.
config="${HERDR_PLUGIN_CONFIG_DIR:-}/.env"
if [ -f "$config" ]; then
  set -a
  # shellcheck source=/dev/null
  . "$config"
  set +a
fi

# How many lines of scrollback to scan for URLs.
lines="${URL_PICKER_LINES:-2000}"

# Print a message in the popup and wait for a keypress so the user can read it
# before the popup vanishes.
notify() {
  printf '%s\n' "$1" >&2
  printf 'Press any key to close...' >&2
  read -r -n 1 _ </dev/tty || true
}

if [ -z "$pane_id" ]; then
  notify "url-picker: no source pane id (URL_PICKER_SOURCE_PANE unset)"
  exit 1
fi

# `recent-unwrapped` rejoins soft-wrapped lines so URLs split across terminal
# columns come back whole. `--format text` yields plain text (no JSON, no ANSI).
text="$("$herdr" pane read "$pane_id" --source recent-unwrapped --lines "$lines" --format text)" || {
  notify "url-picker: failed to read pane $pane_id"
  exit 1
}

# Neovim text is captured by the action before this modal opens because
# opening it can close transient preview windows.
if [ -f "$snapshot" ]; then
  text="$(printf '%s\n%s\n' "$text" "$(cat "$snapshot")")"
fi

urls="$(printf '%s\n' "$text" | "$here/extract-urls.sh")"

if [ -z "$urls" ]; then
  notify "No URLs found in this pane."
  exit 0
fi

# fzf exits non-zero when the user cancels (Esc / Ctrl-C); treat that as "no
# selection" rather than an error.
selected="$(printf '%s\n' "$urls" | fzf --prompt='open url> ' --height=100% --reverse --no-multi)" || true

if [ -n "${selected:-}" ]; then
  case "$(uname -s)" in
    Darwin) open "$selected" ;;
    *)      xdg-open "$selected" >/dev/null 2>&1 & ;;
  esac
fi
