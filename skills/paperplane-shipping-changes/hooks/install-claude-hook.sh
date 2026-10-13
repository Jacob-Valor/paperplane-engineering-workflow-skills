#!/usr/bin/env bash
# Adds (or removes) the paperplane guard as a Claude Code PreToolUse hook on Bash.
# Usage: bash hooks/install-claude-hook.sh [--project|--user] [--uninstall]
#   --project (default) <repo root>/.claude/settings.local.json
#   --user              $HOME/.claude/settings.json
# Keeps every other setting. Running it again does not add a second entry.
# --uninstall removes only the paperplane guard entry.
# Exit codes: 0 done · 1 settings file unreadable or not writable ·
#             2 usage error, not in a git repo, or neither jq nor python3
set -uo pipefail

usage() { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; }
scope=project
uninstall=0
for arg in "$@"; do
  case "$arg" in
    --project) scope=project ;;
    --user) scope=user ;;
    --uninstall) uninstall=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $arg"; usage; exit 2 ;;
  esac
done

guard="$(cd "$(dirname "$0")" && pwd)/claude-guard.sh"
command="bash $(printf '%q' "$guard")"

if [ "$scope" = user ]; then
  [ -n "${HOME:-}" ] || { echo "HOME is not set"; exit 2; }
  file="$HOME/.claude/settings.json"
else
  root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "not inside a git repo; cd into the repo or use --user"; exit 2; }
  file="$root/.claude/settings.local.json"
fi

if [ -s "$file" ]; then
  current=$(cat "$file") || { echo "cannot read $file"; exit 1; }
else
  [ "$uninstall" -eq 1 ] && { echo "no $file; nothing to remove"; exit 0; }
  current='{}'
fi

# An entry is ours when its command runs paperplane-shipping-changes/hooks/claude-guard.sh.
jq_prog='
def ours: (.command? // "") | type == "string" and test("paperplane-shipping-changes/hooks/claude-guard\\.sh");
def strip:
  if (.hooks.PreToolUse | type) == "array" then
    .hooks.PreToolUse |= map(
      if (.hooks | type) == "array" and any(.hooks[]; ours)
      then (.hooks |= map(select(ours | not))) | select(.hooks | length > 0)
      else . end)
    | if .hooks.PreToolUse == [] then del(.hooks.PreToolUse) else . end
    | if .hooks == {} then del(.hooks) else . end
  else . end;
if $uninstall == "1" then strip
else strip | .hooks.PreToolUse += [{"matcher": "Bash", "hooks": [{"type": "command", "command": $cmd}]}]
end'

py_prog='
import json, re, sys
cmd, uninstall = sys.argv[1], sys.argv[2] == "1"
d = json.loads(sys.stdin.read())
if not isinstance(d, dict):
    raise SystemExit("settings file is not a JSON object")
def ours(h):
    c = h.get("command") if isinstance(h, dict) else None
    return isinstance(c, str) and re.search(r"paperplane-shipping-changes/hooks/claude-guard\.sh", c) is not None
hooks = d.get("hooks")
if isinstance(hooks, dict) and isinstance(hooks.get("PreToolUse"), list):
    kept = []
    for e in hooks["PreToolUse"]:
        if isinstance(e, dict) and isinstance(e.get("hooks"), list) and any(ours(h) for h in e["hooks"]):
            e["hooks"] = [h for h in e["hooks"] if not ours(h)]
            if not e["hooks"]:
                continue
        kept.append(e)
    hooks["PreToolUse"] = kept
    if not kept:
        del hooks["PreToolUse"]
    if not hooks:
        del d["hooks"]
if not uninstall:
    d.setdefault("hooks", {}).setdefault("PreToolUse", []).append(
        {"matcher": "Bash", "hooks": [{"type": "command", "command": cmd}]})
print(json.dumps(d, indent=2))'

if command -v jq >/dev/null 2>&1; then
  updated=$(printf '%s' "$current" | jq --arg cmd "$command" --arg uninstall "$uninstall" "$jq_prog")
elif command -v python3 >/dev/null 2>&1; then
  updated=$(printf '%s' "$current" | python3 -c "$py_prog" "$command" "$uninstall")
else
  echo "needs jq or python3 to edit $file"; exit 2
fi
[ $? -eq 0 ] && [ -n "$updated" ] || { echo "cannot parse $file as JSON; fix it by hand, it was not changed"; exit 1; }

mkdir -p "$(dirname "$file")" || { echo "cannot create $(dirname "$file")"; exit 1; }
tmp="$file.tmp.$$"
printf '%s\n' "$updated" >"$tmp" && mv "$tmp" "$file" || { rm -f "$tmp"; echo "cannot write $file"; exit 1; }
if [ "$uninstall" -eq 1 ]; then
  echo "removed the paperplane guard from $file"
else
  echo "installed the paperplane guard in $file: $command"
  echo "restart Claude Code (or open /hooks) so it loads the hook"
fi
