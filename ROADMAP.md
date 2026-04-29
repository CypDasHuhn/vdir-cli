# vdir-cli Roadmap

Remaining work.

---

## Delete (rm) — Folder Content Confirmation

`rm` currently deletes folders with contents without prompting. The `--force` flag is parsed but never used.

- Prompt `y/n` when deleting a folder with children
- `--force` skips confirmation

---

## Path Resolver — `../` Support

The shared `resolve()` function in `src/path.zig:53` returns `InvalidPath` for `..`. Only `cd.zig` has a local workaround via string manipulation.

- Implement parent traversal in the shared path resolver
- Remove the local workaround in `cd.zig`

---

## Global VDir Storage

Persistence always uses cwd. No support for `~/.config/vdir/` as specified.

- Detect/configurable storage location (local cwd vs global `~/.config/vdir/`)
- Load/save from the appropriate path

---

## `--porcelain` Output Mode

All commands use human-readable output via `std.debug.print`.

- Add a global `--porcelain` flag for machine-parsable output
- Row/column format, no decorations

---

## VDir Struct — Missing Fields

`src/types.zig:33-43` is missing `marker` and `config_path` fields. The typed model (Item/Folder/Query/Reference) exists but runtime uses raw `std.json.Value` — either use the typed model consistently or remove it.

- Add `marker` and `config_path` to VDir struct
- Migrate runtime code from `std.json.Value` to the typed model (or drop the typed model)

---

## Decisions Made

- **Storage**: `.vdir.json` (structure, committable) + `.vdir-marker` (position, gitignored)
- **Queries**: `exec`-only — shell out to external commands, collect output paths
- **Scope**: One vdir per directory, no imports (for now)
