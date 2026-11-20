#!/usr/bin/env bash
# tour tests: bash plugins/tour/tests/run.sh (needs jq; the server cases need node >= 18 and curl). Exits non-zero on the first failure.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
bin="$root/bin"; fx="$root/fixtures"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
eq() { [ "$1" = "$2" ] || fail "$3: got [$1], want [$2]"; }
cases=0

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
srv=$!; trap 'kill $srv 2>/dev/null; rm -rf "$tmp"' EXIT
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

echo "tour: $cases cases ok"
