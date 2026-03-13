const std = @import("std");
const persistence = @import("../persistence.zig");
const path = @import("../path.zig");

pub fn run(io: std.Io, allocator: std.mem.Allocator, args: *std.process.Args.Iterator) !void {
    const input_path = args.next() orelse {
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

    const resolved = path.resolve(root, marker, input_path) catch |err| {
        switch (err) {
            path.ResolveError.NotFound => std.debug.print("Path not found: {s}\n", .{input_path}),
            path.ResolveError.NotAFolder => std.debug.print("Not a folder in path: {s}\n", .{input_path}),
            path.ResolveError.InvalidPath => std.debug.print("Invalid path: {s}\n", .{input_path}),
        }
        std.process.exit(1);
    };

    var canonical_path_buffer: [4096]u8 = undefined;
    const canonical_path = path.resolveMarkerPath(canonical_path_buffer[0..], marker, input_path) catch {
        std.debug.print("Invalid path: {s}\n", .{input_path});
        std.process.exit(1);
    };

    const item = resolved.item;
    const item_type_opt = item.object.get("type");
    const item_type = if (item_type_opt) |t| t.string else "folder";
    const display_name = if (resolved.parent == null) "~" else resolved.name;

    std.debug.print("name: {s}\n", .{display_name});
    std.debug.print("path: {s}\n", .{canonical_path});
    std.debug.print("type: {s}\n", .{item_type});

    if (std.mem.eql(u8, item_type, "folder")) {
        const children = item.object.get("children") orelse {
            std.debug.print("children: 0\n", .{});
            return;
        };
        std.debug.print("children: {d}\n", .{children.array.items.len});
        for (children.array.items) |child| {
            const child_type = child.object.get("type").?.string;
            const child_name = child.object.get("name").?.string;
            const prefix: []const u8 = if (std.mem.eql(u8, child_type, "folder"))
                "d"
            else if (std.mem.eql(u8, child_type, "query"))
                "q"
            else
                "r";
            std.debug.print("  {s} {s}\n", .{ prefix, child_name });
        }
        return;
    }

    if (std.mem.eql(u8, item_type, "query")) {
        const scope = item.object.get("scope").?.string;
        const cmd = item.object.get("cmd").?.string;
        std.debug.print("scope: {s}\n", .{scope});
        std.debug.print("cmd: {s}\n", .{if (cmd.len > 0) cmd else "(empty)"});
        return;
    }

    if (std.mem.eql(u8, item_type, "reference")) {
        const target = item.object.get("target").?.string;
        std.debug.print("target: {s}\n", .{target});
        std.debug.print("target_exists: {s}\n", .{if (persistence.fileExists(io, target)) "yes" else "no"});
        return;
    }

    std.debug.print("Unknown item type: {s}\n", .{item_type});
    std.process.exit(1);
}

fn printUsageAndExit() noreturn {
    std.debug.print("Usage: vdir read <path>\n", .{});
    std.process.exit(1);
}
