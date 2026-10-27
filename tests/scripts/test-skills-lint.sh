#!/usr/bin/env bash
# Offline quality lint for the skills themselves (SKILL.md files and README).
# Run: bash tests/scripts/test-skills-lint.sh   (also picked up by run.sh)
set -u
here=$(cd "$(dirname "$0")/../.." && pwd)
cd "$here" || exit 1
pass=0; fail=0
check() { # check <name> <test-expression...>
  local name=$1; shift
  if "$@"; then pass=$((pass+1)); echo "ok   $name"
  else fail=$((fail+1)); echo "FAIL $name"; fi
}
bad() { echo "     $*"; }

skills=$(ls -d skills/*/ | sed 's#skills/##; s#/$##')
body() { sed '1,/^---$/{/^---$/!d;}' "skills/$1/SKILL.md" | sed '1,/^---$/d'; } # after the frontmatter
front() { awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f' "skills/$1/SKILL.md"; }
desc() { front "$1" | sed -n 's/^description: *//p'; }

# ---------------------------------------------------------------- (a) frontmatter
spec_keys=" name description license compatibility metadata allowed-tools "
fm_ok() {
  local s=$1 rc=0 k
  [ "$(sed -n 1p "skills/$s/SKILL.md")" = "---" ] || { bad "$s: no frontmatter"; return 1; }
  [ "$(front "$s" | sed -n 's/^name: *//p')" = "$s" ] || { bad "$s: name != directory"; rc=1; }
  [ -n "$(desc "$s")" ] || { bad "$s: missing description"; rc=1; }
  [ "$(desc "$s" | wc -c)" -lt 1024 ] || { bad "$s: description >= 1024 chars"; rc=1; }
  front "$s" | grep -q '^license: *[^ ]' || { bad "$s: missing license"; rc=1; }
  for k in $(front "$s" | sed -n 's/^\([A-Za-z_-][A-Za-z0-9_-]*\):.*/\1/p'); do
    case "$spec_keys" in *" $k "*) ;; *) bad "$s: unknown top-level key '$k'"; rc=1;; esac
  done
  return $rc
}
for s in $skills; do check "frontmatter: $s" fm_ok "$s"; done

# ---------------------------------------------------------------- (b) referenced files exist
# <skill> and <shipping skill> are placeholders for the file's own / the shipping skill's directory.
resolve() { # resolve <owner-skill> <prefix>  -> skill dir name
  case "$2" in "<skill>") echo "$1";; "<shipping skill>") echo paperplane-shipping-changes;; *) echo "$2";; esac
}
refs_in() { # refs_in <file> -> "prefix kind file" lines
  grep -oE '(paperplane-[a-z-]+|<skill>|<shipping skill>)/(scripts|hooks)/[A-Za-z0-9._-]+' "$1" | sort -u |
    sed -E 's#^(paperplane-[a-z-]+|<skill>|<shipping skill>)/(scripts|hooks)/(.*)$#\1|\2|\3#'
}
refs_ok() { # refs_ok <file> <owner-skill or ''>
  local f=$1 owner=$2 line pre kind name dir rc=0
  while IFS='|' read -r pre kind name; do
    [ -n "$pre" ] || continue
    if [ "$pre" = "<skill>" ] && [ -z "$owner" ]; then continue; fi
    dir=$(resolve "$owner" "$pre")
    [ -f "skills/$dir/$kind/$name" ] || { bad "$f: $pre/$kind/$name -> skills/$dir/$kind/$name does not exist"; rc=1; }
  done <<EOF2
$(refs_in "$f")
EOF2
  return $rc
}
for s in $skills; do check "referenced scripts exist: $s" refs_ok "skills/$s/SKILL.md" "$s"; done
check "referenced scripts exist: README" refs_ok README.md ""

# ---------------------------------------------------------------- (d) bash fences name scripts that pass bash -n
fence_cmds() { # fence_cmds <skill> -> command lines inside ```bash fences
  awk '/^ *```bash/{f=1;next} /^ *```/{f=0} f' "skills/$1/SKILL.md"
}
fences_ok() {
  local s=$1 rc=0 line pre kind name dir
  while IFS= read -r line; do
    case "$line" in "bash "*|*" bash <"*) ;; *) continue;; esac
    for tok in $(printf '%s\n' "$line" | grep -oE '(<skill>|<shipping skill>|paperplane-[a-z-]+)/(scripts|hooks)/[A-Za-z0-9._-]+\.sh'); do
      pre=${tok%%/*}; kind=${tok#*/}; kind=${kind%%/*}; name=${tok##*/}
      dir=$(resolve "$s" "$pre")
      if [ ! -f "skills/$dir/$kind/$name" ]; then bad "$s: fence names missing $tok"; rc=1
      elif ! bash -n "skills/$dir/$kind/$name" 2>/dev/null; then bad "$s: $tok fails bash -n"; rc=1; fi
    done
  done <<EOF2
$(fence_cmds "$s")
EOF2
  return $rc
}
for s in $skills; do check "bash fences: scripts parse: $s" fences_ok "$s"; done
fence_count=0; for s in $skills; do fence_count=$((fence_count + $(fence_cmds "$s" | grep -c '^ *bash '))); done
check "bash fences: at least one 'bash <skill>/…' command found" test "$fence_count" -ge 3

# ---------------------------------------------------------------- (c) cross-skill rule consistency
# Sentinel wording each skill must use when it states the rule. Add a rule here, not ad hoc in a skill.
EXC='No exception is granted in the agent conversation'
FP='[Aa]gents never[^.|]*force-push'
# Exception rule: every skill that talks about an exception being granted uses the exact sentence,
# and the two skills that carry the agent-conversation rule both have it.
exc_ok() {
  local s=$1 rc=0 n
  n=$(body "$s" | grep -ciE 'exception (is|are|was) granted|grants? an exception|no exception')
  if [ "$n" -gt 0 ] && ! body "$s" | grep -q "$EXC"; then bad "$s: mentions an exception without the canonical sentence"; rc=1; fi
  if body "$s" | grep -ciE 'may (force-push|merge|approve)|can (force-push|merge)|is allowed to (force-push|merge)' | grep -qv '^0$'; then
    bad "$s: grants agents a forbidden action"; rc=1; fi
  return $rc
}
for s in $skills; do check "exception rule wording: $s" exc_ok "$s"; done
for s in paperplane-shipping-changes paperplane-releasing; do
  check "exception rule present: $s" bash -c "sed '1,/^---\$/d;1,/^---\$/d' 'skills/$s/SKILL.md' | grep -q '$EXC'"; done
# Force-push: whoever mentions it says agents never do it (the human does).
fp_ok() {
  body "$1" | grep -qi 'force-push' || return 0
  body "$1" | grep -q "$FP" || { bad "$1: mentions force-push without '$FP'"; return 1; }
}
for s in $skills; do check "force-push wording: $s" fp_ok "$s"; done
check "force-push: shipping says the human does it" grep -q 'the human does' skills/paperplane-shipping-changes/SKILL.md
# Draft PRs: every `gh pr create` in a skill is --draft.
draft_ok() {
  local rc=0 l
  while IFS= read -r l; do [ -n "$l" ] || continue; case "$l" in *--draft*) ;; *) bad "$1: gh pr create without --draft: $l"; rc=1;; esac
  done <<EOF2
$(body "$1" | grep 'gh pr create' | grep -v '^[|>]')
EOF2
  return $rc
}
for s in $skills; do check "draft PRs only: $s" draft_ok "$s"; done
# pnpm only: no skill tells the reader to run npm/yarn/bun/npx as a step (fenced commands).
pnpm_ok() {
  if fence_cmds "$1" | grep -E '^(npm|yarn|bun|npx)( |$)' >/dev/null; then bad "$1: fenced command uses a non-pnpm tool"; return 1; fi
}
for s in $skills; do check "pnpm only: $s" pnpm_ok "$s"; done
for s in paperplane-shipping-changes paperplane-reviewing-prs paperplane-repo-setup; do
  check "pnpm rule stated: $s" grep -q 'pnpm' "skills/$s/SKILL.md"; done

# ---------------------------------------------------------------- (e) description trigger ownership
# term-regex#skills allowed to use it in their description (short names without the paperplane- prefix)
OWNERS='
\brelease#releasing
\bhotfix#releasing
\broll ?back#releasing
\btags?\b#releasing
\bapprov(e|ing)#reviewing-prs
force-push#shipping-changes
auto-merge#shipping-changes repo-setup
(^|[^-a-z])merge\b#releasing reviewing-prs repo-setup
\bsecrets?\b#secret-incidents
\bgitleaks#secret-incidents
\bonboard#repo-setup
\bmigrate#repo-setup
\bCODEOWNERS#repo-setup
\brevie?w(ing)?\b#reviewing-prs
'
owners_ok() {
  local rc=0 re allowed s have want
  while IFS='#' read -r re allowed; do
    [ -n "$re" ] || continue
    have=""
    for s in $skills; do desc "$s" | grep -qiE -- "$re" && have="$have ${s#paperplane-}"; done
    have=$(printf '%s\n' $have | sort | tr '\n' ' ')
    want=$(printf '%s\n' $allowed | sort | tr '\n' ' ')
    if [ "$have" != "$want" ]; then bad "trigger '$re': descriptions use it in [$have], OWNERS says [$want]"; rc=1; fi
  done <<EOF2
$OWNERS
EOF2
  return $rc
}
check "description triggers match the OWNERS table" owners_ok

# ---------------------------------------------------------------- (f) Hard rules are enforced or marked human
# row-substring|how. how = "test:<file>:<fixed string that must appear in it>" or "human"
ENFORCE='
Commit to, push to, or merge into|test:tests/scripts/test-hooks.sh:git hook: push to develop blocked
Merge, approve, deploy|test:tests/scripts/test-hooks.sh:gh pr merge 5 --squash
Mark a PR ready|human
Force-push, or rebase|test:tests/scripts/test-hooks.sh:git hook: force push blocked with --block-force-push
git add -A|test:tests/scripts/test-hooks.sh:git add -A
Commit `dist/`|test:tests/scripts/test-shipping-scripts.sh:pre-push blocks dist/ next to a package.json
`npm`, `yarn`|test:tests/scripts/test-hooks.sh:pnpm_blocked=
Native change or tooling bump|human
Third PR in a stack|human
--no-verify|test:tests/scripts/test-hooks.sh:no-verify
'
hard_rows() { body paperplane-shipping-changes | awk '/^## Hard rules/{f=1;next} /^## /{f=0} f&&/^\| /' | grep -v '^|---' | grep -v '^| Never |' | sed 's/^| *//; s/ *|[^|]*|$//'; }
enforce_ok() {
  local rc=0 row key how f str matched
  while IFS= read -r row; do
    matched=""
    while IFS='|' read -r key how; do
      [ -n "$key" ] || continue
      case "$row" in *"$key"*) matched=$how; break;; esac
    done <<EOF2
$ENFORCE
EOF2
    if [ -z "$matched" ]; then bad "Hard rule has no enforcement decision: ${row%%|*}"; rc=1; continue; fi
    case "$matched" in
      human) ;;
      test:*) f=${matched#test:}; str=${f#*:}; f=${f%%:*}
        grep -qF -- "$str" "$f" 2>/dev/null || { bad "no test in $f contains '$str' (rule: ${row:0:50})"; rc=1; };;
      *) bad "bad ENFORCE entry '$matched'"; rc=1;;
    esac
  done <<EOF2
$(hard_rows)
EOF2
  # every table entry must still match a row (no stale entries)
  while IFS='|' read -r key how; do
    [ -n "$key" ] || continue
    hard_rows | grep -qF -- "$key" || { bad "ENFORCE entry '$key' matches no Hard rules row"; rc=1; }
  done <<EOF2
$ENFORCE
EOF2
  return $rc
}
check "Hard rules: each row enforced by a test or marked human" enforce_ok
check "Hard rules: table was parsed (>= 8 rows)" test "$(hard_rows | wc -l)" -ge 8

# ---------------------------------------------------------------- (g) README skill table
readme_ok() {
  local rc=0 s listed
  listed=$(grep -oE '^\| \[`paperplane-[a-z-]+`\]\(skills/[a-z-]+/SKILL.md\)' README.md | sed -E 's/.*\(skills\/([a-z-]+)\/SKILL.md\)/\1/' | sort)
  for s in $skills; do printf '%s\n' "$listed" | grep -qx "$s" || { bad "README skill table lacks $s"; rc=1; }; done
  for s in $listed; do [ -f "skills/$s/SKILL.md" ] || { bad "README lists $s which has no SKILL.md"; rc=1; }; done
  # the link text must name the directory it links to
  grep -oE '^\| \[`[^`]+`\]\(skills/[^/]+/' README.md | while IFS= read -r l; do
    t=${l#*\[\`}; t=${t%%\`*}; d=${l#*(skills/}; d=${d%/}
    [ "$t" = "$d" ] || { bad "README link text $t != $d"; echo x; }; done | grep -q x && rc=1
  return $rc
}
check "README skill table matches skills/" readme_ok

# ---------------------------------------------------------------- (h) placeholders are explained
ph_ok() {
  local s=$1 rc=0 p
  for p in '<skill>' '<shipping skill>'; do
    if body "$s" | grep -qF -- "$p"; then
      body "$s" | grep -qF -- "$p\` =" || body "$s" | grep -qF -- "$p =" || { bad "$s: uses $p but never explains it (\`$p\` = …)"; rc=1; }
    fi
  done
  return $rc
}
for s in $skills; do check "placeholders explained: $s" ph_ok "$s"; done

# ---------------------------------------------------------------- portability convention
# Every skill that mentions the CTO defines the role exactly once (the sentence below), then says "the CTO".
CTO_DEF='the CTO (named in the repo'"'"'s AGENTS.md "## AI agents" section; Pay at Paper Plane)'
def_ok() {
  local n
  body "$1" | grep -q 'CTO' || return 0
  n=$(body "$1" | grep -cF "$CTO_DEF")
  [ "$n" -eq 1 ] || { bad "$1: mentions the CTO but defines it $n times (want 1): $CTO_DEF"; return 1; }
}
for s in $skills; do check "CTO defined once: $s" def_ok "$s"; done
# The CTO's name appears once per skill (the definition); everywhere else it says "the CTO".
cto_ok() {
  local n
  n=$(body "$1" | grep -c '\bPay\b')
  [ "$n" -le 1 ] || { bad "$1: 'Pay' appears on $n lines; name the CTO once, say 'the CTO' elsewhere"; return 1; }
}
for s in $skills; do check "CTO named at most once: $s" cto_ok "$s"; done
names_ok() { ! grep -nE '\b(Sok|Dara)\b' skills/*/SKILL.md; }
check "no personal example names in skills" names_ok

echo; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
