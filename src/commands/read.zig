const std = @import("std");

pub fn run(args: *std.process.Args.Iterator) void {
    const name = args.next() orelse {
        std.debug.print("Usage: vdir read <name>\n", .{});
        std.process.exit(1);
    };
    _ = name;

    std.debug.print("read: not yet implemented\n", .{});
}
