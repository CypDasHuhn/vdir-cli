const std = @import("std");
const persistence = @import("../persistence.zig");
const path = @import("../path.zig");

pub fn run(io: std.Io, allocator: std.mem.Allocator, args: *std.process.Args.Iterator) !void {
    var force = false;
    var target_path: ?[]const u8 = null;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--force") or std.mem.eql(u8, arg, "-f")) {
            force = true;
        } else if (target_path == null) {
            target_path = arg;
        } else {
            printUsageAndExit();
        }
    }

    const delete_path = target_path orelse {
        printUsageAndExit();
    };

    var vdir_json = try persistence.loadVDir(io, allocator) orelse {
        std.debug.print("No vdir found. Run 'vdir init' first.\n", .{});
        std.process.exit(1);
    };
    defer vdir_json.deinit();

    const marker_result = try persistence.loadMarker(io, allocator);
    const marker = marker_result orelse "~";
    defer if (marker_result != null) allocator.free(marker_result.?);

    const root = vdir_json.value.object.getPtr("root") orelse {
        std.debug.print("Invalid vdir format\n", .{});
        std.process.exit(1);
    };

    const resolved = path.resolve(root, marker, delete_path) catch |err| {
        switch (err) {
            path.ResolveError.NotFound => std.debug.print("Path not found: {s}\n", .{delete_path}),
            path.ResolveError.NotAFolder => std.debug.print("Not a folder in path: {s}\n", .{delete_path}),
            path.ResolveError.InvalidPath => std.debug.print("Invalid path: {s}\n", .{delete_path}),
        }
        std.process.exit(1);
    };

    if (resolved.parent == null) {
        std.debug.print("Cannot delete root\n", .{});
        std.process.exit(1);
    }

    const parent = resolved.parent.?;
    const children = parent.object.getPtr("children") orelse {
        std.debug.print("Invalid vdir format\n", .{});
        std.process.exit(1);
    };

    var delete_index: ?usize = null;
    for (children.array.items, 0..) |child, idx| {
        const child_name = child.object.get("name").?.string;
        if (std.mem.eql(u8, child_name, resolved.name)) {
            delete_index = idx;
            break;
        }
    }

    const index = delete_index orelse {
        std.debug.print("Path not found: {s}\n", .{delete_path});
        std.process.exit(1);
    };

    const target_item = children.array.items[index];
    if (!force and hasChildren(target_item)) {
        std.debug.print("Folder '{s}' has contents. Delete? [y/N]: ", .{resolved.name});
        if (!try readConfirmYes()) {
            std.debug.print("Delete cancelled\n", .{});
            return;
        }
    }

    _ = children.array.orderedRemove(index);
    try persistence.saveVDirJson(io, allocator, vdir_json.value);
    std.debug.print("Deleted '{s}'\n", .{resolved.name});
}

fn hasChildren(item: std.json.Value) bool {
    const item_type = item.object.get("type") orelse return false;
    if (!std.mem.eql(u8, item_type.string, "folder")) return false;

    const children = item.object.get("children") orelse return false;
    return children.array.items.len > 0;
}

fn readConfirmYes() !bool {
    const stdin = std.fs.File.stdin();
    var input_buffer: [64]u8 = undefined;
    const bytes_read = try stdin.read(input_buffer[0..]);
    if (bytes_read == 0) return false;

    const trimmed = std.mem.trim(u8, input_buffer[0..bytes_read], " \t\r\n");
    if (trimmed.len == 0) return false;
    return trimmed[0] == 'y' or trimmed[0] == 'Y';
}

fn printUsageAndExit() noreturn {
    std.debug.print("Usage: vdir delete [--force|-f] <path>\n", .{});
    std.process.exit(1);
}
