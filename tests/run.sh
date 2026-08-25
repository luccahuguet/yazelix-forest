#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
steel_bin=${FOREST_STEEL_BIN:-steel}
test_root=$(mktemp -d "${TMPDIR:-/tmp}/forest-tests.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT

mkdir -p "$test_root/steel/cogs"

cd "$repo_root"
if grep -q 'forest-parent-path' forest.scm; then
  echo 'forest.scm must use Steel native parent-name' >&2
  exit 1
fi
if grep -q "helix.redraw '()" forest.scm; then
  echo 'forest.scm must call the public redraw wrapper without arguments' >&2
  exit 1
fi
if ! grep -q 'provide forest-set-toggle-key!' forest.scm; then
  echo 'forest.scm must expose its configured focus toggle to foreground event handling' >&2
  exit 1
fi
if ! grep -q '"event_priority" #t' forest.scm; then
  echo 'the persistent background must receive its focus toggle before native modal components' >&2
  exit 1
fi
if ! grep -q "(list pos 'hidden)" forest.scm; then
  echo 'focused forest must hide cursors owned by lower modal components' >&2
  exit 1
fi
if [ "$(grep -c '(forest-switch-to-editor!)' forest.scm)" -ne 2 ]; then
  echo 'foreground event handlers must let Helix close forest-fg exactly once' >&2
  exit 1
fi
if ! sed -n '/^(define (forest-activate!)/,/^(define (forest-dir-expanded?/p' forest.scm |
  grep -q '(pop-last-component-by-name! "picker")'; then
  echo 'opening a Forest file must dismiss a covered native picker' >&2
  exit 1
fi
STEEL_HOME="$test_root/steel" "$steel_bin" ast --expanded false --require false forest.scm >/dev/null
STEEL_HOME="$test_root/steel" "$steel_bin" tests/forest-tests.scm "$test_root/work"
