const std = @import("std");
const persistence = @import("../persistence.zig");

pub fn run(io: std.Io, allocator: std.mem.Allocator) !void {
    const marker_result = try persistence.loadMarker(io, allocator);
    const marker = marker_result orelse "~";
    defer if (marker_result != null) allocator.free(marker_result.?);

    std.debug.print("{s}\n", .{marker});
}
