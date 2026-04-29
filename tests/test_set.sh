#!/usr/bin/env bash
source "$(dirname "$0")/harness.sh"

echo "=== set ==="

# ── query: cmd:<shell> ────────────────────────────────────────────────────────

t "set cmd:bash creates _default supplier with bash command"
setup set; vdir init; vdir mkq myq; vdir set myq cmd:bash "echo hello"
assert_exit_ok
CMD=$(python3 -c "
import json; d=json.load(open('.vdir.json'))
q=[c for c in d['root']['children'] if c['name']=='myq'][0]
print(q['suppliers']['_default']['cmd']['bash'])
")
if [[ "$CMD" == "echo hello" ]]; then _pass; else _fail "bash cmd not set, got: $CMD"; fi
teardown

t "set cmd:nu writes nu command alongside bash"
setup set; vdir init; vdir mkq myq
vdir set myq cmd:bash "echo hello"
vdir set myq cmd:nu "echo hello"
assert_exit_ok
NU=$(python3 -c "
import json; d=json.load(open('.vdir.json'))
q=[c for c in d['root']['children'] if c['name']=='myq'][0]
print(q['suppliers']['_default']['cmd']['nu'])
")
if [[ "$NU" == "echo hello" ]]; then _pass; else _fail "nu cmd not set, got: $NU"; fi
teardown

t "set scope sets _default.scope"
setup set; vdir init; vdir mkq myq; vdir set myq scope /tmp
assert_exit_ok
SCOPE=$(python3 -c "
import json; d=json.load(open('.vdir.json'))
q=[c for c in d['root']['children'] if c['name']=='myq'][0]
print(q['suppliers']['_default']['scope'])
")
if [[ "$SCOPE" == "/tmp" ]]; then _pass; else _fail "scope not set, got: $SCOPE"; fi
teardown

t "set expr writes expression"
setup set; vdir init; vdir mkq myq; vdir set myq cmd:bash "echo a"; vdir set myq expr "_default"
assert_exit_ok
EXPR=$(python3 -c "
import json; d=json.load(open('.vdir.json'))
q=[c for c in d['root']['children'] if c['name']=='myq'][0]
print(q['expr'])
")
if [[ "$EXPR" == "_default" ]]; then _pass; else _fail "expr not set, got: $EXPR"; fi
teardown

t "set expr with complex expression"
setup set; vdir init; vdir mkq myq; vdir set myq expr "a or b"
assert_exit_ok
EXPR=$(python3 -c "
import json; d=json.load(open('.vdir.json'))
q=[c for c in d['root']['children'] if c['name']=='myq'][0]
print(q['expr'])
")
if [[ "$EXPR" == "a or b" ]]; then _pass; else _fail "expr not set, got: $EXPR"; fi
teardown

t "set supplier lists suppliers"
setup set; vdir init; vdir mkq myq; vdir set myq cmd:bash "echo a"; vdir set myq supplier
assert_exit_ok
assert_either_contains "_default"
teardown

t "set supplier <n> cmd creates named supplier"
setup set; vdir init; vdir mkq myq; vdir set myq supplier mysup cmd "echo x"
assert_exit_ok
CMD=$(python3 -c "
import json; d=json.load(open('.vdir.json'))
q=[c for c in d['root']['children'] if c['name']=='myq'][0]
cmd_map = q['suppliers']['mysup']['cmd']
print(list(cmd_map.values())[0])
")
if [[ "$CMD" == "echo x" ]]; then _pass; else _fail "supplier cmd not set, got: $CMD"; fi
teardown

t "set supplier <n> scope sets scope"
setup set; vdir init; vdir mkq myq; vdir set myq supplier mysup scope /tmp
assert_exit_ok
SCOPE=$(python3 -c "
import json; d=json.load(open('.vdir.json'))
q=[c for c in d['root']['children'] if c['name']=='myq'][0]
print(q['suppliers']['mysup']['scope'])
")
if [[ "$SCOPE" == "/tmp" ]]; then _pass; else _fail "supplier scope not set, got: $SCOPE"; fi
teardown

t "set supplier <n> rm removes supplier"
setup set; vdir init; vdir mkq myq; vdir set myq cmd:bash "echo a"; vdir set myq supplier _default rm
assert_exit_ok
COUNT=$(python3 -c "
import json; d=json.load(open('.vdir.json'))
q=[c for c in d['root']['children'] if c['name']=='myq'][0]
print(len(q['suppliers']))
")
if [[ "$COUNT" == "0" ]]; then _pass; else _fail "supplier not removed, count: $COUNT"; fi
teardown

t "set supplier rm nonexistent errors"
setup set; vdir init; vdir mkq myq; vdir set myq supplier nosup rm
assert_exit_fail
teardown

t "set on folder errors"
setup set; vdir init; vdir mkdir A; vdir set A anything value
assert_exit_fail
assert_either_contains "Folders have no settable properties"
teardown

t "set unknown property errors"
setup set; vdir init; vdir mkq myq; vdir set myq bogusprop value
assert_exit_fail
teardown

t "set unknown shell in cmd:<shell> errors"
setup set; vdir init; vdir mkq myq; vdir set myq cmd:fishbowl "echo x"
assert_exit_fail
assert_either_contains "Unknown shell"
teardown

# ── reference: target ─────────────────────────────────────────────────────────

t "set ref target updates target path"
setup set
vdir init
echo x > /tmp/vdir_set_a.txt
echo x > /tmp/vdir_set_b.txt
vdir ln /tmp/vdir_set_a.txt myref
vdir set myref target /tmp/vdir_set_b.txt
assert_exit_ok
TARGET=$(python3 -c "
import json; d=json.load(open('.vdir.json'))
r=[c for c in d['root']['children'] if c['name']=='myref'][0]
print(r['target'])
")
if [[ "$TARGET" == "/tmp/vdir_set_b.txt" ]]; then _pass; else _fail "target not updated, got: $TARGET"; fi
rm -f /tmp/vdir_set_a.txt /tmp/vdir_set_b.txt
teardown

t "set ref target updates target_type"
setup set
vdir init
echo x > /tmp/vdir_set_file.txt
vdir ln /tmp/vdir_set_file.txt myref
vdir set myref target "$REPO_ROOT"
assert_exit_ok
TYPE=$(python3 -c "
import json; d=json.load(open('.vdir.json'))
r=[c for c in d['root']['children'] if c['name']=='myref'][0]
print(r['target_type'])
")
if [[ "$TYPE" == "folder" ]]; then _pass; else _fail "target_type not updated, got: $TYPE"; fi
rm -f /tmp/vdir_set_file.txt
teardown

t "set ref target to nonexistent errors"
setup set
vdir init
echo x > /tmp/vdir_set_file.txt
vdir ln /tmp/vdir_set_file.txt myref
vdir set myref target /nonexistent/path/xyz
assert_exit_fail
assert_either_contains "does not exist"
rm -f /tmp/vdir_set_file.txt
teardown

t "json valid after all set operations"
setup set; vdir init; vdir mkq myq; vdir set myq cmd:bash "echo a"; vdir set myq scope /tmp; vdir set myq expr "_default"
assert_json_valid ".vdir.json"
teardown

summary
