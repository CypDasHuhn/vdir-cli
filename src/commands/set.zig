const std = @import("std");
const persistence = @import("../persistence.zig");
const pathmod = @import("../path.zig");
const shellmod = @import("../shell.zig");

pub fn run(
    io: std.Io,
    allocator: std.mem.Allocator,
    environ: std.process.Environ,
    args: *std.process.Args.Iterator,
) !void {
    const name = args.next() orelse {
        printUsage();
        std.process.exit(1);
    };
    const property = args.next() orelse {
        printUsage();
        std.process.exit(1);
    };

    var vdir_json = try persistence.loadVDir(io, allocator) orelse {
        std.debug.print("No vdir found. Run 'vdir init' first.\n", .{});
        std.process.exit(1);
    };
    defer vdir_json.deinit();

    const default_shell = shellmod.resolveDefault(io, environ, allocator) catch |err| {
        std.debug.print("Failed to resolve shell: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer default_shell.deinit(allocator);

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
        std.debug.print("Not in a folder\n", .{});
        std.process.exit(1);
    };

    for (children.array.items) |*child| {
        const child_name = child.object.get("name").?.string;
        if (std.mem.eql(u8, child_name, name)) {
            const item_type = child.object.get("type").?.string;
            const json_allocator = vdir_json.arena.allocator();

            if (std.mem.eql(u8, item_type, "folder")) {
                std.debug.print("Folders have no settable properties\n", .{});
                std.process.exit(1);
            } else if (std.mem.eql(u8, item_type, "query")) {
                try handleQuerySet(child, property, args, json_allocator, default_shell);
            } else if (std.mem.eql(u8, item_type, "reference")) {
                try handleReferenceSet(io, child, property, args, json_allocator);
            }

            try persistence.saveVDirJson(io, allocator, vdir_json.value);
            return;
        }
    }

    std.debug.print("Item not found: {s}\n", .{name});
    std.process.exit(1);
}

fn handleQuerySet(
    child: *std.json.Value,
    property: []const u8,
    args: *std.process.Args.Iterator,
    json_allocator: std.mem.Allocator,
    default_shell: shellmod.ShellConfig,
) !void {
    const suppliers = child.object.getPtr("suppliers") orelse {
        std.debug.print("Query needs migration to new format. Delete and recreate.\n", .{});
        std.process.exit(1);
    };

    if (std.mem.eql(u8, property, "expr")) {
        const value = args.next() orelse {
            std.debug.print("Usage: set <query> expr <expression>\n", .{});
            std.process.exit(1);
        };
        const new_value = try json_allocator.dupe(u8, value);
        try child.object.put("expr", .{ .string = new_value });
        std.debug.print("expr = {s}\n", .{value});
    } else if (std.mem.eql(u8, property, "cmd") or
        std.mem.eql(u8, property, "scope") or
        std.mem.eql(u8, property, "shell"))
    {
        const value = args.next() orelse {
            std.debug.print("Usage: set <query> {s} <value>\n", .{property});
            std.process.exit(1);
        };

        if (suppliers.object.count() > 0 and !suppliers.object.contains("_default")) {
            std.debug.print("Warning: query has named suppliers. Setting {s} uses _default supplier.\n", .{property});
        }

        if (suppliers.object.getPtr("_default")) |supplier| {
            try setSupplierProperty(supplier, property, value, args, json_allocator, default_shell);
        } else {
            var new_supplier = std.json.ObjectMap.init(json_allocator);
            try new_supplier.put("scope", .{ .string = "." });
            try new_supplier.put("cmd", .{ .string = "" });
            try putSupplierShell(&new_supplier, default_shell, json_allocator);
            try setSupplierPropertyObject(&new_supplier, property, value, args, json_allocator, default_shell);
            try suppliers.object.put("_default", .{ .object = new_supplier });

            const expr = child.object.get("expr").?.string;
            if (expr.len == 0) {
                try child.object.put("expr", .{ .string = "_default" });
            }
        }

        std.debug.print("{s} = {s}\n", .{ property, value });
    } else if (std.mem.eql(u8, property, "supplier")) {
        const sup_name = args.next() orelse {
            std.debug.print("Suppliers:\n", .{});
            var it = suppliers.object.iterator();
            while (it.next()) |entry| {
                const sup_name_existing = entry.key_ptr.*;
                const sup = entry.value_ptr.*;
                const scope = sup.object.get("scope").?.string;
                const cmd = sup.object.get("cmd").?.string;
                if (sup.object.get("shell")) |shell_val| {
                    const program = shell_val.object.get("program").?.string;
                    const execute_arg = shell_val.object.get("execute_arg").?.string;
                    std.debug.print(
                        "  {s}: scope={s} shell={s} {s} cmd={s}\n",
                        .{ sup_name_existing, scope, program, execute_arg, if (cmd.len > 0) cmd else "(empty)" },
                    );
                } else {
                    std.debug.print("  {s}: scope={s} cmd={s}\n", .{ sup_name_existing, scope, if (cmd.len > 0) cmd else "(empty)" });
                }
            }
            if (suppliers.object.count() == 0) {
                std.debug.print("  (none)\n", .{});
            }
            return;
        };

        const sup_prop = args.next() orelse {
            std.debug.print("Usage: set <query> supplier <name> <scope|cmd|shell|rm> [value]\n", .{});
            std.process.exit(1);
        };

        if (std.mem.eql(u8, sup_prop, "rm")) {
            if (suppliers.object.orderedRemove(sup_name)) {
                std.debug.print("Removed supplier: {s}\n", .{sup_name});
            } else {
                std.debug.print("Supplier not found: {s}\n", .{sup_name});
                std.process.exit(1);
            }
            return;
        }

        const sup_value = args.next() orelse {
            std.debug.print("Usage: set <query> supplier <name> <scope|cmd|shell> <value>\n", .{});
            std.process.exit(1);
        };

        if (!std.mem.eql(u8, sup_prop, "scope") and
            !std.mem.eql(u8, sup_prop, "cmd") and
            !std.mem.eql(u8, sup_prop, "shell"))
        {
            std.debug.print("Supplier properties: scope, cmd, shell, rm\n", .{});
            std.process.exit(1);
        }

        if (suppliers.object.contains("_default") and !std.mem.eql(u8, sup_name, "_default")) {
            std.debug.print("Warning: _default supplier exists. Consider removing it or using 'set <query> cmd' instead.\n", .{});
        }

        const sup_name_owned = try json_allocator.dupe(u8, sup_name);
        if (suppliers.object.getPtr(sup_name)) |supplier| {
            try setSupplierProperty(supplier, sup_prop, sup_value, args, json_allocator, default_shell);
        } else {
            var new_supplier = std.json.ObjectMap.init(json_allocator);
            try new_supplier.put("scope", .{ .string = "." });
            try new_supplier.put("cmd", .{ .string = "" });
            try putSupplierShell(&new_supplier, default_shell, json_allocator);
            try setSupplierPropertyObject(&new_supplier, sup_prop, sup_value, args, json_allocator, default_shell);
            try suppliers.object.put(sup_name_owned, .{ .object = new_supplier });
        }

        std.debug.print("supplier.{s}.{s} = {s}\n", .{ sup_name, sup_prop, sup_value });
    } else {
        std.debug.print("Query properties: cmd, scope, shell, expr, supplier\n", .{});
        std.process.exit(1);
    }
}

fn setSupplierProperty(
    supplier: *std.json.Value,
    property: []const u8,
    value: []const u8,
    args: *std.process.Args.Iterator,
    json_allocator: std.mem.Allocator,
    default_shell: shellmod.ShellConfig,
) !void {
    try setSupplierPropertyObject(&supplier.object, property, value, args, json_allocator, default_shell);
}

fn setSupplierPropertyObject(
    object: *std.json.ObjectMap,
    property: []const u8,
    value: []const u8,
    args: *std.process.Args.Iterator,
    json_allocator: std.mem.Allocator,
    default_shell: shellmod.ShellConfig,
) !void {
    if (std.mem.eql(u8, property, "shell")) {
        if (std.mem.eql(u8, value, "clear")) {
            try putSupplierShell(object, default_shell, json_allocator);
            return;
        }

        const execute_arg = args.next();
        var shell_obj = std.json.ObjectMap.init(json_allocator);
        try shell_obj.put("program", .{ .string = try json_allocator.dupe(u8, value) });
        try shell_obj.put(
            "execute_arg",
            .{ .string = try json_allocator.dupe(u8, execute_arg orelse @import("../shell.zig").defaultExecuteArgForProgram(value)) },
        );
        try object.put("shell", .{ .object = shell_obj });
        return;
    }

    if (object.get("shell") == null) {
        try putSupplierShell(object, default_shell, json_allocator);
    }

    const new_val = try json_allocator.dupe(u8, value);
    try object.put(property, .{ .string = new_val });
}

fn putSupplierShell(
    object: *std.json.ObjectMap,
    shell: shellmod.ShellConfig,
    allocator: std.mem.Allocator,
) !void {
    var shell_obj = std.json.ObjectMap.init(allocator);
    try shell_obj.put("program", .{ .string = try allocator.dupe(u8, shell.program) });
    try shell_obj.put("execute_arg", .{ .string = try allocator.dupe(u8, shell.execute_arg) });
    try object.put("shell", .{ .object = shell_obj });
}

fn handleReferenceSet(
    io: std.Io,
    child: *std.json.Value,
    property: []const u8,
    args: *std.process.Args.Iterator,
    json_allocator: std.mem.Allocator,
) !void {
    if (!std.mem.eql(u8, property, "target")) {
        std.debug.print("Reference properties: target\n", .{});
        std.process.exit(1);
    }

    const value = args.next() orelse {
        std.debug.print("Usage: set <reference> target <path>\n", .{});
        std.process.exit(1);
    };

    const target_type_enum = persistence.getTargetType(io, value) orelse {
        std.debug.print("Target does not exist: {s}\n", .{value});
        std.process.exit(1);
    };
    const new_target_type: []const u8 = if (target_type_enum == .folder) "folder" else "file";
    try child.object.put("target_type", .{ .string = new_target_type });

    const new_value = try json_allocator.dupe(u8, value);
    try child.object.put("target", .{ .string = new_value });

    const child_name = child.object.get("name").?.string;
    std.debug.print("{s}.target = {s}\n", .{ child_name, value });
}

fn printUsage() void {
    std.debug.print(
        \\Usage: vdir set <name> <property> [args...]
        \\
        \\Query properties:
        \\  cmd <command>                       Set command (uses _default supplier)
        \\  scope <path>                        Set scope (uses _default supplier)
        \\  shell <program> [execute_arg]       Set supplier shell (uses _default supplier)
        \\  expr <expression>                   Set boolean expression
        \\  supplier                            List all suppliers
        \\  supplier <name> cmd <command>       Set named supplier command
        \\  supplier <name> scope <path>        Set named supplier scope
        \\  supplier <name> shell <program> [execute_arg]  Set named supplier shell
        \\  supplier <name> rm                  Remove supplier
        \\
        \\Reference properties:
        \\  target <path>                       Set target path
        \\
    , .{});
}
