#!/usr/bin/env bash
# Case scaffold: the shared fixture repo (see ../_shared/scaffold.sh); no tracker fixtures needed.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
exec bash "$here/../_shared/scaffold.sh" "$here"
