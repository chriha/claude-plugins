#!/usr/bin/env bash
# Case setup (run by ../_shared/scaffold.sh in the run dir): checks out feature/31-add-shout (pushed, upstream set) with one
# commit adding branch/* (shout.sh + its test). Planted: PR comment T1 is valid (shout.sh:4 shifts once after `--times N`, so the
# text becomes N); PR comment T2 is invalid (claims `times` is never set, but shout.sh:3 sets it).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
git checkout -q -b feature/31-add-shout
cp -R "$here/branch/." .
git add -A
git -c user.name="Eval" -c user.email="eval@example.invalid" commit -qm "feat: add shout.sh" \
    -m "Prints its text upper-cased, --times N repeats it. Refs #31"
git push -q -u origin feature/31-add-shout
