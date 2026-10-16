#!/usr/bin/env bash
# Claude Code PreToolUse hook: blocks Bash commands an agent must never run in
# paperplanehq repos (merge, approve, force-push, push to develop/uat/main,
# release tags, --no-verify, stage-everything, repo settings, npm/yarn/bun/npx
# in a pnpm repo). Install it with: bash <skill>/hooks/install-claude-hook.sh
# Usage: bash claude-guard.sh < hook-input.json
#   input: {"tool_name":"Bash","tool_input":{"command":"..."},"cwd":"..."}
# Exit codes: 0 allowed · 2 blocked, reason on stderr (Claude Code shows it to
#             the agent) · 1 could not read the input (Claude Code runs the command)
set -uo pipefail
export LC_ALL=C

case "${1:-}" in
  -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

json=$(cat)
field() { # field <key>...: string value at that path, empty if missing
  if command -v jq >/dev/null 2>&1; then
    local path=""
    for k in "$@"; do path="$path.$k"; done
    printf '%s' "$json" | jq -r "($path // \"\") | if type == \"string\" then . else \"\" end"
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$json" | python3 -c '
import json, sys
d = json.load(sys.stdin)
for k in sys.argv[1:]:
    d = d.get(k) if isinstance(d, dict) else None
sys.stdout.write(d if isinstance(d, str) else "")' "$@"
  else
    echo "paperplane guard: needs jq or python3 to read the hook input" >&2
    return 1
  fi
}
unreadable() { echo "paperplane guard: could not read the hook input; command not checked" >&2; exit 1; }

tool=$(field tool_name) || unreadable
[ "$tool" = Bash ] || exit 0
cmd=$(field tool_input command) || unreadable
cwd=$(field cwd) || unreadable
case "$cmd" in *git*|*gh*|*npm*|*npx*|*yarn*|*bun*) ;; *) exit 0 ;; esac
pnpm_repo=0
top=$(git -C "${cwd:-$PWD}" rev-parse --show-toplevel 2>/dev/null) || top=${cwd:-$PWD}
{ [ -f "${cwd:-$PWD}/pnpm-lock.yaml" ] || [ -f "$top/pnpm-lock.yaml" ]; } && pnpm_repo=1

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
R_SETTINGS="repo settings belong to the CTO; do not change them with gh repo edit or gh api PUT/PATCH/DELETE"
R_PNPM="this repo uses pnpm (pnpm-lock.yaml); use pnpm install, pnpm add or pnpm dlx instead"
R_GITCONFIG="git -c core.hooksPath/alias.* skips the repo's hooks or hides the real command; run plain git"

check_refspec() {
  local r=$1 dst
  case "$r" in +*) block "$R_FORCE"; return ;; esac
  case "$r" in *:*) dst=${r##*:} ;; *) dst=$r ;; esac
  case "${dst#refs/heads/}" in develop|uat|main) block "$R_PROTECTED"; return ;; esac
  case "${dst#refs/tags/}" in prod-[0-9]*|uat-[0-9]*) block "$R_TAGS" ;; esac
}

check_push() {
  local a pos=0 dashdash=0
  while [ $# -gt 0 ]; do
    a=$1; shift
    if [ "$dashdash" -eq 0 ]; then
      case "$a" in
        --) dashdash=1; continue ;;
        --for|--forc|--force*) block "$R_FORCE"; return ;;
        --no-veri*) block "$R_NOVERIFY"; return ;;
        --ta*) block "$R_TAGS"; return ;;
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
    [ "$pos" -gt 1 ] && check_refspec "$a"
  done
}

check_commit() {
  local a f j
  while [ $# -gt 0 ]; do
    a=$1; shift
    case "$a" in
      --) return ;;
      --all) block "$R_STAGEALL"; return ;;
      --no-veri*) block "$R_NOVERIFY"; return ;;
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
  local a dashdash=0
  for a in "$@"; do
    if [ "$dashdash" -eq 0 ]; then
      case "$a" in
        --) dashdash=1; continue ;;
        --al|--all|--no-ignore-r*|-A) block "$R_STAGEALL"; return ;;
        --*) continue ;;
        -?*) case "$a" in *A*) block "$R_STAGEALL"; return ;; esac; continue ;;
      esac
    fi
    case "$a" in .|./|:/) block "$R_STAGEALL"; return ;; esac
  done
}

check_git() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -c|--config-env)
        case "${2:-}" in [Cc][Oo][Rr][Ee].[Hh][Oo][Oo][Kk][Ss][Pp][Aa][Tt][Hh]*|[Aa][Ll][Ii][Aa][Ss].*) block "$R_GITCONFIG"; return ;; esac
        shift; [ $# -gt 0 ] && shift ;;
      -C|--git-dir|--work-tree|--namespace) shift; [ $# -gt 0 ] && shift ;;
      -*) shift ;;
      *) break ;;
    esac
  done
  [ $# -gt 0 ] || return 0
  local sub=$1; shift
  case "$sub" in
    push) check_push "$@" ;;
    commit) check_commit "$@" ;;
    add|stage) check_add "$@" ;;
  esac
}

check_gh() {
  local a p1="" p2="" skip=0
  for a in "$@"; do
    if [ "$skip" -eq 1 ]; then skip=0; continue; fi
    case "$a" in -R|--repo) skip=1; continue ;; -*) continue ;; esac
    if [ -z "$p1" ]; then p1=$a; elif [ -z "$p2" ]; then p2=$a; else break; fi
  done
  case "$p1 $p2" in
    "pr merge") block "$R_MERGE" ;;
    "repo edit") block "$R_SETTINGS" ;;
    "release create") block "$R_TAGS" ;;
    "pr review")
      for a in "$@"; do
        case "$a" in --approve|-a) block "$R_APPROVE"; return ;; esac
      done ;;
    api*)
      # Merges and approvals go through POST (REST or graphql), so match the
      # endpoint or mutation; a REST merge endpoint without fields or -X is a GET.
      local method="" fields=0 merge_ep=0 approve=0 review=0
      while [ $# -gt 0 ]; do
        a=$1; shift
        case "$a" in
          -X|--method) method=${1:-}; [ $# -gt 0 ] && shift ;;
          --method=*) method=${a#--method=} ;;
          -X?*) method=${a#-X} ;;
          -f|-F|--field|--raw-field|--input|-f?*|-F?*|--field=*|--raw-field=*|--input=*) fields=1 ;;
        esac
        case "$a" in *mergePullRequest*|*[Aa]utoMerge*|*mergeBranch*) block "$R_MERGE"; return ;; esac
        case "$a" in */merge|*/merges) merge_ep=1 ;; esac
        case "$a" in *APPROVE*) approve=1 ;; esac
        case "$a" in */reviews*|*PullRequestReview*) review=1 ;; esac
      done
      case "$method" in [Gg][Ee][Tt]) fields=0 ;; ?*) fields=1 ;; esac
      [ "$merge_ep" -eq 1 ] && [ "$fields" -eq 1 ] && { block "$R_MERGE"; return; }
      [ "$approve" -eq 1 ] && [ "$review" -eq 1 ] && { block "$R_APPROVE"; return; }
      case "$method" in
        [Pp][Uu][Tt]|[Pp][Aa][Tt][Cc][Hh]|[Dd][Ee][Ll][Ee][Tt][Ee]) block "$R_SETTINGS" ;;
      esac ;;
  esac
}

first_word() { # first argument that is not an option, empty if none
  local a
  for a in "$@"; do case "$a" in -*) ;; *) printf '%s' "$a"; return ;; esac; done
}

check_words() {
  # Drop redirections, leading VAR=value assignments and wrapper commands.
  local -a w=()
  local skip=0 a
  for a in "$@"; do
    if [ "$skip" -eq 1 ]; then skip=0; continue; fi
    case "$a" in
      [0-9]'>'|[0-9]'>>'|'>'|'>>'|'<'|'<<'|'<<<'|'&>'|'>|') skip=1; continue ;;
      '>'*|'<'*|[0-9]'>'*|[0-9]'<'*|'&>'*) continue ;;
    esac
    w+=("$a")
  done
  [ "${#w[@]}" -gt 0 ] || return 0
  set -- "${w[@]}"
  while [ $# -gt 0 ]; do
    case "$1" in
      [A-Za-z_]*=*|if|then|else|elif|fi|do|done|while|until|for|select|case|'esac'|'!'|'{'|'}') shift ;;
      sudo|env|command|builtin|nohup|time|exec|nice|xargs)
        shift
        while [ $# -gt 0 ]; do case "$1" in -*|[A-Za-z_]*=*) shift ;; *) break ;; esac; done ;;
      timeout)
        shift
        while [ $# -gt 0 ]; do case "$1" in -*) shift ;; *) break ;; esac; done
        [ $# -gt 0 ] && shift ;;
      *) break ;;
    esac
  done
  [ $# -gt 0 ] || return 0
  local name=${1##*/}; shift
  case "$name" in
    git) check_git "$@" ;;
    gh) check_gh "$@" ;;
    eval) check_string "$*" ;;
    bash|sh|zsh|dash)
      while [ $# -gt 0 ]; do
        case "$1" in
          -c|-[a-z]*c) [ $# -gt 1 ] && check_string "$2"; return ;;
          -*) shift ;;
          *) return ;;
        esac
      done ;;
  esac
  [ "$pnpm_repo" -eq 1 ] || return 0
  case " $* " in *' -g '*|*' --global '*) return 0 ;; esac  # global installs (npm i -g pnpm)
  local sub
  sub=$(first_word "$@")
  case "$name" in
    npx) block "$R_PNPM" ;;
    npm) case "$sub" in install|i|in|ins|inst|insta|instal|isntall|ci|add) block "$R_PNPM" ;; esac ;;
    yarn) case "$sub" in ''|add|install) block "$R_PNPM" ;; esac ;;
    bun) case "$sub" in install|i|add|a) block "$R_PNPM" ;; esac ;;
  esac
}

# Split a command line into simple commands (on ; & | && || newlines, ( ) and
# backticks) and words, honouring quotes and backslashes; check each command.
# $(...) and `...` inside double quotes are checked on their own; heredoc bodies
# are skipped.
check_string() {
  local s=$1 n=${#1} i=0 j d c q="" tok="" has=0 hd="" hds=0 line
  local -a seg=()
  while [ "$i" -lt "$n" ] && [ -z "$reason" ]; do
    c=${s:i:1}
    if [ -n "$q" ]; then
      if [ "$c" = "$q" ]; then
        q=""
      elif [ "$q" = '"' ] && [ "$c" = '`' ]; then
        j=$((i+1))
        while [ "$j" -lt "$n" ] && [ "${s:j:1}" != '`' ]; do j=$((j+1)); done
        check_string "${s:i+1:j-i-1}"; i=$j
      elif [ "$q" = '"' ] && [ "${s:i:2}" = '$(' ]; then
        j=$((i+2)); d=1
        while [ "$j" -lt "$n" ]; do
          case "${s:j:1}" in '(') d=$((d+1)) ;; ')') d=$((d-1)); [ "$d" -eq 0 ] && break ;; esac
          j=$((j+1))
        done
        check_string "${s:i+2:j-i-2}"; i=$j
      elif [ "$q" = '"' ] && [ "$c" = '\' ]; then
        i=$((i+1)); c=${s:i:1}
        case "$c" in '"'|'\'|'$'|'`') tok+=$c ;; $'\n') ;; *) tok+="\\$c" ;; esac
      else
        tok+=$c
      fi
    else
      case "$c" in
        "'"|'"') q=$c; has=1 ;;
        '\') i=$((i+1)); c=${s:i:1}; [ "$c" = $'\n' ] || { tok+=$c; has=1; } ;;
        ' '|$'\t')
          [ "$has" -eq 1 ] && seg+=("$tok"); tok=""; has=0 ;;
        '&'|$'\n'|';'|'|'|'('|')'|'`')
          if [ "$c" = '&' ] && [ "$has" -eq 1 ] && case "$tok" in *'>'|*'<') true ;; *) false ;; esac; then
            tok+=$c
          else
            [ "$has" -eq 1 ] && seg+=("$tok"); tok=""; has=0
            [ "${#seg[@]}" -gt 0 ] && check_words "${seg[@]}"
            seg=()
            if [ "$c" = $'\n' ] && [ -n "$hd" ]; then
              while [ "$i" -lt "$n" ]; do
                line=${s:i+1}; line=${line%%$'\n'*}
                i=$((i+1+${#line}))
                [ "$hds" -eq 1 ] && line=${line#"${line%%[!$'\t']*}"}
                [ "$line" = "$hd" ] && break
              done
              hd=""
            fi
          fi ;;
        '#')
          if [ "$has" -eq 0 ]; then
            while [ "$i" -lt "$n" ] && [ "${s:i:1}" != $'\n' ]; do i=$((i+1)); done
            continue
          fi
          tok+=$c ;;
        '<')
          # ponytail: one pending heredoc per line; a second one on the same line wins.
          if [ "${s:i:2}" = '<<' ] && [ "${s:i+2:1}" != '<' ]; then
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
          fi
          tok+=$c; has=1 ;;
        *) tok+=$c; has=1 ;;
      esac
    fi
    i=$((i+1))
  done
  [ "$has" -eq 1 ] && seg+=("$tok")
  [ "${#seg[@]}" -gt 0 ] && [ -z "$reason" ] && check_words "${seg[@]}"
  return 0
}

check_string "$cmd"
if [ -n "$reason" ]; then
  echo "paperplane guard: $reason" >&2
  exit 2
fi
exit 0
