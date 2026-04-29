const std = @import("std");
const persistence = @import("../persistence.zig");

pub fn run(io: std.Io, allocator: std.mem.Allocator) !void {
    var vdir_json = try persistence.loadVDir(io, allocator) orelse {
        std.debug.print("No vdir found. Run 'vdir init' first.\n", .{});
        std.process.exit(1);
    };
    defer vdir_json.deinit();

    const marker_result = try persistence.loadMarker(io, allocator);
    const marker = marker_result orelse "~";
    defer if (marker_result != null) allocator.free(marker_result.?);

    std.debug.print("{s}\n", .{marker});
}
