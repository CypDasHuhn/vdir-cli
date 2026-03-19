const std = @import("std");
const config = @import("config.zig");

pub const ContainerError = error{
    SpawnFailed,
    CommandFailed,
    InvalidOutput,
    OutOfMemory,
};

/// List compilers provided by a container
/// Runs: <container> list
/// Returns newline-separated compiler names
pub fn listCompilers(io: std.Io, allocator: std.mem.Allocator, container_path: []const u8) ![][]const u8 {
    var child = std.process.spawn(io, .{
        .argv = &[_][]const u8{ container_path, "list" },
        .stdout = .pipe,
        .stderr = .ignore,
    }) catch {
        return ContainerError.SpawnFailed;
    };

    const stdout = child.stdout orelse return ContainerError.SpawnFailed;
    var buffer: [8192]u8 = undefined;
    var reader = stdout.reader(io, &buffer);

    const output = reader.interface.allocRemaining(allocator, .limited(64 * 1024)) catch {
        _ = child.wait(io) catch {};
        return ContainerError.OutOfMemory;
    };
    defer allocator.free(output);

    const term = child.wait(io) catch {
        return ContainerError.CommandFailed;
    };

    switch (term) {
        .exited => |code| if (code != 0) return ContainerError.CommandFailed,
        else => return ContainerError.CommandFailed,
    }

    // Parse output - one compiler name per line
    var compilers: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (compilers.items) |c| allocator.free(c);
        compilers.deinit(allocator);
    }

    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len > 0) {
            try compilers.append(allocator, try allocator.dupe(u8, trimmed));
        }
    }

    return try compilers.toOwnedSlice(allocator);
}

/// Shell command map: shell name -> command
pub const ShellCommandMap = std.StringHashMap([]const u8);

/// Run a compiler with arguments
/// Runs: <container> run <compiler_name> <args...>
/// Returns parsed shell -> command map
pub fn runCompiler(
    io: std.Io,
    allocator: std.mem.Allocator,
    container_path: []const u8,
    compiler_name: []const u8,
    args: []const u8,
) !ShellCommandMap {
    // Build argv: container run compiler_name args
    var argv_list: std.ArrayList([]const u8) = .empty;
    defer argv_list.deinit(allocator);

    try argv_list.append(allocator, container_path);
    try argv_list.append(allocator, "run");
    try argv_list.append(allocator, compiler_name);
    if (args.len > 0) {
        try argv_list.append(allocator, args);
    }

    var child = std.process.spawn(io, .{
        .argv = argv_list.items,
        .stdout = .pipe,
        .stderr = .ignore,
    }) catch {
        return ContainerError.SpawnFailed;
    };

    const stdout = child.stdout orelse return ContainerError.SpawnFailed;
    var buffer: [8192]u8 = undefined;
    var reader = stdout.reader(io, &buffer);

    const output = reader.interface.allocRemaining(allocator, .limited(64 * 1024)) catch {
        _ = child.wait(io) catch {};
        return ContainerError.OutOfMemory;
    };
    defer allocator.free(output);

    const term = child.wait(io) catch {
        return ContainerError.CommandFailed;
    };

    switch (term) {
        .exited => |code| if (code != 0) return ContainerError.CommandFailed,
        else => return ContainerError.CommandFailed,
    }

    return try parseCompilerOutput(allocator, output);
}

/// Parse compiler output in plain text format:
/// shell: command
/// e.g.:
/// bash: rg -l 'pattern' .
/// nu: rg -l 'pattern' (pwd)
pub fn parseCompilerOutput(allocator: std.mem.Allocator, output: []const u8) !ShellCommandMap {
    var map = ShellCommandMap.init(allocator);
    errdefer {
        var it = map.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        map.deinit();
    }

    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        // Find first colon
        if (std.mem.indexOfScalar(u8, trimmed, ':')) |colon_idx| {
            const shell_name = std.mem.trim(u8, trimmed[0..colon_idx], " \t");
            const command = std.mem.trim(u8, trimmed[colon_idx + 1 ..], " \t");

            if (shell_name.len > 0 and command.len > 0) {
                const key = try allocator.dupe(u8, shell_name);
                errdefer allocator.free(key);
                const val = try allocator.dupe(u8, command);
                try map.put(key, val);
            }
        }
    }

    return map;
}

/// Convert ShellCommandMap to JSON ObjectMap for storage
pub fn shellMapToJson(allocator: std.mem.Allocator, shell_map: *const ShellCommandMap) !std.json.ObjectMap {
    var json_map = std.json.ObjectMap.init(allocator);
    errdefer json_map.deinit();

    var it = shell_map.iterator();
    while (it.next()) |entry| {
        const key = try allocator.dupe(u8, entry.key_ptr.*);
        const val = try allocator.dupe(u8, entry.value_ptr.*);
        try json_map.put(key, .{ .string = val });
    }

    return json_map;
}

/// Rebuild the compiler cache by querying all containers
pub fn rebuildCache(io: std.Io, allocator: std.mem.Allocator) ![]config.CacheEntry {
    const containers = try config.loadContainers(io, allocator);
    defer {
        for (containers) |c| allocator.free(c);
        allocator.free(containers);
    }

    var entries: std.ArrayList(config.CacheEntry) = .empty;
    errdefer {
        for (entries.items) |e| {
            allocator.free(e.compiler);
            allocator.free(e.container);
        }
        entries.deinit(allocator);
    }

    for (containers) |container_path| {
        const compilers = listCompilers(io, allocator, container_path) catch continue;
        defer {
            for (compilers) |c| allocator.free(c);
            allocator.free(compilers);
        }

        for (compilers) |compiler_name| {
            try entries.append(allocator, .{
                .compiler = try allocator.dupe(u8, compiler_name),
                .container = try allocator.dupe(u8, container_path),
            });
        }
    }

    const result = try entries.toOwnedSlice(allocator);

    // Save to cache file
    try config.saveCompilerCache(io, allocator, result);

    return result;
}
