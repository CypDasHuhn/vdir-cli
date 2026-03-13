const std = @import("std");
const persistence = @import("../persistence.zig");
const path = @import("../path.zig");

pub fn run(io: std.Io, allocator: std.mem.Allocator, args: *std.process.Args.Iterator) !void {
    const target_path = args.next() orelse {
        std.debug.print("Usage: vdir cd <path>\n", .{});
        std.process.exit(1);
    };

    if (args.next() != null) {
        std.debug.print("Usage: vdir cd <path>\n", .{});
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

    var marker_buffer: [4096]u8 = undefined;
    const canonical_path = path.resolveMarkerPath(marker_buffer[0..], marker, target_path) catch {
        std.debug.print("Invalid path: {s}\n", .{target_path});
        std.process.exit(1);
    };

    const target = path.resolveMarker(root, canonical_path) catch |err| {
        switch (err) {
            path.ResolveError.NotFound => std.debug.print("Path not found: {s}\n", .{target_path}),
            path.ResolveError.NotAFolder => std.debug.print("Not a folder: {s}\n", .{target_path}),
            path.ResolveError.InvalidPath => std.debug.print("Invalid path: {s}\n", .{target_path}),
        }
        std.process.exit(1);
    };

    _ = target.object.get("children") orelse {
        std.debug.print("Not a folder: {s}\n", .{target_path});
        std.process.exit(1);
    };

    try persistence.saveMarker(io, canonical_path);
    std.debug.print("marker: {s}\n", .{canonical_path});
}
