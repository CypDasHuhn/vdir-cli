#!/usr/bin/env bash
source "$(dirname "$0")/harness.sh"

echo "=== mkq ==="

t "mkq creates empty query with no suppliers"
setup mkq; vdir init; vdir mkq myq
assert_exit_ok
COUNT=$(python3 -c "
import json; d=json.load(open('.vdir.json'))
q=[c for c in d['root']['children'] if c['name']=='myq'][0]
print(len(q['suppliers']))
")
if [[ "$COUNT" == "0" ]]; then _pass; else _fail "expected 0 suppliers, got: $COUNT"; fi
teardown

t "mkq creates query visible in ls"
setup mkq; vdir init; vdir mkq myq; vdir ls
assert_either_contains "myq"
teardown

t "mkq --raw creates query with default shell"
setup mkq; vdir init; vdir mkq myq --raw "echo /tmp/foo"
assert_exit_ok
SUPPLIERS=$(python3 -c "
import json; d=json.load(open('.vdir.json'))
q=[c for c in d['root']['children'] if c['name']=='myq'][0]
print(list(q['suppliers'].keys()))
")
if echo "$SUPPLIERS" | grep -q "_default"; then _pass; else _fail "no _default supplier, got: $SUPPLIERS"; fi
teardown

t "mkq --raw --shell bash stores under bash key"
setup mkq; vdir init; vdir mkq myq --raw --shell bash "echo /tmp/foo"
assert_exit_ok
CMD=$(python3 -c "
import json; d=json.load(open('.vdir.json'))
q=[c for c in d['root']['children'] if c['name']=='myq'][0]
print(q['suppliers']['_default']['cmd']['bash'])
")
if [[ "$CMD" == "echo /tmp/foo" ]]; then _pass; else _fail "bash cmd not stored, got: $CMD"; fi
teardown

t "mkq --raw --shell nu stores under nu key"
setup mkq; vdir init; vdir mkq myq --raw --shell nu "glob **/*.rs"
assert_exit_ok
CMD=$(python3 -c "
import json; d=json.load(open('.vdir.json'))
q=[c for c in d['root']['children'] if c['name']=='myq'][0]
print(q['suppliers']['_default']['cmd']['nu'])
")
if [[ "$CMD" == "glob **/*.rs" ]]; then _pass; else _fail "nu cmd not stored, got: $CMD"; fi
teardown

t "mkq duplicate name errors"
setup mkq; vdir init; vdir mkq myq; vdir mkq myq
assert_exit_fail
assert_either_contains "already exists"
teardown

t "mkq duplicate name does not write"
setup mkq; vdir init; vdir mkq myq; vdir mkq myq
COUNT=$(python3 -c "import json; d=json.load(open('.vdir.json')); print(len(d['root']['children']))")
if [[ "$COUNT" == "1" ]]; then _pass; else _fail "expected 1 child, got $COUNT"; fi
teardown

t "mkq unknown compiler errors"
setup mkq; vdir init; vdir mkq myq noSuchCompiler123 "some args"
assert_exit_fail
assert_either_contains "not found"
teardown

t "mkq --raw --shell with unknown shell errors"
setup mkq; vdir init; vdir mkq myq --raw --shell fishbowl "echo x"
assert_exit_fail
assert_either_contains "Unknown shell"
teardown

t "mkq json valid after creation"
setup mkq; vdir init; vdir mkq myq --raw --shell bash "echo x"
assert_json_valid ".vdir.json"
teardown

t "mkq query always has expr field"
setup mkq; vdir init; vdir mkq myq
EXPR=$(python3 -c "
import json; d=json.load(open('.vdir.json'))
q=[c for c in d['root']['children'] if c['name']=='myq'][0]
print('expr' in q)
")
if [[ "$EXPR" == "True" ]]; then _pass; else _fail "expr field missing"; fi
teardown

t "mkq query always has suppliers field"
setup mkq; vdir init; vdir mkq myq
SUPS=$(python3 -c "
import json; d=json.load(open('.vdir.json'))
q=[c for c in d['root']['children'] if c['name']=='myq'][0]
print('suppliers' in q)
")
if [[ "$SUPS" == "True" ]]; then _pass; else _fail "suppliers field missing"; fi
teardown

t "no .vdir.json errors"
setup mkq; vdir mkq myq
assert_exit_fail
assert_either_contains "No vdir found"
teardown

summary
