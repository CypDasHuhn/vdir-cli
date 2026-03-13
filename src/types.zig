const std = @import("std");

pub const Item = union(enum) {
    folder: Folder,
    query: Query,
    reference: Reference,

    pub fn getName(self: Item) []const u8 {
        return switch (self) {
            .folder => |f| f.name,
            .query => |q| q.name,
            .reference => |r| r.name,
        };
    }
};

pub const Folder = struct {
    name: []const u8,
    children: []Item,
};

pub const Query = struct {
    name: []const u8,
    scope: []const u8,
    cmd: []const u8,
};

pub const Reference = struct {
    name: []const u8,
    target: []const u8,
};

pub const VDir = struct {
    root: Folder,

    pub fn init() VDir {
        return .{
            .root = .{
                .name = "",
                .children = &.{},
            },
        };
    }
};
