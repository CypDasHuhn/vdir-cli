const std = @import("std");
const persistence = @import("../persistence.zig");
const path = @import("../path.zig");

const ItemType = enum { folder, query, reference };

pub fn run(io: std.Io, allocator: std.mem.Allocator, args: *std.process.Args.Iterator) !void {
    var query_mode = false;
    var positional: [2][]const u8 = undefined;
    var positional_count: usize = 0;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-q") or std.mem.eql(u8, arg, "--query")) {
            query_mode = true;
        } else {
            if (positional_count >= positional.len) {
                printUsageAndExit();
            }
            positional[positional_count] = arg;
            positional_count += 1;
        }
    }

    if (positional_count == 0) {
        printUsageAndExit();
    }

    var item_type: ItemType = undefined;
    var name: []const u8 = undefined;
    var target: ?[]const u8 = null;

    if (query_mode) {
        if (positional_count != 1) {
            printUsageAndExit();
        }
        item_type = .query;
        name = positional[0];
    } else if (persistence.fileExists(io, positional[0])) {
        item_type = .reference;
        target = positional[0];
        if (positional_count == 2) {
            name = positional[1];
        } else {
            name = std.fs.path.basename(target.?);
        }
    } else {
        if (positional_count != 1) {
            printUsageAndExit();
        }
        item_type = .folder;
        name = positional[0];
    }

    var vdir_json = try persistence.loadVDir(io, allocator) orelse {
        std.debug.print("No vdir found. Run 'vdir init' first.\n", .{});
        std.process.exit(1);
    };
    defer vdir_json.deinit();

    const root = vdir_json.value.object.getPtr("root") orelse {
        std.debug.print("Invalid vdir format\n", .{});
        std.process.exit(1);
    };

    const marker_result = try persistence.loadMarker(io, allocator);
    const marker = marker_result orelse "~";
    defer if (marker_result != null) allocator.free(marker_result.?);

    const current = path.resolveMarker(root, marker) catch |err| {
        switch (err) {
            path.ResolveError.NotFound => std.debug.print("Current path not found: {s}\n", .{marker}),
            path.ResolveError.NotAFolder => std.debug.print("Not a folder: {s}\n", .{marker}),
            path.ResolveError.InvalidPath => std.debug.print("Invalid path: {s}\n", .{marker}),
        }
        std.process.exit(1);
    };

    const children = current.object.getPtr("children") orelse {
        std.debug.print("Cannot add items under non-folder marker: {s}\n", .{marker});
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

    switch (item_type) {
        .folder => {
            try new_item.put("type", .{ .string = "folder" });
            try new_item.put("name", .{ .string = name });
            try new_item.put("children", .{ .array = std.json.Array.init(json_allocator) });
            std.debug.print("d {s}\n", .{name});
        },
        .query => {
            try new_item.put("type", .{ .string = "query" });
            try new_item.put("name", .{ .string = name });
            try new_item.put("scope", .{ .string = "." });
            try new_item.put("cmd", .{ .string = "" });
            std.debug.print("q {s}\n", .{name});
        },
        .reference => {
            try new_item.put("type", .{ .string = "reference" });
            try new_item.put("name", .{ .string = name });
            try new_item.put("target", .{ .string = target.? });
            std.debug.print("r {s} -> {s}\n", .{ name, target.? });
        },
    }

    try children.array.append(.{ .object = new_item });

    try persistence.saveVDirJson(io, allocator, vdir_json.value);
}

fn printUsageAndExit() noreturn {
    std.debug.print("Usage: vdir add <name>           (create folder)\n", .{});
    std.debug.print("       vdir add -q <name>        (create query)\n", .{});
    std.debug.print("       vdir add <path> [name]    (create reference)\n", .{});
    std.process.exit(1);
}
