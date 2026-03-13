const std = @import("std");
const persistence = @import("../persistence.zig");

pub fn run(io: std.Io, allocator: std.mem.Allocator, args: *std.process.Args.Iterator) !void {
    const path = args.next() orelse {
        std.debug.print("Usage: vdir cd <path>\n", .{});
        std.process.exit(1);
    };

    const vdir_json = try persistence.loadVDir(io, allocator) orelse {
        std.debug.print("No vdir found. Run 'vdir init' first.\n", .{});
        std.process.exit(1);
    };
    defer vdir_json.deinit();

    // TODO: Resolve and validate path
    try persistence.saveMarker(io, path);
    std.debug.print("marker: {s}\n", .{path});
}
