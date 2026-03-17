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
        if (try shellmod.loadUserConfig(io, environ, allocator)) |parsed| {
            defer parsed.deinit();

            if (parsed.value.object.get("compiler")) |compiler_val| {
                const program = compiler_val.object.get("program") orelse {
                    std.debug.print("compiler: invalid config\n", .{});
                    std.process.exit(1);
                };
                std.debug.print("program: {s}\n", .{program.string});
                return;
            }
        }

        std.debug.print("(none)\n", .{});
        return;
    }

    if (std.mem.eql(u8, action.?, "clear")) {
        var config = try loadOrInitUserConfig(io, environ, allocator);
        defer config.deinit();

        _ = config.value.object.orderedRemove("compiler");
        try shellmod.saveUserConfig(io, environ, allocator, config.value);
        std.debug.print("compiler cleared\n", .{});
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

    var config = try loadOrInitUserConfig(io, environ, allocator);
    defer config.deinit();

    const json_allocator = config.arena.allocator();
    var compiler_obj = std.json.ObjectMap.init(json_allocator);
    try compiler_obj.put("program", .{ .string = try json_allocator.dupe(u8, program) });
    try config.value.object.put("compiler", .{ .object = compiler_obj });

    if (config.value.object.get("opened_once") == null) {
        try config.value.object.put("opened_once", .{ .bool = false });
    }

    try shellmod.saveUserConfig(io, environ, allocator, config.value);
    std.debug.print("compiler.program = {s}\n", .{program});
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
        \\Usage: vdir compiler [set <program> | clear]
        \\
        \\Examples:
        \\  vdir compiler
        \\  vdir compiler set vc
        \\  vdir compiler clear
        \\
    , .{});
}
