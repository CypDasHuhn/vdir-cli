const std = @import("std");
const builtin = @import("builtin");

pub const COMPILERS_FILE = "compilers.txt";
pub const CACHE_FILE = "compiler-cache.txt";

pub const ConfigError = error{
    HomeNotFound,
    OutOfMemory,
    AccessDenied,
    FileNotFound,
};

/// Get the home directory path
pub fn getHomeDir(allocator: std.mem.Allocator) ![]const u8 {
    if (builtin.os.tag == .windows) {
        if (std.c.getenv("USERPROFILE")) |ptr| {
            return try allocator.dupe(u8, std.mem.span(ptr));
        }
    }

    if (std.c.getenv("HOME")) |ptr| {
        return try allocator.dupe(u8, std.mem.span(ptr));
    }

    return ConfigError.HomeNotFound;
}

/// Get the vdir config directory path (~/.vdir)
pub fn getConfigDir(allocator: std.mem.Allocator) ![]const u8 {
    const home = try getHomeDir(allocator);
    defer allocator.free(home);

    return try std.fs.path.join(allocator, &.{ home, ".vdir" });
}

/// Ensure the config directory exists
pub fn ensureConfigDir(io: std.Io, allocator: std.mem.Allocator) !void {
    const config_dir = try getConfigDir(allocator);
    defer allocator.free(config_dir);

    // Check if directory exists by trying to open it
    const cwd = std.Io.Dir.cwd();
    if (cwd.openDir(io, config_dir, .{})) |dir| {
        dir.close(io);
        return; // Already exists
    } else |_| {}

    // Create directory using mkdir command
    var child = std.process.spawn(io, .{
        .argv = &[_][]const u8{ "mkdir", "-p", config_dir },
        .stdout = .ignore,
        .stderr = .ignore,
    }) catch return ConfigError.AccessDenied;

    const term = child.wait(io) catch return ConfigError.AccessDenied;
    switch (term) {
        .exited => |code| if (code != 0) return ConfigError.AccessDenied,
        else => return ConfigError.AccessDenied,
    }
}

/// Load container paths from compilers.txt
pub fn loadContainers(io: std.Io, allocator: std.mem.Allocator) ![][]const u8 {
    const config_dir = try getConfigDir(allocator);
    defer allocator.free(config_dir);

    const file_path = try std.fs.path.join(allocator, &.{ config_dir, COMPILERS_FILE });
    defer allocator.free(file_path);

    const cwd = std.Io.Dir.cwd();
    const file = cwd.openFile(io, file_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            return allocator.alloc([]const u8, 0);
        }
        return err;
    };
    defer file.close(io);

    var containers: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (containers.items) |item| allocator.free(item);
        containers.deinit(allocator);
    }

    var buf: [4096]u8 = undefined;
    var reader = file.reader(io, &buf);
    const content = reader.interface.allocRemaining(allocator, .limited(64 * 1024)) catch |err| {
        return err;
    };
    defer allocator.free(content);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        // Skip empty lines and comments
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        try containers.append(allocator, try allocator.dupe(u8, trimmed));
    }

    return try containers.toOwnedSlice(allocator);
}

/// Save container paths to compilers.txt
pub fn saveContainers(io: std.Io, allocator: std.mem.Allocator, containers: []const []const u8) !void {
    try ensureConfigDir(io, allocator);

    const config_dir = try getConfigDir(allocator);
    defer allocator.free(config_dir);

    const file_path = try std.fs.path.join(allocator, &.{ config_dir, COMPILERS_FILE });
    defer allocator.free(file_path);

    const cwd = std.Io.Dir.cwd();
    const file = try cwd.createFile(io, file_path, .{});
    defer file.close(io);

    var buffer: [4096]u8 = undefined;
    var writer = file.writer(io, &buffer);
    for (containers) |container| {
        try writer.interface.writeAll(container);
        try writer.interface.writeAll("\n");
    }
    try writer.flush();
}

/// Add a container path to compilers.txt
pub fn addContainer(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !void {
    const containers = try loadContainers(io, allocator);
    defer {
        for (containers) |c| allocator.free(c);
        allocator.free(containers);
    }

    // Check if already exists
    for (containers) |c| {
        if (std.mem.eql(u8, c, path)) {
            return; // Already exists
        }
    }

    // Create new list with the added container
    var new_containers = try allocator.alloc([]const u8, containers.len + 1);
    defer allocator.free(new_containers);

    for (containers, 0..) |c, i| {
        new_containers[i] = c;
    }
    new_containers[containers.len] = path;

    try saveContainers(io, allocator, new_containers);
}

/// Remove a container path from compilers.txt
pub fn removeContainer(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !bool {
    const containers = try loadContainers(io, allocator);
    defer {
        for (containers) |c| allocator.free(c);
        allocator.free(containers);
    }

    // Find and remove
    var found = false;
    var new_list: std.ArrayList([]const u8) = .empty;
    defer new_list.deinit(allocator);

    for (containers) |c| {
        if (std.mem.eql(u8, c, path)) {
            found = true;
        } else {
            try new_list.append(allocator, c);
        }
    }

    if (found) {
        try saveContainers(io, allocator, new_list.items);
    }

    return found;
}

/// Cache entry: compiler_name -> container_path
pub const CacheEntry = struct {
    compiler: []const u8,
    container: []const u8,
};

/// Load compiler cache from compiler-cache.txt
pub fn loadCompilerCache(io: std.Io, allocator: std.mem.Allocator) ![]CacheEntry {
    const config_dir = try getConfigDir(allocator);
    defer allocator.free(config_dir);

    const file_path = try std.fs.path.join(allocator, &.{ config_dir, CACHE_FILE });
    defer allocator.free(file_path);

    const cwd = std.Io.Dir.cwd();
    const file = cwd.openFile(io, file_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            return allocator.alloc(CacheEntry, 0);
        }
        return err;
    };
    defer file.close(io);

    var entries: std.ArrayList(CacheEntry) = .empty;
    errdefer {
        for (entries.items) |e| {
            allocator.free(e.compiler);
            allocator.free(e.container);
        }
        entries.deinit(allocator);
    }

    var buf: [4096]u8 = undefined;
    var reader = file.reader(io, &buf);
    const content = reader.interface.allocRemaining(allocator, .limited(64 * 1024)) catch |err| {
        return err;
    };
    defer allocator.free(content);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Format: compiler_name:container_path
        if (std.mem.indexOfScalar(u8, trimmed, ':')) |idx| {
            const compiler = trimmed[0..idx];
            const container = trimmed[idx + 1 ..];
            try entries.append(allocator, .{
                .compiler = try allocator.dupe(u8, compiler),
                .container = try allocator.dupe(u8, container),
            });
        }
    }

    return try entries.toOwnedSlice(allocator);
}

/// Save compiler cache to compiler-cache.txt
pub fn saveCompilerCache(io: std.Io, allocator: std.mem.Allocator, entries: []const CacheEntry) !void {
    try ensureConfigDir(io, allocator);

    const config_dir = try getConfigDir(allocator);
    defer allocator.free(config_dir);

    const file_path = try std.fs.path.join(allocator, &.{ config_dir, CACHE_FILE });
    defer allocator.free(file_path);

    const cwd = std.Io.Dir.cwd();
    const file = try cwd.createFile(io, file_path, .{});
    defer file.close(io);

    var buffer: [4096]u8 = undefined;
    var writer = file.writer(io, &buffer);
    for (entries) |entry| {
        try writer.interface.writeAll(entry.compiler);
        try writer.interface.writeAll(":");
        try writer.interface.writeAll(entry.container);
        try writer.interface.writeAll("\n");
    }
    try writer.flush();
}

/// Find which container provides a compiler
pub fn findCompilerContainer(io: std.Io, allocator: std.mem.Allocator, compiler_name: []const u8) !?[]const u8 {
    const cache = try loadCompilerCache(io, allocator);
    defer {
        for (cache) |e| {
            allocator.free(e.compiler);
            allocator.free(e.container);
        }
        allocator.free(cache);
    }

    for (cache) |entry| {
        if (std.mem.eql(u8, entry.compiler, compiler_name)) {
            return try allocator.dupe(u8, entry.container);
        }
    }

    return null;
}
