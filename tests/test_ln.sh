#!/usr/bin/env bash
source "$(dirname "$0")/harness.sh"

echo "=== ln ==="

TESTFILE=$(mktemp /tmp/vdir_ln_test_file.XXXXXX)
TESTDIR=$(mktemp -d /tmp/vdir_ln_test_dir.XXXXXX)

t "ln <file> uses basename as name"
setup ln; vdir init; vdir ln "$TESTFILE"
assert_exit_ok
BASENAME=$(basename "$TESTFILE")
assert_either_contains "$BASENAME"
teardown

t "ln <file> creates reference in ls"
setup ln; vdir init; vdir ln "$TESTFILE" myfile; vdir ls
assert_either_contains "myfile"
teardown

t "ln <dir> creates reference with target_type folder"
setup ln; vdir init; vdir ln "$TESTDIR" mydir
assert_exit_ok
assert_json_field ".vdir.json" "d['root']['children'][0]['target_type']" "folder"
teardown

t "ln <file> creates reference with target_type file"
setup ln; vdir init; vdir ln "$TESTFILE" myfile
assert_exit_ok
assert_json_field ".vdir.json" "d['root']['children'][0]['target_type']" "file"
teardown

t "ln <file> [name] uses custom name"
setup ln; vdir init; vdir ln "$TESTFILE" myalias
assert_exit_ok
assert_json_field ".vdir.json" "d['root']['children'][0]['name']" "myalias"
teardown

t "ln /nonexistent errors"
setup ln; vdir init; vdir ln /nonexistent/path/xyz
assert_exit_fail
assert_either_contains "does not exist"
teardown

t "ln duplicate name errors"
setup ln; vdir init; vdir ln "$TESTFILE" myfile; vdir ln "$TESTFILE" myfile
assert_exit_fail
assert_either_contains "already exists"
teardown

t "ln duplicate name does not corrupt json"
setup ln; vdir init; vdir ln "$TESTFILE" myfile; vdir ln "$TESTFILE" myfile
assert_json_valid ".vdir.json"
COUNT=$(python3 -c "import json; d=json.load(open('.vdir.json')); print(len(d['root']['children']))")
if [[ "$COUNT" == "1" ]]; then _pass; else _fail "expected 1 child, got $COUNT"; fi
teardown

t "ln stores target path"
setup ln; vdir init; vdir ln "$TESTFILE" myfile
assert_json_field ".vdir.json" "d['root']['children'][0]['target']" "$TESTFILE"
teardown

t "no .vdir.json errors"
setup ln; vdir ln "$TESTFILE" myfile
assert_exit_fail
assert_either_contains "No vdir found"
teardown

rm -f "$TESTFILE"
rm -rf "$TESTDIR"

summary
