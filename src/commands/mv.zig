const std = @import("std");
const persistence = @import("../persistence.zig");
const pathmod = @import("../path.zig");

pub fn run(io: std.Io, allocator: std.mem.Allocator, args: *std.process.Args.Iterator) !void {
    const source = args.next() orelse {
        std.debug.print("Usage: vdir mv <name> <newname|folder>\n", .{});
        std.process.exit(1);
    };
    const dest = args.next() orelse {
        std.debug.print("Usage: vdir mv <name> <newname|folder>\n", .{});
        std.process.exit(1);
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

    const current = pathmod.resolveMarker(root, marker) catch |err| {
        switch (err) {
            pathmod.ResolveError.NotFound => std.debug.print("Current path not found: {s}\n", .{marker}),
            pathmod.ResolveError.NotAFolder => std.debug.print("Not a folder: {s}\n", .{marker}),
            pathmod.ResolveError.InvalidPath => std.debug.print("Invalid path: {s}\n", .{marker}),
        }
        std.process.exit(1);
    };

    const children = current.object.getPtr("children") orelse {
        std.debug.print("Not in a folder\n", .{});
        std.process.exit(1);
    };

    // Find source item
    var source_idx: ?usize = null;
    for (children.array.items, 0..) |child, i| {
        const child_name = child.object.get("name").?.string;
        if (std.mem.eql(u8, child_name, source)) {
            source_idx = i;
            break;
        }
    }

    if (source_idx == null) {
        std.debug.print("Item not found: {s}\n", .{source});
        std.process.exit(1);
    }

    // Check if dest is a folder (move into it) or a new name (rename)
    var dest_folder: ?*std.json.Value = null;
    for (children.array.items) |*child| {
        const child_name = child.object.get("name").?.string;
        if (std.mem.eql(u8, child_name, dest)) {
            const child_type = child.object.get("type").?.string;
            if (std.mem.eql(u8, child_type, "folder")) {
                dest_folder = child;
            } else {
                std.debug.print("Item '{s}' already exists and is not a folder\n", .{dest});
                std.process.exit(1);
            }
            break;
        }
    }

    if (dest_folder) |folder| {
        // Move into folder
        const dest_children = folder.object.getPtr("children") orelse {
            std.debug.print("Invalid folder structure\n", .{});
            std.process.exit(1);
        };

        // Check for name conflict in destination
        const item = children.array.items[source_idx.?];
        const item_name = item.object.get("name").?.string;
        for (dest_children.array.items) |child| {
            const child_name = child.object.get("name").?.string;
            if (std.mem.eql(u8, child_name, item_name)) {
                std.debug.print("Item '{s}' already exists in '{s}'\n", .{ item_name, dest });
                std.process.exit(1);
            }
        }

        // Move: add to dest, remove from source
        try dest_children.array.append(item);
        _ = children.array.orderedRemove(source_idx.?);

        std.debug.print("{s} -> {s}/\n", .{ source, dest });
    } else {
        // Rename
        const json_allocator = vdir_json.arena.allocator();
        const new_name = try json_allocator.dupe(u8, dest);
        try children.array.items[source_idx.?].object.put("name", .{ .string = new_name });

        std.debug.print("{s} -> {s}\n", .{ source, dest });
    }

    try persistence.saveVDirJson(io, allocator, vdir_json.value);
}
