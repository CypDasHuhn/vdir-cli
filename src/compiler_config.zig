const std = @import("std");
const shellmod = @import("shell.zig");

pub const CompilerConfig = struct {
    program: []const u8,
    source: Source,

    pub const Source = enum {
        user,
    };

    pub fn deinit(self: CompilerConfig, allocator: std.mem.Allocator) void {
        switch (self.source) {
            .user => allocator.free(self.program),
        }
    }
};

pub fn resolveConfigured(
    io: std.Io,
    environ: std.process.Environ,
    allocator: std.mem.Allocator,
) !?CompilerConfig {
    var parsed = try shellmod.loadUserConfig(io, environ, allocator) orelse return null;
    defer parsed.deinit();

    const compiler_val = parsed.value.object.get("compiler") orelse return null;
    const program_val = compiler_val.object.get("program") orelse return error.InvalidConfig;

    return .{
        .program = try allocator.dupe(u8, program_val.string),
        .source = .user,
    };
}

pub fn compileCommand(
    allocator: std.mem.Allocator,
    io: std.Io,
    compiler: CompilerConfig,
    shell_program: []const u8,
    input: []const u8,
) ![]u8 {
    const run_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{
            compiler.program,
            "compile",
            "--shell",
            shell_program,
            "--input",
            input,
        },
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(64 * 1024),
    });
    defer allocator.free(run_result.stdout);
    defer allocator.free(run_result.stderr);

    switch (run_result.term) {
        .exited => |code| if (code != 0) return error.CommandFailed,
        else => return error.CommandFailed,
    }

    const trimmed = std.mem.trim(u8, run_result.stdout, " \t\r\n");
    return try allocator.dupe(u8, trimmed);
}
