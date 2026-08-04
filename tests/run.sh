#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
steel_bin=${FOREST_STEEL_BIN:-steel}
test_root=$(mktemp -d "${TMPDIR:-/tmp}/forest-tests.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT

mkdir -p "$test_root/steel/cogs"

cd "$repo_root"
STEEL_HOME="$test_root/steel" "$steel_bin" ast --expanded false --require false forest.scm >/dev/null
STEEL_HOME="$test_root/steel" "$steel_bin" tests/forest-tests.scm "$test_root/work"
