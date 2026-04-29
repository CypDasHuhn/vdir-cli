#!/usr/bin/env bash
source "$(dirname "$0")/harness.sh"

echo "=== query system ==="

# Helper: create a query with a bash command that lists specific files
make_supplier() {
    local query_name="$1" sup_name="$2" files="$3"
    # write a script that echoes each file
    local script="/tmp/vdir_q_${sup_name}.sh"
    printf '#!/bin/sh\n' > "$script"
    for f in $files; do printf 'echo %s\n' "$f" >> "$script"; done
    chmod +x "$script"

    if [[ "$sup_name" == "_default" ]]; then
        vdir set "$query_name" cmd:bash "$script"
        vdir set "$query_name" expr "_default"
    else
        vdir set "$query_name" supplier "$sup_name" cmd "$script"
        vdir set "$query_name" supplier "$sup_name" scope "."
    fi
}

cleanup_scripts() {
    rm -f /tmp/vdir_q_*.sh
}

# ── output parsing ────────────────────────────────────────────────────────────

t "command output lines become file paths"
setup query
vdir init
vdir mkq myq --raw --shell bash "printf '/tmp/a.txt\n/tmp/b.txt\n'"
vdir ls -lr
assert_either_contains "/tmp/a.txt"
assert_either_contains "/tmp/b.txt"
teardown

t "trailing newline in output does not produce empty path"
setup query
vdir init
vdir mkq myq --raw --shell bash "printf '/tmp/a.txt\n\n'"
vdir ls -lr
COMBINED="$STDERR$STDOUT"
# Should contain /tmp/a.txt but not a blank f line
if echo "$COMBINED" | grep -qP '^  f $'; then _fail "blank path in output"; else _pass; fi
teardown

t "blank lines in output are ignored"
setup query
vdir init
vdir mkq myq --raw --shell bash "printf '\n\n/tmp/c.txt\n\n'"
vdir ls -lr
assert_either_contains "/tmp/c.txt"
teardown

t "whitespace-only lines are ignored"
setup query
vdir init
vdir mkq myq --raw --shell bash "printf '   \n/tmp/d.txt\n   \n'"
vdir ls -lr
assert_either_contains "/tmp/d.txt"
teardown

t "duplicate paths deduplicated within one supplier"
setup query
vdir init
vdir mkq myq --raw --shell bash "printf '/tmp/same.txt\n/tmp/same.txt\n'"
vdir ls -lr
COMBINED="$STDERR$STDOUT"
COUNT=$(echo "$COMBINED" | grep -cF "/tmp/same.txt" || true)
if [[ "$COUNT" -eq 1 ]]; then _pass; else _fail "expected 1 occurrence, got $COUNT"; fi
teardown

# ── expression language ───────────────────────────────────────────────────────

t "single supplier name evaluates to its file set"
setup query
vdir init
vdir mkq myq
make_supplier myq _default "/tmp/expr_a.txt"
vdir ls -lr
assert_either_contains "/tmp/expr_a.txt"
cleanup_scripts
teardown

t "empty expr unions all suppliers"
setup query
vdir init
vdir mkq myq
make_supplier myq _default "/tmp/expr_x.txt"
vdir set myq expr ""
vdir ls -lr
assert_either_contains "/tmp/expr_x.txt"
cleanup_scripts
teardown

t "or expression unions two supplier sets"
setup query
vdir init
vdir mkq myq

# supplier a: only a.txt
local_script_a="/tmp/vdir_q_supa.sh"
printf '#!/bin/sh\necho /tmp/or_a.txt\n' > "$local_script_a"; chmod +x "$local_script_a"
vdir set myq supplier supa cmd "$local_script_a"
vdir set myq supplier supa scope "."

# supplier b: only b.txt
local_script_b="/tmp/vdir_q_supb.sh"
printf '#!/bin/sh\necho /tmp/or_b.txt\n' > "$local_script_b"; chmod +x "$local_script_b"
vdir set myq supplier supb cmd "$local_script_b"
vdir set myq supplier supb scope "."

vdir set myq expr "supa or supb"
vdir ls -lr
assert_either_contains "/tmp/or_a.txt"
assert_either_contains "/tmp/or_b.txt"
rm -f "$local_script_a" "$local_script_b"
teardown

t "and expression intersects two supplier sets"
setup query
vdir init
vdir mkq myq

# supplier a: a.txt and shared.txt
local_script_a="/tmp/vdir_q_and_a.sh"
printf '#!/bin/sh\necho /tmp/and_a.txt\necho /tmp/and_shared.txt\n' > "$local_script_a"; chmod +x "$local_script_a"
vdir set myq supplier supa cmd "$local_script_a"
vdir set myq supplier supa scope "."

# supplier b: b.txt and shared.txt
local_script_b="/tmp/vdir_q_and_b.sh"
printf '#!/bin/sh\necho /tmp/and_b.txt\necho /tmp/and_shared.txt\n' > "$local_script_b"; chmod +x "$local_script_b"
vdir set myq supplier supb cmd "$local_script_b"
vdir set myq supplier supb scope "."

vdir set myq expr "supa and supb"
vdir ls -lr
COMBINED="$STDERR$STDOUT"
# Only shared.txt should appear
if echo "$COMBINED" | grep -qF "/tmp/and_shared.txt"; then _pass; else _fail "shared file not in and result | $COMBINED"; fi
if echo "$COMBINED" | grep -qF "/tmp/and_a.txt"; then _fail "exclusive file leaked into and result"; else _pass; fi
rm -f "$local_script_a" "$local_script_b"
teardown

t "not expression subtracts from universe"
setup query
vdir init
vdir mkq myq

local_script_all="/tmp/vdir_q_not_all.sh"
printf '#!/bin/sh\necho /tmp/not_x.txt\necho /tmp/not_y.txt\n' > "$local_script_all"; chmod +x "$local_script_all"
vdir set myq supplier all cmd "$local_script_all"
vdir set myq supplier all scope "."

local_script_exc="/tmp/vdir_q_not_exc.sh"
printf '#!/bin/sh\necho /tmp/not_x.txt\n' > "$local_script_exc"; chmod +x "$local_script_exc"
vdir set myq supplier exc cmd "$local_script_exc"
vdir set myq supplier exc scope "."

vdir set myq expr "not exc"
vdir ls -lr
COMBINED="$STDERR$STDOUT"
if echo "$COMBINED" | grep -qF "/tmp/not_y.txt"; then _pass; else _fail "expected y.txt in not result"; fi
if echo "$COMBINED" | grep -qF "/tmp/not_x.txt"; then _fail "excluded file still present"; else _pass; fi
rm -f "$local_script_all" "$local_script_exc"
teardown

t "unknown supplier name in expression errors"
setup query
vdir init
vdir mkq myq
vdir set myq expr "nosuchsup"
vdir ls -lr
# Should produce an error, not silently succeed
assert_either_contains "unknown"
teardown

t "and of two non-overlapping sets is empty"
setup query
vdir init
vdir mkq myq

local_a="/tmp/vdir_q_empty_a.sh"
printf '#!/bin/sh\necho /tmp/empty_a.txt\n' > "$local_a"; chmod +x "$local_a"
vdir set myq supplier supa cmd "$local_a"
vdir set myq supplier supa scope "."

local_b="/tmp/vdir_q_empty_b.sh"
printf '#!/bin/sh\necho /tmp/empty_b.txt\n' > "$local_b"; chmod +x "$local_b"
vdir set myq supplier supb cmd "$local_b"
vdir set myq supplier supb scope "."

vdir set myq expr "supa and supb"
vdir ls -lr
COMBINED="$STDERR$STDOUT"
# No results should appear (or explicit "no results" marker)
if echo "$COMBINED" | grep -qF "/tmp/empty_a.txt"; then _fail "unexpected result a"; else _pass; fi
if echo "$COMBINED" | grep -qF "/tmp/empty_b.txt"; then _fail "unexpected result b"; else _pass; fi
rm -f "$local_a" "$local_b"
teardown

# ── shell selection ────────────────────────────────────────────────────────────

t "command runs in scope directory when scope is a path"
setup query
vdir init
vdir mkq myq
# Command prints pwd; scope set to /tmp
local_s="/tmp/vdir_q_scope.sh"
printf '#!/bin/sh\npwd\n' > "$local_s"; chmod +x "$local_s"
vdir set myq cmd:bash "$local_s"
vdir set myq scope /tmp
vdir ls -lr
assert_either_contains "/tmp"
rm -f "$local_s"
teardown

t "no matching shell returns empty set without error"
setup query
vdir init
# Create query with only a fake shell command; no such shell in PATH
vdir mkq myq
python3 -c "
import json
d = json.load(open('.vdir.json'))
q = [c for c in d['root']['children'] if c['name']=='myq'][0]
q['suppliers'] = {'_default': {'scope': '.', 'cmd': {'fakeshell999': 'echo /tmp/x'}}}
q['expr'] = '_default'
json.dump(d, open('.vdir.json','w'), indent=2)
"
vdir ls -lr
# Should exit ok (empty result), not crash
assert_exit_ok
teardown

summary
