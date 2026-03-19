#!/bin/bash
# Demo compiler container for testing

case "$1" in
    list)
        echo "grep-files"
        echo "find-todos"
        ;;
    run)
        compiler="$2"
        shift 2
        args="$*"

        case "$compiler" in
            grep-files)
                echo "bash: grep -rl '$args' ."
                echo "nu: rg -l '$args' (pwd)"
                ;;
            find-todos)
                echo "bash: grep -rn 'TODO\\|FIXME' ."
                echo "nu: rg 'TODO|FIXME' (pwd)"
                ;;
            *)
                echo "Unknown compiler: $compiler" >&2
                exit 1
                ;;
        esac
        ;;
    *)
        echo "Usage: $0 list | run <compiler> [args]" >&2
        exit 1
        ;;
esac
