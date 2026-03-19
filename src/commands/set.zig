const std = @import("std");
const persistence = @import("../persistence.zig");
const pathmod = @import("../path.zig");
const shell = @import("../shell.zig");

pub fn run(io: std.Io, allocator: std.mem.Allocator, args: *std.process.Args.Iterator) !void {
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

    // Find item
    for (children.array.items) |*child| {
        const child_name = child.object.get("name").?.string;
        if (std.mem.eql(u8, child_name, name)) {
            const item_type = child.object.get("type").?.string;
            const json_allocator = vdir_json.arena.allocator();

            if (std.mem.eql(u8, item_type, "folder")) {
                std.debug.print("Folders have no settable properties\n", .{});
                std.process.exit(1);
            } else if (std.mem.eql(u8, item_type, "query")) {
                try handleQuerySet(child, property, args, json_allocator);
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
    } else if (std.mem.startsWith(u8, property, "cmd:")) {
        // cmd:shell syntax - set shell-specific command
        const shell_name = property[4..];
        const target_shell = shell.Shell.fromString(shell_name) orelse {
            std.debug.print("Unknown shell: {s}\n", .{shell_name});
            std.debug.print("Supported shells: bash, zsh, nu, powershell, cmd\n", .{});
            std.process.exit(1);
        };

        const value = args.next() orelse {
            std.debug.print("Usage: set <query> cmd:{s} <command>\n", .{shell_name});
            std.process.exit(1);
        };

        // Get or create _default supplier
        var supplier: *std.json.Value = undefined;
        if (suppliers.object.getPtr("_default")) |sup| {
            supplier = sup;
        } else {
            var new_supplier = std.json.ObjectMap.init(json_allocator);
            try new_supplier.put("scope", .{ .string = "." });
            const cmd_map = std.json.ObjectMap.init(json_allocator);
            try new_supplier.put("cmd", .{ .object = cmd_map });
            try suppliers.object.put("_default", .{ .object = new_supplier });
            supplier = suppliers.object.getPtr("_default").?;

            // Also set expr to _default if empty
            const expr = child.object.get("expr").?.string;
            if (expr.len == 0) {
                try child.object.put("expr", .{ .string = "_default" });
            }
        }

        // Get or create cmd map
        var cmd_map: *std.json.Value = undefined;
        if (supplier.object.getPtr("cmd")) |cm| {
            if (cm.* == .object) {
                cmd_map = cm;
            } else {
                // Migrate from string to object
                const new_cmd_map = std.json.ObjectMap.init(json_allocator);
                try supplier.object.put("cmd", .{ .object = new_cmd_map });
                cmd_map = supplier.object.getPtr("cmd").?;
            }
        } else {
            const new_cmd_map = std.json.ObjectMap.init(json_allocator);
            try supplier.object.put("cmd", .{ .object = new_cmd_map });
            cmd_map = supplier.object.getPtr("cmd").?;
        }

        // Set the shell-specific command
        const shell_key = try json_allocator.dupe(u8, target_shell.toString());
        const cmd_value = try json_allocator.dupe(u8, value);
        try cmd_map.object.put(shell_key, .{ .string = cmd_value });

        std.debug.print("cmd:{s} = {s}\n", .{ shell_name, value });
    } else if (std.mem.eql(u8, property, "scope")) {
        // Direct scope sets _default supplier
        const value = args.next() orelse {
            std.debug.print("Usage: set <query> scope <value>\n", .{});
            std.process.exit(1);
        };

        // Warn if named suppliers exist
        if (suppliers.object.count() > 0 and !suppliers.object.contains("_default")) {
            std.debug.print("Warning: query has named suppliers. Setting scope uses _default supplier.\n", .{});
        }

        // Get or create _default supplier
        if (suppliers.object.getPtr("_default")) |supplier| {
            const new_val = try json_allocator.dupe(u8, value);
            try supplier.object.put("scope", .{ .string = new_val });
        } else {
            var new_supplier = std.json.ObjectMap.init(json_allocator);
            try new_supplier.put("scope", .{ .string = "." });
            const cmd_map = std.json.ObjectMap.init(json_allocator);
            try new_supplier.put("cmd", .{ .object = cmd_map });
            const new_val = try json_allocator.dupe(u8, value);
            try new_supplier.put("scope", .{ .string = new_val });
            try suppliers.object.put("_default", .{ .object = new_supplier });

            // Also set expr to _default if empty
            const expr = child.object.get("expr").?.string;
            if (expr.len == 0) {
                try child.object.put("expr", .{ .string = "_default" });
            }
        }

        std.debug.print("scope = {s}\n", .{value});
    } else if (std.mem.eql(u8, property, "supplier")) {
        const sup_name = args.next() orelse {
            // No name = list suppliers
            std.debug.print("Suppliers:\n", .{});
            var it = suppliers.object.iterator();
            while (it.next()) |entry| {
                const name = entry.key_ptr.*;
                const sup = entry.value_ptr.*;
                const scope = sup.object.get("scope").?.string;
                std.debug.print("  {s}: scope={s}\n", .{ name, scope });

                // Print cmd map
                if (sup.object.get("cmd")) |cmd_val| {
                    if (cmd_val == .object) {
                        var cmd_it = cmd_val.object.iterator();
                        while (cmd_it.next()) |cmd_entry| {
                            std.debug.print("    {s}: {s}\n", .{ cmd_entry.key_ptr.*, cmd_entry.value_ptr.string });
                        }
                        if (cmd_val.object.count() == 0) {
                            std.debug.print("    (no shell commands)\n", .{});
                        }
                    } else if (cmd_val == .string) {
                        // Legacy format
                        std.debug.print("    (legacy) {s}\n", .{cmd_val.string});
                    }
                }
            }
            if (suppliers.object.count() == 0) {
                std.debug.print("  (none)\n", .{});
            }
            return;
        };

        const sup_prop = args.next() orelse {
            std.debug.print("Usage: set <query> supplier <name> <scope|cmd|rm> [value]\n", .{});
            std.process.exit(1);
        };

        // Handle remove
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
            std.debug.print("Usage: set <query> supplier <name> <scope|cmd> <value>\n", .{});
            std.process.exit(1);
        };

        if (!std.mem.eql(u8, sup_prop, "scope") and !std.mem.eql(u8, sup_prop, "cmd")) {
            std.debug.print("Supplier properties: scope, cmd, rm\n", .{});
            std.process.exit(1);
        }

        // Warn if _default exists and creating named supplier
        if (suppliers.object.contains("_default") and !std.mem.eql(u8, sup_name, "_default")) {
            std.debug.print("Warning: _default supplier exists. Consider removing it or using 'set <query> cmd' instead.\n", .{});
        }

        // Get or create this supplier
        const sup_name_owned = try json_allocator.dupe(u8, sup_name);
        if (suppliers.object.getPtr(sup_name)) |supplier| {
            const new_val = try json_allocator.dupe(u8, sup_value);
            try supplier.object.put(sup_prop, .{ .string = new_val });
        } else {
            var new_supplier = std.json.ObjectMap.init(json_allocator);
            try new_supplier.put("scope", .{ .string = "." });
            try new_supplier.put("cmd", .{ .string = "" });
            const new_val = try json_allocator.dupe(u8, sup_value);
            try new_supplier.put(sup_prop, .{ .string = new_val });
            try suppliers.object.put(sup_name_owned, .{ .object = new_supplier });
        }

        std.debug.print("supplier.{s}.{s} = {s}\n", .{ sup_name, sup_prop, sup_value });
    } else {
        std.debug.print("Query properties: cmd, scope, expr, supplier\n", .{});
        std.process.exit(1);
    }
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

    // Validate new target exists and update target_type
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
        \\  cmd:<shell> <command>               Set shell-specific command
        \\  scope <path>                        Set scope (uses _default supplier)
        \\  expr <expression>                   Set boolean expression
        \\  supplier                            List all suppliers
        \\  supplier <name> cmd <command>       Set named supplier command
        \\  supplier <name> scope <path>        Set named supplier scope
        \\  supplier <name> rm                  Remove supplier
        \\
        \\Supported shells: bash, zsh, nu, powershell, cmd
        \\
        \\Reference properties:
        \\  target <path>                       Set target path
        \\
        \\Examples:
        \\  vdir set myquery cmd:bash "rg -l 'TODO' ."
        \\  vdir set myquery cmd:nu "rg -l 'TODO' (pwd)"
        \\
    , .{});
}
