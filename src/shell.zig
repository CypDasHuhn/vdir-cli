const std = @import("std");
const builtin = @import("builtin");

pub const USER_FILE = ".vdir-user.json";

pub const ShellSource = enum {
    supplier,
    user,
    environment,
    default,
};

pub const ShellConfig = struct {
    program: []const u8,
    execute_arg: []const u8,
    source: ShellSource,

    pub fn deinit(self: ShellConfig, allocator: std.mem.Allocator) void {
        switch (self.source) {
            .user, .environment => {
                allocator.free(self.program);
                allocator.free(self.execute_arg);
            },
            .supplier, .default => {},
        }
    }
};

pub fn resolveDefault(
    io: std.Io,
    environ: std.process.Environ,
    allocator: std.mem.Allocator,
) !ShellConfig {
    if (try loadUserShell(io, environ, allocator)) |config| {
        return .{
            .program = config.program,
            .execute_arg = config.execute_arg,
            .source = .user,
        };
    }

    var env_map = try std.process.Environ.createMap(environ, allocator);
    defer env_map.deinit();

    if (builtin.os.tag == .windows) {
        return .{ .program = "pwsh", .execute_arg = "-Command", .source = .default };
    }

    if (env_map.get("SHELL")) |shell_program| {
        if (shell_program.len > 0) {
            return .{
                .program = try allocator.dupe(u8, shell_program),
                .execute_arg = try allocator.dupe(u8, defaultExecuteArgForProgram(shell_program)),
                .source = .environment,
            };
        }
    }

    return .{ .program = "/bin/sh", .execute_arg = "-c", .source = .default };
}

pub fn resolveForSupplier(supplier: *const std.json.Value, default_shell: ShellConfig) !ShellConfig {
    if (supplier.object.get("shell")) |shell_val| {
        const program = shell_val.object.get("program") orelse return error.InvalidConfig;
        const execute_arg = shell_val.object.get("execute_arg") orelse return error.InvalidConfig;
        return .{
            .program = program.string,
            .execute_arg = execute_arg.string,
            .source = .supplier,
        };
    }

    return default_shell;
}

pub fn defaultExecuteArgForProgram(program: []const u8) []const u8 {
    const basename = std.fs.path.basename(program);
    if (std.ascii.eqlIgnoreCase(basename, "cmd") or std.ascii.eqlIgnoreCase(basename, "cmd.exe")) {
        return "/C";
    }
    if (std.ascii.eqlIgnoreCase(basename, "powershell") or
        std.ascii.eqlIgnoreCase(basename, "powershell.exe") or
        std.ascii.eqlIgnoreCase(basename, "pwsh") or
        std.ascii.eqlIgnoreCase(basename, "pwsh.exe"))
    {
        return "-Command";
    }
    if (std.ascii.eqlIgnoreCase(basename, "nu") or std.ascii.eqlIgnoreCase(basename, "nu.exe")) {
        return "-c";
    }
    if (std.ascii.eqlIgnoreCase(basename, "bash") or
        std.ascii.eqlIgnoreCase(basename, "bash.exe") or
        std.ascii.eqlIgnoreCase(basename, "sh") or
        std.ascii.eqlIgnoreCase(basename, "sh.exe") or
        std.ascii.eqlIgnoreCase(basename, "zsh") or
        std.ascii.eqlIgnoreCase(basename, "zsh.exe") or
        std.ascii.eqlIgnoreCase(basename, "fish") or
        std.ascii.eqlIgnoreCase(basename, "fish.exe") or
        std.ascii.eqlIgnoreCase(basename, "elvish") or
        std.ascii.eqlIgnoreCase(basename, "elvish.exe"))
    {
        return "-c";
    }
    return "-c";
}

pub fn homeDir(environ: std.process.Environ, allocator: std.mem.Allocator) ![]const u8 {
    var env_map = try std.process.Environ.createMap(environ, allocator);
    defer env_map.deinit();

    if (builtin.os.tag == .windows) {
        if (env_map.get("USERPROFILE")) |value| {
            if (value.len > 0) return try allocator.dupe(u8, value);
        }
    } else {
        if (env_map.get("HOME")) |value| {
            if (value.len > 0) return try allocator.dupe(u8, value);
        }
    }

    return error.HomeNotFound;
}

pub fn userConfigPath(environ: std.process.Environ, allocator: std.mem.Allocator) ![]const u8 {
    const home = try homeDir(environ, allocator);
    defer allocator.free(home);
    return try std.fs.path.join(allocator, &[_][]const u8{ home, USER_FILE });
}

pub fn loadUserConfig(
    io: std.Io,
    environ: std.process.Environ,
    allocator: std.mem.Allocator,
) !?std.json.Parsed(std.json.Value) {
    const path = userConfigPath(environ, allocator) catch |err| switch (err) {
        error.HomeNotFound => return null,
        else => return err,
    };
    defer allocator.free(path);

    const cwd = std.Io.Dir.cwd();
    const file = cwd.openFile(io, path, .{}) catch |err| {
        if (err == error.FileNotFound) return null;
        return err;
    };
    defer file.close(io);

    var buffer: [8192]u8 = undefined;
    var reader = file.reader(io, &buffer);
    const content = try reader.interface.allocRemaining(allocator, .limited(1024 * 1024));
    defer allocator.free(content);

    return try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
}

pub fn saveUserConfig(
    io: std.Io,
    environ: std.process.Environ,
    allocator: std.mem.Allocator,
    json: std.json.Value,
) !void {
    const path = try userConfigPath(environ, allocator);
    defer allocator.free(path);

    const cwd = std.Io.Dir.cwd();
    const file = try cwd.createFile(io, path, .{});
    defer file.close(io);

    var buffer: [8192]u8 = undefined;
    var writer = file.writer(io, &buffer);
    try writer.interface.print("{f}", .{std.json.fmt(json, .{ .whitespace = .indent_2 })});
    try writer.interface.writeAll("\n");
    try writer.flush();
}

fn loadUserShell(
    io: std.Io,
    environ: std.process.Environ,
    allocator: std.mem.Allocator,
) !?struct { program: []const u8, execute_arg: []const u8 } {
    var parsed = try loadUserConfig(io, environ, allocator) orelse return null;
    defer parsed.deinit();

    if (parsed.value.object.get("shell")) |shell_val| {
        const program = shell_val.object.get("program") orelse return error.InvalidConfig;
        const execute_arg = shell_val.object.get("execute_arg") orelse return error.InvalidConfig;
        return .{
            .program = try allocator.dupe(u8, program.string),
            .execute_arg = try allocator.dupe(u8, execute_arg.string),
        };
    }

    return null;
}
