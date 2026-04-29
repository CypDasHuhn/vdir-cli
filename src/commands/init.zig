const std = @import("std");
const types = @import("../types.zig");
const persistence = @import("../persistence.zig");

pub fn run(io: std.Io) !void {
    const cwd = std.Io.Dir.cwd();

    cwd.access(io, persistence.VDIR_FILE, .{}) catch |err| {
        if (err == error.FileNotFound) {
            const vdir = types.VDir.init();
            try persistence.saveVDir(io, vdir);
            std.debug.print("Initialized empty vdir\n", .{});
            return;
        }
        return err;
    };

    std.debug.print("vdir already initialized\n", .{});
    std.process.exit(1);
}
