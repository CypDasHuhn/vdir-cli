#!/usr/bin/env bash
source "$(dirname "$0")/harness.sh"

echo "=== rm ==="

t "rm removes existing item"
setup rm; vdir init; vdir mkdir A; vdir rm A
assert_exit_ok
vdir ls
if [[ -z "$STDERR$STDOUT" ]]; then _pass; else _fail "item still present"; fi
teardown

t "rm nonexistent errors"
setup rm; vdir init; vdir rm nosuch
assert_exit_fail
assert_either_contains "not found"
teardown

t "rm query removes directly"
setup rm; vdir init; vdir mkq myq; vdir rm myq
assert_exit_ok
teardown

t "rm reference removes directly"
setup rm
vdir init
echo "x" > /tmp/vdir_rm_ref.txt
vdir ln /tmp/vdir_rm_ref.txt myref
vdir rm myref
assert_exit_ok
rm -f /tmp/vdir_rm_ref.txt
teardown

t "rm empty folder removes without prompt"
setup rm; vdir init; vdir mkdir A; vdir rm A
assert_exit_ok
teardown

t "rm --force removes non-empty folder without prompt"
setup rm; vdir init; vdir mkdir A; vdir cd A; vdir mkdir B; vdir cd "~"; vdir rm --force A
assert_exit_ok
teardown

t "rm --force removes folder with children"
setup rm; vdir init; vdir mkdir A; vdir cd A; vdir mkdir B; vdir mkdir C; vdir cd "~"; vdir rm --force A
assert_exit_ok
COUNT=$(python3 -c "import json; d=json.load(open('.vdir.json')); print(len(d['root']['children']))")
if [[ "$COUNT" == "0" ]]; then _pass; else _fail "folder not removed, children count: $COUNT"; fi
teardown

t "json valid after rm"
setup rm; vdir init; vdir mkdir A; vdir mkdir B; vdir rm A
assert_json_valid ".vdir.json"
teardown

t "no .vdir.json errors"
setup rm; vdir rm A
assert_exit_fail
assert_either_contains "No vdir found"
teardown

summary
