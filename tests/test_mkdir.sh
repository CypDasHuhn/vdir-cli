#!/usr/bin/env bash
source "$(dirname "$0")/harness.sh"

echo "=== mkdir ==="

t "creates folder visible in ls"
setup mkdir; vdir init; vdir mkdir myfolder; vdir ls
assert_exit_ok
assert_either_contains "myfolder"
teardown

t "duplicate name errors"
setup mkdir; vdir init; vdir mkdir myfolder; vdir mkdir myfolder
assert_exit_fail
assert_either_contains "already exists"
teardown

t "duplicate name does not write"
setup mkdir; vdir init; vdir mkdir myfolder; vdir mkdir myfolder
assert_json_valid ".vdir.json"
# Only one folder should exist
COUNT=$(python3 -c "import json; d=json.load(open('.vdir.json')); print(len(d['root']['children']))")
if [[ "$COUNT" == "1" ]]; then _pass; else _fail "expected 1 child, got $COUNT"; fi
teardown

t "new folder has empty children"
setup mkdir; vdir init; vdir mkdir myfolder
assert_json_field ".vdir.json" "d['root']['children'][0]['children']" "[]"
teardown

t "name with spaces accepted"
setup mkdir; vdir init; vdir mkdir "my folder"
assert_exit_ok
assert_either_contains "my folder"
teardown

t "name starting with . accepted (hidden)"
setup mkdir; vdir init; vdir mkdir ".hidden"
assert_exit_ok
# visible with -a
vdir ls -a
assert_either_contains ".hidden"
teardown

t "name with / is an error"
setup mkdir; vdir init; vdir mkdir "foo/bar"
assert_exit_fail
teardown

t "empty name is an error"
setup mkdir; vdir init; vdir mkdir ""
assert_exit_fail
teardown

t "no .vdir.json errors"
setup mkdir; vdir mkdir myfolder
assert_exit_fail
assert_either_contains "No vdir found"
teardown

summary
