const std = @import("std");
const persistence = @import("../persistence.zig");
const path = @import("../path.zig");

pub fn run(io: std.Io, allocator: std.mem.Allocator, args: *std.process.Args.Iterator) !void {
    var rename_source = false;
    var old_path: ?[]const u8 = null;
    var new_name: ?[]const u8 = null;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--source") or std.mem.eql(u8, arg, "-s")) {
            rename_source = true;
        } else if (old_path == null) {
            old_path = arg;
        } else if (new_name == null) {
            new_name = arg;
        } else {
            printUsageAndExit();
        }
    }

    const old = old_path orelse {
        printUsageAndExit();
    };
    const new = new_name orelse {
        printUsageAndExit();
    };

    if (new.len == 0 or
        std.mem.indexOfScalar(u8, new, '/') != null or
        std.mem.eql(u8, new, ".") or
        std.mem.eql(u8, new, "..") or
        std.mem.eql(u8, new, "~"))
    {
        std.debug.print("Invalid new name: '{s}'\n", .{new});
        std.process.exit(1);
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

    const resolved = path.resolve(root, marker, old) catch |err| {
        switch (err) {
            path.ResolveError.NotFound => std.debug.print("Path not found: {s}\n", .{old}),
            path.ResolveError.NotAFolder => std.debug.print("Not a folder in path: {s}\n", .{old}),
            path.ResolveError.InvalidPath => std.debug.print("Invalid path: {s}\n", .{old}),
        }
        std.process.exit(1);
    };

    if (resolved.parent == null) {
        std.debug.print("Cannot rename root\n", .{});
        std.process.exit(1);
    }

    const parent = resolved.parent.?;
    const children = parent.object.getPtr("children") orelse {
        std.debug.print("Invalid vdir format\n", .{});
        std.process.exit(1);
    };

    var rename_index: ?usize = null;
    for (children.array.items, 0..) |child, idx| {
        const child_name = child.object.get("name").?.string;
        if (std.mem.eql(u8, child_name, resolved.name)) {
            rename_index = idx;
        } else if (std.mem.eql(u8, child_name, new)) {
            std.debug.print("Item '{s}' already exists\n", .{new});
            std.process.exit(1);
        }
    }

    const index = rename_index orelse {
        std.debug.print("Path not found: {s}\n", .{old});
        std.process.exit(1);
    };

    const json_allocator = vdir_json.arena.allocator();
    const item = &children.array.items[index];

    if (rename_source) {
        const item_type = item.object.get("type") orelse {
            std.debug.print("Invalid vdir format\n", .{});
            std.process.exit(1);
        };

        if (!std.mem.eql(u8, item_type.string, "reference")) {
            std.debug.print("--source can only be used with reference items\n", .{});
            std.process.exit(1);
        }

        const target_ptr = item.object.getPtr("target") orelse {
            std.debug.print("Invalid reference format\n", .{});
            std.process.exit(1);
        };
        const old_target = target_ptr.string;

        var new_target_buffer: [4096]u8 = undefined;
        const new_target = if (std.fs.path.dirname(old_target)) |dirname|
            try std.fmt.bufPrint(new_target_buffer[0..], "{s}{c}{s}", .{ dirname, std.fs.path.sep, new })
        else
            new;

        if (persistence.fileExists(io, new_target)) {
            std.debug.print("Source target already exists: {s}\n", .{new_target});
            std.process.exit(1);
        }

        try std.Io.Dir.cwd().rename(io, old_target, new_target);
        target_ptr.* = .{ .string = try json_allocator.dupe(u8, new_target) };
    }

    const name_ptr = item.object.getPtr("name") orelse {
        std.debug.print("Invalid vdir format\n", .{});
        std.process.exit(1);
    };
    name_ptr.* = .{ .string = try json_allocator.dupe(u8, new) };

    try persistence.saveVDirJson(io, allocator, vdir_json.value);

    if (rename_source) {
        std.debug.print("Renamed '{s}' to '{s}' and source target\n", .{ resolved.name, new });
    } else {
        std.debug.print("Renamed '{s}' to '{s}'\n", .{ resolved.name, new });
    }
}

fn printUsageAndExit() noreturn {
    std.debug.print("Usage: vdir rename [--source|-s] <path> <new_name>\n", .{});
    std.process.exit(1);
}
