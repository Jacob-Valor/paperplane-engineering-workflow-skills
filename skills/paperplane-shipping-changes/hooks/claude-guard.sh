#!/usr/bin/env bash
# Claude Code PreToolUse hook: blocks Bash commands an agent must never run in
# paperplanehq repos (merge, approve, force-push, push to develop/uat/main,
# release tags, --no-verify, stage-everything, repo settings, npm/yarn/bun/npx
# in a pnpm repo). Install it with: bash <skill>/hooks/install-claude-hook.sh
# Usage: bash claude-guard.sh < hook-input.json
#   input: {"tool_name":"Bash","tool_input":{"command":"..."},"cwd":"..."}
# Exit codes: 0 allowed · 2 blocked, reason on stderr (Claude Code shows it to
#             the agent) · 1 could not read the input (Claude Code runs the command)
#
# Limits: a best-effort guard for an agent that is not trying to evade it, not a
# sandbox. What it still does NOT catch:
#  - tools other than Bash (Edit/Write on hooks or settings, MCP tools, an IDE);
#  - commands built from text it cannot read: files over 64KB, binary files,
#    scripts nested more than 3 deep, files that do not exist yet, stdin from
#    cat or a file, aliases, shell functions, GIT_SSH_COMMAND, a hook that an
#    earlier command wrote;
#  - values behind $VAR, $(...) or backticks: a push naming one is blocked, but
#    "$G push" is only caught when the next word is push, merge or pr;
#  - python/node/ruby/perl code beyond a text scan for git/gh command lines (a
#    command assembled from pieces, or run through a library, passes);
#  - remote hops it cannot parse (ssh/docker exec running a far-side script, git
#    inside a Makefile target or a CI job);
#  - protected-file edits made by interpreters (python -c "open(...)"), find
#    -delete from a parent directory, or paths with .. in the middle; self-protection
#    covers rm/mv/cp/tee/sed -i/redirects and the like, not every program that
#    can write a file.
# Branch protection and required reviews on the server are the real control.
set -uo pipefail
export LC_ALL=C

case "${1:-}" in
  -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

tool=$(field tool_name) || unreadable
case "$tool" in [Bb][Aa][Ss][Hh]) ;; *) exit 0 ;; esac
cmd=$(STRICT=1 field tool_input command) || unreadable # a command we cannot read is not a pass
cwd=$(field cwd) || unreadable
edir=${cwd:-$PWD} # directory the command runs in; cd/pushd move it
gdir=$edir        # directory of the git command being checked (git -C)

pnpm_at() { # pnpm_at <dir>: 0 if dir or its repo root has pnpm-lock.yaml
  local top
  top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || top=$1
  [ -f "$1/pnpm-lock.yaml" ] || [ -f "$top/pnpm-lock.yaml" ]
}
resolve_dir() { # resolve_dir <arg>: absolute path of an existing dir under edir, else fail
  local p=$1
  case "$p" in ''|*'$'*|*'`'*|'~'*|-) return 1 ;; /*) ;; *) p=$edir/$p ;; esac
  [ -d "$p" ] && (cd "$p" 2>/dev/null && pwd -P)
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
R_SETTINGS="repo settings belong to the CTO; do not change them with gh repo edit or gh api PUT/PATCH/DELETE"
R_PNPM="this repo uses pnpm (pnpm-lock.yaml); use pnpm install, pnpm add or pnpm dlx instead"
R_GITCONFIG="core.hooksPath, alias.* and GIT_CONFIG_*/GIT_DIR/GIT_EXEC_PATH skip the repo's hooks or hide the real command; run plain git"
R_PLUMBING="git send-pack skips the pre-push hook; use git push"
R_REFSPEC="refspecs with wildcards, {braces} or \$'...' can reach develop/uat/main; name the branch"
R_GHEXT="gh aliases and extensions hide or run other commands; use plain gh"
R_GHFILE="gh api graphql with query=@file or --input hides the mutation; put the query inline"
R_DYNPUSH="name the branch literally: the guard cannot see what \$VAR, \${...} or \$(...) holds in a git push"
R_DYNCMD="the command word is a variable or substitution the guard cannot see through; write git and gh literally"
R_HIDDEN="piping decoded or downloaded text into a shell (or eval/sh -c of a substitution) hides the command; run the command itself"
R_SELF="the guard and its settings are the CTO's to change; do not remove, edit or disable them"
R_REFWRITE="moving develop/uat/main with update-ref or branch -f/-m/-d rewrites a protected branch; a human does that"

SOH=$'\001' # marks $VAR / ${...} in a word: the guard cannot see the value
STX=$'\002' # marks $(...) / backticks in a word

current_branch() { git -C "$gdir" symbolic-ref --short -q HEAD 2>/dev/null; }

check_refspec() {
  local r=$1 dst
  case "$r" in +*) block "$R_FORCE"; return ;; esac
  case "$r" in *'*'*|*'{'*) block "$R_REFSPEC"; return ;; esac
  [ "$r" = : ] && { block "$R_ALLBRANCHES"; return; } # matching branches, develop included
  case "$r" in *:*) dst=${r##*:} ;; *) dst=$r ;; esac
  case "$dst" in HEAD|@) dst=$(current_branch) ;; esac # pushes the branch you are on
  case "$dst" in refs/heads/*) dst=${dst#refs/heads/} ;; heads/*) dst=${dst#heads/} ;; esac
  case "$dst" in develop|uat|main) block "$R_PROTECTED"; return ;; esac
  case "${dst#refs/tags/}" in prod-[0-9]*|uat-[0-9]*) block "$R_TAGS" ;; esac
}

check_bare_push() { # check_bare_push <remote or empty>: what a push with no refspec reaches
  local b rem v
  b=$(current_branch)
  [ -n "$b" ] || return 0
  rem=${1:-$(git -C "$gdir" config --get "branch.$b.remote" 2>/dev/null)}
  rem=${rem:-origin}
  case "$(git -C "$gdir" config --get push.default 2>/dev/null)" in
    upstream|tracking) check_refspec "$(git -C "$gdir" config --get "branch.$b.merge" 2>/dev/null)" ;;
    *) check_refspec HEAD ;;
  esac
  while IFS= read -r v; do [ -n "$v" ] && check_refspec "$v"; done <<EOF
$(git -C "$gdir" config --get-all "remote.$rem.push" 2>/dev/null)
EOF
}

check_push() {
  local a pos=0 dashdash=0 remote=""
  [ "$ansic" -eq 1 ] && { block "$R_REFSPEC"; return; }
  while [ $# -gt 0 ]; do
    a=$1; shift
    if [ "$dashdash" -eq 0 ]; then
      case "$a" in
        --) dashdash=1; continue ;;
        --for|--forc|--force*) block "$R_FORCE"; return ;;
        --no-veri*) block "$R_NOVERIFY"; return ;;
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
      case "$a" in *"$SOH"*|*"$STX"*) block "$R_DYNPUSH"; return ;; esac
      check_refspec "$a"
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

check_git() {
  local k
  gdir=$edir
  while [ $# -gt 0 ]; do
    case "$1" in
      -c|--config-env)
        hooky "${2:-}" && { block "$R_GITCONFIG"; return; }
        shift; [ $# -gt 0 ] && shift ;;
      -c?*) hooky "${1#-c}" && { block "$R_GITCONFIG"; return; }; shift ;;
      --config-env=*) hooky "${1#--config-env=}" && { block "$R_GITCONFIG"; return; }; shift ;;
      -C) k=$(resolve_dir "${2:-}") && gdir=$k; shift; [ $# -gt 0 ] && shift ;;
      --git-dir|--work-tree|--namespace) shift; [ $# -gt 0 ] && shift ;;
      -*) shift ;;
      *) break ;;
    esac
  done
  [ $# -gt 0 ] || return 0
  local sub=$1; shift
  case "$sub" in *"$SOH"*|*"$STX"*) block "$R_DYNCMD"; return ;; esac
  case "$sub" in
    push) check_push "$@" ;;
    branch) check_branch "$@" ;;
    update-ref) check_updateref "$@" ;;
    clean) for k in "$@"; do case "$k" in --*) ;; -*x*|-*X*) block "$R_SELF"; return ;; esac; done ;; # -x also deletes ignored settings.local.json
    rm|mv) for k in "$@"; do is_prot "$k" 1 && { block "$R_SELF"; return; }; done ;;
    commit) check_commit "$@" ;;
    add|stage) check_add "$@" ;;
    merge|rebase|cherry-pick|am) check_noverify "$@" ;;
    send-pack) block "$R_PLUMBING" ;;
    config) check_config "$@" ;;
  esac
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

hooky() { # hooky <key[=value]>: true for core.hooksPath and alias.* settings
  case "$1" in [Pp][Uu][Ss][Hh].[Dd][Ee][Ff][Aa][Uu][Ll][Tt]=[Mm][Aa][Tt][Cc][Hh][Ii][Nn][Gg]*|[Rr][Ee][Mm][Oo][Tt][Ee].*.[Pp][Uu][Ss][Hh]=*) return 0 ;; esac
  case "$1" in [Cc][Oo][Rr][Ee].[Hh][Oo][Oo][Kk][Ss][Pp][Aa][Tt][Hh]*|[Aa][Ll][Ii][Aa][Ss].*) return 0 ;; esac
  return 1
}

check_noverify() {
  local a
  while [ $# -gt 0 ]; do
    a=$1; shift
    case "$a" in
      --) return ;;
      -m|-F|-X|--message|--file|--strategy-option) [ $# -gt 0 ] && shift ;;
      --no-veri*) block "$R_NOVERIFY"; return ;;
    esac
  done
}

check_config() { # writing core.hooksPath or alias.* is blocked; reading stays allowed
  local a n=0 hit=0 ro=0
  case "${1:-}" in get|list) return 0 ;; esac
  while [ $# -gt 0 ]; do
    a=$1; shift
    case "$a" in
      --get|--get-all|--get-regexp|--get-urlmatch|--get-color|--get-colorbool|-l|--list|--unset|--unset-all|--remove-section|--rename-section|--edit|-e) ro=1 ;;
      --file|-f|--blob|--default|--type|-t) [ $# -gt 0 ] && shift ;;
      -*) ;;
      *) n=$((n+1)); hooky "$a" && hit=1 ;;
    esac
  done
  [ "$ro" -eq 0 ] && [ "$hit" -eq 1 ] && [ "$n" -ge 2 ] && block "$R_GITCONFIG"
  return 0
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
    "alias set"|"alias import"|"extension install"|"extension exec"|"ext install"|"ext exec") block "$R_GHEXT" ;;
    "release create") block "$R_TAGS" ;;
    "pr review")
      for a in "$@"; do
        case "$a" in --approve|-a) block "$R_APPROVE"; return ;; esac
      done ;;
    api*)
      # Merges and approvals go through POST (REST or graphql), so match the
      # endpoint or mutation; a REST merge endpoint without fields or -X is a GET.
      local method="" fields=0 merge_ep=0 approve=0 review=0 hidden=0 graphql=0 inp=0
      while [ $# -gt 0 ]; do
        a=$1; shift
        case "$a" in
          -X|--method) method=${1:-}; [ $# -gt 0 ] && shift ;;
          --method=*) method=${a#--method=} ;;
          -X?*) method=${a#-X} ;;
          -f|-F|--field|--raw-field|--input|-f?*|-F?*|--field=*|--raw-field=*|--input=*) fields=1 ;;
        esac
        case "$a" in --input|--input=*) inp=1; hidden=1 ;; *query=@*) hidden=1 ;; graphql) graphql=1 ;; esac
        case "$a" in *mergePullRequest*|*[Aa]utoMerge*|*mergeBranch*) block "$R_MERGE"; return ;; esac
        case "$a" in */merge|*/merges) merge_ep=1 ;; esac
        case "$a" in *APPROVE*) approve=1 ;; esac
        case "$a" in */reviews*|*PullRequestReview*) review=1 ;; esac
      done
      case "$method" in [Gg][Ee][Tt]) fields=0 ;; ?*) fields=1 ;; esac
      [ "$graphql" -eq 1 ] && [ "$hidden" -eq 1 ] && ! case "$method" in [Gg][Ee][Tt]) true ;; *) false ;; esac && { block "$R_GHFILE"; return; }
      [ "$review" -eq 1 ] && [ "$inp" -eq 1 ] && [ "$fields" -eq 1 ] && { block "$R_APPROVE"; return; }
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

is_cmd() { # words a wrapper (sudo, env, xargs, ssh, ...) may be running
  case "$1" in ./*) return 0 ;; esac
  case "${1##*/}" in git|gh|npm|npx|yarn|bun|bunx|find|bash|sh|zsh|dash|ksh|mksh|ash|fish|csh|tcsh|eval|source) return 0 ;; esac
  case "${1##*/}" in rm|mv|cp|tee|truncate|chmod|chown|chgrp|unlink|shred|ln|install|rsync|dd|sed|gsed|perl|ruby|awk|gawk|python|python2|python3|python3.*|node|nodejs) return 0 ;; esac
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
  case "$p" in
    .claude/hooks/paperplane-guard.sh|*/.claude/hooks/paperplane-guard.sh) return 0 ;;
    .claude/settings.json|*/.claude/settings.json|.claude/settings.local.json|*/.claude/settings.local.json) return 0 ;;
    .omp/hooks/pre/paperplane-guard.ts|*/.omp/hooks/pre/paperplane-guard.ts) return 0 ;;
    .omp/hooks/pre/paperplane-guard.sh|*/.omp/hooks/pre/paperplane-guard.sh) return 0 ;;
    .git/hooks/pre-push|*/.git/hooks/pre-push|.husky/pre-push|*/.husky/pre-push) return 0 ;;
  esac
  if [ "${2:-0}" = 1 ]; then
    case "$p" in
      .claude|*/.claude|.claude/hooks|*/.claude/hooks|.omp|*/.omp|.omp/hooks|*/.omp/hooks|.omp/hooks/pre|*/.omp/hooks/pre) return 0 ;;
      .husky|*/.husky|.git/hooks|*/.git/hooks) return 0 ;;
    esac
  fi
  return 1
}

is_prot() { # is_prot <path> [dir]: does this argument name (or glob to) a protected file
  local p=$1 abs m
  case "$p" in ''|-*|*"$SOH"*|*"$STX"*) return 1 ;; esac
  case "$p" in /*) abs=$p ;; *) abs=$edir/$p ;; esac
  prot_lit "$p" "${2:-0}" && return 0
  prot_lit "$abs" "${2:-0}" && return 0
  case "$p" in
    *'*'*|*'?'*|*'['*|*'{'*)
      while IFS= read -r m; do
        [ -n "$m" ] && prot_lit "$m" "${2:-0}" && return 0
      done <<EOF
$(cd "$edir" 2>/dev/null && compgen -G "$p")
EOF
      case "$p" in *.claude*|*.omp*|*.husky*|*.git/*) return 0 ;; esac ;; # a pattern we cannot expand: fail closed
  esac
  return 1
}

check_self() { # check_self <command> <args...>: commands that remove or rewrite the guard and its settings
  local name=$1 a last="" tdir="" tnext=0 continue_chk=0 any=0 inpl=0 plus=0 minus=0 del=0 dd=0
  shift
  case "$name" in
    rm|mv|tee|truncate|chmod|chown|chgrp|unlink|shred|ln|cp|install|rsync|dd|sed|gsed|perl|ruby|awk|gawk|find) ;;
    *) return 0 ;;
  esac
  case "$name" in rm|mv|shred|unlink|find) dd=1 ;; esac
  for a in "$@"; do
    case "$a" in
      of=*) a=${a#of=} ;;
      --target-directory=*) tdir=${a#--target-directory=} ;;
      -delete|-exec|-execdir) del=1 ;;
    esac
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
    rm|mv|tee|truncate|chown|chgrp|unlink|shred|dd) [ "$any" -eq 1 ] && block "$R_SELF" ;;
    chmod) [ "$any" -eq 1 ] && ! { [ "$plus" -eq 1 ] && [ "$minus" -eq 0 ]; } && block "$R_SELF" ;;
    ln|cp|install|rsync)
      [ -n "$tdir" ] && last=$tdir
      [ -n "$last" ] && is_prot "$last" 1 && block "$R_SELF" ;;
    sed|gsed|perl|ruby|awk|gawk) [ "$inpl" -eq 1 ] && [ "$any" -eq 1 ] && block "$R_SELF" ;;
    find) [ "$del" -eq 1 ] && [ "$any" -eq 1 ] && block "$R_SELF" ;;
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
  [ -f "$f" ] && [ -r "$f" ] || return 0
  size=$(wc -c < "$f" 2>/dev/null | tr -d ' ')
  [ "${size:-999999}" -le 65536 ] 2>/dev/null || return 0
  grep -qI . "$f" 2>/dev/null || return 0 # empty or binary
  body=$(cat "$f" 2>/dev/null)
  if [ "$kind" = auto ]; then
    first=$(head -n 1 "$f" 2>/dev/null)
    case "$first" in '#!'*python*|'#!'*node*|'#!'*ruby*|'#!'*perl*|'#!'*php*) kind=code ;; *) kind=shell ;; esac
  fi
  sdepth=$((sdepth+1))
  if [ "$kind" = shell ]; then check_string "$body"; else scan_code "$body"; fi
  sdepth=$((sdepth-1))
  if [ -z "$before" ] && [ -n "$reason" ]; then reason="script $p: $reason"; fi
}

check_interp() { # python/node/ruby/perl arguments: inline code is scanned, a script file is read
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
      -*) ;;
      *) check_script code "$a"; return ;;
    esac
  done
}

dyn_cmd() { # the command word is dynamic: block when it looks like git/gh push, merge or pr
  case "${1:-}" in push|merge|pr) block "$R_DYNCMD"; return 0 ;; esac
  return 1
}

check_words() {
  # Drop redirections, leading VAR=value assignments and wrapper commands.
  local -a w=()
  local skip=0 a hs="" envbad=0 k ps=0 first stdinf="" wrapped=0
  for a in "$@"; do
    if [ "$skip" -ne 0 ]; then
      [ "$skip" -eq 1 ] && hs=$a
      [ "$skip" -eq 2 ] && is_prot "$a" && block "$R_SELF"
      [ "$skip" -eq 3 ] && stdinf=$a
      skip=0; continue
    fi
    case "$a" in
      '<<<') skip=1; continue ;;
      '<<<'*) hs=${a#<<<}; continue ;;
      "<$STX") ps=1; continue ;; # <( ... ) process substitution
      [0-9]'>'|[0-9]'>>'|'>'|'>>'|'&>'|'>|') skip=2; continue ;;
      '<'|'<<') skip=3; continue ;;
      '>'*|[0-9]'>'*|'&>'*) is_prot "${a##*>}" && block "$R_SELF"; continue ;;
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
    case "$a" in PAPERPLANE_ALLOW_NO_GITLEAKS=*) block "$R_SELF" ;; esac
  done
  case "$first" in
    export|unset|declare|typeset|readonly|env|set|local)
      for a in "$@"; do case "$a" in PAPERPLANE_ALLOW_NO_GITLEAKS*) block "$R_SELF" ;; esac; done ;;
  esac
  while [ $# -gt 0 ]; do
    case "$1" in
      GIT_CONFIG_*=*|GIT_DIR=*|GIT_EXEC_PATH=*) envbad=1; shift ;;
      [A-Za-z_]*=*|if|then|else|elif|fi|do|done|while|until|for|select|case|'esac'|'!'|'{'|'}') shift ;;
      sudo|doas|env|command|builtin|nohup|time|exec|nice|ionice|setsid|stdbuf|xargs|watch|ssh|su|script|runuser|flock|busybox|chroot|docker|podman|kubectl|parallel|pkexec|caffeinate|arch|gosu|su-exec|*/sudo|*/doas|*/env|*/nohup|*/nice|*/xargs|*/ssh|*/watch|*/setsid|*/stdbuf|*/ionice|*/time|*/command)
        shift; wrapped=1
        while [ $# -gt 0 ] && ! is_cmd "$1"; do
          case "$1" in GIT_CONFIG_*=*|GIT_DIR=*|GIT_EXEC_PATH=*) envbad=1 ;; esac
          case "$1" in
            *"$SOH"*|*"$STX"*) dyn_cmd "${2:-}" && return ;;
            *[[:space:]]*) check_string "$1" ;; # ssh host "git push ...", watch 'git ...'
          esac
          shift
        done ;;
      timeout)
        shift; wrapped=1
        while [ $# -gt 0 ]; do case "$1" in -*) shift ;; *) break ;; esac; done
        [ $# -gt 0 ] && shift ;;
      *) break ;;
    esac
  done
  [ $# -gt 0 ] || return 0
  local cmd0=$1 name=${1##*/}
  shift
  case "$cmd0" in
    *"$SOH"*|*"$STX"*) dyn_cmd "${1:-}" && return ;;
    *\\*) [ "$ansic" -eq 1 ] && dyn_cmd "${1:-}" && return ;;
    *[[:space:]]*) [ "$wrapped" -eq 1 ] && { check_string "$cmd0"; return; } ;; # timeout 5 'git push ...'
  esac
  case "$name" in
    curl|wget|gunzip|zcat|bzcat|xzcat|uudecode|rev|tr|openssl) SEG_HIDDEN=1 ;;
    base64|gzip|bzip2|xz|xxd|brotli|zstd)
      for a in "$@"; do case "$a" in -d*|-D*|--decode*|--decompress|-r|-r*) SEG_HIDDEN=1 ;; esac; done ;;
    echo|printf) SEG_TEXT="$*" ;;
    cat) [ $# -eq 1 ] && SEG_FILE=$1 ;;
  esac
  check_self "$name" "$@"
  case "$cmd0" in */*) check_script auto "$cmd0" ;; esac
  case "$name" in
    git) [ "$envbad" -eq 1 ] && { block "$R_GITCONFIG"; return; }; check_git "$@" ;;
    gh) check_gh "$@" ;;
    find) check_find "$@" ;;
    cd|pushd) k=$(resolve_dir "$(first_word "$@")") && edir=$k; return 0 ;;
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
          case "$*" in *"$STX"*|"\$$SOH"*) block "$R_HIDDEN"; return ;; esac
          check_string "$*" ;;
        source|.) [ $# -gt 0 ] && check_script shell "$1" ;;
        bash|sh|zsh|dash|ksh|mksh|ash|fish|csh|tcsh)
          local sflag=0
          while [ $# -gt 0 ]; do
            case "$1" in
              -c|-[a-z]*c)
                if [ $# -gt 1 ]; then
                  case "$2" in *"$STX"*|"\$$SOH"*) block "$R_HIDDEN"; return ;; esac
                  check_string "$2"
                fi
                return ;;
              -s) sflag=1; shift ;;
              -o|+o|-O|+O) shift; [ $# -gt 0 ] && shift ;;
              -*) shift ;;
              *) [ "$sflag" -eq 0 ] && { check_script shell "$1"; return; }; break ;;
            esac
          done
          # no script and no -c: the shell reads its commands from stdin
          [ "$PIPE_IN" -eq 1 ] && { block "$R_HIDDEN"; return; }
          [ -n "$PIPE_TEXT" ] && check_string "$PIPE_TEXT"
          [ -n "$stdinf" ] && check_script shell "$stdinf"
          [ -n "$PIPE_FILE" ] && check_script shell "$PIPE_FILE" ;;
      esac ;;
  esac
  pnpm_at "$edir" || return 0
  case " $* " in *' -g '*|*' --global '*) return 0 ;; esac  # global installs (npm i -g pnpm)
  case "$name" in
    npx|bunx) block "$R_PNPM" ;;
    npm) check_npm "$@" ;;
    yarn) check_yarn "$@" ;;
    bun) check_bun "$@" ;;
  esac
}

run_seg() {
  PIPE_IN=$PIPE_NEXT; PIPE_TEXT=$PIPE_NEXT_TEXT; PIPE_FILE=$PIPE_NEXT_FILE
  PIPE_NEXT=0; PIPE_NEXT_TEXT=""; PIPE_NEXT_FILE=""; SEG_HIDDEN=0; SEG_TEXT=""; SEG_FILE=""
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
check_string() {
  local s=$1 n=${#1} i=0 j d c q="" tok="" has=0 hd="" hds=0 line body k prev nx
  local hdskip=-1 arend=-1 dbr=0 saved_hd=$HDBODY saved_edir=$edir sp=0
  local -a seg=() edstack=()
  HDBODY=""
  while [ "$i" -lt "$n" ] && [ -z "$reason" ]; do
    c=${s:i:1}
    if [ -n "$q" ]; then
      if [ "$c" = "$q" ]; then
        q=""
      elif [ "$q" = '"' ] && [ "$c" = '`' ]; then
        j=$((i+1))
        while [ "$j" -lt "$n" ] && [ "${s:j:1}" != '`' ]; do j=$((j+1)); done
        check_string "${s:i+1:j-i-1}"; i=$j; tok+="\$$STX"
      elif [ "$q" = '"' ] && [ "${s:i:2}" = '$(' ]; then
        j=$((i+2)); d=1
        while [ "$j" -lt "$n" ]; do
          case "${s:j:1}" in '(') d=$((d+1)) ;; ')') d=$((d-1)); [ "$d" -eq 0 ] && break ;; esac
          j=$((j+1))
        done
        check_string "${s:i+2:j-i-2}"; i=$j; tok+="\$$STX"
      elif [ "$q" = '"' ] && [ "$c" = '$' ]; then
        case "${s:i+1:1}" in
          [A-Za-z_0-9@*#?!\$\{-]) tok+="\$$SOH" ;;
          *) tok+=$c ;;
        esac
      elif [ "$q" = '"' ] && [ "$c" = '\' ]; then
        i=$((i+1)); c=${s:i:1}
        case "$c" in '"'|'\'|'$'|'`') tok+=$c ;; $'\n') ;; *) tok+="\\$c" ;; esac
      else
        tok+=$c
      fi
    else
      if [ "$c" = '(' ] && [ "${s:i:2}" = '((' ] && [ "$i" -gt "$arend" ]; then
        j=$i; d=0 # arithmetic: << in here is a shift, not a heredoc
        while [ "$j" -lt "$n" ]; do
          case "${s:j:1}" in '(') d=$((d+1)) ;; ')') d=$((d-1)); [ "$d" -eq 0 ] && break ;; esac
          j=$((j+1))
        done
        arend=$j
      fi
      case "$c" in
        "'"|'"')
          case "$tok" in *'$') tok=${tok%?}; ansic=1 ;; esac # $'..' and $".." expand what we cannot see
          q=$c; has=1 ;;
        '$')
          nx=${s:i+1:1}
          case "$nx" in
            '(')
              j=$((i+2)); d=1
              while [ "$j" -lt "$n" ]; do
                case "${s:j:1}" in '(') d=$((d+1)) ;; ')') d=$((d-1)); [ "$d" -eq 0 ] && break ;; esac
                j=$((j+1))
              done
              [ "${s:i:3}" = '$((' ] || check_string "${s:i+2:j-i-2}"
              i=$j; tok+="\$$STX"; has=1 ;;
            [A-Za-z_0-9@*#?!\$\{-]) tok+="\$$SOH"; has=1 ;;
            *) tok+=$c; has=1 ;;
          esac ;;
        '`')
          j=$((i+1))
          while [ "$j" -lt "$n" ] && [ "${s:j:1}" != '`' ]; do j=$((j+1)); done
          check_string "${s:i+1:j-i-1}"; i=$j; tok+="\$$STX"; has=1 ;;
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
            [ "$c" = '(' ] && [ "$tok" = '<' ] && tok="<$STX" # <( ... ): the shell reads a command's output
            if [ "$has" -eq 1 ]; then
              [ "$tok" = ']]' ] && dbr=0
              seg+=("$tok")
            fi
            tok=""; has=0
            if [ "${#seg[@]}" -gt 0 ]; then
              run_seg "${seg[@]}"
              [ "$c" = '|' ] && { PIPE_NEXT=$SEG_HIDDEN; PIPE_NEXT_TEXT=$SEG_TEXT; PIPE_NEXT_FILE=$SEG_FILE; }
            fi
            seg=()
            case "$c" in
              '|'|'&') [ "${s:i+1:1}" = "$c" ] && [ "$c" = '|' ] && { i=$((i+1)); PIPE_NEXT=0; PIPE_NEXT_TEXT=""; PIPE_NEXT_FILE=""; } ;;
            esac
            if [ "$c" = '(' ]; then edstack[sp]=$edir; sp=$((sp+1))
            elif [ "$c" = ')' ] && [ "$sp" -gt 0 ]; then sp=$((sp-1)); edir=${edstack[sp]}
            elif [ "$c" = $'\n' ]; then
              dbr=0
              [ "$hdskip" -ge 0 ] && i=$hdskip
              hdskip=-1; HDBODY=""
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
        *) tok+=$c; has=1 ;;
      esac
    fi
    i=$((i+1))
  done
  [ "$has" -eq 1 ] && seg+=("$tok")
  [ "${#seg[@]}" -gt 0 ] && [ -z "$reason" ] && run_seg "${seg[@]}"
  HDBODY=$saved_hd; edir=$saved_edir
  return 0
}

HDBODY=""; ansic=0; sdepth=0
PIPE_NEXT=0; PIPE_NEXT_TEXT=""; PIPE_NEXT_FILE=""; PIPE_IN=0; PIPE_TEXT=""; PIPE_FILE=""
SEG_HIDDEN=0; SEG_TEXT=""; SEG_FILE=""
check_string "$cmd"
if [ -n "$reason" ]; then
  echo "paperplane guard: $reason" >&2
  exit 2
fi
exit 0
