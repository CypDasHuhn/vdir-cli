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

const max_path_segments: usize = 256;

/// Canonicalizes `input_path` against `marker` and writes the result into `out_buffer`.
/// Canonical format is always "~" or "~/a/b/c".
pub fn resolveMarkerPath(
    out_buffer: []u8,
    marker: []const u8,
    input_path: []const u8,
) ResolveError![]const u8 {
    var segments: [max_path_segments][]const u8 = undefined;
    var len: usize = 0;

    // Marker is always interpreted from root.
    try applyMarker(&segments, &len, marker);

    if (std.mem.eql(u8, input_path, "~")) {
        len = 0;
    } else if (std.mem.startsWith(u8, input_path, "~/")) {
        len = 0;
        try applyRelativePath(&segments, &len, input_path[2..]);
    } else if (std.mem.startsWith(u8, input_path, "~")) {
        return ResolveError.InvalidPath;
    } else {
        try applyRelativePath(&segments, &len, input_path);
    }

    return writeCanonicalPath(out_buffer, segments[0..len]);
}

/// Resolve a path relative to the marker position.
/// Returns the target item and its parent folder.
pub fn resolve(
    root: *std.json.Value,
    marker: []const u8,
    path: []const u8,
) ResolveError!ResolveResult {
    var path_buffer: [4096]u8 = undefined;
    const canonical_path = try resolveMarkerPath(path_buffer[0..], marker, path);

    var current = root;
    var parent: ?*std.json.Value = null;
    var resolved_name = getName(root);

    if (std.mem.eql(u8, canonical_path, "~")) {
        return .{
            .item = root,
            .parent = null,
            .name = resolved_name,
        };
    }

    var path_segments = std.mem.splitScalar(u8, canonical_path[2..], '/');
    while (path_segments.next()) |segment| {
        const children = getChildren(current) orelse return ResolveError.NotAFolder;

        var found: ?*std.json.Value = null;
        for (children.array.items) |*child| {
            const child_name = child.object.get("name").?.string;
            if (std.mem.eql(u8, child_name, segment)) {
                found = child;
                break;
            }
        }

        const matched = found orelse return ResolveError.NotFound;
        parent = current;
        current = matched;
        resolved_name = segment;
    }

    return .{
        .item = current,
        .parent = parent,
        .name = resolved_name,
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
    return (try resolve(root, "~", marker)).item;
}

fn applyMarker(
    segments: *[max_path_segments][]const u8,
    len: *usize,
    marker: []const u8,
) ResolveError!void {
    len.* = 0;

    if (marker.len == 0 or std.mem.eql(u8, marker, "~")) {
        return;
    }

    if (std.mem.startsWith(u8, marker, "~/")) {
        try applyRelativePath(segments, len, marker[2..]);
        return;
    }

    if (std.mem.startsWith(u8, marker, "~")) {
        return ResolveError.InvalidPath;
    }

    // Backward compatibility for older marker values stored without "~/" prefix.
    try applyRelativePath(segments, len, marker);
}

fn applyRelativePath(
    segments: *[max_path_segments][]const u8,
    len: *usize,
    path: []const u8,
) ResolveError!void {
    if (path.len == 0) return;

    var iter = std.mem.splitScalar(u8, path, '/');
    while (iter.next()) |segment| {
        if (segment.len == 0 or std.mem.eql(u8, segment, ".")) {
            continue;
        }

        if (std.mem.eql(u8, segment, "..")) {
            if (len.* == 0) return ResolveError.InvalidPath;
            len.* -= 1;
            continue;
        }

        if (std.mem.eql(u8, segment, "~")) {
            return ResolveError.InvalidPath;
        }

        if (len.* >= max_path_segments) {
            return ResolveError.InvalidPath;
        }

        segments[len.*] = segment;
        len.* += 1;
    }
}

fn writeCanonicalPath(out_buffer: []u8, segments: []const []const u8) ResolveError![]const u8 {
    if (segments.len == 0) {
        if (out_buffer.len < 1) return ResolveError.InvalidPath;
        out_buffer[0] = '~';
        return out_buffer[0..1];
    }

    if (out_buffer.len < 2) return ResolveError.InvalidPath;
    out_buffer[0] = '~';

    var index: usize = 1;
    for (segments) |segment| {
        if (index >= out_buffer.len) return ResolveError.InvalidPath;
        out_buffer[index] = '/';
        index += 1;

        if (index + segment.len > out_buffer.len) return ResolveError.InvalidPath;
        @memcpy(out_buffer[index .. index + segment.len], segment);
        index += segment.len;
    }

    return out_buffer[0..index];
}

fn getChildren(item: *std.json.Value) ?*std.json.Value {
    return item.object.getPtr("children");
}

fn getName(item: *std.json.Value) []const u8 {
    return item.object.get("name").?.string;
}

test "resolveMarkerPath normalizes marker and relative segments" {
    var out: [128]u8 = undefined;

    const p1 = try resolveMarkerPath(out[0..], "~", "folder");
    try std.testing.expectEqualStrings("~/folder", p1);

    const p2 = try resolveMarkerPath(out[0..], "~/a/b", "..");
    try std.testing.expectEqualStrings("~/a", p2);

    const p3 = try resolveMarkerPath(out[0..], "~/a/b", "~/x/y");
    try std.testing.expectEqualStrings("~/x/y", p3);

    const p4 = try resolveMarkerPath(out[0..], "legacy/path", ".");
    try std.testing.expectEqualStrings("~/legacy/path", p4);
}

test "resolveMarkerPath rejects traversal above root" {
    var out: [32]u8 = undefined;
    try std.testing.expectError(ResolveError.InvalidPath, resolveMarkerPath(out[0..], "~", "../x"));
}

test "resolve supports parent traversal and root paths" {
    const json_text =
        \\{
        \\  "root": {
        \\    "name": "",
        \\    "children": [
        \\      {
        \\        "type": "folder",
        \\        "name": "a",
        \\        "children": [
        \\          {
        \\            "type": "folder",
        \\            "name": "b",
        \\            "children": []
        \\          },
        \\          {
        \\            "type": "folder",
        \\            "name": "c",
        \\            "children": []
        \\          }
        \\        ]
        \\      }
        \\    ]
        \\  }
        \\}
    ;

    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_text, .{});
    defer parsed.deinit();

    const root = parsed.value.object.getPtr("root").?;

    const rel = try resolve(root, "~/a/b", "../c");
    try std.testing.expectEqualStrings("c", rel.name);
    try std.testing.expect(rel.parent != null);

    const abs = try resolve(root, "~/a/b", "~");
    try std.testing.expect(abs.parent == null);
}
