const std = @import("std");
const persistence = @import("../persistence.zig");

pub fn run(allocator: std.mem.Allocator) !void {
    var vdir_json = try persistence.loadVDir(allocator) orelse {
        std.debug.print("No vdir found. Run 'vdir init' first.\n", .{});
        std.process.exit(1);
    };
    defer vdir_json.deinit();

    const marker_result = try persistence.loadMarker(allocator);
    const marker = marker_result orelse "~";
    defer if (marker_result != null) allocator.free(marker_result.?);

    std.debug.print("{s}\n", .{marker});
}
