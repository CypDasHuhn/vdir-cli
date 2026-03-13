const std = @import("std");
const types = @import("types.zig");

pub const VDIR_FILE = ".vdir.json";
pub const MARKER_FILE = ".vdir-marker";

pub fn loadMarker(io: std.Io, allocator: std.mem.Allocator) !?[]const u8 {
    const cwd = std.Io.Dir.cwd();
    const file = cwd.openFile(io, MARKER_FILE, .{}) catch |err| {
        if (err == error.FileNotFound) return null;
        return err;
    };
    defer file.close(io);

    var buffer: [4096]u8 = undefined;
    var reader = file.reader(io, &buffer);
    const content = reader.interface.allocRemaining(allocator, .limited(4096)) catch |err| {
        return err;
    };

    const trimmed = std.mem.trimEnd(u8, content, "\n\r");
    if (trimmed.len != content.len) {
        const result = try allocator.dupe(u8, trimmed);
        allocator.free(content);
        return result;
    }
    return content;
}

pub fn saveMarker(io: std.Io, path: []const u8) !void {
    const cwd = std.Io.Dir.cwd();
    const file = try cwd.createFile(io, MARKER_FILE, .{});
    defer file.close(io);

    var buffer: [4096]u8 = undefined;
    var writer = file.writer(io, &buffer);
    try writer.interface.writeAll(path);
    try writer.interface.writeAll("\n");
    try writer.flush();
}

pub fn loadVDir(io: std.Io, allocator: std.mem.Allocator) !?std.json.Parsed(std.json.Value) {
    const cwd = std.Io.Dir.cwd();
    const file = cwd.openFile(io, VDIR_FILE, .{}) catch |err| {
        if (err == error.FileNotFound) return null;
        return err;
    };
    defer file.close(io);

    var buffer: [8192]u8 = undefined;
    var reader = file.reader(io, &buffer);
    const content = reader.interface.allocRemaining(allocator, .limited(1024 * 1024)) catch |err| {
        return err;
    };
    defer allocator.free(content);

    return try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
}

pub fn saveVDir(io: std.Io, vdir: types.VDir) !void {
    const cwd = std.Io.Dir.cwd();
    const file = try cwd.createFile(io, VDIR_FILE, .{});
    defer file.close(io);

    var buffer: [8192]u8 = undefined;
    var writer = file.writer(io, &buffer);

    _ = vdir;
    try writer.interface.writeAll(
        \\{
        \\  "root": {
        \\    "name": "",
        \\    "children": []
        \\  }
        \\}
        \\
    );
    try writer.flush();
}

pub fn saveVDirJson(io: std.Io, allocator: std.mem.Allocator, json: std.json.Value) !void {
    _ = allocator;
    const cwd = std.Io.Dir.cwd();
    const file = try cwd.createFile(io, VDIR_FILE, .{});
    defer file.close(io);

    var buffer: [16384]u8 = undefined;
    var writer = file.writer(io, &buffer);

    try writer.interface.print("{f}", .{std.json.fmt(json, .{ .whitespace = .indent_2 })});
    try writer.interface.writeAll("\n");
    try writer.flush();
}

pub fn fileExists(io: std.Io, path: []const u8) bool {
    const cwd = std.Io.Dir.cwd();
    cwd.access(io, path, .{}) catch return false;
    return true;
}
