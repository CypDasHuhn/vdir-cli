#!/usr/bin/env bash
# Test harness — source this from every test file.
# Provides: setup, teardown, assert_*, run helpers.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VDIR="$REPO_ROOT/zig-out/bin/vdir_cli"
TMPBASE=$(mktemp -d)

PASS=0
FAIL=0
CURRENT_TEST=""

# ── lifecycle ────────────────────────────────────────────────────────────────

setup() {
    local name="${1:-test}"
    TEST_DIR=$(mktemp -d "$TMPBASE/${name}.XXXXXX")
    cd "$TEST_DIR" || exit 1
}

teardown() {
    cd "$REPO_ROOT" || exit 1
    rm -rf "$TEST_DIR"
}

cleanup_all() {
    rm -rf "$TMPBASE"
}
trap cleanup_all EXIT

# ── run helpers ──────────────────────────────────────────────────────────────

# Run vdir; captures stdout→STDOUT, stderr→STDERR, exit code→STATUS
vdir() {
    STDOUT=$("$VDIR" "$@" 2>/tmp/vdir_harness_stderr.$$)
    STATUS=$?
    STDERR=$(cat /tmp/vdir_harness_stderr.$$)
    rm -f /tmp/vdir_harness_stderr.$$
}

# Run vdir with stdin provided (for confirmation prompts)
vdir_stdin() {
    local input="$1"; shift
    STDOUT=$(echo "$input" | "$VDIR" "$@" 2>/tmp/vdir_harness_stderr.$$)
    STATUS=$?
    STDERR=$(cat /tmp/vdir_harness_stderr.$$)
    rm -f /tmp/vdir_harness_stderr.$$
}

# ── assertions ───────────────────────────────────────────────────────────────

_pass() {
    PASS=$((PASS + 1))
    echo "  PASS  $CURRENT_TEST"
}

_fail() {
    FAIL=$((FAIL + 1))
    echo "  FAIL  $CURRENT_TEST"
    echo "        $*"
}

t() {
    CURRENT_TEST="$1"
}

assert_exit_ok() {
    if [[ $STATUS -eq 0 ]]; then
        _pass
    else
        _fail "expected exit 0, got $STATUS | stderr: $STDERR"
    fi
}

assert_exit_fail() {
    if [[ $STATUS -ne 0 ]]; then
        _pass
    else
        _fail "expected non-zero exit, got 0 | stderr: $STDERR"
    fi
}

assert_stderr_contains() {
    local want="$1"
    if echo "$STDERR" | grep -qF "$want"; then
        _pass
    else
        _fail "stderr did not contain '$want' | stderr: $STDERR"
    fi
}

assert_stderr_not_contains() {
    local want="$1"
    if ! echo "$STDERR" | grep -qF "$want"; then
        _pass
    else
        _fail "stderr should not contain '$want' | stderr: $STDERR"
    fi
}

assert_stdout_contains() {
    local want="$1"
    if echo "$STDOUT" | grep -qF "$want"; then
        _pass
    else
        _fail "stdout did not contain '$want' | stdout: $STDOUT"
    fi
}

assert_either_contains() {
    local want="$1"
    if echo "$STDOUT$STDERR" | grep -qF "$want"; then
        _pass
    else
        _fail "neither stdout nor stderr contained '$want'"
    fi
}

assert_file_exists() {
    local f="$1"
    if [[ -e "$f" ]]; then
        _pass
    else
        _fail "file does not exist: $f"
    fi
}

assert_file_not_exists() {
    local f="$1"
    if [[ ! -e "$f" ]]; then
        _pass
    else
        _fail "file should not exist: $f"
    fi
}

assert_file_contains() {
    local f="$1" want="$2"
    if grep -qF "$want" "$f" 2>/dev/null; then
        _pass
    else
        _fail "file '$f' did not contain '$want'"
    fi
}

assert_file_not_contains() {
    local f="$1" want="$2"
    if ! grep -qF "$want" "$f" 2>/dev/null; then
        _pass
    else
        _fail "file '$f' should not contain '$want'"
    fi
}

assert_json_valid() {
    local f="${1:-.vdir.json}"
    if python3 -c "import json,sys; json.load(open('$f'))" 2>/dev/null; then
        _pass
    else
        _fail "invalid JSON in $f"
    fi
}

assert_json_field() {
    local f="$1" expr="$2" want="$3"
    local got
    got=$(python3 -c "import json; d=json.load(open('$f')); print($expr)" 2>/dev/null)
    if [[ "$got" == "$want" ]]; then
        _pass
    else
        _fail "json[$expr]: expected '$want', got '$got'"
    fi
}

assert_output_line() {
    # Check combined stderr+stdout (since current impl uses debug print → stderr)
    local want="$1"
    if echo "$STDERR$STDOUT" | grep -qF "$want"; then
        _pass
    else
        _fail "output did not contain line '$want' | stderr: $STDERR"
    fi
}

# ── summary ──────────────────────────────────────────────────────────────────

summary() {
    local total=$((PASS + FAIL))
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ${PASS}/${total} passed"
    if [[ $FAIL -gt 0 ]]; then
        echo "  ${FAIL} failed"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        exit 1
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Shared: init a vdir and optionally build a small tree
init_vdir() {
    vdir init
}

# Build a sample tree: folder A, folder B inside A, a query, a reference
build_sample_tree() {
    local ref_target="${1:-$REPO_ROOT}"
    vdir init
    vdir mkdir A
    vdir cd A
    vdir mkdir B
    vdir cd "~"
    vdir mkq myquery
    vdir ln "$ref_target" myref
}
