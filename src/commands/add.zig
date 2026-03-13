const std = @import("std");
const persistence = @import("../persistence.zig");

const ItemType = enum { folder, query, reference };

pub fn run(io: std.Io, allocator: std.mem.Allocator, args: *std.process.Args.Iterator) !void {
    var item_type: ItemType = .folder;
    var name: ?[]const u8 = null;
    var target: ?[]const u8 = null;

    // Parse arguments
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-q") or std.mem.eql(u8, arg, "--query")) {
            item_type = .query;
        } else if (name == null) {
            // First positional argument
            if (item_type != .query and persistence.fileExists(io, arg)) {
                // It's a path that exists - make it a reference
                item_type = .reference;
                target = arg;
            } else {
                name = arg;
            }
        } else if (target != null and name == null) {
            // Second positional after a path - custom name for reference
            name = arg;
        } else {
            // If we already have a target, this is the name
            if (item_type == .reference and target != null) {
                name = arg;
            }
        }
    }

    // For references, if no custom name given, derive from path
    if (item_type == .reference) {
        if (target == null) {
            std.debug.print("Usage: vdir add <path> [name]    (create reference)\n", .{});
            std.process.exit(1);
        }
        if (name == null) {
            // Use basename of target as name
            name = std.fs.path.basename(target.?);
        }
    }

    if (name == null) {
        std.debug.print("Usage: vdir add <name>           (create folder)\n", .{});
        std.debug.print("       vdir add -q <name>        (create query)\n", .{});
        std.debug.print("       vdir add <path> [name]    (create reference)\n", .{});
        std.process.exit(1);
    }

    // Load vdir
    var vdir_json = try persistence.loadVDir(io, allocator) orelse {
        std.debug.print("No vdir found. Run 'vdir init' first.\n", .{});
        std.process.exit(1);
    };
    defer vdir_json.deinit();

    // Get root children array
    const root = vdir_json.value.object.getPtr("root") orelse {
        std.debug.print("Invalid vdir format\n", .{});
        std.process.exit(1);
    };
    const children = root.object.getPtr("children") orelse {
        std.debug.print("Invalid vdir format\n", .{});
        std.process.exit(1);
    };

    // Check for duplicate name
    for (children.array.items) |child| {
        const child_name = child.object.get("name").?.string;
        if (std.mem.eql(u8, child_name, name.?)) {
            std.debug.print("Item '{s}' already exists\n", .{name.?});
            std.process.exit(1);
        }
    }

    // Create new item using the JSON's arena allocator
    const json_allocator = vdir_json.arena.allocator();
    var new_item = std.json.ObjectMap.init(json_allocator);

    switch (item_type) {
        .folder => {
            try new_item.put("type", .{ .string = "folder" });
            try new_item.put("name", .{ .string = name.? });
            try new_item.put("children", .{ .array = std.json.Array.init(json_allocator) });
            std.debug.print("d {s}\n", .{name.?});
        },
        .query => {
            try new_item.put("type", .{ .string = "query" });
            try new_item.put("name", .{ .string = name.? });
            try new_item.put("scope", .{ .string = "." });
            try new_item.put("cmd", .{ .string = "" });
            std.debug.print("q {s}\n", .{name.?});
        },
        .reference => {
            try new_item.put("type", .{ .string = "reference" });
            try new_item.put("name", .{ .string = name.? });
            try new_item.put("target", .{ .string = target.? });
            std.debug.print("r {s} -> {s}\n", .{ name.?, target.? });
        },
    }

    try children.array.append(.{ .object = new_item });

    // Save
    try persistence.saveVDirJson(io, allocator, vdir_json.value);
}
