#!/usr/bin/env bash
source "$(dirname "$0")/harness.sh"

echo "=== mv ==="

t "mv renames item in place"
setup mv; vdir init; vdir mkdir A; vdir mv A B
assert_exit_ok
vdir ls -l
assert_either_contains "B"
assert_stderr_not_contains " A"
teardown

t "mv rename updates json name field"
setup mv; vdir init; vdir mkdir A; vdir mv A B
assert_json_field ".vdir.json" "d['root']['children'][0]['name']" "B"
teardown

t "mv into folder moves item"
setup mv; vdir init; vdir mkdir target; vdir mkdir item; vdir mv item target
assert_exit_ok
INNER=$(python3 -c "import json; d=json.load(open('.vdir.json')); t=[c for c in d['root']['children'] if c['name']=='target'][0]; print(t['children'][0]['name'])")
if [[ "$INNER" == "item" ]]; then _pass; else _fail "item not inside target, got: $INNER"; fi
teardown

t "mv into folder removes from source"
setup mv; vdir init; vdir mkdir target; vdir mkdir item; vdir mv item target
COUNT=$(python3 -c "import json; d=json.load(open('.vdir.json')); print(len(d['root']['children']))")
if [[ "$COUNT" == "1" ]]; then _pass; else _fail "source still has item, root children: $COUNT"; fi
teardown

t "mv source not found errors"
setup mv; vdir init; vdir mv nosuch B
assert_exit_fail
assert_either_contains "not found"
teardown

t "mv rename to existing non-folder name errors"
setup mv; vdir init; vdir mkdir A; vdir mkq B; vdir mv A B
assert_exit_fail
teardown

t "mv moves folder with its children"
setup mv; vdir init
vdir mkdir target
vdir mkdir mover; vdir cd mover; vdir mkdir child; vdir cd "~"
vdir mv mover target
INNER=$(python3 -c "import json; d=json.load(open('.vdir.json')); t=[c for c in d['root']['children'] if c['name']=='target'][0]; m=[c for c in t['children'] if c['name']=='mover'][0]; print(m['children'][0]['name'])")
if [[ "$INNER" == "child" ]]; then _pass; else _fail "children not preserved: $INNER"; fi
teardown

t "mv moves query preserving suppliers"
setup mv; vdir init
vdir mkdir dest
vdir mkq myq --raw --shell bash "echo /tmp/foo"
vdir mv myq dest
EXPR=$(python3 -c "import json; d=json.load(open('.vdir.json')); dest=[c for c in d['root']['children'] if c['name']=='dest'][0]; q=[c for c in dest['children'] if c['name']=='myq'][0]; print(q['expr'])")
if [[ "$EXPR" == "_default" ]]; then _pass; else _fail "expr not preserved: $EXPR"; fi
teardown

t "json valid after mv"
setup mv; vdir init; vdir mkdir A; vdir mv A B
assert_json_valid ".vdir.json"
teardown

t "no .vdir.json errors"
setup mv; vdir mv A B
assert_exit_fail
assert_either_contains "No vdir found"
teardown

summary
