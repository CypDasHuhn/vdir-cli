const std = @import("std");

pub fn run(args: *std.process.Args.Iterator) void {
    const name = args.next() orelse {
        std.debug.print("Usage: vdir move <name> <dir>\n", .{});
        std.process.exit(1);
    };
    const dir = args.next() orelse {
        std.debug.print("Usage: vdir move <name> <dir>\n", .{});
        std.process.exit(1);
    };
    _ = name;
    _ = dir;

    std.debug.print("move: not yet implemented\n", .{});
}
