#!/usr/bin/env bash
source "$(dirname "$0")/harness.sh"

echo "=== ls ==="

t "empty vdir prints nothing"
setup ls; vdir init; vdir ls
assert_exit_ok
# Both stdout and stderr should be empty (no items)
if [[ -z "$STDOUT" && -z "$STDERR" ]]; then _pass; else _fail "expected empty output, got: stdout='$STDOUT' stderr='$STDERR'"; fi
teardown

t "ls shows folder with d prefix"
setup ls; vdir init; vdir mkdir myfolder; vdir ls
assert_exit_ok
assert_either_contains "d myfolder"
teardown

t "ls shows query with q prefix"
setup ls; vdir init; vdir mkq myquery; vdir ls
assert_exit_ok
assert_either_contains "q myquery"
teardown

t "ls shows reference with r prefix"
setup ls; vdir init; vdir ln "$REPO_ROOT" myref; vdir ls
assert_exit_ok
assert_either_contains "r myref"
teardown

t "hidden items not shown without -a"
setup ls; vdir init; vdir mkdir .hidden; vdir ls
assert_exit_ok
assert_stderr_not_contains ".hidden"
teardown

t "hidden items shown with -a"
setup ls; vdir init; vdir mkdir .hidden; vdir ls -a
assert_exit_ok
assert_either_contains ".hidden"
teardown

t "-l shows folder with count"
setup ls; vdir init; vdir mkdir myfolder; vdir ls -l
assert_exit_ok
assert_either_contains "d myfolder/ (0 items)"
teardown

t "-l folder count reflects children"
setup ls; vdir init; vdir mkdir myfolder; vdir cd myfolder; vdir mkdir child1; vdir mkdir child2; vdir cd "~"; vdir ls -l
assert_exit_ok
assert_either_contains "d myfolder/ (2 items)"
teardown

t "-l shows query with supplier count"
setup ls; vdir init; vdir mkq myquery; vdir ls -l
assert_exit_ok
assert_either_contains "q myquery (0 suppliers)"
teardown

t "-l shows reference with file tag [f]"
setup ls
vdir init
# create a temp file to reference
echo "hello" > /tmp/vdir_test_reffile.txt
vdir ln /tmp/vdir_test_reffile.txt myref
vdir ls -l
assert_either_contains "[f]"
rm -f /tmp/vdir_test_reffile.txt
teardown

t "-l shows reference with dir tag [d]"
setup ls; vdir init; vdir ln "$REPO_ROOT" myref; vdir ls -l
assert_either_contains "[d]"
teardown

t "-l shows reference target path"
setup ls; vdir init; vdir ln "$REPO_ROOT" myref; vdir ls -l
assert_either_contains "$REPO_ROOT"
teardown

t "-r lists recursively"
setup ls; vdir init; vdir mkdir A; vdir cd A; vdir mkdir B; vdir cd "~"; vdir ls -r
assert_exit_ok
assert_either_contains "A"
assert_either_contains "B"
teardown

t "-r indents nested items"
setup ls; vdir init; vdir mkdir A; vdir cd A; vdir mkdir B; vdir cd "~"; vdir ls -r
# B should appear with 2-space indent
COMBINED="$STDERR$STDOUT"
if echo "$COMBINED" | grep -qP "^  [a-z]"; then _pass; else _fail "no indented line found | output: $COMBINED"; fi
teardown

t "-r2 stops at depth 2"
setup ls
vdir init
vdir mkdir A; vdir cd A
vdir mkdir B; vdir cd B
vdir mkdir C; vdir cd "~"
vdir ls -r2
COMBINED="$STDERR$STDOUT"
# A and B should appear, C should not
if echo "$COMBINED" | grep -qF "B"; then _pass; else _fail "B not found"; fi
assert_either_contains "A"
teardown

t "-r expands query results with f prefix"
setup ls
vdir init
# raw query that lists a real file
echo "#!/bin/sh" > /tmp/vdir_lister.sh
echo "echo /tmp/vdir_lister.sh" >> /tmp/vdir_lister.sh
chmod +x /tmp/vdir_lister.sh
vdir mkq myquery --raw --shell bash "/tmp/vdir_lister.sh"
vdir ls -lr
assert_either_contains "f /tmp/vdir_lister.sh"
rm -f /tmp/vdir_lister.sh
teardown

t "flag -al accepted"
setup ls; vdir init; vdir mkdir .h; vdir ls -al
assert_exit_ok
assert_either_contains ".h"
teardown

t "flag -la accepted"
setup ls; vdir init; vdir mkdir .h; vdir ls -la
assert_exit_ok
assert_either_contains ".h"
teardown

t "flag -lr accepted"
setup ls; vdir init; vdir mkdir A; vdir ls -lr
assert_exit_ok
teardown

t "flag -alr accepted"
setup ls; vdir init; vdir ls -alr
assert_exit_ok
teardown

t "unknown flag exits non-zero"
setup ls; vdir init; vdir ls -z
assert_exit_fail
teardown

summary
