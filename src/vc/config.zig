const std = @import("std");
const shellmod = @import("shared_shell");

pub const USER_FILE = ".vdir-vc.json";

pub const default_config_json =
    \\{
    \\  "rules": [
    \\    {
    \\      "matches": ["rg"],
    \\      "shells": {
    \\        "nu": "rg -l ${input} (pwd)",
    \\        "pwsh": "rg -l ${input} (Get-Location)",
    \\        "powershell": "rg -l ${input} (Get-Location)",
    \\        "cmd": "rg -l ${input} %CD%",
    \\        "bash": "rg -l ${input} \"$(pwd)\"",
    \\        "sh": "rg -l ${input} \"$(pwd)\"",
    \\        "zsh": "rg -l ${input} \"$(pwd)\"",
    \\        "fish": "rg -l ${input} (pwd)",
    \\        "default": "rg -l ${input} ."
    \\      }
    \\    }
    \\  ]
    \\}
;

pub fn configPath(environ: std.process.Environ, allocator: std.mem.Allocator) ![]const u8 {
    const home = try shellmod.homeDir(environ, allocator);
    defer allocator.free(home);
    return try std.fs.path.join(allocator, &[_][]const u8{ home, USER_FILE });
}

pub fn load(
    io: std.Io,
    environ: std.process.Environ,
    allocator: std.mem.Allocator,
) !struct { parsed: std.json.Parsed(std.json.Value), source: Source } {
    const path = configPath(environ, allocator) catch |err| switch (err) {
        error.HomeNotFound => {
            return .{
                .parsed = try std.json.parseFromSlice(std.json.Value, allocator, default_config_json, .{}),
                .source = .builtin,
            };
        },
        else => return err,
    };
    defer allocator.free(path);

    const cwd = std.Io.Dir.cwd();
    const file = cwd.openFile(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            return .{
                .parsed = try std.json.parseFromSlice(std.json.Value, allocator, default_config_json, .{}),
                .source = .builtin,
            };
        },
        else => return err,
    };
    defer file.close(io);

    var buffer: [8192]u8 = undefined;
    var reader = file.reader(io, &buffer);
    const content = try reader.interface.allocRemaining(allocator, .limited(1024 * 1024));
    defer allocator.free(content);

    return .{
        .parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{}),
        .source = .user,
    };
}

pub fn initUserConfig(
    io: std.Io,
    environ: std.process.Environ,
    allocator: std.mem.Allocator,
) ![]const u8 {
    const path = try configPath(environ, allocator);
    errdefer allocator.free(path);

    const cwd = std.Io.Dir.cwd();
    const file = try cwd.createFile(io, path, .{});
    defer file.close(io);

    var buffer: [8192]u8 = undefined;
    var writer = file.writer(io, &buffer);
    try writer.interface.writeAll(default_config_json);
    try writer.interface.writeAll("\n");
    try writer.flush();

    return path;
}

pub const Source = enum {
    builtin,
    user,
};
