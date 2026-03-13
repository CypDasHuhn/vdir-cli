const std = @import("std");

pub fn run(args: *std.process.Args.Iterator) void {
    const old = args.next() orelse {
        std.debug.print("Usage: vdir rename <old> <new>\n", .{});
        std.process.exit(1);
    };
    const new = args.next() orelse {
        std.debug.print("Usage: vdir rename <old> <new>\n", .{});
        std.process.exit(1);
    };
    _ = old;
    _ = new;

    std.debug.print("rename: not yet implemented\n", .{});
}
