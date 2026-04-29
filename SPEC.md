# vdir — System Specification & Test Plan

This document describes what vdir is, what it must do, and every behavior that
needs to be verified. It is the basis for generating unit and integration tests.

The Neovim plugin counterpart is specified in `~/repos/vdir.nvim/SPEC.md`.

---

## What is vdir?

vdir is a **virtual directory system** for organizing files that are scattered
across a real filesystem. Instead of relying on where things actually live on
disk, you build a named, navigable tree that reflects how you think about your
work. That tree contains three kinds of items:

- **Folder** — a named container for other items (folders, queries, references).
  Has no counterpart on disk. Pure organizational structure.
- **Query** — a saved search. When expanded, it runs one or more shell commands
  and collects the file paths they emit. The result is a live, dynamic set of
  files matching some criteria.
- **Reference** — a named alias pointing to a real file or directory anywhere on
  disk.

You navigate the virtual tree with a **marker** — a pointer to your current
position inside the tree, analogous to a working directory. The marker persists
between sessions.

The tree is stored in `.vdir.json` (committable, shared). The marker is stored
in `.vdir-marker` (gitignored, personal).

vdir.nvim is a Neovim plugin that renders the vdir tree as a panel in the
editor, using neo-tree as the UI framework. All mutations go through the CLI;
the plugin owns only the visual presentation and user interaction.

---

## vdir-cli — Command Specification

### General rules

- Every command that mutates state reads the current `.vdir.json`, applies the
  change, and writes it back atomically before exiting.
- Every command that needs the marker reads `.vdir-marker` if it exists. If the
  file is missing, the marker defaults to `~` (root of the virtual tree).
- If `.vdir.json` is not found in the current directory, every command except
  `init` must exit with a non-zero status and print a clear error message.
- All output intended for human consumption goes to stderr. Output intended for
  machine consumption (query results, `ls` lines parsed by the plugin) goes to
  stdout.
- Exit code 0 = success. Exit code non-zero = failure.

### Path syntax

Every path argument in a vdir command follows these rules:

| Pattern | Meaning |
|---------|---------|
| `~` | Root of the virtual tree |
| `~/foo/bar` | Absolute path from root |
| `foo` | Relative to current marker |
| `foo/bar` | Relative, multiple segments |
| `..` | Parent of current marker |
| `../foo` | Sibling of current marker |
| `.` | Current marker (no-op segment) |

Attempting to `..` above root is an error.

---

### `vdir init`

Initialize a new vdir in the current directory.

**Creates:**
- `.vdir.json` with an empty root folder
- Does NOT create `.vdir-marker` (marker starts at `~` implicitly)

**Behavior:**
- If `.vdir.json` already exists, exit with an error. Do not overwrite.
- The initial `.vdir.json` must be valid JSON with a root folder and empty
  children array.

**Tests:**
- [ ] Creates `.vdir.json` in current directory
- [ ] `.vdir.json` is valid JSON with `root.children = []`
- [ ] Running `init` twice prints an error and does not overwrite
- [ ] Does not create `.vdir-marker`

---

### `vdir pwd`

Print the current marker path.

**Output:** The current marker string (e.g. `~` or `~/foo/bar`), one line.

**Tests:**
- [ ] With no marker file, prints `~`
- [ ] After `cd foo`, prints `~/foo`
- [ ] Output is exactly the marker string with no trailing whitespace except a
  newline

---

### `vdir cd <path>`

Move the marker to a new position in the virtual tree.

**Behavior:**
- Resolves `<path>` relative to the current marker using the path rules above.
- Validates that the resolved path exists and is a folder (not a query or reference).
- Saves the resolved path to `.vdir-marker`.
- Prints the new marker on success.

**Tests:**
- [ ] `cd ~` moves marker to root
- [ ] `cd foo` moves marker to `~/foo` when at root
- [ ] `cd foo/bar` moves marker to `~/foo/bar`
- [ ] `cd ~/foo` moves marker to `~/foo` regardless of current position
- [ ] `cd ..` moves marker to parent
- [ ] `cd ../sibling` moves marker to sibling folder
- [ ] `cd .` keeps marker unchanged
- [ ] `cd` to a nonexistent name errors, marker unchanged
- [ ] `cd` to a query errors (queries are not navigable)
- [ ] `cd` to a reference errors (references are not navigable)
- [ ] `cd ..` at root errors (cannot go above root)
- [ ] Deep path: `cd a/b/c/d` works when the hierarchy exists
- [ ] Marker file is written with the resolved (not raw) path

---

### `vdir ls [flags]`

List items at the current marker.

**Flags:**
- `-a` — include hidden items (names starting with `.`)
- `-l` — long format (shows item type prefix, count/target info)
- `-r` — recursive (expand folders and queries)
- `-rN` — recursive up to N levels deep (e.g. `-r2`)
- Flags may be combined in any order: `-al`, `-la`, `-lr`, `-rl`, `-alr`, etc.

**Long format output lines:**

| Item type | Format |
|-----------|--------|
| Folder | `d <name>/ (<N> items)` |
| Query | `q <name> (<N> suppliers)` |
| Reference (file) | `r <name> -> <target> [f]` |
| Reference (dir) | `r <name> -> <target> [d]` |
| Query result | `f <path>` |

**Short format output lines:**

| Item type | Format |
|-----------|--------|
| Folder | `d <name>` |
| Query | `q <name>` |
| Reference | `r <name>` |

**Indentation:** 2 spaces per depth level when recursive.

**Tests:**
- [ ] Empty marker: prints nothing
- [ ] Lists folders, queries, references at current marker
- [ ] Items with names starting with `.` are hidden without `-a`
- [ ] Items with names starting with `.` appear with `-a`
- [ ] `-l` shows type prefix and metadata for all three item types
- [ ] Folder count in `-l` reflects actual number of direct children
- [ ] Supplier count in `-l` reflects actual number of suppliers on the query
- [ ] Reference shows target path and type tag `[f]` or `[d]` in `-l`
- [ ] `-r` recursively lists all folders and queries
- [ ] `-r2` stops at depth 2
- [ ] `-r0` lists only the immediate marker level (depth 0 = no recursion)
- [ ] Recursion indents each level by 2 spaces
- [ ] `-r` expands queries into their file results (prefixed `f`)
- [ ] Query with no results shows `(no results)` when recursive
- [ ] Flag combinations `-al`, `-lr`, `-alr` all accepted
- [ ] Unknown flag exits with non-zero and prints error
- [ ] Output is parseable by vdir.nvim (line-by-line format is stable)

---

### `vdir mkdir <name>`

Create a new folder at the current marker.

**Behavior:**
- Creates a folder with the given name as a child of the current marker.
- Name must not already exist among the marker's children.
- Saves `.vdir.json`.

**Tests:**
- [ ] Creates a folder visible in `ls`
- [ ] Duplicate name errors, nothing written
- [ ] Folder starts with zero children
- [ ] Name with spaces accepted
- [ ] Name starting with `.` accepted (hidden folder)
- [ ] Name with `/` in it is an error (slash is a path separator)
- [ ] Empty name is an error

---

### `vdir mkq <name> [options] [compiler] [args]`

Create a new query at the current marker.

**Modes:**

| Invocation | Effect |
|-----------|--------|
| `mkq <name>` | Empty query, no suppliers, no expression |
| `mkq <name> <compiler> [args]` | Compiler-based query; runs the compiler to generate shell commands |
| `mkq <name> --raw <cmd>` | Raw query; stores the command string for the default shell |
| `mkq <name> --raw --shell <shell> <cmd>` | Raw query; stores command for the specified shell |

**Compiler mode:** Looks up `<compiler>` in the compiler cache, runs
`<container> run <compiler> [args]`, parses the output as a `shell: command`
map, stores it in the `_default` supplier's `cmd` object.

**Raw mode:** Creates a `_default` supplier whose `cmd` object has exactly one
key: the selected shell mapped to the raw command string.

**Tests:**
- [ ] `mkq foo` creates an empty query with no suppliers
- [ ] `mkq foo ripgrep "TODO"` (with ripgrep compiler available) creates a query
  with shell commands in `_default.cmd`
- [ ] `mkq foo --raw "find . -name '*.rs'"` creates query with default shell command
- [ ] `mkq foo --raw --shell bash "find . -name '*.rs'"` stores under `bash` key
- [ ] `mkq foo --raw --shell nu "glob **/*.rs"` stores under `nu` key
- [ ] Duplicate name at marker errors, nothing written
- [ ] Unknown compiler errors with helpful message
- [ ] Compiler returning empty output errors
- [ ] `--shell` with unknown shell name errors
- [ ] Empty name is an error

---

### `vdir ln <path> [name]`

Create a reference to a real file or directory.

**Behavior:**
- `<path>` must point to an existing file or directory on the real filesystem.
- If `[name]` is omitted, uses the basename of `<path>`.
- Stores `target_type` as `"file"` or `"folder"`.
- Name must not already exist among the marker's children.

**Tests:**
- [ ] `ln /some/file.txt` creates reference named `file.txt`
- [ ] `ln /some/file.txt myalias` creates reference named `myalias`
- [ ] `ln /some/dir` creates reference with `target_type = "folder"`
- [ ] `ln /some/file.txt` creates reference with `target_type = "file"`
- [ ] `ln /nonexistent` errors (path must exist)
- [ ] Duplicate name errors, nothing written
- [ ] Relative path for `<path>` resolved from current working directory
- [ ] Empty name is an error

---

### `vdir rm <name>`

Remove an item from the current marker.

**Behavior:**
- Removes the named item from the marker's children.
- For folders: if the folder has any children, prompts for confirmation (y/n).
  Default is no. `--force` skips the prompt.
- For queries and references: removed immediately, no prompt.

**Tests:**
- [ ] Removes an existing item
- [ ] Removing nonexistent name errors
- [ ] Removing a non-empty folder without `--force` prompts
- [ ] Entering `y` at prompt removes the folder
- [ ] Entering `n` at prompt aborts, nothing written
- [ ] `--force` removes non-empty folder without prompting
- [ ] Removing empty folder requires no confirmation
- [ ] Removing a query removes it directly
- [ ] Removing a reference removes it directly

---

### `vdir mv <name> <destination>`

Rename or move an item.

**Two behaviors depending on `<destination>`:**

| Destination | Behavior |
|-------------|----------|
| Simple name (no `/`) | Rename in place |
| Path ending at an existing folder | Move item into that folder |

**Tests:**
- [ ] `mv foo bar` renames item `foo` to `bar` at current marker
- [ ] `mv foo myfolder` where `myfolder` is a folder: moves `foo` inside `myfolder`
- [ ] `mv foo ~/other` moves item to absolute vdir path
- [ ] `mv foo ../sibling` moves item to a sibling folder
- [ ] Destination name already exists at target: error
- [ ] Source name does not exist: error
- [ ] Moving a folder (with children) preserves all children
- [ ] Moving a query preserves all suppliers and expression
- [ ] Renaming to same name is a no-op (or error — define behavior)

---

### `vdir info <name>`

Print detailed information about an item at the current marker.

**Output for folder:**
```
name: <name>
type: folder
children: <count>
```

**Output for query:**
```
name: <name>
type: query
expr: <expression or "(empty)">
suppliers:
  <supplier_name>:
    scope: <path>
    compiler: <name>   (if compiler-based)
    args: <args>       (if compiler-based with args)
    raw: true          (if raw mode)
    cmd:
      <shell>: <command>
      ...
```

**Output for reference:**
```
name: <name>
type: reference
target: <path>
target_type: <file|folder>
```

**Tests:**
- [ ] Info for folder shows correct child count
- [ ] Info for empty query shows `expr: (empty)` and no suppliers
- [ ] Info for compiler query shows compiler name and args
- [ ] Info for raw query shows `raw: true`
- [ ] Info for query shows all shells and commands in `cmd`
- [ ] Info for reference shows target path and type
- [ ] Nonexistent name errors

---

### `vdir set <name> <property> [args...]`

Modify properties of an existing item at the current marker.

#### For queries:

| Property | Usage | Effect |
|----------|-------|--------|
| `cmd:<shell>` | `set <name> cmd:bash "rg -l TODO ."` | Sets the bash command on `_default` supplier |
| `scope` | `set <name> scope /some/dir` | Sets scope on `_default` supplier |
| `expr` | `set <name> expr "a and b"` | Sets the boolean expression |
| `supplier` | `set <name> supplier` | Lists all suppliers |
| `supplier <n> cmd <cmd>` | `set <name> supplier mysup cmd "rg ."` | Sets cmd on named supplier |
| `supplier <n> scope <path>` | `set <name> supplier mysup scope /dir` | Sets scope on named supplier |
| `supplier <n> rm` | `set <name> supplier mysup rm` | Removes a named supplier |

#### For references:

| Property | Usage | Effect |
|----------|-------|--------|
| `target` | `set <name> target /new/path` | Updates target path (must exist on disk) |

**Tests:**
- [ ] `set foo cmd:bash "..."` creates `_default` supplier if absent, writes command
- [ ] `set foo cmd:nu "..."` writes nu command (coexists with bash)
- [ ] `set foo scope /dir` creates or updates `_default.scope`
- [ ] `set foo expr "a or b"` writes expression
- [ ] `set foo expr ""` clears expression
- [ ] `set foo supplier` with no name prints supplier list
- [ ] `set foo supplier mysup cmd "..."` creates or updates named supplier
- [ ] `set foo supplier mysup scope /dir` updates scope on named supplier
- [ ] `set foo supplier mysup rm` removes named supplier
- [ ] Removing nonexistent supplier errors
- [ ] `set` on a folder errors (folders have no settable properties)
- [ ] `set ref target /new` updates target and `target_type`
- [ ] `set ref target /nonexistent` errors
- [ ] Unknown property name errors
- [ ] Unknown shell in `cmd:<shell>` errors

---

### `vdir compiler <subcommand>`

Manage compiler containers.

#### `vdir compiler list`

List all available compilers from all registered containers.

**Output:** One line per compiler:
```
  <compiler_name> (from <container_path>)
```

**Tests:**
- [ ] With no containers registered: prints nothing or an empty-state message
- [ ] With a container registered: lists its compilers
- [ ] Compilers from multiple containers all appear

#### `vdir compiler add <path>`

Register a compiler container (a binary/script that implements the container protocol).

**Container protocol:**
- `<container> list` → newline-separated compiler names
- `<container> run <compiler> [args]` → lines of `shell: command`

**Tests:**
- [ ] Adds path to the container registry (persisted to config)
- [ ] Adding a nonexistent path errors
- [ ] Adding the same path twice is idempotent or warns

#### `vdir compiler test <compiler> [args]`

Run a compiler and show its output (the shell → command map it would produce).

**Tests:**
- [ ] Prints output header and the shell-command pairs
- [ ] Unknown compiler name errors
- [ ] With args, passes them to the compiler

#### `vdir compiler rebuild`

Re-query all registered containers and refresh the compiler cache.

**Tests:**
- [ ] Cache updated with current state of all containers
- [ ] Compilers from removed containers no longer appear after rebuild
- [ ] Containers that fail to respond are skipped, others still processed

---

## Query System — Detailed Specification

### Suppliers

A query has zero or more **suppliers**. Each supplier has:
- `scope` — a filesystem path. The command runs with this as its working directory.
  `.` means the directory containing `.vdir.json`.
- `cmd` — an object mapping shell names to command strings.
  e.g. `{ "bash": "rg -l TODO .", "nu": "rg -l TODO (pwd)" }`
- (optional) `compiler` — name of the compiler that generated the commands
- (optional) `args` — the argument string passed to the compiler
- (optional) `raw: true` — marks that the command was set manually

The special supplier name `_default` is the one targeted by the simple
`set cmd:shell`, `set scope`, and `set expr` commands.

### Expression language

A query has an `expr` field — a boolean expression over supplier names:

| Construct | Meaning |
|-----------|---------|
| `supplier_name` | Run that supplier, take its file set |
| `a and b` | Intersection of a's and b's file sets |
| `a or b` | Union |
| `not a` | All files from all suppliers minus a's set |
| `(a or b) and c` | Grouped expression |

If `expr` is empty, the result is the union of all suppliers.

**Tests:**
- [ ] Single supplier name evaluates to that supplier's file set
- [ ] `a and b` returns only files in both sets
- [ ] `a or b` returns files in either set
- [ ] `not a` returns all files from all suppliers except a's files
- [ ] Parentheses group correctly: `(a or b) and c`
- [ ] Empty expression unions all suppliers
- [ ] Unknown supplier name in expression errors
- [ ] Malformed expression (unmatched parens, double operators) errors
- [ ] Expression with only whitespace treated as empty

### Shell selection

When executing a supplier, vdir selects a shell from the `cmd` map:

1. Check the user's `$SHELL` environment variable. If that shell has an entry
   in the `cmd` map, use it.
2. Otherwise, iterate the known shells in preference order
   (`bash`, `zsh`, `nu`, `powershell`, `cmd`) and use the first one that is
   both in the `cmd` map and available in `$PATH`.
3. If no shell matches, return an empty file set (do not error).

**Tests:**
- [ ] With only `bash` in cmd map and `$SHELL=bash`: uses bash
- [ ] With `bash` and `nu` in map, `$SHELL=nu`: uses nu
- [ ] With only `bash` in map, `$SHELL=zsh`, bash in PATH: falls back to bash
- [ ] With no matching shell in PATH: returns empty set without error
- [ ] Shell command is invoked with correct argv (`bash -c`, `nu -c`,
  `pwsh -Command`, `cmd /c`)
- [ ] Command runs in `scope` directory when scope is not `.`
- [ ] Command runs in vdir directory when scope is `.`

### Query execution

- Output of the shell command is split on newlines.
- Each non-empty, trimmed line is treated as a file path.
- Duplicate paths within a supplier's output are deduplicated.
- Set operations (and/or/not) operate on these deduplicated sets.

**Tests:**
- [ ] Trailing newline in command output does not produce empty path
- [ ] Blank lines in output are ignored
- [ ] Whitespace-only lines are ignored
- [ ] Same path from two suppliers: appears once in union
- [ ] `and` of two suppliers with no overlap: empty result
- [ ] `not` with empty supplier set: returns full universe from other suppliers

---

## Data format — `.vdir.json`

```json
{
  "root": {
    "name": "",
    "children": [
      {
        "type": "folder",
        "name": "MyFolder",
        "children": [...]
      },
      {
        "type": "query",
        "name": "todos",
        "expr": "_default",
        "suppliers": {
          "_default": {
            "scope": ".",
            "compiler": "ripgrep",
            "args": "TODO|FIXME",
            "cmd": {
              "bash": "rg -l 'TODO|FIXME' .",
              "nu": "rg -l 'TODO|FIXME' (pwd)"
            }
          }
        }
      },
      {
        "type": "reference",
        "name": "config",
        "target": "/home/user/.config/nvim",
        "target_type": "folder"
      }
    ]
  }
}
```

**Tests:**
- [ ] File is valid JSON after every mutation
- [ ] Indentation is 2 spaces
- [ ] File ends with a newline
- [ ] Root always has `"name": ""`
- [ ] Folders always have a `"children"` array (never null/absent)
- [ ] Queries always have `"expr"` (may be empty string) and `"suppliers"` object
- [ ] References always have `"target"` and `"target_type"`
- [ ] No extra fields added on read-modify-write cycles (round-trip stability)

---

## Compiler container protocol

A compiler container is any executable that implements:

### `<container> list`

Exit 0. Stdout: one compiler name per line. No other output.

### `<container> run <compiler_name> [args]`

Exit 0 on success. Stdout: lines of `shell: command`, e.g.:
```
bash: rg -l 'pattern' .
nu: rg -l 'pattern' (pwd)
```

Lines with empty shell name or empty command are ignored.

**Tests:**
- [ ] Container returning multiple compilers: all parsed correctly
- [ ] Container `run` output: each `shell: command` line stored in cmd map
- [ ] Colon in command value does not break parsing (only first colon is split)
- [ ] Empty lines in container output are skipped
- [ ] Container exiting non-zero: error propagated to user
- [ ] Container not found in PATH: clear error message

---

## Error handling summary

Every command must:
- Print a human-readable error message to stderr on failure
- Exit non-zero
- Leave `.vdir.json` unchanged if an error occurs mid-operation (no partial writes)

| Scenario | Expected behavior |
|----------|------------------|
| No `.vdir.json` in cwd | Error: "No vdir found. Run 'vdir init' first." |
| Path not found in tree | Error: "Path not found: <path>" |
| Target is not a folder | Error: "Not a folder: <path>" |
| Item name already exists | Error: "Item '<name>' already exists" |
| Item not found | Error: "Item not found: <name>" |
| Real path does not exist (for `ln`, `set target`) | Error: "Target does not exist: <path>" |
| Unknown compiler | Error: "Compiler not found: <name>" |
| Unknown shell | Error: "Unknown shell: <name>" |
| Unknown flag | Error: "Unknown flag: <flag>" |
| Unknown command | Error: "Unknown command: <cmd>" |
| `..` above root | Error: "Invalid path: <path>" |
