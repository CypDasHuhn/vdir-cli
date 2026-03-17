const std = @import("std");
const persistence = @import("../persistence.zig");
const pathmod = @import("../path.zig");
const query = @import("../query.zig");
const shellmod = @import("../shell.zig");
const compilermod = @import("../compiler_config.zig");

const Flags = struct {
    show_hidden: bool = false,
    long_format: bool = false,
    recursive: bool = false,
    max_depth: ?usize = null,
    path_mode: PathMode = .basename,
};

const PathMode = enum {
    basename,
    relative,
    full,
};

pub fn run(
    io: std.Io,
    allocator: std.mem.Allocator,
    environ: std.process.Environ,
    args: *std.process.Args.Iterator,
) !void {
    var flags = Flags{};
    const cwd = try std.process.currentPathAlloc(io, allocator);
    defer allocator.free(cwd);

    // Parse flags
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--rel")) {
            flags.path_mode = .relative;
        } else if (std.mem.eql(u8, arg, "--full")) {
            flags.path_mode = .full;
        } else if (std.mem.eql(u8, arg, "-a")) {
            flags.show_hidden = true;
        } else if (std.mem.eql(u8, arg, "-l")) {
            flags.long_format = true;
        } else if (std.mem.eql(u8, arg, "-r")) {
            flags.recursive = true;
        } else if (std.mem.startsWith(u8, arg, "-r")) {
            flags.recursive = true;
            const depth_str = arg[2..];
            flags.max_depth = std.fmt.parseInt(usize, depth_str, 10) catch {
                std.debug.print("Invalid depth: {s}\n", .{depth_str});
                std.process.exit(1);
            };
        } else if (std.mem.eql(u8, arg, "-al") or std.mem.eql(u8, arg, "-la")) {
            flags.show_hidden = true;
            flags.long_format = true;
        } else if (std.mem.eql(u8, arg, "-ar") or std.mem.eql(u8, arg, "-ra")) {
            flags.show_hidden = true;
            flags.recursive = true;
        } else if (std.mem.eql(u8, arg, "-lr") or std.mem.eql(u8, arg, "-rl")) {
            flags.long_format = true;
            flags.recursive = true;
        } else if (std.mem.eql(u8, arg, "-alr") or std.mem.eql(u8, arg, "-arl") or
            std.mem.eql(u8, arg, "-lar") or std.mem.eql(u8, arg, "-lra") or
            std.mem.eql(u8, arg, "-ral") or std.mem.eql(u8, arg, "-rla"))
        {
            flags.show_hidden = true;
            flags.long_format = true;
            flags.recursive = true;
        } else {
            std.debug.print("Unknown flag: {s}\n", .{arg});
            std.process.exit(1);
        }
    }

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
    const shell = shellmod.resolveDefault(io, environ, allocator) catch |err| {
        std.debug.print("Failed to resolve shell: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer shell.deinit(allocator);
    const compiler = compilermod.resolveConfigured(io, environ, allocator) catch |err| {
        std.debug.print("Failed to resolve compiler: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer if (compiler) |active| active.deinit(allocator);

    const current = pathmod.resolveMarker(root, marker) catch |err| {
        switch (err) {
            pathmod.ResolveError.NotFound => std.debug.print("Current path not found: {s}\n", .{marker}),
            pathmod.ResolveError.NotAFolder => std.debug.print("Not a folder: {s}\n", .{marker}),
            pathmod.ResolveError.InvalidPath => std.debug.print("Invalid path: {s}\n", .{marker}),
        }
        std.process.exit(1);
    };

    try listItems(io, allocator, current, flags, shell, compiler, cwd, 0);
}

fn listItems(
    io: std.Io,
    allocator: std.mem.Allocator,
    item: *std.json.Value,
    flags: Flags,
    shell: shellmod.ShellConfig,
    compiler: ?compilermod.CompilerConfig,
    cwd: []const u8,
    depth: usize,
) !void {
    const children = item.object.get("children") orelse {
        // Query markers behave like dynamic folders.
        const item_type = item.object.get("type").?.string;
        if (std.mem.eql(u8, item_type, "query")) {
            try expandQuery(io, allocator, item, flags, shell, compiler, cwd, depth);
        } else if (std.mem.eql(u8, item_type, "reference")) {
            const target = item.object.get("target").?.string;
            std.debug.print("-> {s}\n", .{target});
        }
        return;
    };

    for (children.array.items) |child| {
        const item_name = child.object.get("name").?.string;

        // Skip hidden unless -a
        if (!flags.show_hidden and item_name.len > 0 and item_name[0] == '.') {
            continue;
        }

        const item_type = child.object.get("type").?.string;
        const indent = "  " ** 8; // max 8 levels

        if (flags.long_format) {
            printIndent(indent, depth);
            if (std.mem.eql(u8, item_type, "folder")) {
                const folder_children = child.object.get("children").?.array;
                std.debug.print("d {s}/ ({d} items)\n", .{ item_name, folder_children.items.len });
            } else if (std.mem.eql(u8, item_type, "query")) {
                const suppliers: usize = if (child.object.get("suppliers")) |s|
                    s.object.count()
                else if (child.object.get("cmd") != null)
                    1
                else
                    0;
                std.debug.print("q {s} ({d} suppliers)\n", .{ item_name, suppliers });
            } else {
                const target = child.object.get("target").?.string;
                const target_type = if (child.object.get("target_type")) |tt| tt.string else "?";
                const tt_char: u8 = if (std.mem.eql(u8, target_type, "folder")) 'd' else 'f';
                std.debug.print("r {s} -> {s} [{c}]\n", .{ item_name, target, tt_char });
            }
        } else {
            printIndent(indent, depth);
            const prefix: []const u8 = if (std.mem.eql(u8, item_type, "folder"))
                "d"
            else if (std.mem.eql(u8, item_type, "query"))
                "q"
            else
                "r";
            std.debug.print("{s} {s}\n", .{ prefix, item_name });
        }

        // Recursive
        if (flags.recursive) {
            const max = flags.max_depth orelse 10;
            if (depth < max) {
                if (std.mem.eql(u8, item_type, "folder")) {
                    const child_ptr = @constCast(&child);
                    try listItems(io, allocator, child_ptr, flags, shell, compiler, cwd, depth + 1);
                } else if (std.mem.eql(u8, item_type, "query")) {
                    const child_ptr = @constCast(&child);
                    try expandQuery(io, allocator, child_ptr, flags, shell, compiler, cwd, depth + 1);
                }
            }
        }
    }
}

fn expandQuery(
    io: std.Io,
    allocator: std.mem.Allocator,
    item: *std.json.Value,
    flags: Flags,
    shell: shellmod.ShellConfig,
    compiler: ?compilermod.CompilerConfig,
    cwd: []const u8,
    depth: usize,
) !void {
    var temp_suppliers: ?std.json.Value = null;
    const suppliers_val = if (item.object.get("suppliers")) |suppliers|
        suppliers
    else if (item.object.get("cmd")) |cmd_val| blk: {
        const scope = if (item.object.get("scope")) |scope_val| scope_val.string else ".";
        var supplier = std.json.ObjectMap.init(allocator);
        try supplier.put("scope", .{ .string = scope });
        try supplier.put("cmd", .{ .string = cmd_val.string });

        var suppliers = std.json.ObjectMap.init(allocator);
        try suppliers.put("_default", .{ .object = supplier });
        temp_suppliers = .{ .object = suppliers };
        break :blk temp_suppliers.?;
    } else return;
    const expr = if (item.object.get("expr")) |e| e.string else "";

    var result = query.execute(allocator, io, &suppliers_val.object, expr, shell, compiler) catch |err| {
        const indent = "  " ** 8;
        printIndent(indent, depth);
        switch (err) {
            query.QueryError.InvalidExpression => std.debug.print("(invalid expression)\n", .{}),
            query.QueryError.UnknownSupplier => std.debug.print("(unknown supplier)\n", .{}),
            query.QueryError.CommandFailed => std.debug.print("(command failed)\n", .{}),
            else => std.debug.print("(error)\n", .{}),
        }
        return;
    };
    defer result.deinit();

    const indent = "  " ** 8;
    var it = result.files.keyIterator();
    while (it.next()) |key| {
        const display_path = try formatDisplayPath(allocator, cwd, key.*, flags.path_mode);
        defer allocator.free(display_path);

        printIndent(indent, depth);
        if (flags.long_format) {
            std.debug.print("f {s}\n", .{display_path});
        } else {
            std.debug.print("{s}\n", .{display_path});
        }
    }

    if (result.count() == 0) {
        printIndent(indent, depth);
        std.debug.print("(no results)\n", .{});
    }
}

fn printIndent(indent: []const u8, depth: usize) void {
    const len = @min(depth * 2, indent.len);
    if (len > 0) {
        std.debug.print("{s}", .{indent[0..len]});
    }
}

fn formatDisplayPath(
    allocator: std.mem.Allocator,
    cwd: []const u8,
    path: []const u8,
    mode: PathMode,
) ![]u8 {
    return switch (mode) {
        .full => normalizeSeparators(allocator, path),
        .basename => allocator.dupe(u8, std.fs.path.basename(path)),
        .relative => blk: {
            if (!std.fs.path.isAbsolute(path)) {
                break :blk normalizeSeparators(allocator, path);
            }

            const relative = std.fs.path.relative(allocator, cwd, null, cwd, path) catch
                return normalizeSeparators(allocator, path);
            errdefer allocator.free(relative);

            if (std.fs.path.isAbsolute(relative)) {
                allocator.free(relative);
                break :blk normalizeSeparators(allocator, path);
            }

            const normalized = try normalizeSeparators(allocator, relative);
            allocator.free(relative);
            break :blk normalized;
        },
    };
}

fn normalizeSeparators(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const result = try allocator.dupe(u8, path);
    for (result) |*ch| {
        if (ch.* == '\\') ch.* = '/';
    }
    return result;
}
