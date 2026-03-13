const std = @import("std");
const persistence = @import("../persistence.zig");
const pathmod = @import("../path.zig");

pub fn run(io: std.Io, allocator: std.mem.Allocator, args: *std.process.Args.Iterator) !void {
    const name = args.next() orelse {
        std.debug.print("Usage: vdir info <name>\n", .{});
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

    const children = current.object.get("children") orelse {
        std.debug.print("Not in a folder\n", .{});
        std.process.exit(1);
    };

    // Find item
    for (children.array.items) |child| {
        const child_name = child.object.get("name").?.string;
        if (std.mem.eql(u8, child_name, name)) {
            const item_type = child.object.get("type").?.string;

            std.debug.print("name: {s}\n", .{child_name});
            std.debug.print("type: {s}\n", .{item_type});

            if (std.mem.eql(u8, item_type, "folder")) {
                const folder_children = child.object.get("children").?.array;
                std.debug.print("children: {d}\n", .{folder_children.items.len});
            } else if (std.mem.eql(u8, item_type, "query")) {
                // New format with suppliers
                if (child.object.get("suppliers")) |suppliers_val| {
                    const expr = if (child.object.get("expr")) |e| e.string else "";
                    std.debug.print("expr: {s}\n", .{if (expr.len > 0) expr else "(empty)"});
                    std.debug.print("suppliers:\n", .{});
                    var it = suppliers_val.object.iterator();
                    while (it.next()) |entry| {
                        const sup_name = entry.key_ptr.*;
                        const sup = entry.value_ptr.*;
                        const scope = sup.object.get("scope").?.string;
                        const cmd = sup.object.get("cmd").?.string;
                        std.debug.print("  {s}:\n", .{sup_name});
                        std.debug.print("    scope: {s}\n", .{scope});
                        std.debug.print("    cmd: {s}\n", .{if (cmd.len > 0) cmd else "(empty)"});
                    }
                } else {
                    // Old format fallback
                    const scope = child.object.get("scope").?.string;
                    const cmd = child.object.get("cmd").?.string;
                    std.debug.print("scope: {s}\n", .{scope});
                    std.debug.print("cmd: {s}\n", .{if (cmd.len > 0) cmd else "(empty)"});
                }
            } else if (std.mem.eql(u8, item_type, "reference")) {
                const target = child.object.get("target").?.string;
                const target_type = if (child.object.get("target_type")) |tt| tt.string else "unknown";
                std.debug.print("target: {s}\n", .{target});
                std.debug.print("target_type: {s}\n", .{target_type});
            }
            return;
        }
    }

    std.debug.print("Item not found: {s}\n", .{name});
    std.process.exit(1);
}
