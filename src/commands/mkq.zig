const std = @import("std");
const persistence = @import("../persistence.zig");
const pathmod = @import("../path.zig");

pub fn run(io: std.Io, allocator: std.mem.Allocator, args: *std.process.Args.Iterator) !void {
    const name = args.next() orelse {
        std.debug.print("Usage: vdir mkq <name> [cmd]\n", .{});
        std.process.exit(1);
    };

    // Optional inline command for simple queries
    const inline_cmd = args.next();

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
        std.debug.print("Cannot add to non-folder\n", .{});
        std.process.exit(1);
    };

    for (children.array.items) |child| {
        const child_name = child.object.get("name").?.string;
        if (std.mem.eql(u8, child_name, name)) {
            std.debug.print("Item '{s}' already exists\n", .{name});
            std.process.exit(1);
        }
    }

    const json_allocator = vdir_json.arena.allocator();
    var new_item = std.json.ObjectMap.init(json_allocator);

    try new_item.put("type", .{ .string = "query" });
    try new_item.put("name", .{ .string = name });

    var suppliers = std.json.ObjectMap.init(json_allocator);

    // If inline command provided, create _default supplier
    if (inline_cmd) |cmd| {
        var default_supplier = std.json.ObjectMap.init(json_allocator);
        try default_supplier.put("scope", .{ .string = "." });
        try default_supplier.put("cmd", .{ .string = cmd });
        try suppliers.put("_default", .{ .object = default_supplier });
        try new_item.put("expr", .{ .string = "_default" });
    } else {
        try new_item.put("expr", .{ .string = "" });
    }

    try new_item.put("suppliers", .{ .object = suppliers });

    try children.array.append(.{ .object = new_item });
    try persistence.saveVDirJson(io, allocator, vdir_json.value);

    if (inline_cmd) |cmd| {
        std.debug.print("q {s}: {s}\n", .{ name, cmd });
    } else {
        std.debug.print("q {s}\n", .{name});
    }
}
