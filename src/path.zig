const std = @import("std");

pub const ResolveError = error{
    NotFound,
    NotAFolder,
    InvalidPath,
};

pub const ResolveResult = struct {
    item: *std.json.Value,
    parent: ?*std.json.Value,
    name: []const u8,
};

/// Resolve a path relative to the marker position.
/// Returns the target item and its parent folder.
pub fn resolve(
    root: *std.json.Value,
    marker: []const u8,
    path: []const u8,
) ResolveError!ResolveResult {
    // Start from root or marker position
    var current = if (std.mem.startsWith(u8, path, "~/") or std.mem.eql(u8, path, "~"))
        root
    else
        try resolveMarker(root, marker);

    var remaining_path = if (std.mem.startsWith(u8, path, "~/"))
        path[2..]
    else if (std.mem.eql(u8, path, "~"))
        ""
    else
        path;

    // Handle empty path (current location)
    if (remaining_path.len == 0) {
        return .{
            .item = current,
            .parent = null,
            .name = getName(current),
        };
    }

    var parent: ?*std.json.Value = null;
    var segments = std.mem.splitScalar(u8, remaining_path, '/');

    while (segments.next()) |segment| {
        if (segment.len == 0) continue;

        if (std.mem.eql(u8, segment, "..")) {
            // Go up to parent - we'd need to track parent chain
            // For now, return error
            return ResolveError.InvalidPath;
        }

        // Find child with this name
        const children = getChildren(current) orelse return ResolveError.NotAFolder;

        var found: ?*std.json.Value = null;
        for (children.array.items, 0..) |*child, i| {
            _ = i;
            const child_name = child.object.get("name").?.string;
            if (std.mem.eql(u8, child_name, segment)) {
                found = child;
                break;
            }
        }

        if (found) |child| {
            parent = current;
            current = child;
        } else {
            return ResolveError.NotFound;
        }
    }

    return .{
        .item = current,
        .parent = parent,
        .name = getName(current),
    };
}

/// Find an item by name in the current folder (marker position)
pub fn findChild(
    root: *std.json.Value,
    marker: []const u8,
    name: []const u8,
) ResolveError!ResolveResult {
    const current = try resolveMarker(root, marker);
    const children = getChildren(current) orelse return ResolveError.NotAFolder;

    for (children.array.items) |*child| {
        const child_name = child.object.get("name").?.string;
        if (std.mem.eql(u8, child_name, name)) {
            return .{
                .item = child,
                .parent = current,
                .name = name,
            };
        }
    }

    return ResolveError.NotFound;
}

/// Get children array pointer for modifications
pub fn getChildrenMut(
    root: *std.json.Value,
    marker: []const u8,
) ResolveError!*std.json.Array {
    const current = try resolveMarker(root, marker);
    const obj = &current.object;
    const children_ptr = obj.getPtr("children") orelse return ResolveError.NotAFolder;
    return &children_ptr.array;
}

pub fn resolveMarker(root: *std.json.Value, marker: []const u8) ResolveError!*std.json.Value {
    if (std.mem.eql(u8, marker, "~") or marker.len == 0) {
        return root;
    }

    // Marker is a path from root
    var current = root;
    var segments = std.mem.splitScalar(u8, marker, '/');

    // Skip leading ~ if present
    if (segments.peek()) |first| {
        if (std.mem.eql(u8, first, "~")) {
            _ = segments.next();
        }
    }

    while (segments.next()) |segment| {
        if (segment.len == 0) continue;

        const children = getChildren(current) orelse return ResolveError.NotAFolder;

        var found: ?*std.json.Value = null;
        for (children.array.items) |*child| {
            const child_name = child.object.get("name").?.string;
            if (std.mem.eql(u8, child_name, segment)) {
                found = child;
                break;
            }
        }

        current = found orelse return ResolveError.NotFound;
    }

    return current;
}

fn getChildren(item: *std.json.Value) ?*std.json.Value {
    return item.object.getPtr("children");
}

fn getName(item: *std.json.Value) []const u8 {
    return item.object.get("name").?.string;
}
