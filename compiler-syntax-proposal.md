# Compiler System Syntax Proposal

## Overview

This document proposes syntax changes to support the new compiler system with three layers:

1. **Vdir** - Manages a global registry of compiler containers
2. **Containers** - External executables containing multiple compilers
3. **Compilers** - Transform commands into shell-to-command mappings

---

## 1. Container Registry

Vdir maintains a global `~/.vdir/compilers.txt` file listing container paths.

```
# One container per line
# Paths, or command names if in PATH

/home/user/.config/vdir/containers/ripgrep-compiler
/home/user/.config/vdir/containers/fd-compiler.nu
my-compiler-container
```

### Compiler Cache

Compiler metadata is cached in `~/.vdir/` and reloaded when:
- Running `vdir compiler add/remove`
- Running `vdir compiler reload`

---

## 2. Container Protocol

Containers are executables (binaries, `.sh`, `.nu`, `.ps1`, etc.) that respond to:

```bash
# List available compiler names (newline-separated)
<container> list

# Run a specific compiler with arguments
<container> run <compiler_name> <args...>
```

### Output Format for `run`

The compiler outputs a shell-to-command mapping in plain text:

```
bash: rg -l 'pattern' .
nu: rg -l 'pattern' (pwd)
powershell: rg -l 'pattern' (Get-Location)
```

---

## 3. Supplier Syntax Changes

### Current syntax (single command)

```bash
vdir mkq myquery "rg -l 'TODO'"
vdir set myquery cmd "rg -l 'TODO'"
```

### New syntax with compilers

```bash
# Using a compiler (default behavior)
vdir mkq myquery ripgrep "'TODO'"
# Equivalent to: compiler "ripgrep" transforms "'TODO'" into shell map

# Raw mode - bypass compiler, single shell command
vdir mkq myquery --raw "rg -l 'TODO'"

# Raw mode with explicit shell target
vdir mkq myquery --raw --shell nu "rg -l 'TODO' (pwd)"
```

### Setting supplier with shell map directly

```bash
# Set individual shell commands
vdir set myquery cmd:bash "rg -l 'TODO' ."
vdir set myquery cmd:nu "rg -l 'TODO' (pwd)"
vdir set myquery cmd:powershell "rg -l 'TODO' (Get-Location)"
```

---

## 4. Container Management Commands

```bash
# List registered containers
vdir compiler containers

# Add a container
vdir compiler add <path-or-name>

# Remove a container
vdir compiler remove <path-or-name>

# Reload compiler cache from containers
vdir compiler reload

# List all available compilers (from all containers)
vdir compiler list

# List compilers from specific container
vdir compiler list --container <name>

# Show which container provides a compiler
vdir compiler which <compiler-name>

# Test a compiler transformation
vdir compiler test <compiler-name> <args...>
```

---

## 5. Supplier Data Structure Changes

### Current structure

```json
{
  "type": "query",
  "name": "myquery",
  "scope": ".",
  "cmd": "rg -l 'pattern'"
}
```

### New structure

```json
{
  "type": "query",
  "name": "myquery",
  "scope": ".",
  "suppliers": {
    "main": {
      "compiler": "ripgrep",
      "args": "'pattern'",
      "cmd": {
        "bash": "rg -l 'pattern' .",
        "nu": "rg -l 'pattern' (pwd)"
      }
    }
  },
  "expr": "main"
}
```

For raw suppliers (no compiler):

```json
{
  "type": "query",
  "name": "myquery",
  "scope": ".",
  "suppliers": {
    "main": {
      "raw": true,
      "cmd": {
        "bash": "rg -l 'pattern' ."
      }
    }
  },
  "expr": "main"
}
```

---

## 6. Shell Resolution Order

When executing a supplier:

1. Determine default shell:
   - **Windows**: `cmd`
   - **Unix**: `$SHELL`
2. Look for command in `cmd` map for that shell
3. If not found, iterate through available shells in `cmd` map:
   - Check if shell is in PATH
   - Use first available shell
4. Execute using vdir's internal shell syntax knowledge

---

## 7. Built-in Shell Knowledge

Vdir maintains internal knowledge of shell syntax for:

| Shell | Execute command | Check if in PATH |
|-------|-----------------|------------------|
| bash | `bash -c "<cmd>"` | `command -v <name>` |
| zsh | `zsh -c "<cmd>"` | `command -v <name>` |
| nu | `nu -c "<cmd>"` | `which <name>` |
| powershell | `pwsh -Command "<cmd>"` | `Get-Command <name>` |
| cmd | `cmd /c "<cmd>"` | `where <name>` |

---

## 8. Example Workflow

```bash
# Register a compiler container
vdir compiler add ~/.config/vdir/compilers/search-tools

# See available compilers
vdir compiler list
# Output:
#   ripgrep (from search-tools)
#   fd (from search-tools)

# Create query using compiler
vdir mkq todos ripgrep "TODO|FIXME"

# The compiler transforms this into shell-specific commands
# Stored in .vdir.json with the full shell map

# Create raw query (no compiler)
vdir mkq custom --raw --shell bash "find . -name '*.rs'"

# Add another shell variant manually
vdir set custom cmd:nu "glob **/*.rs"

# Reload compiler cache after modifying containers externally
vdir compiler reload
```
