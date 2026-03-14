const std = @import("std");
const shellmod = @import("../shell.zig");

pub fn run(
    io: std.Io,
    allocator: std.mem.Allocator,
    environ: std.process.Environ,
    args: *std.process.Args.Iterator,
) !void {
    const action = args.next();

    if (action == null) {
        const resolved = shellmod.resolveDefault(io, environ, allocator) catch |err| {
            std.debug.print("Failed to resolve shell: {s}\n", .{@errorName(err)});
            std.process.exit(1);
        };
        defer resolved.deinit(allocator);
        std.debug.print("program: {s}\n", .{resolved.program});
        std.debug.print("execute_arg: {s}\n", .{resolved.execute_arg});
        std.debug.print("source: {s}\n", .{@tagName(resolved.source)});
        return;
    }

    if (std.mem.eql(u8, action.?, "clear")) {
        var config = try loadOrInitUserConfig(io, environ, allocator);
        defer config.deinit();

        _ = config.value.object.orderedRemove("shell");
        try shellmod.saveUserConfig(io, environ, allocator, config.value);
        std.debug.print("shell cleared\n", .{});
        return;
    }

    if (!std.mem.eql(u8, action.?, "set")) {
        printUsage();
        std.process.exit(1);
    }

    const program = args.next() orelse {
        printUsage();
        std.process.exit(1);
    };
    const execute_arg = args.next() orelse shellmod.defaultExecuteArgForProgram(program);

    var config = try loadOrInitUserConfig(io, environ, allocator);
    defer config.deinit();

    const json_allocator = config.arena.allocator();
    var shell_obj = std.json.ObjectMap.init(json_allocator);
    try shell_obj.put("program", .{ .string = try json_allocator.dupe(u8, program) });
    try shell_obj.put("execute_arg", .{ .string = try json_allocator.dupe(u8, execute_arg) });
    try config.value.object.put("shell", .{ .object = shell_obj });

    if (config.value.object.get("opened_once") == null) {
        try config.value.object.put("opened_once", .{ .bool = false });
    }

    try shellmod.saveUserConfig(io, environ, allocator, config.value);
    std.debug.print("shell.program = {s}\n", .{program});
    std.debug.print("shell.execute_arg = {s}\n", .{execute_arg});
}

fn loadOrInitUserConfig(
    io: std.Io,
    environ: std.process.Environ,
    allocator: std.mem.Allocator,
) !std.json.Parsed(std.json.Value) {
    if (try shellmod.loadUserConfig(io, environ, allocator)) |parsed| {
        return parsed;
    }

    const arena = try allocator.create(std.heap.ArenaAllocator);
    errdefer allocator.destroy(arena);
    arena.* = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const arena_allocator = arena.allocator();

    var root = std.json.ObjectMap.init(arena_allocator);
    try root.put("opened_once", .{ .bool = false });

    return .{
        .arena = arena,
        .value = .{ .object = root },
    };
}

fn printUsage() void {
    std.debug.print(
        \\Usage: vdir shell [set <program> [execute_arg] | clear]
        \\
        \\Examples:
        \\  vdir shell
        \\  vdir shell set pwsh -Command
        \\  vdir shell set bash
        \\  vdir shell set cmd /C
        \\  vdir shell clear
        \\
    , .{});
}
