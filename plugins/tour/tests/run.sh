#!/usr/bin/env bash
# tour tests: bash plugins/tour/tests/run.sh (needs git, jq; the server cases also need node >= 18 and curl). gh/glab are stubs, origin is a local bare repo. Exits non-zero on the first failure.
set -euo pipefail
bin="$(cd "$(dirname "$0")/../bin" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null
export CLAUDE_PLUGIN_DATA="$tmp/data" STUB_LOG="$tmp/stub.log" FIX="$tmp/fix"
mkdir -p "$FIX" "$tmp/stubs"; : > "$STUB_LOG"
fail() { echo "FAIL: $*" >&2; exit 1; }
eq() { [ "$1" = "$2" ] || fail "$3: got [$1], want [$2]"; }

# gh/glab stubs: log the call, answer from $FIX
cat > "$tmp/stubs/gh" <<'STUB'
#!/usr/bin/env bash
echo "gh $*" >> "$STUB_LOG"
case "$*" in
    "pr view"*"closingIssuesReferences"*) cat "$FIX/gh-pr.json" ;;   # real gh returns only number/url per closing issue
    "api -X POST repos/"*"/pulls/"*"/comments"*)   # tour-post (#43)
        if [ -e "$FIX/post-fail" ]; then echo '{"message": "Validation Failed"}'; echo "gh: Unprocessable Entity (HTTP 422)" >&2; exit 1; fi
        [ -e "$FIX/slow" ] && sleep 1
        echo '{"id": 555, "html_url": "https://github.com/acme/app/pull/7#discussion_r555"}' ;;
    "issue view 3 "*"--json title,body"*) echo '{"title": "The ticket", "body": "ticket text"}' ;;
    "issue view"*) echo '{}' ;; *) echo "unexpected gh $*" >&2; exit 1 ;; esac
STUB
cat > "$tmp/stubs/glab" <<'STUB'
#!/usr/bin/env bash
echo "glab[$GITLAB_HOST] $*" >> "$STUB_LOG"
case "$*" in
    api*/closes_issues) cat "$FIX/glab-issues.json" ;;
    "api -X POST"*discussions*) [ -e "$FIX/post-fail" ] && { echo "glab: 400 Bad request: position is invalid" >&2; exit 1; }; cat > "$FIX/glab-payload.json"; cat "$FIX/glab-disc.json" ;;   # tour-post (#43)
    api*/merge_requests/*) cat "$FIX/glab-mr.json" ;;
    *) echo "unexpected glab $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$tmp/stubs/gh" "$tmp/stubs/glab"
export PATH="$tmp/stubs:$PATH"

# remote_repo <dir> <remote url>: clone-like repo whose origin is a local bare repo reached through insteadOf; main pushed
remote_repo() {
    git init -q --bare "$1.git"; git init -q -b main "$1"
    (cd "$1" && git remote add origin "$2" && git config "url.$1.git.insteadOf" "$2")
}
# pr <dir> <ref> <branch> <message>: commit what is staged on <branch> from main, push it as <ref>, back to main
pr() {
    (cd "$1" && git checkout -q -b "$3" main && git add -A && git commit -qm "$4" &&
     git push -q origin "HEAD:$2" && git rev-parse HEAD && git checkout -q main)
}

# --- fixtures: GitHub repo, PR #7 touching every kind of hunk (#39)
gh_url='git@github.com:acme/app.git'
remote_repo "$tmp/gh" "$gh_url"
cd "$tmp/gh"
mkdir src
printf 'one\ntwo\nthree\nfour\nfive\nsix\n' > src/app.txt
printf 'gone\n' > src/old.txt
printf 'moved a\nmoved b\nmoved c\nmoved d\n' > src/before.txt
printf 'edit a\nedit b\nedit c\nedit d\nedit e\n' > src/edited.txt
printf '\0\1\2' > logo.bin
printf '#!/bin/sh\n' > run.sh
git add -A && git commit -qm base && git push -q origin main
printf 'one\nTWO\nthree\nfour\nfive\nSIX\nseven\n' > src/app.txt           # two hunks
git rm -q src/old.txt                                                      # deletion
git mv src/before.txt src/after.txt                                        # pure rename
git mv src/edited.txt src/edited2.txt; printf 'edit a\nEDIT b\nedit c\nedit d\nedit e\n' > src/edited2.txt  # rename + edit
printf '\0\1\2\3' > logo.bin                                               # binary change
chmod +x run.sh                                                            # mode only
printf 'new\n' > src/new.txt; : > src/empty.txt                            # add, empty add
gh_head="$(pr "$tmp/gh" refs/pull/7/head feature/seven 'seven')"
jq -n --arg sha "$gh_head" '{number: 7, title: "Seven", body: "Closes #3", url: "https://github.com/acme/app/pull/7",
    baseRefName: "main", headRefName: "feature/seven", headRefOid: $sha,
    closingIssuesReferences: [{number: 3, url: "https://github.com/acme/app/issues/3"}]}' > "$FIX/gh-pr.json"
git -C "$tmp/gh" status --short | grep -q . && fail "gh fixture repo left dirty"

# --- tour-fetch, GitHub: metadata, worktree, atoms (#39)
cd "$tmp/gh"
out="$("$bin/tour-fetch" 7)"
eq "$(jq -r '[.platform, .host, .project, .iid, .title, .cached] | join(" ")' <<<"$out")" "github github.com acme/app 7 Seven false" "gh metadata"
eq "$(jq -r '[.target_branch, .source_branch, .head_sha] | join(" ")' <<<"$out")" "main feature/seven $gh_head" "gh refs"
eq "$(jq -r '.ticket | [.id, .summary, .text] | join("|")' <<<"$out")" "#3|The ticket|ticket text" "gh linked ticket"
dir="$(jq -r .dir <<<"$out")"; wt="$(jq -r .worktree <<<"$out")"
eq "$dir" "$tmp/data/github.com/acme/app/7/$gh_head" "data dir outside the repo"
eq "$(git -C "$wt" rev-parse HEAD)" "$gh_head" "worktree at the head SHA"
eq "$(git -C "$wt" symbolic-ref -q HEAD || echo detached)" detached "worktree is detached"
eq "$(jq -r .base_sha <<<"$out")" "$(git rev-parse main)" "merge-base"
eq "$(git -C "$tmp/gh" status --short | grep -v '^??' | wc -l | tr -d ' ')" 0 "repo working tree stays clean"
[ -f "$dir/meta.json" ] && [ -f "$dir/atoms.json" ] || fail "meta.json / atoms.json missing"
grep -q 'gh pr view 7 --repo github.com/acme/app' "$STUB_LOG" || fail "gh was not called as expected"
# URL form resolves to the same data dir
eq "$("$bin/tour-fetch" https://github.com/acme/app/pull/7 | jq -r .dir)" "$dir" "gh URL form"

# --- atoms: every hunk and every file (#39)
atoms="$dir/atoms.json"
eq "$(jq -r '[.[] | select(.file == "src/app.txt")] | map(.kind) | join(",")' "$atoms")" "hunk,hunk" "two hunks in app.txt"
eq "$(jq -r '[.[] | select(.file == "src/app.txt")][0] | [.old.start, .old.count, .new.start, .new.count, .lines[0], .lines[1]] | join("|")' "$atoms")" '2|1|2|1|-two|+TWO' "hunk ranges and lines"
eq "$(jq -r '[.[] | select(.file == "src/app.txt")][1] | [.old.start, .old.count, .new.start, .new.count] | join("|")' "$atoms")" '6|1|6|2' "second hunk ranges"
eq "$(jq -r '.[] | select(.file == "src/old.txt") | [.kind, .status, .old.start, .old.count, .new.start, .new.count] | join("|")' "$atoms")" 'hunk|deleted|1|1|0|0' "deletion"
eq "$(jq -r '.[] | select(.file == "src/after.txt") | [.kind, .status, .old_file] | join("|")' "$atoms")" 'rename|renamed|src/before.txt' "pure rename"
eq "$(jq -r '.[] | select(.file == "src/edited2.txt") | [.kind, .status, .old_file] | join("|")' "$atoms")" 'hunk|renamed|src/edited.txt' "rename with edit"
eq "$(jq -r '.[] | select(.file == "logo.bin") | .kind' "$atoms")" binary "binary change"
eq "$(jq -r '.[] | select(.file == "run.sh") | [.kind, .mode.old, .mode.new] | join("|")' "$atoms")" 'mode|100644|100755' "mode-only change"
eq "$(jq -r '.[] | select(.file == "src/new.txt") | [.kind, .status] | join("|")' "$atoms")" 'hunk|added' "added file"
eq "$(jq -r '.[] | select(.file == "src/empty.txt") | [.kind, .status] | join("|")' "$atoms")" 'add|added' "empty added file"
eq "$(jq -r '[.[].id] | join(",")' "$atoms" | cut -d, -f1-3)" "a1,a2,a3" "ids start at a1"
eq "$(jq '[.[] | select(.kind == "hunk")] | length' "$atoms")" "$(grep -c '^@@ ' "$dir/diff.patch")" "every hunk has an atom"
eq "$(jq -r '[.[].id] | unique | length' "$atoms")" "$(jq length "$atoms")" "ids unique"
eq "$(jq -r '[.[].file] | unique | sort | join(",")' "$atoms")" "$(git -C "$tmp/gh" diff --name-only -M main "$gh_head" | sort | tr '\n' ',' | sed 's/,$//')" "atoms cover every changed file"
# stable: a second run into a fresh data dir gives the same atoms
CLAUDE_PLUGIN_DATA="$tmp/data2" "$bin/tour-fetch" 7 >/dev/null
cmp -s "$atoms" "$tmp/data2/github.com/acme/app/7/$gh_head/atoms.json" || fail "atoms differ between runs"

# re-running into the same data dir reuses the worktree and rewrites identical atoms
"$bin/tour-fetch" 7 >/dev/null
cmp -s "$atoms" "$tmp/data2/github.com/acme/app/7/$gh_head/atoms.json" || fail "atoms differ on a re-run in the same dir"
eq "$(git -C "$wt" rev-parse HEAD)" "$gh_head" "worktree reused"

# --- cache hit: reported without fetching again (#39)
echo '{}' > "$dir/tour.json"
git -C "$tmp/gh.git" update-ref -d refs/pull/7/head    # a re-fetch of the head ref would now fail
rm -rf "$wt"; git -C "$tmp/gh" worktree prune
cout="$("$bin/tour-fetch" 7 --no-open)"
eq "$(jq -r '[.cached, .no_open, .head_sha] | join(" ")' <<<"$cout")" "true true $gh_head" "cache hit reported"
[ ! -d "$wt" ] || fail "cache hit must not recreate the worktree"
rm "$dir/tour.json"

# --- tour-fetch, GitLab with a subgroup and a self-hosted host (#39)
gl_url='git@gitlab.example.com:group/sub/proj.git'
remote_repo "$tmp/gl" "$gl_url"
cd "$tmp/gl"
printf 'a\nb\n' > f.txt; git add -A && git commit -qm base && git push -q origin main
printf 'a\nB\n' > f.txt
gl_head="$(pr "$tmp/gl" refs/merge-requests/12/head fix/twelve 'twelve')"
jq -n --arg sha "$gl_head" '{iid: 12, title: "Twelve", description: "desc", web_url: "https://gitlab.example.com/group/sub/proj/-/merge_requests/12",
    target_branch: "main", source_branch: "fix/twelve", sha: $sha, diff_refs: {base_sha: "basesha", head_sha: $sha, start_sha: "startsha"}}' > "$FIX/glab-mr.json"
echo '[{"iid": 5, "title": "GL ticket", "description": "gl text"}]' > "$FIX/glab-issues.json"
out="$("$bin/tour-fetch" 12)"
eq "$(jq -r '[.platform, .host, .project, .iid, .title, .description, .cached] | join("|")' <<<"$out")" "gitlab|gitlab.example.com|group/sub/proj|12|Twelve|desc|false" "gl metadata"
eq "$(jq -r '.ticket | [.id, .summary, .text] | join("|")' <<<"$out")" "#5|GL ticket|gl text" "gl linked ticket"
eq "$(jq -r .dir <<<"$out")" "$tmp/data/gitlab.example.com/group/sub/proj/12/$gl_head" "gl data dir"
eq "$(jq -r '.[0] | [.id, .file, .kind, .lines[0], .lines[1]] | join("|")' "$(jq -r .atoms_file <<<"$out")")" 'a1|f.txt|hunk|-b|+B' "gl atoms"
grep -q 'glab\[gitlab.example.com\] api projects/group%2Fsub%2Fproj/merge_requests/12$' "$STUB_LOG" || fail "glab not called as expected"
eq "$("$bin/tour-fetch" https://gitlab.example.com/group/sub/proj/-/merge_requests/12 | jq -r .dir)" "$(jq -r .dir <<<"$out")" "gl URL form"

# --- tour-drift (#39)
# drift_repo <dir> <remote url>: a project with a manifest, a lockfile-less layout and some config
drift_repo() {
    remote_repo "$1" "$2"
    (cd "$1" && mkdir -p src config db/migrations &&
     printf '{"name": "x", "dependencies": {"left-pad": "^1.0.0"}}\n' > package.json &&
     printf 'package main\n' > src/main.go &&
     printf 'app:\n  name: x\n  debug: false\n' > config/app.yml &&
     printf 'A=1\nB=2\n' > .env.example &&
     printf 'create table a ();\n' > db/migrations/001_a.sql &&
     git add -A && git commit -qm base && git push -q origin main)
}
drift_repo "$tmp/dr" 'git@github.com:acme/drift.git'
cd "$tmp/dr"
printf '{"name": "x", "dependencies": {"left-pad": "^2.0.0", "brick-math": "^0.12"}}\n' > package.json     # bump + new
mkdir -p newmod db/migrations; printf 'package newmod\n' > newmod/x.go
printf 'create table b ();\n' > db/migrations/002_b.sql
printf 'app:\n  name: x\n  debug: true\n  timeout: 5\n' > config/app.yml
printf 'A=1\nC=3\n' > .env.example
dr_head="$(pr "$tmp/dr" refs/pull/1/head feature/drift 'drift')"
jq -n --arg sha "$dr_head" '{number: 1, title: "Drift", body: "", url: "u", baseRefName: "main", headRefName: "feature/drift", headRefOid: $sha, closingIssuesReferences: []}' > "$FIX/gh-pr.json"
dd="$("$bin/tour-fetch" 1 | jq -r .dir)"
drift="$("$bin/tour-drift" "$dd")"
atom_of() { jq -r --arg f "$1" '[.[] | select(.file == $f) | .id] | join(",")' "$dd/atoms.json"; }
eq "$(jq -r '[.[] | select(.kind == "new_dependency")] | map(.detail) | join("|")' <<<"$drift")" "brick-math ^0.12" "new dependency (a bump is not new)"
eq "$(jq -r '.[] | select(.kind == "new_dependency") | .atoms | join(",")' <<<"$drift")" "$(atom_of package.json)" "new dependency atoms"
eq "$(jq -r '[.[] | select(.kind == "new_migration")] | map(.detail) | join("|")' <<<"$drift")" "db/migrations/002_b.sql" "new migration"
eq "$(jq -r '.[] | select(.kind == "new_migration") | .atoms | join(",")' <<<"$drift")" "$(atom_of db/migrations/002_b.sql)" "migration atoms"
eq "$(jq -r '[.[] | select(.kind == "changed_config")] | map(.detail) | sort | join("|")' <<<"$drift")" "$(printf '%s|%s' '.env.example: -B +C' 'config/app.yml: ~debug +timeout')" "changed config and env keys"
eq "$(jq -r '[.[] | select(.kind == "new_top_level_dir")] | map(.detail) | join("|")' <<<"$drift")" "newmod/" "new top-level dir (db/ existed)"
eq "$(jq -r '.[] | select(.kind == "new_top_level_dir") | .atoms | join(",")' <<<"$drift")" "$(atom_of newmod/x.go)" "top-level dir atoms"

# a changed route file is flagged with the route paths
git -C "$tmp/dr" checkout -q main
mkdir -p "$tmp/dr/routes"; printf "Route::get('/users', fn() => 1);\n" > "$tmp/dr/routes/web.php"
git -C "$tmp/dr" add -A && git -C "$tmp/dr" commit -qm routes && git -C "$tmp/dr" push -q origin main
printf "Route::get('/users', fn() => 1);\nRoute::post('/orders', fn() => 2);\n" > "$tmp/dr/routes/web.php"
r_head="$(pr "$tmp/dr" refs/pull/2/head feature/route 'route')"
jq -n --arg sha "$r_head" '{number: 2, title: "R", body: "", url: "u", baseRefName: "main", headRefName: "feature/route", headRefOid: $sha, closingIssuesReferences: []}' > "$FIX/gh-pr.json"
rd="$("$bin/tour-fetch" 2 | jq -r .dir)"
eq "$("$bin/tour-drift" "$rd" | jq -r '.[] | [.kind, .detail] | join("|")')" "changed_config|routes/web.php: +/orders" "route change"

# new dependencies in go.mod and requirements.txt (lockfile/manifest kinds beyond package.json)
printf 'module x\n\ngo 1.21\n\nrequire (\n\tgithub.com/a/b v1.0.0\n)\n' > "$tmp/dr/go.mod"
printf 'requests==2.0\n' > "$tmp/dr/requirements.txt"
git -C "$tmp/dr" add -A && git -C "$tmp/dr" commit -qm manifests && git -C "$tmp/dr" push -q origin main
printf 'module x\n\ngo 1.21\n\nrequire (\n\tgithub.com/a/b v1.1.0\n\tgithub.com/c/d v0.3.0\n)\n' > "$tmp/dr/go.mod"
printf 'requests==2.1\nflask>=3\n' > "$tmp/dr/requirements.txt"
m_head="$(pr "$tmp/dr" refs/pull/4/head feature/manifests 'manifests')"
jq -n --arg sha "$m_head" '{number: 4, title: "M", body: "", url: "u", baseRefName: "main", headRefName: "feature/manifests", headRefOid: $sha, closingIssuesReferences: []}' > "$FIX/gh-pr.json"
md="$("$bin/tour-fetch" 4 | jq -r .dir)"
eq "$("$bin/tour-drift" "$md" | jq -r '[.[] | select(.kind == "new_dependency") | .detail] | sort | join("|")')" "flask >=3|github.com/c/d v0.3.0" "go.mod and requirements.txt dependencies"

# a plain code change flags nothing
printf 'package main\n\nfunc main() {}\n' > "$tmp/dr/src/main.go"
mkdir -p "$tmp/dr/src/config"; printf 'package config\n' > "$tmp/dr/src/config/loader.go"    # code under config/ is not a config change
p_head="$(pr "$tmp/dr" refs/pull/3/head feature/plain 'plain')"
jq -n --arg sha "$p_head" '{number: 3, title: "P", body: "", url: "u", baseRefName: "main", headRefName: "feature/plain", headRefOid: $sha, closingIssuesReferences: []}' > "$FIX/gh-pr.json"
pd="$("$bin/tour-fetch" 3 | jq -r .dir)"
eq "$("$bin/tour-drift" "$pd" | jq -c .)" "[]" "plain code change flags nothing"

# --- #51 tour-fetch: C-quoted paths in diff headers and rename lines are unquoted
remote_repo "$tmp/qp" 'git@github.com:acme/quoted.git'
cd "$tmp/qp"
q_quote='quo"te.txt'; q_tab="$(printf 'tab\there.txt')"; q_back='back\slash.txt'; q_ctl="$(printf 'ctl\001x.txt')"
q_nl="$(printf 'new\nline.txt')"; q_sp='sp ace"q.txt'
for f in "$q_quote" "$q_tab" "$q_back" "$q_ctl" "$q_nl" "$q_sp" 'my file.txt' 'héllo.txt' 'plain.txt' "$(printf 'ren\tfrom.txt')" 'old"name.txt'; do printf 'one\n' > "$f"; done
git add -A && git commit -qm base && git push -q origin main
for f in "$q_quote" "$q_tab" "$q_back" "$q_ctl" "$q_nl" "$q_sp" 'my file.txt' 'héllo.txt'; do printf 'two\n' > "$f"; done
git mv "$(printf 'ren\tfrom.txt')" 'ren"to.txt'; git mv 'old"name.txt' 'plain-new.txt'; git mv 'plain.txt' "$(printf 'to\ttab.txt')"
q_head="$(pr "$tmp/qp" refs/pull/9/head feature/quoted 'quoted')"
jq -n --arg sha "$q_head" '{number: 9, title: "Q", body: "", url: "u", baseRefName: "main", headRefName: "feature/quoted", headRefOid: $sha, closingIssuesReferences: []}' > "$FIX/gh-pr.json"
qa="$("$bin/tour-fetch" 9 | jq -r .atoms_file)"
for f in "$q_quote" "$q_tab" "$q_back" "$q_ctl" "$q_nl" "$q_sp" 'my file.txt' 'héllo.txt'; do
    eq "$(jq -r --arg f "$f" '[.[] | select(.file == $f and .old_file == $f and .kind == "hunk")] | length' "$qa")" 1 "atom with the real path for [$f]"
done
# identical content, so git pairs the renames by name order: both sides quoted, quoted → plain, plain → quoted
eq "$(jq -r --arg f "$(printf 'to\ttab.txt')" --arg o "$(printf 'ren\tfrom.txt')" '[.[] | select(.file == $f and .old_file == $o and .kind == "rename" and .status == "renamed")] | length' "$qa")" 1 "quoted rename, both sides quoted"
eq "$(jq -r '[.[] | select(.file == "plain-new.txt" and .old_file == "old\"name.txt" and .kind == "rename")] | length' "$qa")" 1 "rename from a quoted path to a plain one"
eq "$(jq -r '[.[] | select(.file == "ren\"to.txt" and .old_file == "plain.txt" and .kind == "rename")] | length' "$qa")" 1 "rename from a plain path to a quoted one"
eq "$(jq -r '[.[] | select((.file | startswith("\"")) or (.old_file | startswith("\"")))] | length' "$qa")" 0 "no path keeps its quotes"
cd "$tmp/gh"


# --- #40/#42 tour-validate and tour-serve
root="$(dirname "$bin")"; fx="$root/fixtures"; cases=0

# ok <name> <tour.json>: tour-validate exits 0 with no output
ok() {
    local rc=0 out; out=$("$bin/tour-validate" "$2" "$fx/atoms.json" 2>&1) || rc=$?
    eq "$rc" 0 "$1 exit ($out)"; eq "$out" "" "$1 output"; cases=$((cases + 1))
}
# bad <name> <fixture> <jq mutation> <expected error line, exact>: exit 1 and that line is printed
bad() {
    local rc=0 out
    jq "$3" "$fx/$2" > "$tmp/t.json"
    out=$("$bin/tour-validate" "$tmp/t.json" "$fx/atoms.json" 2>&1) || rc=$?
    eq "$rc" 1 "$1 exit ($out)"
    printf '%s\n' "$out" | grep -Fxq -- "$4" || fail "$1: missing line [$4] in:
$out"
    cases=$((cases + 1))
}

# --- #40 tour-validate: passing fixtures (all layers, base only)
ok "full fixture" "$fx/tour.full.json"
ok "base fixture" "$fx/tour.base.json"

# --- #40 coverage: dropped, double-assigned and unknown atoms
bad "dropped atom (mechanical)" tour.full.json 'del(.mechanical.atoms[0])' \
    '$: atom "a9" is not assigned to any block or to mechanical'
bad "dropped atom (block)" tour.full.json '.chapters[3].blocks[0].atoms = []' \
    '$.chapters[3].blocks[0].atoms: must not be empty'
bad "dropped atom (block, coverage)" tour.full.json 'del(.chapters[3])' \
    '$: atom "a7" is not assigned to any block or to mechanical'
bad "double-assigned atom" tour.full.json '.chapters[1].blocks[0].atoms += ["a1"]' \
    '$.chapters[1].blocks[0].atoms[1]: atom "a1" is assigned twice (first at $.chapters[0].blocks[0].atoms[0])'
bad "atom in block and mechanical" tour.base.json '.mechanical.atoms += ["a1"]' \
    '$.mechanical.atoms[2]: atom "a1" is assigned twice (first at $.chapters[0].blocks[0].atoms[0])'
bad "unknown atom id" tour.full.json '.chapters[0].blocks[0].atoms += ["zz"]' \
    '$.chapters[0].blocks[0].atoms[1]: unknown atom id "zz" (not in atoms.json)'
bad "unknown atom id in drift" tour.full.json '.drift[0].atoms = ["q9"]' \
    '$.drift[0].atoms[0]: unknown atom id "q9" (not in atoms.json)'

# --- #40 enums
bad "bad risk enum" tour.full.json '.summary.risk = "huge"' \
    '$.summary.risk: invalid value "huge", expected one of low|medium|high'
bad "bad why_source enum" tour.full.json '.chapters[0].blocks[0].why_source = "guess"' \
    '$.chapters[0].blocks[0].why_source: invalid value "guess", expected one of ticket|mr|code|unclear'
bad "bad platform enum" tour.base.json '.mr.platform = "bitbucket"' \
    '$.mr.platform: invalid value "bitbucket", expected one of gitlab|github'
bad "bad layer enum" tour.base.json '.layers += ["magic"]' \
    '$.layers[1]: invalid value "magic", expected one of base|deep|active|arch|rules|drift'

# --- #40 required fields and shapes
bad "missing block field" tour.full.json 'del(.chapters[0].blocks[0].what)' \
    '$.chapters[0].blocks[0].what: required field missing'
bad "missing mr field" tour.base.json 'del(.mr.head_sha)' '$.mr.head_sha: required field missing'
bad "missing chapters" tour.base.json 'del(.chapters)' '$.chapters: required field missing'
bad "empty string" tour.base.json '.chapters[0].title = ""' '$.chapters[0].title: must be a non-empty string'
bad "wrong type" tour.base.json '.mr.iid = "88"' '$.mr.iid: must be a positive integer'
bad "layers without base" tour.full.json '.layers |= map(select(. != "base"))' '$.layers: must include "base"'
bad "duplicate chapter id" tour.full.json '.chapters[1].id = "c1"' '$.chapters: duplicate chapter id "c1"'

# --- #40 layer rules: a layer field without its layer, and a listed layer without its field
bad "intent without active" tour.base.json '.chapters[0].intent = "teaser"' \
    '$.chapters[0].intent: only valid when layer "active" is listed in layers'
bad "probes without active" tour.base.json '.chapters[0].probes = []' \
    '$.chapters[0].probes: only valid when layer "active" is listed in layers'
bad "graph without arch" tour.base.json '.graph = {"mermaid": "graph LR"}' \
    '$.graph: only valid when layer "arch" is listed in layers'
bad "drift without drift layer" tour.base.json '.drift = []' '$.drift: only valid when layer "drift" is listed in layers'
bad "callers without deep" tour.full.json '.layers |= map(select(. != "deep"))' \
    '$.chapters[0].blocks[0].impact[0].callers: only valid when layer "deep" is listed in layers'
bad "rules_flags without rules" tour.full.json '.layers |= map(select(. != "rules"))' \
    '$.chapters[0].blocks[1].rules_flags: only valid when layer "rules" is listed in layers'
bad "active without intent" tour.full.json 'del(.chapters[0].intent)' '$.chapters[0].intent: required field missing'
bad "arch without graph" tour.full.json 'del(.graph)' '$.graph: required field missing'

# --- #40 usage and unreadable input
rc=0; "$bin/tour-validate" "$fx/tour.full.json" >/dev/null 2>&1 || rc=$?; eq "$rc" 2 "usage exit"
printf '{' > "$tmp/broken.json"
rc=0; "$bin/tour-validate" "$tmp/broken.json" "$fx/atoms.json" >/dev/null 2>&1 || rc=$?; eq "$rc" 2 "invalid JSON exit"
rc=0; "$bin/tour-validate" "$tmp/missing.json" "$fx/atoms.json" >/dev/null 2>&1 || rc=$?; eq "$rc" 2 "missing file exit"
printf "null" > "$tmp/null.json"
rc=0; "$bin/tour-validate" "$tmp/null.json" "$fx/atoms.json" >/dev/null 2>&1 || rc=$?; eq "$rc" 1 "null JSON exit"
cases=$((cases + 4))

# --- #42 tour-serve / server.mjs (needs node >= 18 and curl)
data="$tmp/data"; mkdir -p "$data/worktree/app" "$tmp/outside"
cp "$fx/tour.full.json" "$data/tour.json"; cp "$fx/atoms.json" "$data/atoms.json"
printf 'line1\nline2\n' > "$data/worktree/app/a.txt"; echo SECRET > "$tmp/outside/secret.txt"
ln -s "$tmp/outside/secret.txt" "$data/worktree/app/link.txt"
"$bin/tour-serve" "$data" --no-open > "$tmp/serve.out" 2> "$tmp/serve.err" &
srv=$!; trap 'kill $srv 2>/dev/null || true; rm -rf "$tmp"' EXIT
for _ in $(seq 50); do grep -q '^http' "$tmp/serve.out" && break; sleep 0.1; done
url="$(head -1 "$tmp/serve.out")"
case "$url" in http://127.0.0.1:[0-9]*/\?token=[0-9a-f]*) ;; *) fail "serve url [$url] $(cat "$tmp/serve.err")" ;; esac
base="${url%%/\?*}"; tok="${url##*token=}"; cases=$((cases + 1))
code() { curl -s -o "$tmp/body" -w '%{http_code}' "$@"; }
H=(-H "X-Tour-Token: $tok")
eq "$(code "$base/")" 403 "no token: page rejected"
eq "$(code "$base/api/tour")" 403 "no token: api rejected"
eq "$(code "$base/api/tour" -H 'X-Tour-Token: nope')" 403 "wrong token rejected"
eq "$(code "$base/?token=nope")" 403 "wrong query token rejected"
eq "$(code "$base/?token=$tok")" 302 "query token redirects"
eq "$(curl -s -D - -o /dev/null "$base/?token=$tok" | grep -ci '^set-cookie: tour=')" 1 "token sets cookie"
jar="-b tour=$tok"
eq "$(code $jar "$base/")" 200 "cookie auth serves the page"
grep -q '<title>Tour</title>' "$tmp/body" || fail "index.html body"
eq "$(code "${H[@]}" "$base/app.js")" 200 "app.js served"
eq "$(code "${H[@]}" "$base/server/server.mjs")" 404 "non-ui file not served"
eq "$(code "${H[@]}" -H 'Host: evil.example' "$base/api/tour")" 403 "foreign Host rejected"
eq "$(code "${H[@]}" "$base/api/tour")" 200 "tour served"
eq "$(jq -r .mr.iid "$tmp/body")" 1234 "tour body"
eq "$(code "${H[@]}" "$base/api/atoms")" 200 "atoms served"
eq "$(jq '.atoms | length' "$tmp/body")" 10 "atoms body"
cases=$((cases + 11))

eq "$(code "${H[@]}" "$base/api/state")" 200 "state GET (none yet)"; eq "$(cat "$tmp/body")" '{}' "empty state"
eq "$(code "${H[@]}" -X PUT -d '{"understood":{"c1/0":true},"pos":{"chapter":"c1","block":0}}' "$base/api/state")" 200 "state PUT"
eq "$(code "${H[@]}" "$base/api/state")" 200 "state GET"; eq "$(jq -r '.understood["c1/0"]' "$tmp/body")" true "state persisted"
eq "$(jq -r '.pos.chapter' "$data/state.json")" c1 "state.json written beside tour.json"
# --- #44 active-review predictions live only in state.json, and the UI never sends them off the machine
eq "$(code "${H[@]}" -X PUT -d '{"predictions":{"c1":{"text":"ImportRequest rules","revealed":true}}}' "$base/api/state")" 200 "predictions PUT"
eq "$(jq -r '.predictions.c1.text' "$data/state.json")" "ImportRequest rules" "predictions persisted in state.json"
eq "$(grep -c 'fetch(' "$bin/../ui/app.js")" "$(grep 'fetch(' "$bin/../ui/app.js" | grep -vc "https\?://")" "every fetch in app.js is same-origin"
eq "$(grep -c "predictions" "$bin/../server/server.mjs")" 0 "server has no special handling that could forward predictions"
cases=$((cases + 4))
eq "$(code "${H[@]}" -X PUT -d '[1]' "$base/api/state")" 400 "state PUT rejects non-object"
eq "$(code "${H[@]}" -X PUT -d 'not json' "$base/api/state")" 400 "state PUT rejects invalid JSON"
eq "$(code -X PUT -d '{}' "$base/api/state")" 403 "state PUT needs the token"
cases=$((cases + 8))

eq "$(code "${H[@]}" "$base/api/file?path=app/a.txt")" 200 "file served"; eq "$(head -1 "$tmp/body")" line1 "file body"
eq "$(code "${H[@]}" "$base/api/file?path=../outside/secret.txt")" 404 "traversal rejected"
eq "$(code "${H[@]}" "$base/api/file?path=app/%2e%2e/%2e%2e/outside/secret.txt")" 404 "encoded traversal rejected"
eq "$(code "${H[@]}" "$base/api/file?path=$tmp/outside/secret.txt")" 404 "absolute path rejected"
eq "$(code "${H[@]}" "$base/api/file?path=app/link.txt")" 404 "symlink out of the worktree rejected"
eq "$(code "${H[@]}" "$base/api/file?path=app")" 404 "directory rejected"
eq "$(code "${H[@]}" "$base/api/file")" 404 "missing path rejected"
cases=$((cases + 8))
rc=0; "$bin/tour-serve" "$tmp/nodir" >/dev/null 2>&1 || rc=$?; eq "$rc" 1 "serve without tour.json exits 1"
cases=$((cases + 1))
kill "$srv" 2>/dev/null || true

# --- #43 tour-post: inline comment payloads for GitHub and GitLab (stubbed gh/glab)
mkpd() { # <dir> <mr json>: a data dir whose tour.json carries only the mr
    mkdir -p "$1"; jq -n --argjson mr "$2" '{version: 1, mr: $mr}' > "$1/tour.json"
}
mkpd "$tmp/pd-gh" "$(jq -n --arg s "$gh_head" '{platform: "github", project: "acme/app", iid: 7, url: "https://github.com/acme/app/pull/7", head_sha: $s}')"
mkpd "$tmp/pd-gl" "$(jq -n --arg s "$gl_head" '{platform: "gitlab", project: "group/sub/proj", iid: 12, url: "https://gitlab.example.com/group/sub/proj/-/merge_requests/12", head_sha: $s}')"
: > "$STUB_LOG"
ghcall() { printf 'hello\n' | "$bin/tour-post" "$tmp/pd-gh" "$@"; }
last() { grep '^gh api -X POST' "$STUB_LOG" | tail -1; }
eq "$(ghcall --path src/app.txt --new-line 7 | jq -c .)" '{"id":555,"url":"https://github.com/acme/app/pull/7#discussion_r555","inline":true}' "gh post result"
case "$(last)" in "gh api -X POST repos/acme/app/pulls/7/comments -f body=hello -f commit_id=$gh_head -f path=src/app.txt -F line=7 -f side=RIGHT") ;; *) fail "gh added line: $(last)" ;; esac
ghcall --path src/app.txt --old-line 6 >/dev/null
case "$(last)" in *"-f path=src/app.txt -F line=6 -f side=LEFT") ;; *) fail "gh removed line is LEFT: $(last)" ;; esac
ghcall --path src/edited2.txt --old-path src/edited.txt --old-line 2 --new-line 2 >/dev/null
case "$(last)" in *"-f path=src/edited2.txt -F line=2 -f side=RIGHT") ;; *) fail "gh renamed file, context line uses the new path: $(last)" ;; esac
ghcall --path src/edited2.txt --old-path src/edited.txt --old-line 2 >/dev/null
case "$(last)" in *"-f path=src/edited2.txt -F line=2 -f side=LEFT") ;; *) fail "gh renamed file, removed line uses the new path: $(last)" ;; esac
touch "$FIX/post-fail"
rc=0; ghcall --path src/app.txt --new-line 7 > "$tmp/post.out" 2> "$tmp/post.err" || rc=$?
eq "$rc" 1 "gh refusal exits 1"; eq "$(cat "$tmp/post.out")" "" "gh refusal prints no result"
grep -Fq 'gh: Unprocessable Entity (HTTP 422)' "$tmp/post.err" || fail "gh error not verbatim: $(cat "$tmp/post.err")"
rm "$FIX/post-fail"
rc=0; printf x | "$bin/tour-post" "$tmp/pd-gh" --path f --new-line 0 >/dev/null 2>&1 || rc=$?; eq "$rc" 2 "line 0 is usage"
rc=0; "$bin/tour-post" "$tmp/pd-gh" --path f </dev/null >/dev/null 2>&1 || rc=$?; eq "$rc" 2 "no line is usage"
rc=0; printf '  \n' | "$bin/tour-post" "$tmp/pd-gh" --path f --new-line 1 >/dev/null 2>&1 || rc=$?; eq "$rc" 2 "empty comment is usage"
rc=0; "$bin/tour-post" "$tmp/pd-gh" --path f --new-line "2 3" </dev/null >/dev/null 2>&1 || rc=$?; eq "$rc" 2 "two numbers in one line value is usage"
rc=0; "$bin/tour-post" "$tmp/pd-gh" --bogus </dev/null >/dev/null 2>&1 || rc=$?; eq "$rc" 2 "unknown option is usage"
rc=0; "$bin/tour-post" "$tmp/none" --path f --new-line 1 </dev/null >/dev/null 2>&1 || rc=$?; eq "$rc" 2 "no tour.json is usage"
printf 'from file\n' > "$tmp/body.txt"; ghcall --path src/app.txt --new-line 7 --body-file "$tmp/body.txt" </dev/null >/dev/null
case "$(last)" in *"-f body=from file "*) ;; *) fail "--body-file: $(last)" ;; esac
cases=$((cases + 17))

echo '{"id": "d1", "notes": [{"id": 77, "position": {"new_line": 2}}]}' > "$FIX/glab-disc.json"
glcall() { printf 'hello\n' | "$bin/tour-post" "$tmp/pd-gl" "$@"; }
pos() { jq -c "[.body, (.position | [.base_sha, .start_sha, .head_sha, .position_type, .old_path, .new_path, .old_line, .new_line])]" "$FIX/glab-payload.json"; }
eq "$(glcall --path f.txt --new-line 2 | jq -c .)" '{"id":77,"url":"https://gitlab.example.com/group/sub/proj/-/merge_requests/12#note_77","inline":true}' "gl post result"
eq "$(pos)" "[\"hello\",[\"basesha\",\"startsha\",\"$gl_head\",\"text\",\"f.txt\",\"f.txt\",null,2]]" "gl added line: new_line only"
glcall --path f.txt --old-line 2 >/dev/null
eq "$(pos | jq -c '.[1][6:8]')" '[2,null]' "gl removed line: old_line only"
glcall --path f.txt --old-line 3 --new-line 4 >/dev/null
eq "$(pos | jq -c '.[1][6:8]')" '[3,4]' "gl context line: both lines"
glcall --path src/after.txt --old-path src/before.txt --old-line 1 >/dev/null
eq "$(pos | jq -c '.[1][4:8]')" '["src/before.txt","src/after.txt",1,null]' "gl renamed file: old and new path"
glcall --path src/app.txt --new-line 7 >/dev/null     # second hunk of a multi-hunk file: absolute line numbers
eq "$(pos | jq -c '.[1][4:8]')" '["src/app.txt","src/app.txt",null,7]' "gl multi-hunk line"
glcall --path src/old.txt --old-line 1 >/dev/null
eq "$(pos | jq -c '.[1][4:8]')" '["src/old.txt","src/old.txt",1,null]' "gl deleted file"
echo '{"id": "d2", "notes": [{"id": 78, "position": null}]}' > "$FIX/glab-disc.json"
eq "$(glcall --path f.txt --new-line 2 | jq -c '[.id, .inline]')" '[78,false]' "gl dropped position reported"
touch "$FIX/post-fail"; rc=0; glcall --path f.txt --new-line 2 > "$tmp/post.out" 2> "$tmp/post.err" || rc=$?
eq "$rc" 1 "gl refusal exits 1"; eq "$(cat "$tmp/post.out")" "" "gl refusal prints no result"
eq "$(cat "$tmp/post.err")" "glab: 400 Bad request: position is invalid" "gl error verbatim"; rm "$FIX/post-fail"
cases=$((cases + 3))
mkpd "$tmp/pd-gl2" "$(jq -n '{platform: "gitlab", project: "group/sub/proj", iid: 12, url: "https://gitlab.example.com/group/sub/proj/-/merge_requests/12", head_sha: "0000000000000000000000000000000000000000"}')"
rm -f "$FIX/glab-payload.json"
rc=0; printf 'x' | "$bin/tour-post" "$tmp/pd-gl2" --path f.txt --new-line 2 >/dev/null 2> "$tmp/post.err" || rc=$?
eq "$rc" 1 "gl moved head exits 1"; grep -q 'head moved' "$tmp/post.err" || fail "gl moved head message"
[ ! -e "$FIX/glab-payload.json" ] || fail "nothing is posted when the head moved"
cases=$((cases + 11))

# --- #43 server: POST /api/comment posts one draft per call, marks it, never twice, keeps it on failure
cd "$tmp"
cdata="$tmp/cdata"; mkdir -p "$cdata"
jq -n --argjson mr "$(jq -c '.mr' "$fx/tour.base.json" | jq --arg s "$gh_head" '.head_sha = $s | .project = "acme/app" | .iid = 7 | .url = "https://github.com/acme/app/pull/7"')" '{version: 1, mr: $mr}' > "$cdata/tour.json"
cat > "$cdata/atoms.json" <<'JSON'
{"version": 1, "atoms": [
 {"id": "a1", "file": "src/app.txt", "old_file": "src/app.txt", "kind": "hunk", "old": {"start": 2, "count": 1}, "new": {"start": 2, "count": 1}, "lines": ["-two", "+TWO"]},
 {"id": "a2", "file": "src/app.txt", "old_file": "src/app.txt", "kind": "hunk", "old": {"start": 6, "count": 1}, "new": {"start": 6, "count": 2}, "lines": ["-six", "+SIX", "+seven"]},
 {"id": "a3", "file": "src/edited2.txt", "old_file": "src/edited.txt", "kind": "hunk", "old": {"start": 2, "count": 1}, "new": {"start": 2, "count": 1}, "lines": ["-edit b", "+EDIT b"]},
 {"id": "a4", "file": "src/after.txt", "old_file": "src/before.txt", "kind": "rename", "old": null, "new": null, "lines": []}
]}
JSON
"$bin/tour-serve" "$cdata" --no-open > "$tmp/serve2.out" 2> "$tmp/serve2.err" &
srv2=$!; trap 'kill $srv2 2>/dev/null || true; rm -rf "$tmp"' EXIT
for _ in $(seq 50); do grep -q '^http' "$tmp/serve2.out" && break; sleep 0.1; done
url2="$(head -1 "$tmp/serve2.out")"; base2="${url2%%/\?*}"; tok2="${url2##*token=}"; H2=(-H "X-Tour-Token: $tok2")
drafts='{"drafts": {
 "add": {"id": "add", "atom": "a2", "kind": "add", "new_line": 7, "body": "second hunk"},
 "del": {"id": "del", "atom": "a3", "kind": "del", "old_line": 2, "body": "renamed, removed line"},
 "ctx": {"id": "ctx", "atom": "a1", "kind": "ctx", "old_line": 4, "new_line": 4, "body": "context"},
 "far": {"id": "far", "atom": "a1", "kind": "add", "new_line": 9, "body": "outside the atom"},
 "none": {"id": "none", "atom": "a4", "kind": "add", "new_line": 1, "body": "rename atom has no lines"},
 "ctx2": {"id": "ctx2", "atom": "a1", "kind": "ctx", "old_line": 40, "new_line": 40, "body": "far"},
 "ctx3": {"id": "ctx3", "atom": "a1", "kind": "ctx", "old_line": 4, "new_line": 5, "body": "offset"},
 "slowd": {"id": "slowd", "atom": "a2", "kind": "add", "new_line": 6, "body": "slow"},
 "empty": {"id": "empty", "atom": "a1", "kind": "add", "new_line": 2, "body": " "}}}'
eq "$(code "${H2[@]}" -X PUT -d "$drafts" "$base2/api/state")" 200 "drafts saved"
: > "$STUB_LOG"
eq "$(code "${H2[@]}" -X POST -d '{"id":"add"}' "$base2/api/comment")" 200 "post a draft"
eq "$(jq -r '.draft.posted.id' "$tmp/body")" 555 "response carries the note id"
case "$(last)" in "gh api -X POST repos/acme/app/pulls/7/comments -f body=second hunk -f commit_id=$gh_head -f path=src/app.txt -F line=7 -f side=RIGHT") ;; *) fail "server added line: $(last)" ;; esac
eq "$(jq -r '.drafts.add.posted | [.id, .url] | join(" ")' "$cdata/state.json")" "555 https://github.com/acme/app/pull/7#discussion_r555" "note id saved in state.json"
eq "$(code "${H2[@]}" -X POST -d '{"id":"add"}' "$base2/api/comment")" 409 "a posted draft cannot be posted twice"
eq "$(grep -c '^gh api -X POST' "$STUB_LOG")" 1 "exactly one post"
eq "$(code "${H2[@]}" -X PUT -d '{"drafts": {}}' "$base2/api/state")" 200 "stale state PUT"
eq "$(jq -r '.drafts.add.posted.id' "$cdata/state.json")" 555 "a stale PUT keeps the note id"
eq "$(code "${H2[@]}" -X POST -d '{"id":"del"}' "$base2/api/comment")" 404 "draft dropped by the stale PUT is gone"
code "${H2[@]}" -X PUT -d "$drafts" "$base2/api/state" >/dev/null
eq "$(code "${H2[@]}" -X POST -d '{"id":"del"}' "$base2/api/comment")" 200 "post a removed line"
case "$(last)" in *"-f path=src/edited2.txt -F line=2 -f side=LEFT") ;; *) fail "server removed line in a renamed file: $(last)" ;; esac
eq "$(code "${H2[@]}" -X POST -d '{"id":"ctx"}' "$base2/api/comment")" 200 "post a context line"
case "$(last)" in *"-f path=src/app.txt -F line=4 -f side=RIGHT") ;; *) fail "server context line: $(last)" ;; esac
n=$(grep -c '^gh api -X POST' "$STUB_LOG")
eq "$(code "${H2[@]}" -X POST -d '{"id":"far"}' "$base2/api/comment")" 400 "line outside the atom rejected"
eq "$(code "${H2[@]}" -X POST -d '{"id":"none"}' "$base2/api/comment")" 400 "atom without lines rejected"
eq "$(code "${H2[@]}" -X POST -d '{"id":"empty"}' "$base2/api/comment")" 400 "empty comment rejected"
eq "$(code "${H2[@]}" -X POST -d '{"id":"nope"}' "$base2/api/comment")" 404 "unknown draft"
eq "$(code -X POST -d '{"id":"far"}' "$base2/api/comment")" 403 "posting needs the token"
eq "$(grep -c '^gh api -X POST' "$STUB_LOG")" "$n" "rejected drafts post nothing"
# a failed post keeps the draft, shows the CLI error verbatim, and can be retried
printf '%s' "$drafts" | jq -c '.drafts.far.new_line = 2 | .drafts.add.body = "again"' > "$tmp/d2.json"
code "${H2[@]}" -X PUT -d @"$tmp/d2.json" "$base2/api/state" >/dev/null
touch "$FIX/post-fail"
eq "$(code "${H2[@]}" -X POST -d '{"id":"far"}' "$base2/api/comment")" 502 "failed post"
grep -Fq 'gh: Unprocessable Entity (HTTP 422)' "$tmp/body" || fail "error not verbatim: $(cat "$tmp/body")"
eq "$(jq -r '.drafts.far | [has("posted"), .body] | join(" ")' "$cdata/state.json")" "false outside the atom" "failed post keeps the draft"
rm "$FIX/post-fail"
eq "$(code "${H2[@]}" -X POST -d '{"id":"far"}' "$base2/api/comment")" 200 "retry after a failure posts"
# ctx lines must belong to the atom (a1: -2 +2, so old == new); a double click posts once
eq "$(code "${H2[@]}" -X POST -d '{"id":"ctx2"}' "$base2/api/comment")" 400 "context line far from the atom rejected"
eq "$(code "${H2[@]}" -X POST -d '{"id":"ctx3"}' "$base2/api/comment")" 400 "context line with a wrong old/new offset rejected"
touch "$FIX/slow"; : > "$STUB_LOG"
curl -s -o "$tmp/b1" -w '%{http_code}' "${H2[@]}" -X POST -d '{"id":"slowd"}' "$base2/api/comment" > "$tmp/c1" & p1=$!
sleep 0.3; c2="$(code "${H2[@]}" -X POST -d '{"id":"slowd"}' "$base2/api/comment")"; wait $p1
eq "$c2" 409 "second click while the first is in flight"; eq "$(cat "$tmp/c1")" 200 "first click posts"
eq "$(grep -c '^gh api -X POST' "$STUB_LOG")" 1 "double click posts once"; rm "$FIX/slow"
cases=$((cases + 29))
kill "$srv2" 2>/dev/null || true

# --- #45 server: chapter chat runs a read-only `claude -p --resume`, streams it, persists the session, shows CLI errors verbatim
cat > "$tmp/stubs/claude-stub" <<'STUB'
#!/usr/bin/env bash
echo "claude $* | cwd=$(pwd -P) | key=${ANTHROPIC_API_KEY:-unset}" >> "$STUB_LOG"
cat > "$FIX/claude-stdin.$(grep -c '^claude ' "$STUB_LOG")"
if [ -e "$FIX/claude-fail" ]; then echo "Claude usage limit reached" >&2; exit 1; fi
if [ -e "$FIX/claude-error-result" ]; then echo '{"type":"result","is_error":true,"result":"rate limited, resets at 5pm","session_id":"sess-0000-aaaa"}'; exit 1; fi
echo '{"type":"system","subtype":"init","session_id":"sess-1234-abcd"}'
echo '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hel"}},"session_id":"sess-1234-abcd"}'
echo '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"lo"}},"session_id":"sess-1234-abcd"}'
echo '{"type":"result","is_error":false,"result":"Hello","session_id":"sess-1234-abcd"}'
STUB
chmod +x "$tmp/stubs/claude-stub"
chdata="$tmp/chdata"; mkdir -p "$chdata/worktree"; cp "$fx/tour.full.json" "$chdata/tour.json"; cp "$fx/atoms.json" "$chdata/atoms.json"
ch="$(jq -r '.chapters[0].id' "$chdata/tour.json")"
env -u ANTHROPIC_API_KEY TOUR_CLAUDE_BIN="$tmp/stubs/claude-stub" "$bin/tour-serve" "$chdata" --no-open > "$tmp/serve3.out" 2> "$tmp/serve3.err" &
srv3=$!; trap 'kill $srv3 2>/dev/null || true; rm -rf "$tmp"' EXIT
for _ in $(seq 50); do grep -q '^http' "$tmp/serve3.out" && break; sleep 0.1; done
url3="$(head -1 "$tmp/serve3.out")"; base3="${url3%%/\?*}"; H3=(-H "X-Tour-Token: ${url3##*token=}")
chat() { code "${H3[@]}" -X POST -d "$(jq -nc --arg c "$1" --arg m "$2" '{chapter: $c, message: $m}')" "$base3/api/chat"; }
: > "$STUB_LOG"
eq "$(chat "$ch" 'why is this guarded?')" 200 "chat answers"
eq "$(grep '^data:' "$tmp/body" | sed 's/^data: //' | jq -rs '[.[] | select(.type == "text") | .text] | join("")')" "Hello" "reply streams as SSE text events"
eq "$(grep '^data:' "$tmp/body" | tail -1)" 'data: {"type":"done"}' "stream ends with done"
call="$(grep '^claude ' "$STUB_LOG" | head -1)"
case "$call" in "claude -p --output-format stream-json --verbose --include-partial-messages --tools Read,Grep,Glob --allowedTools Read,Grep,Glob | cwd=$(cd "$chdata/worktree" && pwd -P) | key=unset") ;; *) fail "first call must be read-only, in the worktree, no key: $call" ;; esac
case "$call" in *Bash*|*Edit*|*Write*|*--resume*) fail "first call has a write tool or a resume: $call" ;; esac
grep -q 'Validate the import payload' "$FIX/claude-stdin.1" || fail "first message injects the chapter"
grep -q 'why is this guarded?' "$FIX/claude-stdin.1" || fail "first message carries the question"
eq "$(jq -r .session "$chdata/chat/$ch.json")" sess-1234-abcd "session id persisted"
eq "$(chat "$ch" 'and the caller?')" 200 "second turn"
case "$(grep '^claude ' "$STUB_LOG" | tail -1)" in *"--tools Read,Grep,Glob --allowedTools Read,Grep,Glob --resume sess-1234-abcd |"*) ;; *) fail "second turn resumes: $(tail -1 "$STUB_LOG")" ;; esac
eq "$(cat "$FIX/claude-stdin.2")" 'and the caller?' "resumed turn sends only the question"
code "${H3[@]}" "$base3/api/chat?chapter=$ch" >/dev/null
eq "$(jq -c '[.messages[].role]' "$tmp/body")" '["user","assistant","user","assistant"]' "a reload gets the conversation back"
# a restarted server resumes the stored session
kill "$srv3"; wait "$srv3" 2>/dev/null || true
env TOUR_CLAUDE_BIN="$tmp/stubs/claude-stub" "$bin/tour-serve" "$chdata" --no-open > "$tmp/serve3.out" 2> "$tmp/serve3.err" &
srv3=$!
for _ in $(seq 50); do grep -q '^http' "$tmp/serve3.out" && break; sleep 0.1; done
url3="$(head -1 "$tmp/serve3.out")"; base3="${url3%%/\?*}"; H3=(-H "X-Tour-Token: ${url3##*token=}")
eq "$(chat "$ch" 'after restart')" 200 "turn after a restart"
case "$(grep '^claude ' "$STUB_LOG" | tail -1)" in *"--resume sess-1234-abcd |"*) ;; *) fail "restart resumes: $(tail -1 "$STUB_LOG")" ;; esac
# CLI failures are shown verbatim and not retried
n=$(grep -c '^claude ' "$STUB_LOG"); touch "$FIX/claude-fail"
eq "$(chat "$ch" 'again')" 200 "failing CLI still streams"
eq "$(grep '^data:' "$tmp/body" | tail -1 | sed 's/^data: //' | jq -r '[.type, .error] | join(": ")')" "error: Claude usage limit reached" "stderr shown verbatim"
rm "$FIX/claude-fail"; touch "$FIX/claude-error-result"
chat "$ch" 'again' >/dev/null
eq "$(grep '^data:' "$tmp/body" | tail -1 | sed 's/^data: //' | jq -r .error)" "rate limited, resets at 5pm" "result error shown verbatim"
rm "$FIX/claude-error-result"
eq "$(grep -c '^claude ' "$STUB_LOG")" $((n + 2)) "one spawn per message, no retry"
# a failed first turn stores no session, so the next turn still sends the chapter context
rm -f "$chdata/chat/$ch.json"; touch "$FIX/claude-error-result"
chat "$ch" 'first' >/dev/null
eq "$(jq -r '.session' "$chdata/chat/$ch.json")" null "failed first turn keeps no session"
rm "$FIX/claude-error-result"
chat "$ch" 'retry by hand' >/dev/null
grep -q 'Validate the import payload' "$FIX/claude-stdin.$(grep -c '^claude ' "$STUB_LOG")" || fail "next turn after a failed first one re-sends the chapter"
eq "$(chat nope 'x')" 404 "unknown chapter"
eq "$(chat "$ch" ' ')" 400 "empty message"
eq "$(code -X POST -d '{}' "$base3/api/chat")" 403 "chat needs the token"
cases=$((cases + 21))
kill "$srv3" 2>/dev/null || true

# --- #56 UI renders atoms without hunks (rename, binary, mode, add) instead of throwing (needs node >= 18)
ui_out="$(node "$bin/../tests/ui-atoms.mjs" "$bin/../ui/app.js" 2>&1)" || fail "app.js throws on no-hunk atoms: $ui_out"
case "$ui_out" in *"Could not load the tour"*) fail "no-hunk atoms: tour not loaded: $ui_out" ;; esac
for k in rename binary mode add; do case "$ui_out" in *"· $k"*) ;; *) fail "no-hunk atom kind [$k] not shown: $ui_out" ;; esac; done
cases=$((cases + 1))

echo "tour: $cases cases ok"
