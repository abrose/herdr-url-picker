#!/usr/bin/env bash
# Action entrypoint. Runs when the user triggers `url-picker.pick` (via a
# keybinding or `herdr plugin action invoke`).
#
# An action's stdout is captured, not shown, so it can't host fzf itself.
# Instead it captures the pane the user invoked from and opens the picker
# popup, handing that pane id over so the popup knows where to read URLs.
set -euo pipefail

herdr="${HERDR_BIN_PATH:-herdr}"

# focused_pane_id is the pane that had focus when the action fired — i.e. the
# one whose printed URLs the user wants to pick from.
pane_id="$(printf '%s' "${HERDR_PLUGIN_CONTEXT_JSON:-}" | jq -r '.focused_pane_id // empty')"

if [ -z "$pane_id" ]; then
  echo "url-picker: no focused pane in invocation context" >&2
  exit 1
fi

# Snapshot Neovim before opening the popup: modal focus can close transient
# preview windows, removing the URL-bearing buffer from Neovim's live state.
snapshot="$(mktemp "${HERDR_PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}}/nvim-snapshot.XXXXXX")"
process_info="$("$herdr" pane process-info --pane "$pane_id" 2>/dev/null)" || process_info=""
nvim_socket="$(printf '%s' "$process_info" |
  jq -r '.result.process_info.foreground_processes[]?.argv | select(index("--listen")) | .[index("--listen") + 1]' |
  head -n 1)"
if [ -z "$nvim_socket" ]; then
  nvim_pid="$(printf '%s' "$process_info" |
    jq -r '.result.process_info.foreground_processes[]? | select(.name == "nvim") | .pid' | head -n 1)"
  if [ -r "/proc/$nvim_pid/environ" ]; then
    nvim_socket="$(tr '\0' '\n' <"/proc/$nvim_pid/environ" | sed -n 's/^NVIM_LISTEN_ADDRESS=//p' | head -n 1)"
  elif [ -n "$nvim_pid" ]; then
    nvim_socket="$(ps eww -p "$nvim_pid" -o command= | tr ' ' '\n' | sed -n 's/^NVIM_LISTEN_ADDRESS=//p' | head -n 1)"
  fi
fi
chmod 600 "$snapshot"
if [ -n "$nvim_socket" ]; then
  nvim --server "$nvim_socket" --remote-expr \
    'join(map(tabpagebuflist(), "join(getbufline(v:val, 1, \"$\"), \"\\n\")"), "\n")' \
    >"$snapshot" 2>/dev/null || true
fi

if ! "$herdr" plugin pane open \
  --plugin url-picker \
  --entrypoint picker \
  --env "URL_PICKER_SOURCE_PANE=$pane_id" \
  --env "URL_PICKER_NVIM_SNAPSHOT=$snapshot"; then
  rm -f "$snapshot"
  exit 1
fi
