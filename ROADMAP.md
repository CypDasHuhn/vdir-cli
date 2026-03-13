# vdir-cli Roadmap

Scope: Minimal implementation to support `commands.md` functionality.

---

## Phase 1: Data Model & Persistence

### 1.1 Core Types

Define the fundamental structures:

```
Item (tagged union)
├── Folder    { name, children: []Item }
├── Query     { name, scope, cmd }
└── Reference { name, target_path }
```

Query executes `cmd` in `scope` directory, collects output paths.

### 1.2 VDir State

```
VDir
├── root: Folder
├── marker: Path (current position)
└── config_path: where this vdir is stored
```

### 1.3 Persistence

Two files, separate concerns:

| File | Contents | Git |
|------|----------|-----|
| `.vdir.json` | Structure (folders, queries, refs) | commit |
| `.vdir-marker` | Current marker path | ignore |

Location: project root (local vdir) or `~/.config/vdir/` (global)

Load/save functions for both.

---

## Phase 2: Path Resolution

### 2.1 Path Types

- `~/` → resolves to vdir root
- `../` → parent of current marker
- `name` or `foo/bar` → relative to marker

### 2.2 Implementation

- Parse path string into segments
- Resolve against marker position
- Return target Item or error

---

## Phase 3: Commands

### 3.1 Navigation

| Command | Description |
|---------|-------------|
| `cd <path>` | Move marker to directory |

### 3.2 Read Operations

| Command | Description |
|---------|-------------|
| `ls` | List items at marker |
| `ls -a` | Include hidden |
| `ls -l` | Long format |
| `ls -r[N]` | Recursive, N levels deep |
| `read <name>` | Show item details (reference target, query definition) |

### 3.3 Modify Operations

| Command | Description |
|---------|-------------|
| `add <name>` | Create folder or query |
| `add <ref> [name]` | Create reference to file/dir |
| `delete <name>` | Remove item (confirm if folder has contents) |
| `delete --force <name>` | Remove without confirmation |
| `rename <name> <new>` | Rename item |
| `move <name> <dir>` | Move item to directory |
| `query-edit <name>` | Edit query definition |

---

## Phase 4: CLI Structure

### 4.1 Subcommand Routing

```
vdir <command> [args] [flags]
```

Replace clap boilerplate with subcommand dispatch:

- Parse first positional as command
- Route to handler with remaining args

### 4.2 Output

- Human-readable by default
- Consider `--porcelain` for script-friendly output later

---

## Implementation Order

1. **Types** - Item, Folder, Query, Reference, VDir
2. **Persistence** - save/load vdir state
3. **Path resolution** - parse and resolve paths
4. **cd** - marker movement (validates path resolution works)
5. **ls** - basic listing (validates data model works)
6. **add folder** - create folders
7. **add reference** - create references
8. **delete** - remove items
9. **rename/move** - modify structure
10. **read** - inspect items
11. **add query** - create queries (predicate format TBD)
12. **query-edit** - modify queries
13. **ls -r** - recursive listing with query expansion

---

## Decisions Made

- **Storage**: `.vdir.json` (structure, committable) + `.vdir-marker` (position, gitignored)
- **Queries**: `exec`-only - shell out to external commands, collect output paths
- **Scope**: One vdir per directory, no imports (for now)
