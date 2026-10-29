#!/usr/bin/env bash
# Claude Code PreToolUse hook: blocks Bash commands an agent must never run in
# paperplanehq repos (merge, approve, force-push, push to develop/uat/main, release
# tags, --no-verify, stage-everything, repo settings, npm/yarn/bun/npx in a pnpm repo)
# and Edit/Write/MultiEdit/NotebookEdit of the guard's own files. Install it with:
# bash <skill>/hooks/install-claude-hook.sh
# Usage: bash claude-guard.sh < hook-input.json
#   input: {"tool_name":"Bash","tool_input":{"command":"..."},"cwd":"..."}
#          {"tool_name":"Edit","tool_input":{"file_path":"..."},"cwd":"..."}
# Exit codes: 0 allowed · 2 blocked, reason on stderr (Claude Code shows it to
#             the agent) · 1 could not read the input and it names no tool we guard;
#             input that names the Bash/Edit/Write tools but cannot be read fails closed (2)
#
# Limits: a best-effort guard for an agent that is not trying to evade it, not a
# sandbox. The git pre-push hook (hooks/git-pre-push) and the server's branch
# protection and required reviews are the real controls. What this does NOT catch:
#  - tools other than Bash/Edit/Write/MultiEdit/NotebookEdit (MCP tools, an IDE);
#  - a ref the guard cannot read: a literal VAR=value in the same command is
#    followed, but "git push origin $B" with an unknown $B (or $(echo main)) is
#    allowed while the branch you are on is not develop/uat/main, because blocking
#    every variable blocked normal work; HEAD:$B is judged the same way. A literal
#    protected name, "$B:develop", ${B:-default} forms, xargs-fed refs and a protected
#    current branch are still refused. "$G push" is only caught when the next word
#    is push, merge or pr, and "$GH api ..." is checked as gh;
#  - commands built from text it cannot read: files over 64KB, binary files, scripts
#    nested more than 3 deep, files that do not exist yet (a file this same command
#    wrote is scanned), stdin from a file, shell aliases, shell functions defined
#    elsewhere, GIT_SSH_COMMAND, a hook an earlier command wrote, git config
#    include.path files (git aliases are expanded; "!" shell aliases are refused);
#  - eval/source of well-known init generators (ssh-agent -s, direnv export, pyenv
#    init, brew shellenv, kubectl completion, ...) is allowed; direnv runs .envrc,
#    which an agent could have written;
#  - python/node/ruby/perl code beyond a text scan for git/gh command lines (a
#    command assembled from pieces, or run through a library, passes); code from a
#    heredoc, here-string or pipe is scanned the same way;
#  - remote hops it cannot parse (ssh/docker/kubectl running a far-side script, git
#    inside a Makefile target or a CI job); "docker run img git push ..." is unwrapped;
#  - protected-file changes made by programs it does not know (python -c
#    "open(...)", cp from a script), find -delete with a name pattern that does not
#    mention the file (find . -name '*.json' -delete from the repo root), rm -rf .git
#    from a subdirectory (../.git), symlinks in a Bash path (the Edit/Write check does
#    resolve the directory), and a hook-skipping variable set some other way (set -a;
#    a script's own export);
#  - size: over 128KB, over 6000 statements or $( ) nested over 64 deep the guard
#    stops parsing; it then refuses ("command too large to check; split it") when
#    the text names git, gh or a protected path, and lets it run otherwise;
#  - a hook that times out (60s) lets the command run. The installed command fails
#    closed (exit 2) when this file is missing or exits with anything but 0 or 2.
set -uo pipefail
export LC_ALL=C

case "${1:-}" in
  -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

json=$(cat)
field() { # field <key>...: string value at that path, empty if missing; STRICT=1: not a string fails
  if command -v jq >/dev/null 2>&1; then
    local path=""
    for k in "$@"; do path="$path.$k"; done
    if [ -n "${STRICT:-}" ]; then
      printf '%s' "$json" | jq -r "($path) | if type == \"string\" then . else error(\"not a string\") end" 2>/dev/null
    else
      printf '%s' "$json" | jq -r "($path // \"\") | if type == \"string\" then . else \"\" end"
    fi
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$json" | python3 -c '
import json, sys
d = json.load(sys.stdin)
for k in sys.argv[1:]:
    d = d.get(k) if isinstance(d, dict) else None
if not isinstance(d, str) and __import__("os").environ.get("STRICT"):
    sys.exit(3)
sys.stdout.write(d if isinstance(d, str) else "")' "$@"
  else
    echo "paperplane guard: needs jq or python3 to read the hook input" >&2
    return 1
  fi
}
unreadable() { echo "paperplane guard: could not read the hook input; command not checked" >&2; exit 1; }
unreadable_closed() { echo "paperplane guard: could not read the $tool call's input; refusing to run it unchecked" >&2; exit 2; }
unreadable_tool() { # the input is not JSON we can parse: still block it when it names a tool we guard
  local t=${json//[[:space:]]/} name=""
  [ -z "$t" ] || [ "$t" = null ] && exit 0 # no tool call at all
  shopt -s nocasematch
  if [[ $json =~ \"tool_name\"[[:space:]]*:[[:space:]]*\"([A-Za-z]*)\" ]]; then name=${BASH_REMATCH[1]}; fi
  case "$name" in
    bash|edit|write|multiedit|notebookedit)
      echo "paperplane guard: could not read the hook input (needs jq or python3 and valid JSON); refusing to run a $name call unchecked" >&2
      exit 2 ;;
  esac
  shopt -u nocasematch
  # no parser at all and a tool we do not guard: nothing to check
  if [ -n "$name" ] && ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then exit 0; fi
  unreadable
}

tool=$(field tool_name) || unreadable_tool
ftool=0
case "$tool" in
  [Bb][Aa][Ss][Hh]) ;;
  [Ee][Dd][Ii][Tt]|[Ww][Rr][Ii][Tt][Ee]|[Mm][Uu][Ll][Tt][Ii][Ee][Dd][Ii][Tt]|[Nn][Oo][Tt][Ee][Bb][Oo][Oo][Kk][Ee][Dd][Ii][Tt]) ftool=1 ;;
  *) exit 0 ;;
esac
if [ "$ftool" -eq 1 ]; then
  cmd=$(STRICT=1 field tool_input file_path) || cmd=""
  [ -n "$cmd" ] || cmd=$(STRICT=1 field tool_input notebook_path) || cmd=""
else
  cmd=$(STRICT=1 field tool_input command) || unreadable_closed # a command we cannot read is not a pass
fi
cwd=$(field cwd) || unreadable_closed
edir=${cwd:-$PWD} # directory the command runs in; cd/pushd move it
gdir=$edir        # directory of the git command being checked (git -C)

PNPM_CACHE=$'\n' # "dir=0|1" lines: one git fork per directory, not per command
pnpm_at() { # pnpm_at <dir>: 0 if dir or its repo root has pnpm-lock.yaml
  local top hit
  case "$PNPM_CACHE" in
    *$'\n'"$1="*) hit=${PNPM_CACHE#*$'\n'"$1="}; hit=${hit%%$'\n'*}; [ "$hit" = 1 ]; return ;;
  esac
  if [ -f "$1/pnpm-lock.yaml" ]; then hit=1
  else
    top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || top=$1
    if [ -f "$top/pnpm-lock.yaml" ]; then hit=1; else hit=0; fi
  fi
  PNPM_CACHE+="$1=$hit"$'\n'
  [ "$hit" = 1 ]
}
resolve_dir() { # resolve_dir <arg> [base]: sets RD to the absolute path of an existing dir under base (edir), else fails (no fork)
  local p=$1 old=$PWD
  case "$p" in '~') p=${HOME:-'~'} ;; \~/*) [ -n "${HOME:-}" ] && p=$HOME/${p#'~/'} ;; esac
  case "$p" in ''|*'$'*|*'`'*|'~'*|-) return 1 ;; /*) ;; *) p=${2:-$edir}/$p ;; esac
  [ -d "$p" ] || return 1
  cd -P "$p" 2>/dev/null || return 1
  RD=$PWD
  cd "$old" 2>/dev/null || cd /
  return 0
}
move_dir() { # move_dir <arg> <base>: sets ND to where cd/git -C goes; a dir that does not exist (yet) or
  # cannot be read keeps its text, so the branch lookup there finds nothing and fails closed
  if resolve_dir "$1" "$2"; then ND=$RD; return; fi
  case "$1" in
    ''|-) ND="$2/?unknown$SOH" ;;
    /*) norm_path "$1"; ND=$NP ;;
    *) norm_path "$2/$1"; ND=$NP ;;
  esac
}

reason=""
block() { [ -n "$reason" ] || reason=$1; }

R_PROTECTED="pushing to develop/uat/main is not allowed; push your feature/fix/chore branch and open a PR"
R_FORCE="force push is not allowed (--force, -f, --force-with-lease, --force-if-includes, +refspec); merge the remote branch instead"
R_NOVERIFY="--no-verify skips the repo's checks; fix what fails instead"
R_TAGS="pushing release tags (prod-*, uat-*, --tags) or creating releases is the CTO's job"
R_ALLBRANCHES="git push --all/--mirror also pushes develop/uat/main; push one branch by name"
R_STAGEALL="stage files by name (git add path/to/file); git add -A/--all/. and git commit -a can pick up secrets and build output"
R_MERGE="agents never merge PRs or turn on auto-merge; a human merges"
R_APPROVE="agents never approve PRs; a human reviewer approves"
R_SETTINGS="repo settings belong to the CTO; do not change them with gh repo edit/delete/archive/rename, gh secret/variable, gh api on the repo, branch protection, rulesets, hooks, collaborators, environments or keys"
R_REFAPI="creating, moving or deleting develop/uat/main or release refs, tags and releases through the API skips the push checks; a human does that"
R_CLEANX="git clean -x/-X also deletes ignored files such as .claude/settings.local.json (this guard's own settings); use git clean -fd, or -n to preview"
R_PNPM="this repo uses pnpm (pnpm-lock.yaml); use pnpm install, pnpm add or pnpm dlx instead"
R_GITCONFIG="core.hooksPath, alias.* (\"!\" shell aliases above all), paperplane.* and GIT_CONFIG_*/GIT_DIR/GIT_EXEC_PATH skip the repo's hooks or hide the real command; run plain git"
R_PLUMBING="git send-pack skips the pre-push hook; use git push"
R_REFSPEC="refspecs with wildcards, {braces} or \$'...' can reach develop/uat/main; name the branch"
R_GHEXT="gh aliases and extensions hide or run other commands; use plain gh"
R_GHFILE="gh api graphql with query=@file or --input hides the mutation; put the query inline"
R_DYNPUSH="name the branch literally: the guard cannot see what \$VAR, \${...} or \$(...) holds, and the branch you are on is develop/uat/main (or unknown here) or xargs feeds the refs"
R_DYNCMD="the command word is a variable or substitution the guard cannot see through; write git and gh literally"
R_HIDDEN="piping decoded or downloaded text into a shell (or eval/sh -c of a substitution) hides the command; run the command itself"
R_SELF="the guard and its settings are the CTO's to change; do not remove, edit or disable them"
R_SKIPHOOK="HUSKY=0, HUSKY_SKIP_HOOKS, LEFTHOOK=0, SKIP= and PRE_COMMIT_ALLOW_NO_CONFIG turn off the repo's hooks; let the hooks run"
R_REFWRITE="moving develop/uat/main with update-ref or branch -f/-m/-d rewrites a protected branch; a human does that"

SOH=$'\001' # marks $VAR / ${...} in a word: the guard cannot see the value
STX=$'\002' # marks $(...) / backticks in a word
ETX=$'\003' # marks $(...) / <(...) that is a well-known shell-init generator (ssh-agent -s, brew shellenv, ...)

# Facts learned while walking the command, newest first, one "name=value" per line:
# literal VAR=value assignments, and "@vb=<dir>TAB<branch>" for a checkout/switch earlier in
# the same command. check_string saves and restores it, so a subshell or bash -c cannot leak.
VARS=$'\n'
var_get() { # var_get <name>: sets VV to the literal value of a variable; fails when unknown
  VV=""
  case "$1" in
    PWD) VV=$edir; return 0 ;;
    HOME) VV=${HOME:-}; [ -n "$VV" ]; return ;;
  esac
  case "$VARS" in
    *$'\n'"$1="*) VV=${VARS#*$'\n'"$1="}; VV=${VV%%$'\n'*}; [ "$VV" != "$ETX" ] ;;
    *) return 1 ;;
  esac
}
var_set() { # var_set <name> <value>: a value the guard cannot read is stored as unknown
  local v=$2
  case "$v" in *$'\n'*|*"$SOH"*|*"$STX"*|*"$ETX"*) v=$ETX ;; esac
  VARS=$'\n'"$1=$v$VARS"
}
var_unset() { VARS=$'\n'"$1=$ETX$VARS"; }
vb_set() { VARS=$'\n'"@vb=$gdir"$'\t'"$1$VARS"; } # the branch HEAD is on after a checkout/switch in this command
vb_get() { # sets VB when this command moved HEAD in the directory being checked
  local v
  case "$VARS" in
    *$'\n@vb='*) v=${VARS#*$'\n@vb='}; v=${v%%$'\n'*}; [ "${v%%$'\t'*}" = "$gdir" ] || return 1; VB=${v#*$'\t'} ;;
    *) return 1 ;;
  esac
}
dollar_var() { # dollar_var <s> <i>: s[i] is "$". Sets XV to the text for the token and XI to the last char used.
  local s=$1 i=$2 name="" j ch br=0
  XV="\$$SOH"; XI=$i
  j=$((i+1))
  if [ "${s:j:1}" = '{' ]; then br=1; j=$((j+1)); fi
  while :; do
    ch=${s:j:1}
    case "$ch" in [A-Za-z0-9_]) name+=$ch; j=$((j+1)) ;; *) break ;; esac
  done
  case "$name" in ''|[0-9]*) return 0 ;; esac
  if [ "$br" -eq 1 ]; then [ "${s:j:1}" = '}' ] || return 0; j=$((j+1)); fi
  XI=$((j-1)) # a plain $NAME or ${NAME}: the whole reference is one unknown value at worst
  var_get "$name" || return 0
  case "$VV" in ''|*[!A-Za-z0-9_./:@+,=%-]*) return 0 ;; esac
  is_cmd "$VV" && return 0 # G=git; $G push stays a dynamic command word
  XV=$VV
}
gen_ok() { # gen_ok <text of a $( ) or <( )>: one well-known shell-init generator whose output is setup code
  local t=$1 w rest=""
  [ "${#t}" -le 120 ] || return 1 # a generator is a short command; do not scan a big body
  t=${t#"${t%%[![:space:]]*}"}; t=${t%"${t##*[![:space:]]}"}
  case "$t" in ''|*';'*|*'|'*|*'&'*|*'<'*|*'>'*|*'$'*|*'`'*|*'('*|*')'*|*'\'*|*$'\n'*|*'"'*|*"'"*) return 1 ;; esac
  w=${t%% *}; [ "$w" != "$t" ] && rest=${t#* }
  w=${w##*/}
  [ -z "${rest//[A-Za-z0-9 _.=\/:@,-]/}" ] || return 1
  case "$w $rest" in
    "ssh-agent "*|"direnv export "*|"direnv hook "*|"pyenv init "*|"rbenv init "*|"nodenv init "*|"fnm env"*|"mise activate"*|"mise env"*|"mise hook-env"*) return 0 ;;
    "asdf completion "*|"brew shellenv"*|"starship init "*|"zoxide init "*|"conda shell."*|"conda init "*) return 0 ;;
    "kubectl completion "*|"helm completion "*|"gh completion "*|"npm completion"*|"pnpm completion"*|"docker completion "*) return 0 ;;
  esac
  return 1
}

REC=$'\004'; SEP=$'\005'
norm_path() { # norm_path <path>: sets NP to the path with //, /./ and /../ collapsed (text only, no symlinks)
  local IFS=/ part out="" p=$1
  case "$p" in /*) ;; *) p=$edir/$p ;; esac
  for part in $p; do
    case "$part" in
      ''|.) ;;
      ..) out=${out%/*} ;;
      *) out+="/$part" ;;
    esac
  done
  NP=${out:-/}
}
PROT_TREES=""; PROT_PARENTS="" # "<dir>\n" lines: folders holding the guard itself, wherever it is installed
prot_add() { # prot_add <tree|parent> <dir>: the path as written and with symlinks resolved
  local old=$PWD
  [ -n "$2" ] && [ "$2" != / ] || return 0
  norm_path "$2"
  if [ "$1" = tree ]; then PROT_TREES+="$NP"$'\n'; else PROT_PARENTS+="$NP"$'\n'; fi
  if [ -d "$NP" ] && cd -P "$NP" 2>/dev/null; then
    if [ "$1" = tree ]; then PROT_TREES+="$PWD"$'\n'; else PROT_PARENTS+="$PWD"$'\n'; fi
    cd "$old" 2>/dev/null || cd /
  fi
}
self_file=${BASH_SOURCE[0]:-$0}
case "$self_file" in /*) ;; *) self_file=$PWD/$self_file ;; esac
for _ in 1 2 3 4 5 6 7 8; do
  [ -L "$self_file" ] || break
  self_tgt=$(readlink "$self_file") || break
  case "$self_tgt" in /*) self_file=$self_tgt ;; *) self_file=${self_file%/*}/$self_tgt ;; esac
done
self_dir=${self_file%/*}
prot_add tree "$self_dir"
prot_add parent "${self_dir%/*}"
[ "${self_file##*/}" = claude-guard.sh ] && prot_add tree "${self_dir%/*}/scripts" # the skill: hooks/ and scripts/
omp_agent=${PI_CODING_AGENT_DIR:-${HOME:+$HOME/.omp/agent}}
if [ -n "$omp_agent" ]; then prot_add tree "$omp_agent/hooks/pre"; prot_add parent "$omp_agent/hooks"; prot_add parent "$omp_agent"; fi
prot_self() { # prot_self <absolute path> <dir 0|1>: inside a folder that holds the guard
  local rest=$PROT_TREES d
  while [ -n "$rest" ]; do
    d=${rest%%$'\n'*}; rest=${rest#*$'\n'}
    case "$1" in "$d"|"$d"/*) return 0 ;; esac
  done
  [ "$2" = 1 ] || return 1
  rest=$PROT_PARENTS
  while [ -n "$rest" ]; do
    d=${rest%%$'\n'*}; rest=${rest#*$'\n'}
    [ "$1" = "$d" ] && return 0
  done
  return 1
}
note_write() { # note_write <path> <text> <append 0|1>: remember what this command wrote, to scan it if it is run later
  local old=""
  case "$1" in ''|*"$SOH"*|*"$STX"*|*"$ETX"*|/dev/*) return ;; esac
  norm_path "$1"
  if [ "$3" -eq 1 ] && lookup_written "$NP"; then old=$WT$'\n'; fi
  WRITTEN="$REC$NP$SEP$old$2$WRITTEN"
}
lookup_written() { # sets WT to the text last written to the normalized path; fails if this command wrote none
  local rest
  case "$WRITTEN" in
    *"$REC$1$SEP"*) rest=${WRITTEN#*"$REC$1$SEP"}; WT=${rest%%"$REC"*} ;;
    *) return 1 ;;
  esac
}
skipvar() { # skipvar <NAME=value>: an environment variable that switches the repo's git hooks off
  case "$1" in
    HUSKY=0|LEFTHOOK=0) return 0 ;;
    HUSKY_SKIP_HOOKS=0|PRE_COMMIT_ALLOW_NO_CONFIG=0) return 1 ;;
    HUSKY_SKIP_HOOKS=?*|SKIP=?*|PRE_COMMIT_ALLOW_NO_CONFIG=?*|LEFTHOOK_EXCLUDE=?*) return 0 ;;
  esac
  return 1
}
hook_tool() { # hook_tool <command word>: commands whose hooks the variables above switch off
  case "${1##*/}" in git|pnpm|npm|yarn|bun|bunx|npx|husky|lefthook|pre-commit) return 0 ;; esac
  return 1
}

FORKN=0
fork_budget() { # every git/readlink lookup is a fork; a command that needs hundreds is treated as too big
  FORKN=$((FORKN+1))
  [ "$FORKN" -gt 400 ] && too_big
  return 0
}
gitc() { # run git on the repository being checked (git -C <dir>, or --git-dir/GIT_DIR)
  if [ -n "$GDOVR" ]; then git --git-dir="$GDOVR" "$@"; else git -C "$gdir" "$@"; fi
}
CB_CACHE=$'\n' # "<git dir>|<dir>=<branch>" lines: the real branch cannot change while we only read the command
cur_branch() { # sets CB to the branch HEAD is on; "?" when an earlier part of this command moved it somewhere unknown
  local VB key="$GDOVR|$gdir" hit
  CB=""
  if vb_get; then CB=$VB; return; fi
  [ -z "$GDOVR" ] && [ ! -d "$gdir" ] && { CB='?'; return; } # cd/git -C into a dir that does not exist yet
  case "$CB_CACHE" in
    *$'\n'"$key="*) hit=${CB_CACHE#*$'\n'"$key="}; CB=${hit%%$'\n'*}; return ;;
  esac
  fork_budget
  CB=$(gitc symbolic-ref --short -q HEAD 2>/dev/null)
  CB_CACHE+="$key=$CB"$'\n'
}

check_refspec() {
  local r=$1 dst
  case "$r" in +*) block "$R_FORCE"; return ;; esac
  case "$r" in *'*'*|*'{'*) block "$R_REFSPEC"; return ;; esac
  [ "$r" = : ] && { block "$R_ALLBRANCHES"; return; } # matching branches, develop included
  case "$r" in *:*) dst=${r##*:} ;; *) dst=$r ;; esac
  case "$dst" in HEAD|@) cur_branch; dst=$CB; [ "$dst" = '?' ] && { block "$R_PROTECTED"; return; } ;; esac # pushes the branch you are on
  case "$dst" in refs/heads/*) dst=${dst#refs/heads/} ;; heads/*) dst=${dst#heads/} ;; esac
  case "$dst" in develop|uat|main) block "$R_PROTECTED"; return ;; esac
  case "${dst#refs/tags/}" in prod-[0-9]*|uat-[0-9]*) block "$R_TAGS" ;; esac
}

check_bare_push() { # check_bare_push <remote or empty>: what a push with no refspec reaches
  local b rem v key
  cur_branch; b=$CB
  [ -n "$b" ] || return 0
  key="$GDOVR|$gdir|${1:-}|$b" # the same bare push again in one command: already judged and allowed
  case "$BARE_SEEN" in *$'\n'"$key"$'\n'*) return 0 ;; esac
  fork_budget; fork_budget; fork_budget
  rem=${1:-$(gitc config --get "branch.$b.remote" 2>/dev/null)}
  rem=${rem:-origin}
  case "$(gitc config --get push.default 2>/dev/null)" in
    upstream|tracking) check_refspec "$(gitc config --get "branch.$b.merge" 2>/dev/null)" ;;
    *) check_refspec HEAD ;;
  esac
  while IFS= read -r v; do [ -n "$v" ] && check_refspec "$v"; done <<EOF
$(gitc config --get-all "remote.$rem.push" 2>/dev/null)
EOF
  [ -z "$reason" ] && BARE_SEEN+="$key"$'\n'
}

check_dynref() { # a refspec with $VAR / $(...) in it: its value is unknown, so judge what is known
  # A name the guard cannot see is allowed when the branch you are on is not develop/uat/main and the
  # refspec does not spell a protected destination; the git pre-push hook and the server's branch
  # protection are the backstop for a variable that holds main. HEAD:$B is judged the same way.
  local r=$1 src dst b
  case "$r" in +*) block "$R_FORCE"; return ;; esac
  case "$r" in
    *:*)
      src=${r%%:*}; dst=${r#*:}
      case "$dst" in
        *"$SOH"*|*"$STX"*|*"$ETX"*) case "$src" in HEAD|@) ;; *) block "$R_DYNPUSH"; return ;; esac ;;
        *) check_refspec "$r"; return ;;
      esac ;;
  esac
  cur_branch; b=$CB
  case "$b" in develop|uat|main|'?') block "$R_DYNPUSH" ;; esac
}

check_push() {
  local a pos=0 dashdash=0 remote=""
  [ "$ansic" -eq 1 ] && { block "$R_REFSPEC"; return; }
  [ "$XARGS" -eq 1 ] && { block "$R_DYNPUSH"; return; } # xargs appends refs the guard cannot see
  while [ $# -gt 0 ]; do
    a=$1; shift
    if [ "$dashdash" -eq 0 ]; then
      case "$a" in
        --) dashdash=1; continue ;;
        --for|--forc|--force*) block "$R_FORCE"; return ;;
        --no-v|--no-ve|--no-ver|--no-veri|--no-verif|--no-verify|--no-verify=*) block "$R_NOVERIFY"; return ;;
        --ta*|--follow*) block "$R_TAGS"; return ;;
        --al|--all|--branches|--mi*) block "$R_ALLBRANCHES"; return ;;
        --repo=*) pos=1; continue ;;
        --repo) pos=1; [ $# -gt 0 ] && shift; continue ;;
        --push-option|--receive-pack|--exec) [ $# -gt 0 ] && shift; continue ;;
        --*) continue ;;
        -?*)
          case "$a" in *f*) block "$R_FORCE"; return ;; esac
          case "$a" in *o) [ $# -gt 0 ] && shift ;; esac
          continue ;;
      esac
    fi
    pos=$((pos+1))
    [ "$pos" -eq 1 ] && remote=$a
    if [ "$pos" -gt 1 ]; then
      case "$a" in *"$SOH{"*) block "$R_DYNPUSH"; return ;; esac # ${B-main}, ${B:-develop}: the default can be protected
      case "$a" in *"$SOH"*|*"$STX"*|*"$ETX"*) check_dynref "$a" ;; *) check_refspec "$a" ;; esac
      [ -n "$reason" ] && return
    fi
  done
  # no refspec: pushes the current branch, or what push.default/remote.<name>.push points at
  [ "$pos" -le 1 ] && check_bare_push "$remote"
}

check_commit() {
  local a f j
  while [ $# -gt 0 ]; do
    a=$1; shift
    case "$a" in
      --) return ;;
      --all) block "$R_STAGEALL"; return ;;
      --no-v|--no-ve|--no-ver|--no-veri|--no-verif|--no-verify|--no-verify=*) block "$R_NOVERIFY"; return ;;
      --message|--file|--author|--date|--template|--reuse-message|--reedit-message|--fixup|--squash|--trailer|--cleanup)
        [ $# -gt 0 ] && shift ;;
      --*) ;;
      -?*)
        f=${a#-}; j=0
        while [ "$j" -lt "${#f}" ]; do
          case "${f:j:1}" in
            a) block "$R_STAGEALL"; return ;;
            n) block "$R_NOVERIFY"; return ;;
            m|F|c|C|t) [ $((j+1)) -eq "${#f}" ] && [ $# -gt 0 ] && shift; break ;;
            u|S) break ;;
          esac
          j=$((j+1))
        done ;;
    esac
  done
}

check_add() {
  local a p dashdash=0
  for a in "$@"; do
    if [ "$dashdash" -eq 0 ]; then
      case "$a" in
        --) dashdash=1; continue ;;
        --al|--all|--no-ignore-r*|-A) block "$R_STAGEALL"; return ;;
        --*) continue ;;
        -?*) case "$a" in *A*) block "$R_STAGEALL"; return ;; esac; continue ;;
      esac
    fi
    p=${a#:/}; p=${p#':(top)'}
    while :; do case "$p" in ./*) p=${p#./} ;; /*) p=${p#/} ;; *) break ;; esac; done
    case "$p" in ''|.|'*'|'.*') block "$R_STAGEALL"; return ;; esac
  done
}

git_builtin() { # commands git runs itself; an alias of the same name is never used
  case "$1" in
    add|am|apply|archive|bisect|blame|branch|bundle|cat-file|check-attr|check-ignore|check-ref-format|checkout|cherry|cherry-pick|clean|clone|commit|config|count-objects) return 0 ;;
    describe|diff|diff-files|diff-index|diff-tree|difftool|fetch|for-each-ref|format-patch|fsck|gc|grep|hash-object|help|init|log|ls-files|ls-remote|ls-tree|maintenance) return 0 ;;
    merge|merge-base|merge-tree|mv|notes|pull|push|range-diff|read-tree|rebase|reflog|remote|repack|replace|rerere|reset|restore|rev-list|rev-parse|revert|rm) return 0 ;;
    send-pack|shortlog|show|show-branch|show-ref|sparse-checkout|stage|stash|status|submodule|switch|symbolic-ref|tag|update-index|update-ref|var|version|whatchanged|worktree|filter-branch) return 0 ;;
  esac
  return 1
}
alias_of() { # alias_of <name> <-c aliases>: sets AV to what git runs for "git <name>"; fails when it is no alias
  local rest=$2 e
  AV=""
  shopt -s nocasematch
  while [ -n "$rest" ]; do # the last -c wins; the list is newest first
    e=${rest%%$'\n'*}; rest=${rest#*$'\n'}
    case "$e" in "alias.$1="*) AV=${e#*=}; shopt -u nocasematch; return 0 ;; esac
  done
  shopt -u nocasematch
  case "$1" in *[!A-Za-z0-9_-]*|'') return 1 ;; esac
  fork_budget
  AV=$(gitc config --get "alias.$1" 2>/dev/null) && [ -n "$AV" ]
}

check_git() {
  local k a cal=""
  gdir=$edir
  GDOVR=""
  if [ -n "$SEG_GD" ]; then GDOVR=$SEG_GD
  elif var_get GIT_DIR; then resolve_dir "$VV" && GDOVR=$RD; fi
  while [ $# -gt 0 ]; do
    case "$1" in
      -c) hooky "${2:-}" && { block "$R_GITCONFIG"; return; }
        case "${2:-}" in [Aa][Ll][Ii][Aa][Ss].*=*) cal="$2"$'\n'"$cal" ;; esac
        shift; [ $# -gt 0 ] && shift ;;
      --config-env)
        hooky_kv "${2%%=*}" '?unknown' && { block "$R_GITCONFIG"; return; }
        shift; [ $# -gt 0 ] && shift ;;
      -c?*) hooky "${1#-c}" && { block "$R_GITCONFIG"; return; }
        case "${1#-c}" in [Aa][Ll][Ii][Aa][Ss].*=*) cal="${1#-c}"$'\n'"$cal" ;; esac
        shift ;;
      --config-env=*) a=${1#--config-env=}; hooky_kv "${a%%=*}" '?unknown' && { block "$R_GITCONFIG"; return; }; shift ;;
      -C) move_dir "${2:-}" "$gdir"; gdir=$ND; shift; [ $# -gt 0 ] && shift ;;
      --git-dir) resolve_dir "${2:-}" && GDOVR=$RD; shift; [ $# -gt 0 ] && shift ;;
      --git-dir=*) resolve_dir "${1#--git-dir=}" && GDOVR=$RD; shift ;;
      --work-tree|--namespace) shift; [ $# -gt 0 ] && shift ;;
      -*) shift ;;
      *) break ;;
    esac
  done
  [ $# -gt 0 ] || return 0
  local sub=$1; shift
  case "$sub" in *"$SOH"*|*"$STX"*) block "$R_DYNCMD"; return ;; esac
  if ! git_builtin "$sub" && alias_of "$sub" "$cal"; then # git co ...: judge what the alias runs
    case "${AV#"${AV%%[![:space:]]*}"}" in '!'*) block "$R_GITCONFIG"; return ;; esac
    local pre="" q e
    k=$cal
    while [ -n "$k" ]; do e=${k%%$'\n'*}; k=${k#*$'\n'}; printf -v q '%q' "$e"; pre=" -c $q$pre"; done
    [ -n "$GDOVR" ] && { printf -v q '%q' "$GDOVR"; pre=" --git-dir=$q$pre"; }
    printf -v q '%q' "$gdir"; pre="git -C $q$pre $AV"
    [ $# -gt 0 ] && { printf -v q '%q ' "$@"; pre+=" $q"; }
    check_string "$pre"
    return
  fi
  case "$sub" in
    push) check_push "$@" ;;
    branch) check_branch "$@"; track_branch "$@" ;;
    checkout|switch) track_head "$sub" "$@" ;;
    symbolic-ref) track_symref "$@" ;;
    rebase) check_noverify "$@"; check_execopt "$@" ;;
    submodule) check_submodule "$@" ;;
    bisect) [ "${1:-}" = run ] && { shift; [ $# -gt 0 ] && check_string "$(printf '%q ' "$@")"; } ;;
    filter-branch) check_filters "$@" ;;
    update-ref) check_updateref "$@" ;;
    clean) check_clean "$@" ;;
    rm|mv) for k in "$@"; do is_prot "$k" 1 && { block "$R_SELF"; return; }; done ;;
    commit) check_commit "$@" ;;
    add|stage) check_add "$@" ;;
    merge|cherry-pick|am) check_noverify "$@" ;;
    send-pack) block "$R_PLUMBING" ;;
    config) check_config "$@" ;;
  esac
}

branch_exists() { # branch_exists <name>: a local branch, or a remote-tracking one git checkout would create
  fork_budget; fork_budget
  gitc show-ref --verify --quiet "refs/heads/$1" 2>/dev/null && return 0
  [ -n "$(gitc for-each-ref --count=1 "refs/remotes/*/$1" 2>/dev/null)" ]
}
track_head() { # git checkout/switch: remember where HEAD goes, so a later push in the same command is judged there
  local sub=$1 a new="" pos="" dd=0 detach=0
  shift
  while [ $# -gt 0 ]; do
    a=$1; shift
    case "$a" in
      --) dd=1; break ;;
      -b|-B|-c|-C|--orphan) new=${1:-}; [ $# -gt 0 ] && shift ;;
      --create|--force-create) new=${1:-}; [ $# -gt 0 ] && shift ;;
      --orphan=*) new=${a#--orphan=} ;;
      -b?*|-B?*|-c?*|-C?*) case "$a" in -[bBcC][!-]*) new=${a#-?} ;; esac ;;
      -) [ -n "$pos" ] || pos=- ;;
      --detach|-d) detach=1 ;;
      -t|--track|-q|--quiet|-f|--force|-m|--merge|--no-track|--guess|--no-guess|--progress|--no-progress|--recurse-submodules|--no-recurse-submodules|--ignore-other-worktrees) ;;
      -*) ;;
      *) [ -n "$pos" ] || pos=$a ;;
    esac
  done
  if [ -n "$new" ]; then pos=$new
  elif [ "$dd" -eq 1 ] && [ "$sub" = checkout ]; then return 0 # git checkout <tree> -- paths restores files only
  elif [ "$detach" -eq 1 ]; then vb_set ""; return 0
  elif [ -z "$pos" ]; then return 0
  elif [ "$sub" = checkout ]; then
    case "$pos" in
      develop|uat|main|-|'@{-'*|*"$SOH"*|*"$STX"*|*"$ETX"*) ;;
      *) branch_exists "$pos" || return 0 ;; # a path or a commit, not a branch
    esac
  fi
  case "$pos" in -|'@{-'*|*"$SOH"*|*"$STX"*|*"$ETX"*) pos='?' ;; esac # a branch we cannot name
  vb_set "${pos#refs/heads/}"
}
track_symref() { # git symbolic-ref HEAD refs/heads/<branch>
  local a n=0 skip=0 tgt=""
  for a in "$@"; do
    if [ "$skip" -eq 1 ]; then skip=0; continue; fi
    case "$a" in -m) skip=1 ;; -*) ;; *) n=$((n+1)); [ "$n" -eq 2 ] && tgt=$a ;; esac
  done
  [ "$n" -eq 2 ] && [ -n "$tgt" ] && vb_set "${tgt#refs/heads/}"
  return 0
}
track_branch() { # git branch -m/-M <new>: the branch you are on gets a new name
  local a n=0 mv=0 nm=""
  for a in "$@"; do
    case "$a" in -m|-M|--move) mv=1 ;; -*) ;; *) n=$((n+1)); nm=$a ;; esac
  done
  [ "$mv" -eq 1 ] && [ "$n" -eq 1 ] && vb_set "$nm"
  return 0
}
check_execopt() { # git rebase -x/--exec <command>: the command runs after each commit
  local a
  while [ $# -gt 0 ]; do
    a=$1; shift
    case "$a" in
      -x|--exec) [ $# -gt 0 ] && { check_string "$1"; shift; } ;;
      --exec=*) check_string "${a#--exec=}" ;;
      -x?*) check_string "${a#-x}" ;;
    esac
  done
}
check_submodule() { # git submodule foreach [--recursive] <command>
  [ "${1:-}" = foreach ] || return 0
  shift
  while [ $# -gt 0 ]; do case "$1" in -*) shift ;; *) break ;; esac; done
  [ $# -gt 0 ] && check_string "$*"
  return 0
}
check_filters() { # git filter-branch --tree-filter/--index-filter/... <command>
  local a
  while [ $# -gt 0 ]; do
    a=$1; shift
    case "$a" in
      --tree-filter|--index-filter|--msg-filter|--env-filter|--commit-filter|--parent-filter|--tag-name-filter|--setup) [ $# -gt 0 ] && { check_string "$1"; shift; } ;;
    esac
  done
}

check_clean() { # dry runs are fine; -x/-X deletes ignored files, settings.local.json among them
  local k dry=0 x=0
  for k in "$@"; do
    case "$k" in
      --dry-run) dry=1 ;;
      --) break ;;
      --*) ;;
      -*) case "$k" in *n*) dry=1 ;; esac; case "$k" in *[xX]*) x=1 ;; esac ;;
    esac
  done
  [ "$dry" -eq 1 ] && return 0
  [ "$x" -eq 1 ] && { block "$R_CLEANX"; return; }
  # a plain clean removes untracked files that are not ignored: settings.local.json is one when
  # the repo does not ignore it. Ask git, but only when the pathspecs can reach it.
  local reach=1 p specs=0
  for p in "$@"; do
    case "$p" in -*) ;; *)
      if [ "$specs" -eq 0 ]; then specs=1; reach=0; fi
      case "$p" in .|./|'*'|:/|:/.|'.*') reach=1 ;; *) is_prot "$p" 1 && reach=1 ;; esac ;;
    esac
  done
  [ "$reach" -eq 1 ] || return 0
  fork_budget
  if [ -n "$(gitc ls-files --others --exclude-standard -- .claude/settings.json .claude/settings.local.json .claude/hooks/paperplane-guard.sh .omp/hooks/pre/paperplane-guard.ts .husky/pre-push 2>/dev/null)" ]; then
    block "$R_SELF"
  fi
  return 0
}

is_protected_branch() {
  case "$1" in develop|uat|main|refs/heads/develop|refs/heads/uat|refs/heads/main|heads/develop|heads/uat|heads/main) return 0 ;; esac
  return 1
}

check_branch() { # git branch -f/-m/-M/-d/-D/-c/-C touching develop/uat/main
  local a mut=0
  for a in "$@"; do
    case "$a" in
      --force|--move|--delete|--copy) mut=1 ;;
      --*) ;;
      -?*) case "$a" in *[fMmDdCc]*) mut=1 ;; esac ;;
    esac
  done
  [ "$mut" -eq 1 ] || return 0
  for a in "$@"; do
    case "$a" in -*) ;; *) is_protected_branch "$a" && { block "$R_REFWRITE"; return; } ;; esac
  done
}

check_updateref() { # git update-ref [-d] <ref> ...: the first non-option word is the ref
  local a skip=0
  for a in "$@"; do
    [ "$skip" -eq 1 ] && { skip=0; continue; }
    case "$a" in
      --stdin) block "$R_REFWRITE"; return ;;
      -m) skip=1 ;;
      -*) ;;
      *) is_protected_branch "$a" && block "$R_REFWRITE"; return ;;
    esac
  done
}

hooky() { # hooky <key[=value]>: the -c / --config-env form
  local k=${1%%=*} v=""
  case "$1" in *=*) v=${1#*=} ;; esac
  hooky_kv "$k" "$v"
}
hooky_kv() { # hooky_kv <key> <value>: true for settings that skip the hook or aim a push at a protected branch
  local k=$1 v=${2-} r=1
  shopt -s nocasematch
  case "$k" in
    core.hookspath*|include.path|includeif.*.path) r=0 ;;
    push.default) case "$v" in matching*|'?unknown') r=0 ;; esac ;;
    remote.*.push) r=0 ;;
    branch.*.merge) is_protected_branch "$v" && r=0 ;;
    alias.*) case "$v" in *push*|*merge*|*verify*|*hookspath*|'?unknown') r=0 ;; esac
      case "${v#"${v%%[![:space:]]*}"}" in '!'*) r=0 ;; esac ;; # "!cmd" runs a shell command the guard never sees
    paperplane.*) r=0 ;; # paperplane.blockForcePush: the pre-push hook's own switch
  esac
  shopt -u nocasematch
  return $r
}

check_noverify() {
  local a
  while [ $# -gt 0 ]; do
    a=$1; shift
    case "$a" in
      --) return ;;
      -m|-F|-X|--message|--file|--strategy-option) [ $# -gt 0 ] && shift ;;
      --no-v|--no-ve|--no-ver|--no-veri|--no-verif|--no-verify|--no-verify=*) block "$R_NOVERIFY"; return ;;
    esac
  done
}

check_config() { # writing core.hooksPath, hook-skipping aliases or push targets is blocked; reading stays allowed
  local a n=0 ro=0 del=0 k="" v=""
  case "${1:-}" in get|list) return 0 ;; unset|remove-section|rename-section) ro=1; del=1; shift ;; set) shift ;; esac
  while [ $# -gt 0 ]; do
    a=$1; shift
    case "$a" in
      --unset|--unset-all|--remove-section|--rename-section) ro=1; del=1 ;;
      --get|--get-all|--get-regexp|--get-urlmatch|--get-color|--get-colorbool|-l|--list|--edit|-e) ro=1 ;;
      --file|-f|--blob|--default|--type|-t) [ $# -gt 0 ] && shift ;;
      -*" "*) if [ "$n" -eq 1 ]; then n=2; v=$a; fi ;; # alias.x "-c core.hooksPath=/dev/null status": a value, not an option
      -*) ;;
      *) n=$((n+1)); if [ "$n" -eq 1 ]; then k=$a; elif [ "$n" -eq 2 ]; then v=$a; fi ;;
    esac
  done
  if [ "$del" -eq 1 ]; then
    case "$k" in [Pp][Aa][Pp][Ee][Rr][Pp][Ll][Aa][Nn][Ee]|[Pp][Aa][Pp][Ee][Rr][Pp][Ll][Aa][Nn][Ee].*) block "$R_GITCONFIG" ;; esac
  fi
  [ "$ro" -eq 0 ] && [ "$n" -ge 2 ] && hooky_kv "$k" "$v" && block "$R_GITCONFIG"
  return 0
}

api_class() { # api_class <endpoint> <write 0|1>: blocks settings, ref, tag and release writes (not comments, labels, PR edits)
  local e=$1 rest
  [ "$2" -eq 1 ] || return 0
  e=${e#https://api.github.com/}; e=${e#/}; e=${e%/}
  case "$e" in
    repos/*/*/branches/*/protection*|*/rulesets|*/rulesets/*|repos/*/*/hooks|repos/*/*/hooks/*|repos/*/*/collaborators|repos/*/*/collaborators/*) block "$R_SETTINGS"; return ;;
    repos/*/*/environments|repos/*/*/environments/*|repos/*/*/keys|repos/*/*/keys/*|repos/*/*/invitations*|*/actions/secrets*|*/actions/variables*|*/dependabot/secrets*) block "$R_SETTINGS"; return ;;
    repos/*/*/git/refs) block "$R_REFAPI"; return ;;
    repos/*/*/git/refs/heads/develop|repos/*/*/git/refs/heads/uat|repos/*/*/git/refs/heads/main|repos/*/*/git/refs/heads/develop/*|repos/*/*/git/refs/heads/uat/*|repos/*/*/git/refs/heads/main/*) block "$R_REFAPI"; return ;;
    repos/*/*/git/refs/tags/prod-*|repos/*/*/git/refs/tags/uat-*|repos/*/*/git/tags|repos/*/*/git/tags/*) block "$R_TAGS"; return ;;
    repos/*/*/releases|repos/*/*/releases/*) block "$R_TAGS"; return ;;
    repos/*/*) # the repo object itself: exactly repos/<owner>/<repo>
      rest=${e#repos/}
      case "$rest" in */*/*) ;; */*) block "$R_SETTINGS"; return ;; esac ;;
  esac
}

check_gh() {
  local a p1="" p2="" skip=0 bundle j ch
  for a in "$@"; do
    if [ "$skip" -eq 1 ]; then skip=0; continue; fi
    case "$a" in -R|--repo) skip=1; continue ;; -*) continue ;; esac
    if [ -z "$p1" ]; then p1=$a; elif [ -z "$p2" ]; then p2=$a; else break; fi
  done
  case "$p1" in *"$SOH"*|*"$STX"*|*"$ETX"*) block "$R_DYNCMD"; return ;; esac
  case "$p1" in
    pr|repo|secret|variable|workflow|ruleset|alias|extension|ext|release)
      case "$p2" in *"$SOH"*|*"$STX"*|*"$ETX"*) block "$R_DYNCMD"; return ;; esac ;;
  esac
  case "$p1 $p2" in
    "pr merge") block "$R_MERGE" ;;
    "repo edit"|"repo delete"|"repo archive"|"repo unarchive"|"repo rename"|"secret set"|"secret delete"|"secret remove"|"variable set"|"variable delete"|"variable remove"|"workflow disable") block "$R_SETTINGS" ;;
    "ruleset list"|"ruleset view"|"ruleset check"|"ruleset ") ;;
    "ruleset "*) block "$R_SETTINGS" ;;
    "alias set"|"alias import"|"extension install"|"extension exec"|"ext install"|"ext exec") block "$R_GHEXT" ;;
    "release create"|"release delete"|"release edit"|"release delete-asset"|"release upload") block "$R_TAGS" ;;
    "pr review")
      for a in "$@"; do
        case "$a" in
          --approve|--approve=*) block "$R_APPROVE"; return ;;
          --*) ;;
          -?*) # bundled short flags (-ab): -a approves unless it is the value of -b/-F
            bundle=${a#-}; j=0
            while [ "$j" -lt "${#bundle}" ]; do
              ch=${bundle:j:1}
              case "$ch" in a) block "$R_APPROVE"; return ;; b|F|R) break ;; esac
              j=$((j+1))
            done ;;
        esac
      done ;;
    api*)
      # Merges and approvals go through POST (REST or graphql), so match the
      # endpoint or mutation; a REST merge endpoint without fields or -X is a GET.
      local method="" fields=0 merge_ep=0 approve=0 review=0 hidden=0 hevent=0 graphql=0 inp=0 ep="" valskip=0 isval n
      while [ $# -gt 0 ]; do
        a=$1; shift
        isval=$valskip; valskip=0
        case "$a" in
          -X|--method) method=${1:-}; [ $# -gt 0 ] && shift ;;
          --method=*) method=${a#--method=} ;;
          -X?*) method=${a#-X} ;;
          -f|-F|--field|--raw-field|--input) fields=1; valskip=1 ;;
          -f?*|-F?*|--field=*|--raw-field=*|--input=*) fields=1 ;;
          -H|--header|-q|--jq|-t|--template|--cache|--hostname|-p|--preview) valskip=1 ;;
        esac
        n=${a%%\?*} # repos/o/r/pulls/1/merge?merge_method=squash and .../merge/ are the merge endpoint
        while [ "${n%/}" != "$n" ]; do n=${n%/}; done
        if [ "$isval" -eq 0 ]; then
          case "$a" in -*|api) ;; *) [ -n "$ep" ] || ep=$n ;; esac
        fi
        case "$a" in --input|--input=*) inp=1; hidden=1 ;; *query=@*|*query=*"$SOH"*|*query=*"$STX"*|*query=*"$ETX"*) hidden=1 ;; graphql) graphql=1 ;; esac
        case "$a" in *event=@*|*event=*"$SOH"*|*event=*"$STX"*|*event=*"$ETX"*) hevent=1 ;; esac
        case "$a" in *mergePullRequest*|*[Aa]utoMerge*|*mergeBranch*) block "$R_MERGE"; return ;; esac
        case "$a" in
          *[Uu]pdateRepository*|*[Dd]eleteRepository*|*[Aa]rchiveRepository*|*[Uu]narchiveRepository*|*BranchProtectionRule*|*[Rr]uleset*|*[Aa]ddCollaborator*|*[Cc]reateEnvironment*) block "$R_SETTINGS"; return ;;
          *[Cc]reateRef*|*[Uu]pdateRef*|*[Dd]eleteRef*|*[Cc]reateRelease*|*[Uu]pdateRelease*|*[Dd]eleteRelease*|*[Cc]reateTag*) block "$R_REFAPI"; return ;;
        esac
        case "$n" in */merge|*/merges) merge_ep=1 ;; esac
        case "$a" in *APPROVE*) approve=1 ;; esac
        case "$a" in */reviews*|*PullRequestReview*) review=1 ;; esac
      done
      case "$method" in [Gg][Ee][Tt]) fields=0 ;; ?*) fields=1 ;; esac
      [ "$graphql" -eq 1 ] && [ "$hidden" -eq 1 ] && ! case "$method" in [Gg][Ee][Tt]) true ;; *) false ;; esac && { block "$R_GHFILE"; return; }
      [ "$review" -eq 1 ] && { [ "$inp" -eq 1 ] || [ "$hevent" -eq 1 ]; } && [ "$fields" -eq 1 ] && { block "$R_APPROVE"; return; }
      [ "$merge_ep" -eq 1 ] && [ "$fields" -eq 1 ] && { block "$R_MERGE"; return; }
      [ "$approve" -eq 1 ] && [ "$review" -eq 1 ] && { block "$R_APPROVE"; return; }
      api_class "$ep" "$fields" ;;
  esac
}

is_cmd() { # words a wrapper (sudo, env, xargs, ssh, ...) may be running
  local b=${1##*/}
  case "$1" in ./*) return 0 ;; esac
  b=${b#=}
  case "$b" in git|git-?*|gh|npm|npx|yarn|bun|bunx|find|bash|sh|zsh|dash|ksh|mksh|ash|fish|csh|tcsh|eval|source|trap) return 0 ;; esac
  case "$b" in rm|mv|cp|tee|sponge|truncate|chmod|chown|chgrp|unlink|shred|ln|install|rsync|dd|sed|gsed|perl|ruby|awk|gawk|python|python2|python3|python3.*|node|nodejs) return 0 ;; esac
  return 1
}

check_npm() {
  local a
  while [ $# -gt 0 ]; do
    a=$1; shift
    case "$a" in
      --prefix|-w|--workspace|--registry|--userconfig|--cache|--loglevel|--tag|--otp|--scope) [ $# -gt 0 ] && shift ;;
      -*) ;;
      install|i|in|ins|inst|insta|instal|isntall|ci|add|uninstall|un|unlink|remove|rm|r|update|up|upgrade|udpate|exec|x|it|cit|clean-install|ic|install-test|install-ci-test|link|ln|dedupe|ddp|prune) block "$R_PNPM"; return ;;
      run|run-script|rum|urn|test|t|tst|start|stop|restart|view|v|show|info|ls|list|ll|la|root|bin|config|c|pack|publish|version|help|audit|outdated) return ;;
    esac
  done
}

check_yarn() {
  local a
  [ $# -gt 0 ] || { block "$R_PNPM"; return; } # bare yarn installs
  while [ $# -gt 0 ]; do
    a=$1; shift
    case "$a" in
      --cwd|--prefix|--registry|--cache-folder|--modules-folder|workspace) [ $# -gt 0 ] && shift ;;
      --version|-v|--help|-h) return ;;
      -*) ;;
      add|install|remove|dlx|up|upgrade|upgrade-interactive|dedupe|import|link|unlink) block "$R_PNPM"; return ;;
      *) return ;; # yarn test, yarn build: a script
    esac
  done
  block "$R_PNPM" # only options (yarn --frozen-lockfile) installs
}

check_bun() {
  local a
  while [ $# -gt 0 ]; do
    a=$1; shift
    case "$a" in
      --cwd|--config|-c) [ $# -gt 0 ] && shift ;;
      -*) ;;
      install|i|add|a|remove|rm|update|x|link|unlink) block "$R_PNPM"; return ;;
      *) return ;;
    esac
  done
}

check_find() { # find ... -exec <command> ... ;|+ : check each embedded command
  local f inexec=0
  local -a sub=()
  for f in "$@"; do
    if [ "$inexec" -eq 1 ]; then
      case "$f" in
        ';'|'+') [ "${#sub[@]}" -gt 0 ] && check_words "${sub[@]}"; sub=(); inexec=0 ;;
        *) sub+=("$f") ;;
      esac
    else
      case "$f" in -exec|-execdir|-ok|-okdir) inexec=1 ;; esac
    fi
  done
  [ "${#sub[@]}" -gt 0 ] && check_words "${sub[@]}"
  return 0
}

prot_lit() { # prot_lit <path> [dir]: a guard/settings/hook file (or, with dir=1, a directory holding them)
  local p=$1
  while :; do
    case "$p" in *//*) p=${p//\/\//\/} ;; */./*) p=${p//\/.\//\/} ;; *) break ;; esac
  done
  p=${p%/}
  case "$p" in /*) prot_self "$p" "${2:-0}" && return 0 ;; esac
  case "$p" in
    .claude/hooks/paperplane-guard.sh|*/.claude/hooks/paperplane-guard.sh) return 0 ;;
    .claude/settings.json|*/.claude/settings.json|.claude/settings.local.json|*/.claude/settings.local.json) return 0 ;;
    .omp/hooks/pre/paperplane-guard.ts|*/.omp/hooks/pre/paperplane-guard.ts) return 0 ;;
    .omp/hooks/pre/paperplane-guard.sh|*/.omp/hooks/pre/paperplane-guard.sh) return 0 ;;
    */.omp/agent/hooks/pre/paperplane-guard.ts|*/.omp/agent/hooks/pre/paperplane-guard.sh) return 0 ;;
    .git/config|*/.git/config|.git/config.worktree|*/.git/config.worktree) return 0 ;;
    .git/hooks/pre-push|*/.git/hooks/pre-push|.husky/pre-push|*/.husky/pre-push) return 0 ;;
  esac
  if [ "${2:-0}" = 1 ]; then
    case "$p" in
      .claude|*/.claude|.claude/hooks|*/.claude/hooks|.omp|*/.omp|.omp/hooks|*/.omp/hooks|.omp/hooks/pre|*/.omp/hooks/pre) return 0 ;;
      .husky|*/.husky|.git/hooks|*/.git/hooks|.git|./.git) return 0 ;;
    esac
  fi
  return 1
}

is_prot() { # is_prot <path> [dir]: does this argument name (or glob to) a protected file
  local p=$1 abs m
  case "$p" in ''|-*) return 1 ;; esac
  case "$p" in *"$SOH"*|*"$STX"*|*"$ETX"*) prot_lit "$p" "${2:-0}"; return ;; esac # "$DIR/.claude/settings.json": judge the part we can read
  case "$p" in '~') p=${HOME:-'~'} ;; \~/*) [ -n "${HOME:-}" ] && p=$HOME/${p#'~/'} ;; esac
  case "$p" in /*) abs=$p ;; *) abs=$edir/$p ;; esac
  prot_lit "$p" "${2:-0}" && return 0
  prot_lit "$abs" "${2:-0}" && return 0
  case "$p" in
    *..*) norm_path "$p"; prot_lit "$NP" "${2:-0}" && return 0 ;;
  esac
  [ "${2:-0}" = 1 ] && case "$abs" in "$edir/.git"|"$edir/.git/") return 0 ;; esac # rm -rf .git removes every hook and the repo
  case "$p" in
    *'*'*|*'?'*|*'['*|*'{'*)
      while IFS= read -r m; do
        [ -n "$m" ] && { prot_lit "$m" "${2:-0}" || prot_lit "$edir/$m" "${2:-0}"; } && return 0
      done <<EOF
$(cd "$edir" 2>/dev/null && compgen -G "$p")
EOF
      case "$p" in *.claude*|*.omp*|*.husky*|*.git/*) return 0 ;; esac ;; # a pattern we cannot expand: fail closed
  esac
  return 1
}

pat_prot() { # a find -name/-path pattern that can match a guard, settings or hook file
  case "${1##*/}" in settings.json|settings.local.json|paperplane-guard.*|pre-push|*guard*|*settings*|*pre-push*) return 0 ;; esac
  case "$1" in *.claude*|*.husky*|*.omp*|*/.git/hooks*|.git/hooks*) return 0 ;; esac
  return 1
}

check_self() { # check_self <command> <args...>: commands that remove or rewrite the guard and its settings
  local name=$1 a last="" tdir="" tnext=0 continue_chk=0 any=0 inpl=0 plus=0 minus=0 del=0 dd=0 prev=""
  shift
  case "$name" in
    rm|mv|tee|sponge|truncate|chmod|chown|chgrp|unlink|shred|ln|cp|install|rsync|dd|sed|gsed|perl|ruby|awk|gawk|find) ;;
    *) return 0 ;;
  esac
  case "$name" in rm|mv|shred|unlink|find) dd=1 ;; esac
  for a in "$@"; do
    case "$a" in
      of=*) a=${a#of=} ;;
      --target-directory=*) tdir=${a#--target-directory=} ;;
      -delete) del=1 ;;
    esac
    if [ "$name" = find ]; then
      case "$prev" in
        -name|-iname|-path|-ipath|-wholename|-iwholename|-regex|-iregex) pat_prot "$a" && any=1 ;;
        -exec|-execdir|-ok|-okdir) case "${a##*/}" in rm|mv|shred|unlink|truncate|tee|sponge|dd|cp|install) del=1 ;; esac ;;
      esac
    fi
    prev=$a
    case "$name" in
      sed|gsed|perl|ruby)
        case "$a" in --in-place*|-i*|-[A-Za-z]*i*) inpl=1 ;; esac ;;
      awk|gawk) [ "$a" = inplace ] && inpl=1 ;;
      chmod)
        case "$a" in
          -R|-f|-v|-h|-H|-L|-P|-c|--*) ;;
          -*|[ugoa]*-*|[0-7][0-7][0-7]*) minus=1 ;;
          *+[rwxXst]*) plus=1 ;;
        esac ;;
    esac
    if [ "$tnext" -eq 1 ]; then tdir=$a; tnext=0; continue_chk=1; else continue_chk=0; fi
    case "$a" in -t|--target-directory) tnext=1 ;; esac
    case "$a" in -*) ;; *) [ "$continue_chk" -eq 0 ] && last=$a ;; esac
    is_prot "$a" "$dd" && any=1
  done
  case "$name" in
    rm|mv|tee|sponge|truncate|chown|chgrp|unlink|shred|dd) [ "$any" -eq 1 ] && block "$R_SELF" ;;
    chmod) [ "$any" -eq 1 ] && ! { [ "$plus" -eq 1 ] && [ "$minus" -eq 0 ]; } && block "$R_SELF" ;;
    ln|cp|install|rsync)
      [ -n "$tdir" ] && last=$tdir
      [ -n "$last" ] && is_prot "$last" 1 && block "$R_SELF" ;;
    sed|gsed|perl|ruby|awk|gawk) [ "$inpl" -eq 1 ] && [ "$any" -eq 1 ] && block "$R_SELF" ;;
    find) [ "$del" -eq 1 ] && [ "$any" -eq 1 ] && block "$R_SELF"
          [ "$any" -eq 1 ] && SEG_PROT=1 ;; # find .claude | xargs rm
  esac
  return 0
}

scan_code() { # scan_code <text>: python/node/ruby/perl source; check every git/gh command line in it
  local t=$1 line rest ch re='(^|[^[:alnum:]_-])(git|gh)[[:space:]]+(.*)$'
  t=${t//\\n/ }; t=${t//\\r/ }; t=${t//\\t/ }
  for ch in '"' "'" '`' ',' '(' ')' '[' ']' ';' '\'; do t=${t//"$ch"/ }; done
  while IFS= read -r line; do
    while [ -z "$reason" ] && [[ $line =~ $re ]]; do
      rest=${BASH_REMATCH[3]}
      check_string "${BASH_REMATCH[2]} $rest"
      line=$rest
    done
  done <<EOF
$t
EOF
}

check_script() { # check_script <shell|code|auto> <path>: read the script a command is about to run
  local kind=$1 p=$2 f first body before=$reason size
  [ "$sdepth" -ge 3 ] && return 0
  case "$p" in ''|-|'~'*|*'$'*|*"$SOH"*|*"$STX"*) return 0 ;; /*) f=$p ;; *) f=$edir/$p ;; esac
  norm_path "$f"
  if lookup_written "$NP"; then # this command wrote the file: scan what it wrote, not what is on disk
    body=$WT
    first=${body%%$'\n'*}
  else
    [ -f "$f" ] && [ -r "$f" ] || return 0
    size=$(wc -c < "$f" 2>/dev/null | tr -d ' ')
    [ "${size:-999999}" -le 65536 ] 2>/dev/null || return 0
    grep -qI . "$f" 2>/dev/null || return 0 # empty or binary
    body=$(cat "$f" 2>/dev/null)
    first=$(head -n 1 "$f" 2>/dev/null)
  fi
  if [ "$kind" = auto ]; then
    case "$first" in '#!'*python*|'#!'*node*|'#!'*ruby*|'#!'*perl*|'#!'*php*) kind=code ;; *) kind=shell ;; esac
  fi
  sdepth=$((sdepth+1))
  if [ "$kind" = shell ]; then check_string "$body"; else scan_code "$body"; fi
  sdepth=$((sdepth-1))
  if [ -z "$before" ] && [ -n "$reason" ]; then reason="script $p: $reason"; fi
}

check_interp() { # python/node/ruby/perl arguments: inline code is scanned, a script file is read, stdin code is scanned
  local a
  while [ $# -gt 0 ]; do
    a=$1; shift
    case "$a" in
      -m) return ;;
      -W|-X|-r|--require|--import) [ $# -gt 0 ] && shift ;;
      -c|-e|-E|-p|--eval|--print|-[A-Za-z]*[eE])
        if [ $# -gt 0 ]; then
          case "$1" in *"$STX"*|"\$$SOH"*) block "$R_HIDDEN"; return ;; esac
          scan_code "$1"
        fi
        return ;;
      -) break ;;
      -*) ;;
      *) check_script code "$a"; return ;;
    esac
  done
  # no script and no -c: the interpreter reads its code from stdin (heredoc, here-string, pipe, file)
  [ -n "$hs" ] && scan_code "$hs"
  [ -n "$HDBODY" ] && scan_code "$HDBODY"
  [ -n "$PIPE_TEXT" ] && scan_code "$PIPE_TEXT"
  [ -n "$stdinf" ] && check_script code "$stdinf"
  [ -n "$PIPE_FILE" ] && check_script code "$PIPE_FILE"
  return 0
}

dyn_cmd() { # dyn_cmd <args after a command word the guard cannot read>: 0 when the command was judged
  # (blocked, or checked as gh); 1 when it does not look like git/gh at all. "$GH pr create" is fine;
  # push, merge, "pr merge/review" and gh subcommands it does not know are not.
  case "${1:-}" in
    push|merge) block "$R_DYNCMD"; return 0 ;;
    pr)
      case "${2:-}" in
        create|view|list|ready|checks|diff|status|comment|checkout) check_gh "$@" ;;
        *) block "$R_DYNCMD" ;;
      esac
      return 0 ;;
    api|release|repo|secret|variable|workflow|ruleset|alias|extension|ext) check_gh "$@"; return 0 ;;
  esac
  return 1
}

check_words() {
  # Drop redirections, leading VAR=value assignments and wrapper commands.
  local -a w=()
  local skip=0 a hs="" envbad=0 k ps=0 first stdinf="" wrapped=0
  local -a asg=()
  local viax=0 skipenv=0 sgd="" wapp=0 pending_app=0
  local -a wr=()
  for a in "$@"; do
    if [ "$skip" -ne 0 ]; then
      [ "$skip" -eq 1 ] && hs=$a
      if [ "$skip" -eq 2 ]; then is_prot "$a" && block "$R_SELF"; wr+=("$a"); wapp=$pending_app; fi
      [ "$skip" -eq 3 ] && stdinf=$a
      skip=0; continue
    fi
    case "$a" in
      '<<<') skip=1; continue ;;
      '<<<'*) hs=${a#<<<}; continue ;;
      "<$STX") ps=1; continue ;; # <( ... ) process substitution
      "<$ETX") continue ;;      # <( well-known init generator )
      [0-9]'>'|'>'|'&>'|'>|') skip=2; pending_app=0; continue ;;
      [0-9]'>>'|'>>') skip=2; pending_app=1; continue ;;
      '<'|'<<') skip=3; continue ;;
      '>'*|[0-9]'>'*|'&>'*)
        is_prot "${a##*>}" && block "$R_SELF"
        wr+=("${a##*>}"); case "$a" in *'>>'*) wapp=1 ;; *) wapp=0 ;; esac
        continue ;;
      '<'*) stdinf=${a#<}; continue ;;
      [0-9]'<'*) continue ;;
      *'>'*) is_prot "${a##*>}" && block "$R_SELF" ;; # echo x>file
    esac
    w+=("$a")
  done
  [ "${#w[@]}" -gt 0 ] || return 0
  set -- "${w[@]}"
  first=$1
  for a in "$@"; do
    case "$a" in PAPERPLANE_ALLOW_NO_GITLEAKS=*|PAPERPLANE_SKILL_DIR=*) block "$R_SELF" ;; esac
  done
  case "$first" in
    export|unset|declare|typeset|readonly|env|set|local)
      for a in "$@"; do case "$a" in PAPERPLANE_ALLOW_NO_GITLEAKS*|PAPERPLANE_SKILL_DIR*) block "$R_SELF" ;; esac; done ;;
  esac
  case "$first" in
    export|declare|typeset|readonly|local) # export BRANCH=feature/x: a literal value later $BRANCH can be judged by
      for a in "$@"; do
        case "$a" in GIT_CONFIG|GIT_CONFIG=*|GIT_CONFIG_*|GIT_EXEC_PATH|GIT_EXEC_PATH=*) block "$R_GITCONFIG" ;; esac
        case "$a" in [A-Za-z_]*=*) skipvar "$a" && block "$R_SKIPHOOK"; var_set "${a%%=*}" "${a#*=}" ;; esac
      done ;;
    unset) for a in "$@"; do case "$a" in -*) ;; *) var_unset "$a" ;; esac; done ;;
  esac
  while [ $# -gt 0 ]; do
    case "$1" in
      GIT_DIR=*) if resolve_dir "${1#GIT_DIR=}"; then sgd=$RD; else envbad=1; fi; shift ;;
      GIT_CONFIG=*|GIT_CONFIG_*=*|GIT_EXEC_PATH=*) envbad=1; shift ;;
      [A-Za-z_]*=*) skipvar "$1" && skipenv=1; asg+=("$1"); shift ;;
      function) shift; [ $# -gt 0 ] && shift ;; # function f { ...; }: the body is the commands after the brace
      if|then|else|elif|fi|do|done|while|until|for|select|case|'esac'|'!'|'{'|'}'|noglob|nocorrect) shift ;;
      sudo|doas|env|command|builtin|nohup|time|exec|nice|ionice|setsid|stdbuf|xargs|watch|ssh|su|script|runuser|flock|busybox|chroot|docker|docker-compose|podman|nerdctl|kubectl|parallel|pkexec|caffeinate|arch|gosu|su-exec|unbuffer|chronic|*/sudo|*/doas|*/env|*/nohup|*/nice|*/xargs|*/docker-compose|*/ssh|*/watch|*/setsid|*/stdbuf|*/ionice|*/time|*/command|*/unbuffer|*/chronic)
        case "$1" in xargs|*/xargs|parallel) viax=1 ;; esac
        shift; wrapped=1
        while [ $# -gt 0 ] && ! is_cmd "$1"; do
          case "$1" in
            GIT_DIR=*) if resolve_dir "${1#GIT_DIR=}"; then sgd=$RD; else envbad=1; fi ;;
            GIT_CONFIG=*|GIT_CONFIG_*=*|GIT_EXEC_PATH=*) envbad=1 ;;
          esac
          skipvar "$1" && skipenv=1
          [ "$skipenv" -eq 1 ] && hook_tool "$1" && block "$R_SKIPHOOK"
          case "$1" in
            *"$SOH"*|*"$STX"*) dyn_cmd "${@:2}" && return ;;
            *[[:space:]]*) check_string "$1" ;; # ssh host "git push ...", watch 'git ...'
          esac
          shift
        done ;;
      timeout|gtimeout|*/timeout|*/gtimeout)
        shift; wrapped=1
        while [ $# -gt 0 ]; do
          case "$1" in
            -s|-k|--signal|--kill-after) shift; [ $# -gt 0 ] && shift ;;
            -*) shift ;;
            *) break ;;
          esac
        done
        [ $# -gt 0 ] && shift ;; # the duration
      *) break ;;
    esac
  done
  if [ $# -eq 0 ]; then # only assignments: remember the literal ones for $VAR later in the command
    [ "${#asg[@]}" -gt 0 ] && for a in "${asg[@]}"; do var_set "${a%%=*}" "${a#*=}"; done
    return 0
  fi
  local cmd0=$1 name=${1##*/}
  case "$name" in =?*) name=${name#=} ;; esac # zsh: =git is the git on PATH
  shift
  case "$cmd0" in
    *"$SOH"*|*"$STX"*) dyn_cmd "$@" && return ;;
    *\\*) [ "$ansic" -eq 1 ] && dyn_cmd "$@" && return ;;
    *[[:space:]]*) [ "$wrapped" -eq 1 ] && { check_string "$cmd0"; return; } ;; # timeout 5 'git push ...'
  esac
  case "$name" in
    curl|wget|gunzip|zcat|bzcat|xzcat|uudecode|rev|tr|openssl) SEG_HIDDEN=1 ;;
    base64|gzip|bzip2|xz|xxd|brotli|zstd)
      for a in "$@"; do case "$a" in -d*|-D*|--decode*|--decompress|-r|-r*) SEG_HIDDEN=1 ;; esac; done ;;
    echo|printf) SEG_TEXT="$*" ;;
    cat) [ $# -eq 1 ] && SEG_FILE=$1 ;;
  esac
  # remember text this command writes to a file, so a later "bash that-file" is scanned
  local wtxt="" wp
  case "$name" in
    echo|printf) wtxt=$SEG_TEXT ;;
    cat) wtxt=$HDBODY ;;
  esac
  wtxt=${wtxt//\\n/$'\n'}; wtxt=${wtxt//\\t/ }
  if [ "${#wr[@]}" -gt 0 ] && [ -n "$wtxt" ]; then
    for wp in "${wr[@]}"; do note_write "$wp" "$wtxt" "$wapp"; done
  fi
  if [ "$name" = tee ]; then
    wtxt=${PIPE_TEXT:-$HDBODY}; wtxt=${wtxt//\\n/$'\n'}
    if [ -n "$wtxt" ]; then
      local tapp=0
      for wp in "$@"; do
        case "$wp" in -a|--append) tapp=1 ;; -*) ;; *) note_write "$wp" "$wtxt" "$tapp" ;; esac
      done
    fi
  fi
  check_self "$name" "$@"
  if [ "$PIPE_PROT" -eq 1 ]; then # find printed protected files and this command eats the list
    case "$name" in rm|mv|shred|unlink|truncate|tee|sponge|dd|cp|install) block "$R_SELF" ;; esac
  fi
  case "$cmd0" in */*) check_script auto "$cmd0" ;; esac
  XARGS=$viax; SEG_GD=$sgd
  [ "$skipenv" -eq 1 ] && hook_tool "$name" && block "$R_SKIPHOOK"
  case "$name" in
    git) [ "$envbad" -eq 1 ] && { block "$R_GITCONFIG"; return; }; check_git "$@" ;;
    git-?*) [ "$envbad" -eq 1 ] && { block "$R_GITCONFIG"; return; }; check_git "${name#git-}" "$@" ;; # git-push is git push
    trap) # trap 'cmd' EXIT: the command runs later
      [ "${1:-}" = -- ] && shift
      case "${1:-}" in -p|-l|-|'') ;; *"$STX"*|"\$$SOH"*) block "$R_HIDDEN"; return ;; *) check_string "$1" ;; esac ;;
    gh) check_gh "$@" ;;
    find) check_find "$@" ;;
    cd|pushd)
      k='~'; for a in "$@"; do case "$a" in -) k=-; break ;; -*) ;; *) k=$a; break ;; esac; done
      move_dir "$k" "$edir"; edir=$ND; return 0 ;;
    python|python2|python3|python3.*|node|nodejs|ruby|perl) check_interp "$@" ;;
    pnpm|npm|yarn|bun) # pnpm exec git push ...: check what it runs
      if [ $# -gt 0 ]; then
        local -a pa=("$@"); local pi=0
        while [ "$pi" -lt "${#pa[@]}" ]; do
          case "${pa[pi]}" in
            -*) pi=$((pi+1)) ;;
            exec|x|dlx) pi=$((pi+1)); [ "$pi" -lt "${#pa[@]}" ] && check_words "${pa[@]:pi}"; break ;;
            *) break ;;
          esac
        done
      fi ;;
    eval|source|.|bash|sh|zsh|dash|ksh|mksh|ash|fish|csh|tcsh)
      [ -n "$hs" ] && check_string "$hs"
      [ -n "$HDBODY" ] && check_string "$HDBODY" # shell fed by a heredoc
      [ "$ps" -eq 1 ] && { block "$R_HIDDEN"; return; }
      case "$name" in
        eval)
          [ "${1:-}" = -- ] && shift
          case "$*" in *"$STX"*|"\$$SOH"*) block "$R_HIDDEN"; return ;; esac
          check_string "$*" ;;
        source|.) [ $# -gt 0 ] && check_script shell "$1" ;;
        bash|sh|zsh|dash|ksh|mksh|ash|fish|csh|tcsh)
          local sflag=0 cflag=0
          while [ $# -gt 0 ]; do # sh -c -e 'cmd': the command is the first word after the options
            case "$1" in
              --) shift; break ;;
              --rcfile|--init-file) shift; [ $# -gt 0 ] && shift ;;
              --*) shift ;;
              -o|+o|-O|+O) shift; [ $# -gt 0 ] && shift ;;
              -s) sflag=1; shift ;;
              -*c*) cflag=1; shift ;;
              -*|+*) shift ;;
              *) break ;;
            esac
          done
          if [ "$cflag" -eq 1 ]; then
            if [ $# -gt 0 ]; then
              case "$1" in *"$STX"*|"\$$SOH"*) block "$R_HIDDEN"; return ;; esac
              check_string "$1"
            fi
            return
          fi
          [ $# -gt 0 ] && [ "$sflag" -eq 0 ] && { check_script shell "$1"; return; }
          # no script and no -c: the shell reads its commands from stdin
          [ "$PIPE_IN" -eq 1 ] && { block "$R_HIDDEN"; return; }
          [ -n "$PIPE_TEXT" ] && check_string "$PIPE_TEXT"
          [ -n "$stdinf" ] && check_script shell "$stdinf"
          [ -n "$PIPE_FILE" ] && check_script shell "$PIPE_FILE" ;;
      esac ;;
  esac
  case "$name" in npm|npx|yarn|bun|bunx) ;; *) return 0 ;; esac # only these can break the pnpm rule
  pnpm_at "$edir" || return 0
  case " $* " in *' -g '*|*' --global '*) return 0 ;; esac  # global installs (npm i -g pnpm)
  case "$name" in
    npx|bunx)
      for a in "$@"; do
        case "$a" in --version|-v|--help|-h) return 0 ;; -*) ;; *) break ;; esac
      done
      block "$R_PNPM" ;;
    npm) check_npm "$@" ;;
    yarn) check_yarn "$@" ;;
    bun) check_bun "$@" ;;
  esac
}

run_seg() {
  SEGN=$((SEGN+1))
  [ "$SEGN" -gt "$MAXSEG" ] && too_big
  [ "$HALT" -eq 0 ] && [ -z "$reason" ] || return 0
  PIPE_IN=$PIPE_NEXT; PIPE_TEXT=$PIPE_NEXT_TEXT; PIPE_FILE=$PIPE_NEXT_FILE
  PIPE_PROT=$PIPE_NEXT_PROT; PIPE_NEXT_PROT=0
  PIPE_NEXT=0; PIPE_NEXT_TEXT=""; PIPE_NEXT_FILE=""; SEG_HIDDEN=0; SEG_TEXT=""; SEG_FILE=""; SEG_PROT=0; SEG_GD=""
  check_words "$@"
  ansic=0
}

# Split a command line into simple commands (on ; & | && || newlines, ( ) ) and
# words, honouring quotes and backslashes; check each command. $(...) and `...`
# are checked on their own, and leave a marker in the word that holds them (so a
# push that names one can be refused); $VAR and ${...} leave a marker too.
# ( ) scope cd: the directory is restored at ). Heredoc bodies are skipped (but
# checked when a shell reads them); an unterminated heredoc is not skipped, and
# << inside $(( )), (( )) and [[ ]] is not a heredoc.
match_paren() { # match_paren <s> <j> <depth>: MP = index of the ")" that closes the group, or the end of s
  local s=$1 j=$2 d=$3 n=${#1} chunk pre
  while [ "$j" -lt "$n" ]; do
    chunk=${s:j:256}; pre=${chunk%%[()]*}
    if [ "${#pre}" -eq "${#chunk}" ]; then j=$((j+${#chunk})); continue; fi
    j=$((j+${#pre}))
    if [ "${s:j:1}" = '(' ]; then d=$((d+1)); else d=$((d-1)); [ "$d" -eq 0 ] && { MP=$j; return; }; fi
    j=$((j+1))
  done
  MP=$n
}
find_char() { # find_char <s> <j> <char>: MP = index of the next char at or after j, or the end of s
  local s=$1 j=$2 n=${#1} chunk pre
  while [ "$j" -lt "$n" ]; do
    chunk=${s:j:256}; pre=${chunk%%"$3"*}
    j=$((j+${#pre}))
    [ "${#pre}" -lt "${#chunk}" ] && { MP=$j; return; }
  done
  MP=$n
}
WORDSTOP=$' \t\n&;|()<\'"$\\`' # characters that end a run of ordinary word characters

# Hard limits, so a huge or deeply nested command cannot run the hook past its 60 s timeout (which
# fails open): over 128 KB, over 6000 statements, or $( ) nested more than 64 deep, the guard stops
# parsing. It then refuses ("command too large to check; split it") when the text names git or gh
# (or a protected path), and lets it run otherwise.
MAXCMD=131072; MAXSEG=6000; MAXDEPTH=64
SEGN=0; CDEPTH=0; HALT=0; CMD_ALL=""
too_big() {
  local t=${CMD_ALL//[\'\"\\]/} # g''it is still git
  if [[ $t =~ (^|[^[:alnum:]_-])(git|gh)([^[:alnum:]_-]|$) ]]; then
    block "command too large to check; split it (it names git or gh)"
  else
    case "$t" in
      *.claude*|*.husky*|*.omp*|*.git/*) block "command too large to check; split it (it names a protected path)" ;;
      *) HALT=1 ;;
    esac
  fi
}

check_string() {
  local s=$1 n=${#1} i=0 j d c q="" tok="" has=0 hd="" hds=0 line body k prev nx chunk run
  local hdskip=-1 arend=-1 dbr=0 saved_hd=$HDBODY saved_edir=$edir sp=0 saved_vars=$VARS
  local -a seg=() edstack=() vstack=()
  HDBODY=""
  CDEPTH=$((CDEPTH+1))
  [ "$CDEPTH" -gt "$MAXDEPTH" ] && too_big
  while [ "$i" -lt "$n" ] && [ -z "$reason" ] && [ "$HALT" -eq 0 ]; do
    c=${s:i:1}
    if [ -n "$q" ]; then
      if [ "$c" = "$q" ]; then
        q=""
      elif [ "$q" = '"' ] && [ "$c" = '`' ]; then
        find_char "$s" $((i+1)) '`'; j=$MP
        body=${s:i+1:j-i-1}; check_string "$body"; i=$j
        if gen_ok "$body"; then tok+="\$$ETX"; else tok+="\$$STX"; fi
      elif [ "$q" = '"' ] && [ "${s:i:2}" = '$(' ]; then
        match_paren "$s" $((i+2)) 1; j=$MP
        body=${s:i+2:j-i-2}; check_string "$body"; i=$j
        if gen_ok "$body"; then tok+="\$$ETX"; else tok+="\$$STX"; fi
      elif [ "$q" = '"' ] && [ "$c" = '$' ]; then
        case "${s:i+1:1}" in
          [A-Za-z_0-9@*#?!\$\{-]) dollar_var "$s" "$i"; tok+=$XV; i=$XI ;;
          *) tok+=$c ;;
        esac
      elif [ "$q" = '"' ] && [ "$c" = '\' ]; then
        i=$((i+1)); c=${s:i:1}
        case "$c" in '"'|'\'|'$'|'`') tok+=$c ;; $'\n') ;; *) tok+="\\$c" ;; esac
      else
        chunk=${s:i:256}
        if [ "$q" = "'" ]; then run=${chunk%%"'"*}; else run=${chunk%%[\"\\\$\`]*}; fi # up to the next character that matters in this quote
        tok+=$run; i=$((i+${#run}-1))
      fi
    else
      if [ "$c" = '(' ] && [ "${s:i:2}" = '((' ] && [ "$i" -gt "$arend" ]; then
        match_paren "$s" "$i" 0 # arithmetic: << in here is a shift, not a heredoc
        arend=$MP
      fi
      case "$c" in
        "'"|'"')
          case "$tok" in *'$') tok=${tok%?}; ansic=1 ;; esac # $'..' and $".." expand what we cannot see
          q=$c; has=1 ;;
        '$')
          nx=${s:i+1:1}
          case "$nx" in
            '(')
              match_paren "$s" $((i+2)) 1; j=$MP
              body=${s:i+2:j-i-2}
              [ "${s:i:3}" = '$((' ] || check_string "$body"
              i=$j; has=1
              if gen_ok "$body"; then tok+="\$$ETX"; else tok+="\$$STX"; fi ;;
            [A-Za-z_0-9@*#?!\$\{-]) dollar_var "$s" "$i"; tok+=$XV; i=$XI; has=1 ;;
            *) tok+=$c; has=1 ;;
          esac ;;
        '`')
          find_char "$s" $((i+1)) '`'; j=$MP
          body=${s:i+1:j-i-1}; check_string "$body"; i=$j; has=1
          if gen_ok "$body"; then tok+="\$$ETX"; else tok+="\$$STX"; fi ;;
        '\') i=$((i+1)); c=${s:i:1}; [ "$c" = $'\n' ] || { tok+=$c; has=1; } ;;
        ' '|$'\t')
          if [ "$has" -eq 1 ]; then
            case "$tok" in '[[') dbr=1 ;; ']]') dbr=0 ;; esac
            seg+=("$tok")
          fi
          tok=""; has=0 ;;
        '&'|$'\n'|';'|'|'|'('|')')
          if [ "$c" = '&' ] && [ "$has" -eq 1 ] && case "$tok" in *'>'|*'<') true ;; *) false ;; esac; then
            tok+=$c
          else
            if [ "$c" = '(' ] && [ "$tok" = '<' ]; then # <( ... ): the shell reads a command's output
              match_paren "$s" $((i+1)) 1; j=$MP
              if gen_ok "${s:i+1:j-i-1}"; then tok="<$ETX"; else tok="<$STX"; fi
            fi
            if [ "$has" -eq 1 ]; then
              [ "$tok" = ']]' ] && dbr=0
              seg+=("$tok")
            fi
            tok=""; has=0
            if [ "${#seg[@]}" -gt 0 ]; then
              run_seg "${seg[@]}"
              [ "$c" = '|' ] && { PIPE_NEXT=$SEG_HIDDEN; PIPE_NEXT_TEXT=$SEG_TEXT; PIPE_NEXT_FILE=$SEG_FILE; PIPE_NEXT_PROT=$SEG_PROT; }
            fi
            seg=()
            case "$c" in
              '|'|'&') [ "${s:i+1:1}" = "$c" ] && [ "$c" = '|' ] && { i=$((i+1)); PIPE_NEXT=0; PIPE_NEXT_TEXT=""; PIPE_NEXT_FILE=""; } ;;
            esac
            if [ "$c" = '(' ]; then edstack[sp]=$edir; vstack[sp]=$VARS; sp=$((sp+1))
            elif [ "$c" = ')' ] && [ "$sp" -gt 0 ]; then sp=$((sp-1)); edir=${edstack[sp]}; VARS=${vstack[sp]}
            elif [ "$c" = $'\n' ]; then
              dbr=0
              [ "$hdskip" -ge 0 ] && i=$hdskip
              hdskip=-1; HDBODY=""
            fi
          fi ;;
        '#')
          if [ "$has" -eq 0 ]; then
            find_char "$s" "$i" $'\n'; i=$MP
            continue
          fi
          tok+=$c ;;
        '<')
          # ponytail: one pending heredoc per line; a second one on the same line wins.
          prev=""; [ "$i" -gt 0 ] && prev=${s:i-1:1}
          if [ "${s:i:2}" = '<<' ] && [ "${s:i+2:1}" != '<' ] && [ "$prev" != '<' ] && [ "$dbr" -eq 0 ] && [ "$i" -gt "$arend" ]; then
            j=$((i+2)); hds=0; hd=""
            [ "${s:j:1}" = - ] && { hds=1; j=$((j+1)); }
            while [ "${s:j:1}" = ' ' ] || [ "${s:j:1}" = $'\t' ]; do j=$((j+1)); done
            while [ "$j" -lt "$n" ]; do
              case "${s:j:1}" in
                ' '|$'\t'|$'\n'|';'|'&'|'|'|'('|')'|'<'|'>') break ;;
                "'"|'"'|'\') ;;
                *) hd+=${s:j:1} ;;
              esac
              j=$((j+1))
            done
            # Find the body: the lines after this one up to the delimiter line.
            k=$j
            while [ "$k" -lt "$n" ] && [ "${s:k:1}" != $'\n' ]; do k=$((k+1)); done
            body=""; hdskip=-1; HDBODY=""
            while [ "$k" -lt "$n" ]; do
              line=${s:k+1}; line=${line%%$'\n'*}
              k=$((k+1+${#line}))
              [ "$hds" -eq 1 ] && line=${line#"${line%%[!$'\t']*}"}
              if [ "$line" = "$hd" ]; then hdskip=$k; HDBODY=$body; break; fi
              body+=$line$'\n'
            done
          fi
          tok+=$c; has=1 ;;
        *) chunk=${s:i:256}; run=${chunk%%["$WORDSTOP"]*}; tok+=$run; has=1; i=$((i+${#run}-1)) ;;
      esac
    fi
    i=$((i+1))
  done
  [ "$has" -eq 1 ] && seg+=("$tok")
  [ "${#seg[@]}" -gt 0 ] && [ -z "$reason" ] && [ "$HALT" -eq 0 ] && run_seg "${seg[@]}"
  HDBODY=$saved_hd; edir=$saved_edir; VARS=$saved_vars
  CDEPTH=$((CDEPTH-1))
  return 0
}

HDBODY=""; ansic=0; sdepth=0; BARE_SEEN=$'\n'; XARGS=0; GDOVR=""; SEG_GD=""; WRITTEN=""; SEG_PROT=0; PIPE_PROT=0; PIPE_NEXT_PROT=0
PIPE_NEXT=0; PIPE_NEXT_TEXT=""; PIPE_NEXT_FILE=""; PIPE_IN=0; PIPE_TEXT=""; PIPE_FILE=""
SEG_HIDDEN=0; SEG_TEXT=""; SEG_FILE=""
if [ "$ftool" -eq 1 ]; then
  # Edit/Write/MultiEdit/NotebookEdit: the same files rm, mv and redirects may not touch
  if [ -n "$cmd" ]; then
    shopt -s nocasematch # case-insensitive file systems: .CLAUDE/Settings.json is the same file
    case "$cmd" in /*) abs=$cmd ;; *) abs=$edir/$cmd ;; esac
    norm_path "$abs"
    if prot_lit "$cmd" || prot_lit "$abs" || prot_lit "$NP"; then block "$R_SELF"; fi
    dirpart=${NP%/*}; [ -n "$dirpart" ] || dirpart=/
    if [ -d "$dirpart" ] && real=$(cd "$dirpart" 2>/dev/null && pwd -P); then prot_lit "$real/${NP##*/}" && block "$R_SELF"; fi # symlinked directory
    lnk=$abs; hops=0
    while [ -L "$lnk" ] && [ "$hops" -lt 8 ]; do # a symlink to a protected file: writing through it writes the file
      tgt=$(readlink "$lnk") || break
      case "$tgt" in /*) lnk=$tgt ;; *) lnk=${lnk%/*}/$tgt ;; esac
      norm_path "$lnk"; lnk=$NP
      prot_lit "$lnk" && block "$R_SELF"
      hops=$((hops+1))
    done
    shopt -u nocasematch
  fi
else
  CMD_ALL=$cmd
  [ "${#cmd}" -gt "$MAXCMD" ] && too_big
  [ "$HALT" -eq 0 ] && [ -z "$reason" ] && check_string "$cmd"
fi
if [ -n "$reason" ]; then
  echo "paperplane guard: $reason" >&2
  exit 2
fi
exit 0
