#!/usr/bin/env bash
# Behaviour tests for shipping-changes/scripts/resolve-conflicts.sh. Run: bash tests/scripts/run.sh
set -u
here=$(cd "$(dirname "$0")/../.." && pwd)
R="$here/skills/paperplane-shipping-changes/scripts/resolve-conflicts.sh"
P="$here/skills/paperplane-shipping-changes/scripts/pre-push.sh"
pass=0; fail=0
expect() { # expect <name> <wanted-exit> <cmd...>
  local name=$1 want=$2; shift 2
  "$@" >/tmp/pp-test-out.$$ 2>&1; local got=$?
  if [ "$got" -eq "$want" ]; then pass=$((pass+1)); echo "ok   $name"
  else fail=$((fail+1)); echo "FAIL $name: exit $got, wanted $want"; sed 's/^/     /' /tmp/pp-test-out.$$; fi
}
check() { local name=$1; shift; if "$@"; then pass=$((pass+1)); echo "ok   $name"; else fail=$((fail+1)); echo "FAIL $name"; fi; }
said() { grep -q -- "$1" /tmp/pp-test-out.$$; }

work=$(mktemp -d); trap 'rm -rf "$work" /tmp/pp-test-out.$$' EXIT
# Fakes: gh answers `pr view` from $work/pr.json ("no pull requests found" without one) and logs every call;
# pnpm writes a lockfile from package.json in the folder it runs in; gitleaks finds nothing.
bin="$work/bin"; mkdir -p "$bin"
cat > "$bin/gh" <<EOF
#!/bin/sh
echo "\$*" >> "$work/gh.log"
case "\$1 \$2" in
  "pr view") [ -f "$work/pr.json" ] || { echo 'no pull requests found for branch "x"' >&2; exit 1; }
             [ -f "$work/gh.warn" ] && echo "Warning: 'reviewDecision' is deprecated" >&2
             jq -r "\${6:-.}" < "$work/pr.json" ;;
  "pr ready") exit 0 ;;
esac
EOF
cat > "$bin/pnpm" <<'EOF'
#!/bin/sh
[ "$1 $2" = "install --lockfile-only" ] || exit 1
{ echo "lockfileVersion: '9.0'"; echo "# rebuilt from:"; grep '"dep-' package.json || true; } > pnpm-lock.yaml
EOF
printf '#!/bin/sh\nexit 0\n' > "$bin/gitleaks"
chmod +x "$bin"/*
export PATH="$bin:$PATH"
pr_json() { printf '{"number":612,"isDraft":%s,"baseRefName":"develop","reviewDecision":"%s"}\n' "$1" "$2" > "$work/pr.json"; : > "$work/gh.log"; }
no_pr() { rm -f "$work/pr.json"; : > "$work/gh.log"; }

plain() { # plain <name>: bare origin + clone on develop
  local d="$work/$1"
  git init -q --bare "$d.git"; git clone -q "$d.git" "$d" 2>/dev/null
  cd "$d" || exit 1
  git config user.name T; git config user.email t@example.com
  git switch -qc develop
}
diverge() { # diverge <ours-cmd> <theirs-cmd>: feature/x does ours, develop does theirs, both pushed; ends on feature/x
  git switch -qc feature/x; eval "$1"; git add -A; git commit -qm "feat(x): ours"; git push -q -u origin feature/x
  git switch -q develop; eval "$2"; git add -A; git commit -qm "feat(y): theirs"; git push -q origin develop
  git switch -q feature/x
}
conflict() { # conflict <name> <file>: both sides changed <file>
  plain "$1"; echo a > "$2"; git add -- "$2"; git commit -qm init; git push -q origin develop
  diverge "echo ours > '$2'" "echo theirs > '$2'"
}
routes() { # routes <name>: package.json (compatible), lockfile and src/routes.ts conflict
  plain "$1"; mkdir src; printf 'export const routes = [\n  "home",\n];\n' > src/routes.ts
  printf '{\n  "name": "x",\n  "dependencies": {\n  }\n}\n' > package.json; printf "lockfileVersion: '9.0'\n" > pnpm-lock.yaml
  git add .; git commit -qm init; git push -q origin develop
  diverge "printf '{\n  \"name\": \"x\",\n  \"dependencies\": {\n    \"dep-ours\": \"1\"\n  }\n}\n' > package.json; printf '# ours\n' >> pnpm-lock.yaml; printf 'export const routes = [\n  \"home\",\n  \"alerts\",\n];\n' > src/routes.ts" \
          "printf '# theirs\n' >> pnpm-lock.yaml; printf 'export const routes = [\n  \"home\",\n  \"admin\",\n];\n' > src/routes.ts"
}
resolve_routes() { printf 'export const routes = [\n  "home",\n  "admin",\n  "alerts",\n];\n' > src/routes.ts; }
commit_and_push() { git commit -q --no-edit && bash "$P" origin/develop >/dev/null && git push -q origin feature/x; }

# --- refusals
routes refuse; pr_json false ""
git switch -q develop; expect "refuses on develop" 2 bash "$R"
git switch -q feature/x; echo dirty >> src/routes.ts
expect "refuses with uncommitted changes" 2 bash "$R"
git checkout -q -- src/routes.ts
expect "--check without a merge in progress" 2 bash "$R" --check
expect "unknown argument" 2 bash "$R" --force
expect "--check takes no --base" 2 bash "$R" --check --base main
(cd src && expect "refuses outside the repo root" 2 bash "$R")
check "nothing changed by the refusals" bash -c '[ -z "$(git status --porcelain --untracked-files=no)" ] && ! git rev-parse -q --verify MERGE_HEAD >/dev/null'

# --- the main path: a Ready, approved PR
routes main; pr_json false APPROVED; pushed=$(git rev-parse origin/feature/x)
expect "start: code conflict left for a person (exit 4)" 4 bash "$R"
check "start: PR taken back to draft" grep -qx 'pr ready 612 --undo' "$work/gh.log"
check "start: a merge (not a rebase) is in progress" bash -c 'git rev-parse -q --verify MERGE_HEAD >/dev/null'
check "start: lockfile rebuilt by pnpm and staged" bash -c 'grep -q "rebuilt from" pnpm-lock.yaml && ! git diff --name-only --diff-filter=U | grep -qx pnpm-lock.yaml'
check "start: lists the conflict with both sides' commits" bash -c "grep -q '== src/routes.ts' /tmp/pp-test-out.$$ && grep -q 'feat(y): theirs' /tmp/pp-test-out.$$ && grep -q 'feat(x): ours' /tmp/pp-test-out.$$"
expect "check: refuses while markers are left" 1 bash "$R" --check
resolve_routes
expect "check: a resolved file must be staged by name" 1 bash "$R" --check
check "check: prints the exact git add" said 'git add -- src/routes.ts'
git add -- src/routes.ts
expect "check: resolved and staged" 0 bash "$R" --check
check "check: prints commit, pre-push and an explicit push" bash -c "grep -q 'git commit --no-edit' /tmp/pp-test-out.$$ && grep -q 'pre-push.sh origin/develop' /tmp/pp-test-out.$$ && grep -q 'git push origin feature/x' /tmp/pp-test-out.$$"
check "check: drafts the reviewer message for an approved PR" said 'Message for the reviewer'
check "the script never commits, pushes or marks Ready" bash -c "git rev-parse -q --verify MERGE_HEAD >/dev/null && [ \"\$(git rev-parse origin/feature/x)\" = '$pushed' ] && ! grep -qE '^pr ready 612\$' '$work/gh.log'"
expect "the printed steps commit and push" 0 commit_and_push
check "origin has the two-parent merge" bash -c '[ "$(git rev-list --parents -n1 origin/feature/x | wc -w | tr -d " ")" = 3 ] && git merge-base --is-ancestor origin/develop origin/feature/x'
expect "start again: already up to date (exit 3)" 3 bash "$R"

# --- a draft PR is not touched; staged markers are refused
routes staged; pr_json true ""
expect "start on a draft PR" 4 bash "$R"
check "a draft PR is not touched" bash -c "! grep -q -- '--undo' '$work/gh.log'"
git add src/routes.ts
expect "check: refuses markers that were staged" 1 bash "$R" --check

# --- lockfile cases
routes lockonly; pr_json true ""; resolve_routes; git commit -qam "same routes"; git push -q origin feature/x
git switch -q develop; resolve_routes; git commit -qam "same routes"; git push -q origin develop; git switch -q feature/x
expect "lockfile-only conflict: nothing to decide (exit 0)" 0 bash "$R"
expect "lockfile-only: check passes" 0 bash "$R" --check

routes pnpmfail; pr_json true ""
mv "$bin/pnpm" "$bin/pnpm.real"; printf '#!/bin/sh\nexit 1\n' > "$bin/pnpm"; chmod +x "$bin/pnpm"
expect "pnpm fails at start: blocked" 1 bash "$R"
mv "$bin/pnpm.real" "$bin/pnpm"; resolve_routes; git add -- src/routes.ts
expect "check rebuilds the lockfile with pnpm" 0 bash "$R" --check
check "the staged lockfile was rebuilt" bash -c 'git show :pnpm-lock.yaml | grep -q "rebuilt from"'

plain bothjson; printf '{\n  "dependencies": {\n  }\n}\n' > package.json; printf 'lock: 0\n' > pnpm-lock.yaml; git add .; git commit -qm init; git push -q origin develop
diverge "printf '{\n  \"dependencies\": {\n    \"dep-a\": \"1\"\n  }\n}\n' > package.json; echo 'lock: a' > pnpm-lock.yaml" \
        "printf '{\n  \"dependencies\": {\n    \"dep-b\": \"1\"\n  }\n}\n' > package.json; echo 'lock: b' > pnpm-lock.yaml"; pr_json true ""
expect "package.json and lockfile both conflict" 4 bash "$R"
check "the lockfile is not listed as a file to edit" bash -c "! grep -q '== pnpm-lock.yaml' /tmp/pp-test-out.$$"
expect "check: package.json first" 1 bash "$R" --check
git checkout -q --theirs pnpm-lock.yaml
printf '{\n  "dependencies": {\n    "dep-a": "1",\n    "dep-b": "1"\n  }\n}\n' > package.json; git add -- package.json pnpm-lock.yaml
expect "check after taking a lockfile side" 0 bash "$R" --check
check "the lockfile was rebuilt anyway, with both deps" bash -c 'git show :pnpm-lock.yaml | grep -q dep-a && git show :pnpm-lock.yaml | grep -q dep-b'

plain mono; mkdir -p apps/web tools/cli; printf '{\n  "name": "web"\n}\n' > apps/web/package.json; printf '{}\n' > package.json
printf 'lock: 0\n' > pnpm-lock.yaml; printf 'lock: 0\n' > tools/cli/pnpm-lock.yaml; printf '{}\n' > tools/cli/package.json; echo a > r.ts
git add .; git commit -qm init; git push -q origin develop
diverge "printf '{\n  \"name\": \"web-ours\"\n}\n' > apps/web/package.json; echo 'lock: o' > pnpm-lock.yaml; echo 'lock: o' > tools/cli/pnpm-lock.yaml; echo o > r.ts" \
        "printf '{\n  \"name\": \"web-theirs\"\n}\n' > apps/web/package.json; echo 'lock: t' > pnpm-lock.yaml; echo 'lock: t' > tools/cli/pnpm-lock.yaml; echo t > r.ts"; pr_json true ""
expect "monorepo: start lists the code conflict" 4 bash "$R"
check "monorepo: root lockfile waits for apps/web/package.json" said 'apps/web/package.json is resolved'
check "monorepo: nested lockfile rebuilt in its own folder" bash -c 'git show :tools/cli/pnpm-lock.yaml | grep -q "rebuilt from" && ! git diff --name-only --diff-filter=U | grep -qx tools/cli/pnpm-lock.yaml'
check "monorepo: r.ts listed, lockfiles not" bash -c "grep -q '== r.ts' /tmp/pp-test-out.$$ && ! grep -q '== .*pnpm-lock.yaml' /tmp/pp-test-out.$$"
git merge --abort

plain lockgone; printf 'lock: 0\n' > pnpm-lock.yaml; echo a > a; git add .; git commit -qm init; git push -q origin develop
diverge "echo 'lock: ours' > pnpm-lock.yaml" "git rm -q pnpm-lock.yaml"; pr_json true ""
expect "lockfile deleted on the base: a person decides" 4 bash "$R"
check "says changed here, deleted on the base" said 'changed here, deleted on the base'
check "says never edit the lockfile by hand" said 'never edit it by hand'
git rm -q pnpm-lock.yaml
expect "after the person's choice, check passes" 0 bash "$R" --check
git merge --abort

plain lockmine; printf 'lock: 0\n' > pnpm-lock.yaml; echo a > a; git add .; git commit -qm init; git push -q origin develop
diverge "git rm -q pnpm-lock.yaml" "echo 'lock: theirs' > pnpm-lock.yaml"; pr_json true ""
expect "lockfile deleted on our side: not rebuilt, a person decides" 4 bash "$R"
check "says deleted here, changed on the base" said 'deleted here, changed on the base'
git merge --abort

# --- conflicts with no text to merge
plain nomarkers; echo a > a.txt; printf '\000one' > logo.bin; git add .; git commit -qm init; git push -q origin develop
diverge "echo b > a.txt; printf '\000two' > logo.bin" "git rm -q a.txt; printf '\000three' > logo.bin"; pr_json true ""
expect "binary and deleted-file conflicts need a person" 4 bash "$R"
check "names the binary conflict" said 'binary file changed on both sides'
check "names the deleted-file conflict" said 'changed here, deleted on the base'
expect "check does not call them resolved" 1 bash "$R" --check
check "says to check the person chose" said 'check that'
git merge --abort

plain kinds; echo a > a; git add .; git commit -qm init; git push -q origin develop
diverge "echo ours > new.txt; ln -s ours link" "echo theirs > new.txt; ln -s theirs link"; pr_json true ""
expect "both-added text and symlink conflicts" 4 bash "$R"
check "the both-added text file shows its conflict" bash -c "grep -A6 '== new.txt' /tmp/pp-test-out.$$ | grep -q '^-- conflict:'"
check "the symlink is named and left to the person" said 'symlink changed on both sides'
git merge --abort

# --- marker detection
conflict accent café.md
expect "start lists café.md" 4 bash "$R"; git add -- café.md
expect "markers in café.md are caught" 1 bash "$R" --check
check "names café.md" said 'café.md'
git merge --abort

conflict colon ./:notes.txt
bash "$R" >/dev/null 2>&1; git add -- ./:notes.txt
expect "markers in ':notes.txt' are caught" 1 bash "$R" --check
git merge --abort

plain msize; echo '*.md conflict-marker-size=10' > .gitattributes; echo a > doc.md; git add .; git commit -qm init; git push -q origin develop
diverge "echo ours > doc.md" "echo theirs > doc.md"; pr_json true ""
bash "$R" >/dev/null 2>&1; git add -- doc.md
expect "10-character markers are caught" 1 bash "$R" --check
git merge --abort

plain big; { echo base; seq 1 200000; } > big.txt; git add .; git commit -qm init; git push -q origin develop
diverge "sed -i.bak '1s/.*/OURS/' big.txt; rm big.txt.bak" "sed -i.bak '1s/.*/THEIRS/' big.txt; rm big.txt.bak"; pr_json true ""
bash "$R" >/dev/null 2>&1; git add -- big.txt
expect "markers near the top of a 1 MB file are caught" 1 bash "$R" --check
git merge --abort

routes newfile; pr_json true ""
bash "$R" >/dev/null 2>&1; resolve_routes; printf '<<<<<<< HEAD\nnote\n>>>>>>> x\n' > notes.md; git add -- src/routes.ts notes.md
expect "a new file with markers added during the resolution is caught" 1 bash "$R" --check
check "names notes.md" said 'notes.md'
git merge --abort

plain example; printf 'Example:\n<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> branch\nend\n' > docs.md; git add .; git commit -qm init; git push -q origin develop
diverge "sed -i.bak 's/^end$/end ours/' docs.md; rm docs.md.bak" "sed -i.bak 's/^end$/end theirs/' docs.md; rm docs.md.bak"; pr_json true ""
bash "$R" >/dev/null 2>&1
printf 'Example:\n<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> branch\nend ours and theirs\n' > docs.md; git add -- docs.md
expect "example markers already in a parent do not block" 0 bash "$R" --check
git merge --abort

routes unreadable; pr_json true ""
bash "$R" >/dev/null 2>&1; resolve_routes; git add -- src/routes.ts
obj=$(git rev-parse :src/routes.ts); objf=".git/objects/${obj:0:2}/${obj:2}"; chmod 000 "$objf"
expect "fail closed: an unreadable staged file blocks" 1 bash "$R" --check
chmod 644 "$objf"; git merge --abort

# --- merges the script did not start, and other bases
routes byhand; pr_json true ""
git merge -q origin/develop >/dev/null 2>&1; git add -- src/routes.ts pnpm-lock.yaml
expect "check refuses a merge started by hand" 2 bash "$R" --check
check "says to abort it and run the script" said 'git merge --abort'
expect "start refuses while that merge is in progress" 2 bash "$R"
git merge --abort

plain basecli; printf 'lock: 0\n' > pnpm-lock.yaml; printf '{}\n' > package.json; git add .; git commit -qm init; git push -q origin develop; git push -q origin develop:main
git switch -qc feature/x; echo 'lock: ours' > pnpm-lock.yaml; git commit -qam o; git push -q -u origin feature/x
git switch -q main; echo 'lock: main' > pnpm-lock.yaml; git commit -qam m; git push -q origin main
git switch -q develop; echo 'lock: DEVELOP-ONLY' > pnpm-lock.yaml; git commit -qam d; git push -q origin develop; git switch -q feature/x; pr_json true ""
expect "start --base=main (= form)" 0 bash "$R" --base=main
check "merged main, lockfile rebuilt from main" bash -c "grep -q 'origin/main' /tmp/pp-test-out.$$ && [ \"\$(git rev-parse MERGE_HEAD)\" = \"\$(git rev-parse origin/main)\" ]"
expect "check uses the recorded base" 0 bash "$R" --check
check "check names pre-push against origin/main" said 'pre-push.sh origin/main'
git merge --abort

# --- gh
routes gherr; mv "$bin/gh" "$bin/gh.good"
printf '#!/bin/sh\necho "HTTP 401: Bad credentials" >&2; exit 1\n' > "$bin/gh"; chmod +x "$bin/gh"
expect "a gh error stops the start" 2 bash "$R"
check "no merge was started" bash -c '! git rev-parse -q --verify MERGE_HEAD >/dev/null'
mv "$bin/gh.good" "$bin/gh"
pr_json false ""; : > "$work/gh.warn"
expect "a gh warning on stderr does not break the start" 4 bash "$R"
check "... and the Ready PR still goes back to draft" grep -qx 'pr ready 612 --undo' "$work/gh.log"
rm -f "$work/gh.warn"; git merge --abort
no_pr
expect "no PR at all is fine" 4 bash "$R"
git merge --abort

# --- a merge git refuses is not reported as clean
plain refused; echo a > a; git add .; git commit -qm init; git push -q origin develop
diverge "echo b > b" "echo theirs > c.txt"; pr_json true ""
echo mine > c.txt
expect "a refused merge exits 2" 2 bash "$R"
check "says git refused it" said 'git refused the merge'
rm c.txt

# --- check never reads stdin
routes nostdin; pr_json true ""
bash "$R" >/dev/null 2>&1; resolve_routes; git add -- src/routes.ts
expect "check with stdin open does not hang or read it" 0 bash -c "(sleep 5; echo '<<<<<<< x') | timeout 4 bash '$R' --check"
git merge --abort

# --- file names with spaces are quoted in the hint
conflict spaces "my file.txt"
bash "$R" >/dev/null 2>&1; echo resolved > "my file.txt"
expect "unstaged resolved file" 1 bash "$R" --check
check "the hint quotes the name" grep -qF 'git add -- my\ file.txt' /tmp/pp-test-out.$$
git merge --abort

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
