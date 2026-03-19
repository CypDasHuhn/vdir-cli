const std = @import("std");
const persistence = @import("../persistence.zig");
const pathmod = @import("../path.zig");
const shell = @import("../shell.zig");
const config = @import("../config.zig");
const container = @import("../container.zig");

pub fn run(io: std.Io, allocator: std.mem.Allocator, args: *std.process.Args.Iterator) !void {
    const name = args.next() orelse {
        printUsage();
        std.process.exit(1);
    };

    // Parse flags and arguments
    var is_raw = false;
    var target_shell: ?shell.Shell = null;
    var compiler_name: ?[]const u8 = null;
    var command_args: ?[]const u8 = null;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--raw")) {
            is_raw = true;
        } else if (std.mem.eql(u8, arg, "--shell")) {
            const shell_name = args.next() orelse {
                std.debug.print("Error: --shell requires a shell name\n", .{});
                printUsage();
                std.process.exit(1);
            };
            target_shell = shell.Shell.fromString(shell_name) orelse {
                std.debug.print("Unknown shell: {s}\n", .{shell_name});
                std.debug.print("Supported shells: bash, zsh, nu, powershell, cmd\n", .{});
                std.process.exit(1);
            };
        } else if (compiler_name == null) {
            compiler_name = arg;
        } else if (command_args == null) {
            command_args = arg;
        }
    }

    // Load vdir
    var vdir_json = try persistence.loadVDir(io, allocator) orelse {
        std.debug.print("No vdir found. Run 'vdir init' first.\n", .{});
        std.process.exit(1);
    };
    defer vdir_json.deinit();

    const marker_result = try persistence.loadMarker(io, allocator);
    const marker = marker_result orelse "~";
    defer if (marker_result != null) allocator.free(marker_result.?);

    const root = vdir_json.value.object.getPtr("root") orelse {
        std.debug.print("Invalid vdir format\n", .{});
        std.process.exit(1);
    };

    const current = pathmod.resolveMarker(root, marker) catch |err| {
        switch (err) {
            pathmod.ResolveError.NotFound => std.debug.print("Current path not found: {s}\n", .{marker}),
            pathmod.ResolveError.NotAFolder => std.debug.print("Not a folder: {s}\n", .{marker}),
            pathmod.ResolveError.InvalidPath => std.debug.print("Invalid path: {s}\n", .{marker}),
        }
        std.process.exit(1);
    };

    const children = current.object.getPtr("children") orelse {
        std.debug.print("Cannot add to non-folder\n", .{});
        std.process.exit(1);
    };

    // Check if name already exists
    for (children.array.items) |child| {
        const child_name = child.object.get("name").?.string;
        if (std.mem.eql(u8, child_name, name)) {
            std.debug.print("Item '{s}' already exists\n", .{name});
            std.process.exit(1);
        }
    }

    const json_allocator = vdir_json.arena.allocator();
    var new_item = std.json.ObjectMap.init(json_allocator);

    try new_item.put("type", .{ .string = "query" });
    try new_item.put("name", .{ .string = name });

    var suppliers = std.json.ObjectMap.init(json_allocator);

    if (is_raw) {
        // Raw mode: create supplier with single shell command
        if (compiler_name == null) {
            std.debug.print("Error: --raw requires a command\n", .{});
            printUsage();
            std.process.exit(1);
        }

        const raw_cmd = compiler_name.?;
        const use_shell = target_shell orelse shell.getDefaultShell();

        var cmd_map = std.json.ObjectMap.init(json_allocator);
        const shell_name = try json_allocator.dupe(u8, use_shell.toString());
        const cmd_owned = try json_allocator.dupe(u8, raw_cmd);
        try cmd_map.put(shell_name, .{ .string = cmd_owned });

        var default_supplier = std.json.ObjectMap.init(json_allocator);
        try default_supplier.put("scope", .{ .string = "." });
        try default_supplier.put("raw", .{ .bool = true });
        try default_supplier.put("cmd", .{ .object = cmd_map });
        try suppliers.put("_default", .{ .object = default_supplier });
        try new_item.put("expr", .{ .string = "_default" });

        std.debug.print("q {s}: --raw ({s}) {s}\n", .{ name, use_shell.toString(), raw_cmd });
    } else if (compiler_name != null) {
        // Compiler mode: look up compiler and run it
        const comp_name = compiler_name.?;
        const comp_args = command_args orelse "";

        // Find compiler container
        const container_path = try config.findCompilerContainer(io, allocator, comp_name) orelse {
            std.debug.print("Compiler not found: {s}\n", .{comp_name});
            std.debug.print("Use 'vdir compiler list' to see available compilers.\n", .{});
            std.process.exit(1);
        };
        defer allocator.free(container_path);

        // Run compiler
        var shell_map = container.runCompiler(io, allocator, container_path, comp_name, comp_args) catch |err| {
            std.debug.print("Error running compiler: {any}\n", .{err});
            std.process.exit(1);
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
            std.debug.print("Compiler returned no shell commands\n", .{});
            std.process.exit(1);
        }

        // Convert shell map to JSON
        var cmd_map = std.json.ObjectMap.init(json_allocator);
        var it = shell_map.iterator();
        while (it.next()) |entry| {
            const key = try json_allocator.dupe(u8, entry.key_ptr.*);
            const val = try json_allocator.dupe(u8, entry.value_ptr.*);
            try cmd_map.put(key, .{ .string = val });
        }

        var default_supplier = std.json.ObjectMap.init(json_allocator);
        try default_supplier.put("scope", .{ .string = "." });
        const comp_name_owned = try json_allocator.dupe(u8, comp_name);
        try default_supplier.put("compiler", .{ .string = comp_name_owned });
        if (comp_args.len > 0) {
            const comp_args_owned = try json_allocator.dupe(u8, comp_args);
            try default_supplier.put("args", .{ .string = comp_args_owned });
        }
        try default_supplier.put("cmd", .{ .object = cmd_map });
        try suppliers.put("_default", .{ .object = default_supplier });
        try new_item.put("expr", .{ .string = "_default" });

        std.debug.print("q {s}: {s} {s}\n", .{ name, comp_name, comp_args });
    } else {
        // No command - create empty query
        try new_item.put("expr", .{ .string = "" });
        std.debug.print("q {s}\n", .{name});
    }

    try new_item.put("suppliers", .{ .object = suppliers });

    try children.array.append(.{ .object = new_item });
    try persistence.saveVDirJson(io, allocator, vdir_json.value);
}

fn printUsage() void {
    std.debug.print(
        \\Usage: vdir mkq <name> [options] [compiler] [args]
        \\
        \\Create a query with the given name.
        \\
        \\Options:
        \\  --raw              Use raw command (bypass compiler)
        \\  --shell <shell>    Target shell for raw command
        \\
        \\Examples:
        \\  vdir mkq todos ripgrep "TODO|FIXME"
        \\  vdir mkq files --raw "find . -name '*.rs'"
        \\  vdir mkq nufiles --raw --shell nu "glob **/*.rs"
        \\
    , .{});
}
