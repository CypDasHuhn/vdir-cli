const std = @import("std");
const persistence = @import("../persistence.zig");
const pathmod = @import("../path.zig");

pub fn run(io: std.Io, allocator: std.mem.Allocator, args: *std.process.Args.Iterator) !void {
    const path = args.next() orelse {
        std.debug.print("Usage: vdir cd <path>\n", .{});
        std.process.exit(1);
    };

    var vdir_json = try persistence.loadVDir(io, allocator) orelse {
        std.debug.print("No vdir found. Run 'vdir init' first.\n", .{});
        std.process.exit(1);
    };
    defer vdir_json.deinit();

    const marker_result = try persistence.loadMarker(io, allocator);
    const current_marker = marker_result orelse "~";
    defer if (marker_result != null) allocator.free(marker_result.?);

    // Resolve the new path
    const resolved = resolvePath(allocator, current_marker, path) catch |err| {
        switch (err) {
            error.OutOfMemory => return err,
            error.InvalidPath => {
                std.debug.print("Invalid path: {s}\n", .{path});
                std.process.exit(1);
            },
        }
    };
    defer allocator.free(resolved);

    // Validate that the resolved path exists and is a folder
    const root = vdir_json.value.object.getPtr("root") orelse {
        std.debug.print("Invalid vdir format\n", .{});
        std.process.exit(1);
    };

    const target = pathmod.resolveMarker(root, resolved) catch |err| {
        switch (err) {
            pathmod.ResolveError.NotFound => std.debug.print("Path not found: {s}\n", .{path}),
            pathmod.ResolveError.NotAFolder => std.debug.print("Not a folder: {s}\n", .{path}),
            pathmod.ResolveError.InvalidPath => std.debug.print("Invalid path: {s}\n", .{path}),
        }
        std.process.exit(1);
    };

    // Check it's a folder (root has no type field, it's implicitly a folder)
    if (target.object.get("type")) |type_val| {
        if (!std.mem.eql(u8, type_val.string, "folder")) {
            std.debug.print("Not a folder: {s}\n", .{path});
            std.process.exit(1);
        }
    }

    try persistence.saveMarker(io, resolved);
    std.debug.print("marker: {s}\n", .{resolved});
}

fn resolvePath(allocator: std.mem.Allocator, current: []const u8, path: []const u8) ![]const u8 {
    // Handle absolute paths (starting with ~)
    if (std.mem.startsWith(u8, path, "~/") or std.mem.eql(u8, path, "~")) {
        return try allocator.dupe(u8, path);
    }

    // Build list of segments from current marker (max 64 depth)
    var segments: [64][]const u8 = undefined;
    var seg_count: usize = 0;

    // Parse current marker into segments
    var current_iter = std.mem.splitScalar(u8, current, '/');
    while (current_iter.next()) |seg| {
        if (seg.len == 0 or std.mem.eql(u8, seg, "~")) continue;
        if (seg_count >= 64) return error.InvalidPath;
        segments[seg_count] = seg;
        seg_count += 1;
    }

    // Process new path segments
    var path_iter = std.mem.splitScalar(u8, path, '/');
    while (path_iter.next()) |seg| {
        if (seg.len == 0) continue;

        if (std.mem.eql(u8, seg, "..")) {
            if (seg_count == 0) {
                return error.InvalidPath;
            }
            seg_count -= 1;
        } else if (std.mem.eql(u8, seg, ".")) {
            // Current dir, skip
        } else {
            if (seg_count >= 64) return error.InvalidPath;
            segments[seg_count] = seg;
            seg_count += 1;
        }
    }

    // Build result path
    if (seg_count == 0) {
        return try allocator.dupe(u8, "~");
    }

    // Calculate total length
    var total_len: usize = 1; // for '~'
    for (segments[0..seg_count]) |seg| {
        total_len += 1 + seg.len; // '/' + segment
    }

    const result = try allocator.alloc(u8, total_len);
    errdefer allocator.free(result);

    result[0] = '~';
    var pos: usize = 1;
    for (segments[0..seg_count]) |seg| {
        result[pos] = '/';
        pos += 1;
        @memcpy(result[pos..][0..seg.len], seg);
        pos += seg.len;
    }

    return result;
}
