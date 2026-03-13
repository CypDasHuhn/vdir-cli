# Command Notes

## General

- Directories
  - When starting with ~/ will be expanend to root of the vdir
  - Else will be expaned to the current marker
  - ../ will be expanded to parent directory

## Commands

- |Modify
  - add
    - (Folder/Query)
      - `... <name>`
    - Reference
      - `... <reference> <optional:name>`
      - Can be file or directory
  - delete `<name>`
    - Folder
      - gets y/n confirmation if has contents
      - `--force` flag to skip confirmation
  - rename `<name>` `<new name>`
  - move `<name>` `<directory>`
  - query-edit `<name>`
    - fields to edit yet to be determined
- |Read
  - ls
    - `-a` flag to show hidden
    - `-l` flag to show long
    - `-r` flag to show recursive navigating directories and queries
      - `...<num>` to show `<num>` levels deep
  - read `<name>`
- |Move Marker
  - cd `<directory>`
