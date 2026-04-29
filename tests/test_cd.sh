#!/usr/bin/env bash
source "$(dirname "$0")/harness.sh"

echo "=== cd ==="

t "cd ~ moves marker to root"
setup cd; vdir init; vdir mkdir A; vdir cd A; vdir cd "~"
assert_exit_ok
assert_file_contains ".vdir-marker" "~"
teardown

t "cd <name> moves marker to child folder"
setup cd; vdir init; vdir mkdir A; vdir cd A
assert_exit_ok
assert_file_contains ".vdir-marker" "~/A"
teardown

t "cd <path> multi-segment"
setup cd; vdir init; vdir mkdir A; vdir cd A; vdir mkdir B; vdir cd "~"; vdir cd A/B
assert_exit_ok
assert_file_contains ".vdir-marker" "~/A/B"
teardown

t "cd ~/foo absolute from any position"
setup cd; vdir init; vdir mkdir A; vdir cd A; vdir mkdir B; vdir cd B; vdir cd "~/A"
assert_exit_ok
assert_file_contains ".vdir-marker" "~/A"
teardown

t "cd .. moves to parent"
setup cd; vdir init; vdir mkdir A; vdir cd A
assert_exit_ok
vdir cd ".."
assert_exit_ok
assert_file_contains ".vdir-marker" "~"
teardown

t "cd ../sibling moves to sibling"
setup cd; vdir init; vdir mkdir A; vdir mkdir B; vdir cd A; vdir cd "../B"
assert_exit_ok
assert_file_contains ".vdir-marker" "~/B"
teardown

t "cd . keeps marker"
setup cd; vdir init; vdir mkdir A; vdir cd A; vdir cd "."
assert_exit_ok
assert_file_contains ".vdir-marker" "~/A"
teardown

t "cd nonexistent errors"
setup cd; vdir init; vdir cd nosuchfolder
assert_exit_fail
assert_either_contains "not found"
teardown

t "cd nonexistent leaves marker unchanged"
setup cd; vdir init; vdir mkdir A; vdir cd A; vdir cd nosuchfolder
cat .vdir-marker | grep -qF "~/A"
if [[ $? -eq 0 ]]; then t "cd nonexistent leaves marker unchanged"; _pass; else _fail "marker was changed"; fi
teardown

t "cd to a query errors"
setup cd; vdir init; vdir mkq myq; vdir cd myq
assert_exit_fail
teardown

t "cd to a reference errors"
setup cd; vdir init; vdir ln "$REPO_ROOT" myref; vdir cd myref
assert_exit_fail
teardown

t "cd .. at root errors"
setup cd; vdir init; vdir cd ".."
assert_exit_fail
teardown

t "deep path cd a/b/c/d"
setup cd
vdir init
vdir mkdir a; vdir cd a
vdir mkdir b; vdir cd b
vdir mkdir c; vdir cd c
vdir mkdir d; vdir cd "~"
vdir cd a/b/c/d
assert_exit_ok
assert_file_contains ".vdir-marker" "~/a/b/c/d"
teardown

t "marker written as resolved path not raw input"
setup cd; vdir init; vdir mkdir A; vdir cd "~/A"
assert_file_contains ".vdir-marker" "~/A"
assert_file_not_contains ".vdir-marker" "~/A/"
teardown

summary
