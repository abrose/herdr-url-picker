#!/usr/bin/env bash
# Regression test: capture Neovim buffers before opening the popup, then feed
# that snapshot through the picker.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$here/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/state" "$tmp/config"

url="https://example.com/from-neovim"
export TEST_SNAPSHOT_PATH="$tmp/snapshot-path"
export TEST_FZF_INPUT="$tmp/fzf-input"
export TEST_OPENED_URL="$tmp/opened-url"

cat >"$tmp/herdr" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "pane process-info")
    printf '%s\n' '{"result":{"process_info":{"foreground_processes":[{"argv":["nvim"],"name":"nvim","pid":424242}]}}}'
    ;;
  "plugin pane")
    for arg in "$@"; do
      case "$arg" in
        URL_PICKER_SOURCE_PANE=*) source_pane="${arg#*=}" ;;
        URL_PICKER_NVIM_SNAPSHOT=*) snapshot="${arg#*=}" ;;
      esac
    done
    [ "${source_pane:-}" = "test:p1" ] || exit 1
    [ -s "${snapshot:-}" ] || exit 1
    printf '%s' "$snapshot" >"$TEST_SNAPSHOT_PATH"
    ;;
  "pane read")
    ;;
  *)
    exit 1
    ;;
esac
EOF

cat >"$tmp/ps" <<'EOF'
#!/bin/sh
printf '%s\n' 'nvim NVIM_LISTEN_ADDRESS=/tmp/fake-nvim.sock'
EOF

cat >"$tmp/nvim" <<EOF
#!/bin/sh
[ "\$1" = "--server" ] && [ "\$2" = "/tmp/fake-nvim.sock" ] || exit 1
printf '%s\n' 'preview [docs]($url)'
EOF

cat >"$tmp/fzf" <<'EOF'
#!/bin/sh
tee "$TEST_FZF_INPUT" | head -n 1
EOF

cat >"$tmp/uname" <<'EOF'
#!/bin/sh
printf '%s\n' Darwin
EOF

cat >"$tmp/open" <<'EOF'
#!/bin/sh
printf '%s' "$1" >"$TEST_OPENED_URL"
EOF
chmod +x "$tmp/herdr" "$tmp/ps" "$tmp/nvim" "$tmp/fzf" "$tmp/uname" "$tmp/open"

PATH="$tmp:$PATH" \
HERDR_BIN_PATH="$tmp/herdr" \
HERDR_PLUGIN_STATE_DIR="$tmp/state" \
HERDR_PLUGIN_CONTEXT_JSON='{"focused_pane_id":"test:p1"}' \
  "$root/pick.sh"

snapshot="$(cat "$TEST_SNAPSHOT_PATH")"
PATH="$tmp:$PATH" \
HERDR_BIN_PATH="$tmp/herdr" \
HERDR_PLUGIN_CONFIG_DIR="$tmp/config" \
URL_PICKER_SOURCE_PANE="test:p1" \
URL_PICKER_NVIM_SNAPSHOT="$snapshot" \
  "$root/picker.sh"

if ! grep -Fxq "$url" "$TEST_FZF_INPUT"; then
  printf 'FAIL - Neovim URL did not reach fzf\n' >&2
  exit 1
fi
if [ "$(cat "$TEST_OPENED_URL")" != "$url" ]; then
  printf 'FAIL - selected Neovim URL was not opened\n' >&2
  exit 1
fi
if [ -e "$snapshot" ]; then
  printf 'FAIL - Neovim snapshot was not removed\n' >&2
  exit 1
fi

printf 'ok   - Neovim buffers are captured before the popup opens\n'
