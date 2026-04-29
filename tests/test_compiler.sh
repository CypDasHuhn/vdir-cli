#!/usr/bin/env bash
source "$(dirname "$0")/harness.sh"

echo "=== compiler ==="

# Build a fake compiler container for testing
FAKE_CONTAINER="/tmp/vdir_fake_container.sh"
cat > "$FAKE_CONTAINER" << 'EOF'
#!/usr/bin/env bash
CMD="$1"
shift

case "$CMD" in
  list)
    echo "testcomp"
    echo "othercomp"
    ;;
  run)
    COMPILER="$1"; shift
    ARGS="$*"
    case "$COMPILER" in
      testcomp)
        echo "bash: echo /tmp/testcomp_${ARGS}.txt"
        echo "nu: echo /tmp/testcomp_${ARGS}.txt"
        ;;
      othercomp)
        echo "bash: echo /tmp/othercomp.txt"
        ;;
      *)
        echo "Unknown compiler: $COMPILER" >&2
        exit 1
        ;;
    esac
    ;;
  *)
    echo "Unknown command: $CMD" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$FAKE_CONTAINER"

# ── compiler list ─────────────────────────────────────────────────────────────

t "compiler list with no containers shows nothing or empty"
setup compiler
vdir init
vdir compiler list
assert_exit_ok
teardown

t "compiler add registers a container"
setup compiler
vdir init
vdir compiler add "$FAKE_CONTAINER"
assert_exit_ok
teardown

t "compiler list shows compilers from registered container"
setup compiler
vdir init
vdir compiler add "$FAKE_CONTAINER"
vdir compiler list
assert_exit_ok
assert_either_contains "testcomp"
assert_either_contains "othercomp"
teardown

t "compiler list shows container path"
setup compiler
vdir init
vdir compiler add "$FAKE_CONTAINER"
vdir compiler list
assert_either_contains "$FAKE_CONTAINER"
teardown

t "compiler add nonexistent path errors"
setup compiler
vdir init
vdir compiler add /nonexistent/path/container.sh
assert_exit_fail
teardown

t "compiler add same path twice is idempotent"
setup compiler
vdir init
vdir compiler add "$FAKE_CONTAINER"
vdir compiler add "$FAKE_CONTAINER"
assert_exit_ok
teardown

# ── compiler test ─────────────────────────────────────────────────────────────

t "compiler test runs compiler and shows output"
setup compiler
vdir init
vdir compiler add "$FAKE_CONTAINER"
vdir compiler test testcomp myarg
assert_exit_ok
assert_either_contains "bash"
assert_either_contains "myarg"
teardown

t "compiler test unknown compiler errors"
setup compiler
vdir init
vdir compiler add "$FAKE_CONTAINER"
vdir compiler test nosuchcompiler123
assert_exit_fail
teardown

t "compiler test passes args to compiler"
setup compiler
vdir init
vdir compiler add "$FAKE_CONTAINER"
vdir compiler test testcomp specialarg
assert_exit_ok
assert_either_contains "specialarg"
teardown

# ── compiler rebuild ──────────────────────────────────────────────────────────

t "compiler rebuild refreshes cache"
setup compiler
vdir init
vdir compiler add "$FAKE_CONTAINER"
vdir compiler rebuild
assert_exit_ok
teardown

t "compiler rebuild: compilers available after rebuild"
setup compiler
vdir init
vdir compiler add "$FAKE_CONTAINER"
vdir compiler rebuild
vdir compiler list
assert_either_contains "testcomp"
teardown

# ── mkq with compiler ─────────────────────────────────────────────────────────

t "mkq with compiler creates query using compiler output"
setup compiler
vdir init
vdir compiler add "$FAKE_CONTAINER"
vdir compiler rebuild
vdir mkq myq testcomp myarg
assert_exit_ok
BASH_CMD=$(python3 -c "
import json; d=json.load(open('.vdir.json'))
q=[c for c in d['root']['children'] if c['name']=='myq'][0]
print(q['suppliers']['_default']['cmd']['bash'])
")
if echo "$BASH_CMD" | grep -q "myarg"; then _pass; else _fail "compiler args not in cmd: $BASH_CMD"; fi
teardown

t "mkq stores compiler name in supplier"
setup compiler
vdir init
vdir compiler add "$FAKE_CONTAINER"
vdir compiler rebuild
vdir mkq myq testcomp myarg
assert_exit_ok
COMP=$(python3 -c "
import json; d=json.load(open('.vdir.json'))
q=[c for c in d['root']['children'] if c['name']=='myq'][0]
print(q['suppliers']['_default']['compiler'])
")
if [[ "$COMP" == "testcomp" ]]; then _pass; else _fail "compiler name not stored, got: $COMP"; fi
teardown

t "mkq with unknown compiler errors with helpful message"
setup compiler
vdir init
vdir mkq myq nosuchcompiler123 args
assert_exit_fail
assert_either_contains "not found"
teardown

# ── container protocol parsing ────────────────────────────────────────────────

t "container list output: multiple compilers parsed"
setup compiler
vdir init
vdir compiler add "$FAKE_CONTAINER"
vdir compiler list
COMBINED="$STDERR$STDOUT"
if echo "$COMBINED" | grep -q "testcomp" && echo "$COMBINED" | grep -q "othercomp"; then _pass; else _fail "not all compilers listed: $COMBINED"; fi
teardown

t "container run output: colon in command value does not break parsing"
TRICKY_CONTAINER="/tmp/vdir_tricky_container.sh"
cat > "$TRICKY_CONTAINER" << 'SCRIPT'
#!/usr/bin/env bash
case "$1" in
  list) echo "trickcomp" ;;
  run)  echo "bash: rg -l 'foo:bar' ." ;;
esac
SCRIPT
chmod +x "$TRICKY_CONTAINER"
setup compiler
vdir init
vdir compiler add "$TRICKY_CONTAINER"
vdir compiler rebuild
vdir mkq myq trickcomp
CMD=$(python3 -c "
import json; d=json.load(open('.vdir.json'))
q=[c for c in d['root']['children'] if c['name']=='myq'][0]
print(q['suppliers']['_default']['cmd']['bash'])
")
# Should be the full command including the colon-containing part
if [[ "$CMD" == "rg -l 'foo:bar' ." ]]; then _pass; else _fail "colon in cmd not handled, got: $CMD"; fi
rm -f "$TRICKY_CONTAINER"
teardown

rm -f "$FAKE_CONTAINER"

summary
