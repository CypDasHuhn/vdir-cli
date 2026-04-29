#!/usr/bin/env bash
source "$(dirname "$0")/harness.sh"

echo "=== init ==="

t "creates .vdir.json"
setup init; vdir init
assert_exit_ok
assert_file_exists ".vdir.json"
teardown

t ".vdir.json is valid JSON"
setup init; vdir init
assert_json_valid ".vdir.json"
teardown

t "root.children is empty array"
setup init; vdir init
assert_json_field ".vdir.json" "d['root']['children']" "[]"
teardown

t "root name is empty string"
setup init; vdir init
assert_json_field ".vdir.json" "d['root']['name']" ""
teardown

t "init twice prints error"
setup init; vdir init; vdir init
assert_exit_fail
assert_either_contains "already"
teardown

t "init twice does not corrupt .vdir.json"
setup init; vdir init; vdir init
assert_json_valid ".vdir.json"
teardown

t "does not create .vdir-marker"
setup init; vdir init
assert_file_not_exists ".vdir-marker"
teardown

t "no .vdir.json → every other command fails"
setup init
vdir ls
assert_exit_fail
assert_either_contains "No vdir found"
teardown

summary
