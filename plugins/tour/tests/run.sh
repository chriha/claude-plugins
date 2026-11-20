#!/usr/bin/env bash
# Self-check for bin/ scripts: bash plugins/tour/tests/run.sh (needs git, jq). No network: gh/glab are stubs, origin is a local bare repo.
# Exits non-zero on the first failure.
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
    "issue view 3 "*"--json title,body"*) echo '{"title": "The ticket", "body": "ticket text"}' ;;
    "issue view"*) echo '{}' ;; *) echo "unexpected gh $*" >&2; exit 1 ;; esac
STUB
cat > "$tmp/stubs/glab" <<'STUB'
#!/usr/bin/env bash
echo "glab[$GITLAB_HOST] $*" >> "$STUB_LOG"
case "$*" in
    api*/closes_issues) cat "$FIX/glab-issues.json" ;;
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
    target_branch: "main", source_branch: "fix/twelve", sha: $sha, diff_refs: {base_sha: "x", head_sha: $sha, start_sha: "x"}}' > "$FIX/glab-mr.json"
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

echo "tour: all cases passed"
