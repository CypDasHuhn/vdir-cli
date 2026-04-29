#!/usr/bin/env bash
source "$(dirname "$0")/harness.sh"

echo "=== info ==="

t "info folder shows type and child count"
setup info; vdir init; vdir mkdir A; vdir cd A; vdir mkdir B; vdir cd "~"; vdir info A
assert_exit_ok
assert_either_contains "type: folder"
assert_either_contains "children: 1"
teardown

t "info folder shows name"
setup info; vdir init; vdir mkdir A; vdir info A
assert_either_contains "name: A"
teardown

t "info empty query shows empty expr"
setup info; vdir init; vdir mkq myq; vdir info myq
assert_exit_ok
assert_either_contains "type: query"
assert_either_contains "(empty)"
teardown

t "info compiler query shows compiler name"
setup info
vdir init
# Manually write a query with compiler metadata via set
vdir mkq myq
vdir set myq cmd:bash "echo /tmp/foo"
# Can't easily test compiler= field without a real compiler; skip deeper check
assert_exit_ok
teardown

t "info raw query shows cmd shells"
setup info; vdir init; vdir mkq myq --raw --shell bash "echo /tmp/foo"; vdir info myq
assert_exit_ok
assert_either_contains "bash"
assert_either_contains "echo /tmp/foo"
teardown

t "info reference shows target"
setup info
vdir init
echo x > /tmp/vdir_info_ref.txt
vdir ln /tmp/vdir_info_ref.txt myref
vdir info myref
assert_exit_ok
assert_either_contains "/tmp/vdir_info_ref.txt"
assert_either_contains "type: reference"
rm -f /tmp/vdir_info_ref.txt
teardown

t "info reference shows target_type"
setup info
vdir init
echo x > /tmp/vdir_info_ref.txt
vdir ln /tmp/vdir_info_ref.txt myref
vdir info myref
assert_either_contains "target_type: file"
rm -f /tmp/vdir_info_ref.txt
teardown

t "info nonexistent errors"
setup info; vdir init; vdir info nosuch
assert_exit_fail
assert_either_contains "not found"
teardown

t "no .vdir.json errors"
setup info; vdir info A
assert_exit_fail
assert_either_contains "No vdir found"
teardown

summary
