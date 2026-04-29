#!/usr/bin/env bash
source "$(dirname "$0")/harness.sh"

echo "=== data format ==="

t "json valid after init"
setup fmt; vdir init
assert_json_valid ".vdir.json"
teardown

t "json uses 2-space indentation"
setup fmt; vdir init; vdir mkdir A
# Check that "  " (2 spaces) indent is present, not 4-space or tabs
if grep -qP '^\s{2}"' .vdir.json && ! grep -qP '^\t' .vdir.json; then _pass; else _fail "indentation is wrong"; fi
teardown

t "json ends with newline"
setup fmt; vdir init
LAST=$(tail -c 1 .vdir.json | xxd -p)
if [[ "$LAST" == "0a" ]]; then _pass; else _fail "file does not end with newline (last byte: $LAST)"; fi
teardown

t "root always has name empty string"
setup fmt; vdir init
assert_json_field ".vdir.json" "d['root']['name']" ""
teardown

t "folders always have children array"
setup fmt; vdir init; vdir mkdir A
HAS_CHILDREN=$(python3 -c "
import json; d=json.load(open('.vdir.json'))
a=[c for c in d['root']['children'] if c['name']=='A'][0]
print(isinstance(a.get('children'), list))
")
if [[ "$HAS_CHILDREN" == "True" ]]; then _pass; else _fail "folder has no children array"; fi
teardown

t "queries always have expr and suppliers fields"
setup fmt; vdir init; vdir mkq myq
HAS=$(python3 -c "
import json; d=json.load(open('.vdir.json'))
q=[c for c in d['root']['children'] if c['name']=='myq'][0]
print('expr' in q and 'suppliers' in q)
")
if [[ "$HAS" == "True" ]]; then _pass; else _fail "query missing expr or suppliers"; fi
teardown

t "references always have target and target_type"
setup fmt
vdir init
echo x > /tmp/vdir_fmt_ref.txt
vdir ln /tmp/vdir_fmt_ref.txt myref
HAS=$(python3 -c "
import json; d=json.load(open('.vdir.json'))
r=[c for c in d['root']['children'] if c['name']=='myref'][0]
print('target' in r and 'target_type' in r)
")
if [[ "$HAS" == "True" ]]; then _pass; else _fail "reference missing target or target_type"; fi
rm -f /tmp/vdir_fmt_ref.txt
teardown

t "json valid after mkdir"
setup fmt; vdir init; vdir mkdir A
assert_json_valid ".vdir.json"
teardown

t "json valid after mkq"
setup fmt; vdir init; vdir mkq myq
assert_json_valid ".vdir.json"
teardown

t "json valid after ln"
setup fmt
vdir init
echo x > /tmp/vdir_fmt_ln.txt
vdir ln /tmp/vdir_fmt_ln.txt myref
assert_json_valid ".vdir.json"
rm -f /tmp/vdir_fmt_ln.txt
teardown

t "json valid after rm"
setup fmt; vdir init; vdir mkdir A; vdir mkdir B; vdir rm A
assert_json_valid ".vdir.json"
teardown

t "json valid after mv rename"
setup fmt; vdir init; vdir mkdir A; vdir mv A B
assert_json_valid ".vdir.json"
teardown

t "json valid after mv move"
setup fmt; vdir init; vdir mkdir dest; vdir mkdir item; vdir mv item dest
assert_json_valid ".vdir.json"
teardown

t "json valid after set"
setup fmt; vdir init; vdir mkq myq; vdir set myq cmd:bash "echo x"
assert_json_valid ".vdir.json"
teardown

t "json valid after cd (marker only, json untouched)"
setup fmt; vdir init; vdir mkdir A; vdir cd A
assert_json_valid ".vdir.json"
teardown

t "marker file has no extra whitespace except trailing newline"
setup fmt; vdir init; vdir mkdir A; vdir cd A
MARKER=$(cat .vdir-marker)
if [[ "$MARKER" == "~/A" ]]; then _pass; else _fail "marker='$MARKER'"; fi
teardown

summary
