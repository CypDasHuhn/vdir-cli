const std = @import("std");
const persistence = @import("../persistence.zig");
const path = @import("../path.zig");

pub fn run(io: std.Io, allocator: std.mem.Allocator, args: *std.process.Args.Iterator) !void {
    _ = args; // TODO: handle flags (-a, -l, -r)

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

    // Resolve marker to current folder
    const current = path.resolveMarker(root, marker) catch |err| {
        switch (err) {
            path.ResolveError.NotFound => std.debug.print("Current path not found: {s}\n", .{marker}),
            path.ResolveError.NotAFolder => std.debug.print("Not a folder: {s}\n", .{marker}),
            path.ResolveError.InvalidPath => std.debug.print("Invalid path: {s}\n", .{marker}),
        }
        std.process.exit(1);
    };

    const children = current.object.get("children") orelse {
        // Not a folder (query or reference) - just show info
        const item_type = current.object.get("type").?.string;
        if (std.mem.eql(u8, item_type, "query")) {
            const cmd = current.object.get("cmd").?.string;
            std.debug.print("query: {s}\n", .{if (cmd.len > 0) cmd else "(empty)"});
        } else if (std.mem.eql(u8, item_type, "reference")) {
            const target = current.object.get("target").?.string;
            std.debug.print("reference -> {s}\n", .{target});
        }
        return;
    };

    for (children.array.items) |child| {
        const item_type = child.object.get("type").?.string;
        const item_name = child.object.get("name").?.string;
        const prefix: []const u8 = if (std.mem.eql(u8, item_type, "folder"))
            "d"
        else if (std.mem.eql(u8, item_type, "query"))
            "q"
        else
            "r";
        std.debug.print("{s} {s}\n", .{ prefix, item_name });
    }
}
