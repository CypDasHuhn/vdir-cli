const std = @import("std");
const config = @import("../config.zig");
const container = @import("../container.zig");

pub fn run(io: std.Io, allocator: std.mem.Allocator, args: *std.process.Args.Iterator) !void {
    const subcommand = args.next() orelse {
        printUsage();
        return;
    };

    if (std.mem.eql(u8, subcommand, "containers")) {
        try handleContainers(io, allocator);
    } else if (std.mem.eql(u8, subcommand, "add")) {
        try handleAdd(io, allocator, args);
    } else if (std.mem.eql(u8, subcommand, "remove")) {
        try handleRemove(io, allocator, args);
    } else if (std.mem.eql(u8, subcommand, "reload")) {
        try handleReload(io, allocator);
    } else if (std.mem.eql(u8, subcommand, "list")) {
        try handleList(io, allocator, args);
    } else if (std.mem.eql(u8, subcommand, "which")) {
        try handleWhich(io, allocator, args);
    } else if (std.mem.eql(u8, subcommand, "test")) {
        try handleTest(io, allocator, args);
    } else {
        std.debug.print("Unknown subcommand: {s}\n", .{subcommand});
        printUsage();
    }
}

fn printUsage() void {
    std.debug.print(
        \\Usage: vdir compiler <subcommand>
        \\
        \\Subcommands:
        \\  containers           List registered containers
        \\  add <path>           Add a container
        \\  remove <path>        Remove a container
        \\  reload               Reload compiler cache from containers
        \\  list [--container <name>]  List available compilers
        \\  which <name>         Show which container provides a compiler
        \\  test <name> <args>   Test a compiler transformation
        \\
    , .{});
}

fn handleContainers(io: std.Io, allocator: std.mem.Allocator) !void {
    const containers = try config.loadContainers(io, allocator);
    defer {
        for (containers) |c| allocator.free(c);
        allocator.free(containers);
    }

    if (containers.len == 0) {
        std.debug.print("No containers registered.\n", .{});
        std.debug.print("Use 'vdir compiler add <path>' to add a container.\n", .{});
        return;
    }

    std.debug.print("Registered containers:\n", .{});
    for (containers) |c| {
        std.debug.print("  {s}\n", .{c});
    }
}

fn handleAdd(io: std.Io, allocator: std.mem.Allocator, args: *std.process.Args.Iterator) !void {
    const path = args.next() orelse {
        std.debug.print("Usage: vdir compiler add <path>\n", .{});
        std.process.exit(1);
    };

    // Validate path exists
    const cwd = std.Io.Dir.cwd();
    cwd.access(io, path, .{}) catch {
        std.debug.print("Container not found: {s}\n", .{path});
        std.process.exit(1);
    };

    try config.addContainer(io, allocator, path);
    std.debug.print("Added container: {s}\n", .{path});

    // Rebuild cache
    std.debug.print("Rebuilding compiler cache...\n", .{});
    const entries = try container.rebuildCache(io, allocator);
    defer {
        for (entries) |e| {
            allocator.free(e.compiler);
            allocator.free(e.container);
        }
        allocator.free(entries);
    }
    std.debug.print("Cache updated with {d} compiler(s).\n", .{entries.len});
}

fn handleRemove(io: std.Io, allocator: std.mem.Allocator, args: *std.process.Args.Iterator) !void {
    const path = args.next() orelse {
        std.debug.print("Usage: vdir compiler remove <path>\n", .{});
        std.process.exit(1);
    };

    const removed = try config.removeContainer(io, allocator, path);
    if (removed) {
        std.debug.print("Removed container: {s}\n", .{path});

        // Rebuild cache
        std.debug.print("Rebuilding compiler cache...\n", .{});
        const entries = try container.rebuildCache(io, allocator);
        defer {
            for (entries) |e| {
                allocator.free(e.compiler);
                allocator.free(e.container);
            }
            allocator.free(entries);
        }
        std.debug.print("Cache updated with {d} compiler(s).\n", .{entries.len});
    } else {
        std.debug.print("Container not found: {s}\n", .{path});
    }
}

fn handleReload(io: std.Io, allocator: std.mem.Allocator) !void {
    std.debug.print("Rebuilding compiler cache...\n", .{});
    const entries = try container.rebuildCache(io, allocator);
    defer {
        for (entries) |e| {
            allocator.free(e.compiler);
            allocator.free(e.container);
        }
        allocator.free(entries);
    }
    std.debug.print("Cache updated with {d} compiler(s).\n", .{entries.len});

    if (entries.len > 0) {
        std.debug.print("\nAvailable compilers:\n", .{});
        for (entries) |e| {
            std.debug.print("  {s} (from {s})\n", .{ e.compiler, e.container });
        }
    }
}

fn handleList(io: std.Io, allocator: std.mem.Allocator, args: *std.process.Args.Iterator) !void {
    var container_filter: ?[]const u8 = null;

    // Parse optional --container flag
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--container")) {
            container_filter = args.next() orelse {
                std.debug.print("Usage: vdir compiler list [--container <name>]\n", .{});
                std.process.exit(1);
            };
        }
    }

    const entries = try config.loadCompilerCache(io, allocator);
    defer {
        for (entries) |e| {
            allocator.free(e.compiler);
            allocator.free(e.container);
        }
        allocator.free(entries);
    }

    if (entries.len == 0) {
        std.debug.print("No compilers cached.\n", .{});
        std.debug.print("Use 'vdir compiler reload' to rebuild the cache.\n", .{});
        return;
    }

    var count: usize = 0;
    for (entries) |e| {
        if (container_filter) |filter| {
            if (!std.mem.eql(u8, e.container, filter)) continue;
        }
        std.debug.print("  {s} (from {s})\n", .{ e.compiler, e.container });
        count += 1;
    }

    if (count == 0 and container_filter != null) {
        std.debug.print("No compilers found from container: {s}\n", .{container_filter.?});
    }
}

fn handleWhich(io: std.Io, allocator: std.mem.Allocator, args: *std.process.Args.Iterator) !void {
    const compiler_name = args.next() orelse {
        std.debug.print("Usage: vdir compiler which <name>\n", .{});
        std.process.exit(1);
    };

    const container_path = try config.findCompilerContainer(io, allocator, compiler_name);

    if (container_path) |path| {
        defer allocator.free(path);
        std.debug.print("{s} is provided by: {s}\n", .{ compiler_name, path });
    } else {
        std.debug.print("Compiler not found: {s}\n", .{compiler_name});
        std.debug.print("Use 'vdir compiler list' to see available compilers.\n", .{});
    }
}

fn handleTest(io: std.Io, allocator: std.mem.Allocator, args: *std.process.Args.Iterator) !void {
    const compiler_name = args.next() orelse {
        std.debug.print("Usage: vdir compiler test <name> <args>\n", .{});
        std.process.exit(1);
    };

    // Collect remaining args
    var args_buf: [4096]u8 = undefined;
    var args_len: usize = 0;

    while (args.next()) |arg| {
        if (args_len > 0) {
            args_buf[args_len] = ' ';
            args_len += 1;
        }
        @memcpy(args_buf[args_len..][0..arg.len], arg);
        args_len += arg.len;
    }

    const compiler_args = args_buf[0..args_len];

    // Find container
    const container_path = try config.findCompilerContainer(io, allocator, compiler_name) orelse {
        std.debug.print("Compiler not found: {s}\n", .{compiler_name});
        std.debug.print("Use 'vdir compiler list' to see available compilers.\n", .{});
        std.process.exit(1);
    };
    defer allocator.free(container_path);

    std.debug.print("Running: {s} run {s} {s}\n", .{ container_path, compiler_name, compiler_args });
    std.debug.print("\nOutput:\n", .{});

    // Run compiler
    var shell_map = container.runCompiler(io, allocator, container_path, compiler_name, compiler_args) catch |err| {
        std.debug.print("Error running compiler: {any}\n", .{err});
        return;
    };
    defer {
        var it = shell_map.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        shell_map.deinit();
    }

    if (shell_map.count() == 0) {
        std.debug.print("(no output)\n", .{});
        return;
    }

    var it = shell_map.iterator();
    while (it.next()) |entry| {
        std.debug.print("  {s}: {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }
}
