const std = @import("std");
const persistence = @import("../persistence.zig");
const path = @import("../path.zig");

pub fn run(io: std.Io, allocator: std.mem.Allocator, args: *std.process.Args.Iterator) !void {
    const source_path = args.next() orelse {
        printUsageAndExit();
    };
    const destination_path = args.next() orelse {
        printUsageAndExit();
    };
    if (args.next() != null) {
        printUsageAndExit();
    }

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

    const source = path.resolve(root, marker, source_path) catch |err| {
        reportResolveError("source", source_path, err);
    };

    if (source.parent == null) {
        std.debug.print("Cannot move root\n", .{});
        std.process.exit(1);
    }

    const destination = path.resolve(root, marker, destination_path) catch |err| {
        reportResolveError("destination", destination_path, err);
    };

    var destination_path_buffer: [4096]u8 = undefined;
    const destination_canonical = path.resolveMarkerPath(destination_path_buffer[0..], marker, destination_path) catch {
        std.debug.print("Invalid destination path: {s}\n", .{destination_path});
        std.process.exit(1);
    };

    const destination_children_before = destination.item.object.getPtr("children") orelse {
        std.debug.print("Destination is not a folder: {s}\n", .{destination_path});
        std.process.exit(1);
    };

    if (source.parent.? == destination.item) {
        std.debug.print("Item '{s}' is already in that folder\n", .{source.name});
        return;
    }

    const source_type = source.item.object.get("type").?.string;
    if (std.mem.eql(u8, source_type, "folder")) {
        var source_path_buffer: [4096]u8 = undefined;
        const source_canonical = path.resolveMarkerPath(source_path_buffer[0..], marker, source_path) catch {
            std.debug.print("Invalid source path: {s}\n", .{source_path});
            std.process.exit(1);
        };

        if (std.mem.eql(u8, source_canonical, destination_canonical) or
            isDirectDescendant(destination_canonical, source_canonical))
        {
            std.debug.print("Cannot move folder '{s}' into itself or its descendant\n", .{source.name});
            std.process.exit(1);
        }
    }

    for (destination_children_before.array.items) |child| {
        const child_name = child.object.get("name").?.string;
        if (std.mem.eql(u8, child_name, source.name)) {
            std.debug.print("Destination already has item '{s}'\n", .{source.name});
            std.process.exit(1);
        }
    }

    const source_parent_children = source.parent.?.object.getPtr("children") orelse {
        std.debug.print("Invalid vdir format\n", .{});
        std.process.exit(1);
    };

    var source_index: ?usize = null;
    for (source_parent_children.array.items, 0..) |child, idx| {
        const child_name = child.object.get("name").?.string;
        if (std.mem.eql(u8, child_name, source.name)) {
            source_index = idx;
            break;
        }
    }

    const index = source_index orelse {
        std.debug.print("Source item disappeared during move\n", .{});
        std.process.exit(1);
    };

    const moved_item = source_parent_children.array.orderedRemove(index);
    const destination_after = path.resolveMarker(root, destination_canonical) catch {
        std.debug.print("Destination no longer exists: {s}\n", .{destination_path});
        std.process.exit(1);
    };
    const destination_children_after = destination_after.object.getPtr("children") orelse {
        std.debug.print("Destination is no longer a folder: {s}\n", .{destination_path});
        std.process.exit(1);
    };
    try destination_children_after.array.append(moved_item);

    try persistence.saveVDirJson(io, allocator, vdir_json.value);
    std.debug.print("Moved '{s}' to '{s}'\n", .{ source.name, destination_path });
}

fn reportResolveError(kind: []const u8, input: []const u8, err: path.ResolveError) noreturn {
    switch (err) {
        path.ResolveError.NotFound => std.debug.print("{s} path not found: {s}\n", .{ kind, input }),
        path.ResolveError.NotAFolder => std.debug.print("Not a folder in {s} path: {s}\n", .{ kind, input }),
        path.ResolveError.InvalidPath => std.debug.print("Invalid {s} path: {s}\n", .{ kind, input }),
    }
    std.process.exit(1);
}

fn isDirectDescendant(path_value: []const u8, parent_path: []const u8) bool {
    return path_value.len > parent_path.len and
        std.mem.startsWith(u8, path_value, parent_path) and
        path_value[parent_path.len] == '/';
}

fn printUsageAndExit() noreturn {
    std.debug.print("Usage: vdir move <path> <destination_folder>\n", .{});
    std.process.exit(1);
}
