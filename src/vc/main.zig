const std = @import("std");
const shellmod = @import("shared_shell");
const cfgmod = @import("config.zig");

const BuiltinCommand = enum {
    compile,
    config,
    help,
};

fn printUsage() void {
    std.debug.print(
        \\Usage: vc [--shell <program>] <spec...>
        \\       vc compile [--shell <program>] --input <spec>
        \\       vc config [path|init]
        \\
        \\Examples:
        \\  vc rg TODO
        \\  vc --shell nu rg TODO
        \\  vc compile --shell pwsh --input "rg TODO"
        \\  vc config
        \\  vc config init
        \\
    , .{});
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var args = try std.process.Args.iterateAllocator(init.minimal.args, allocator);
    defer args.deinit();
    _ = args.next();

    const first = args.next() orelse {
        printUsage();
        std.process.exit(1);
    };

    if (std.meta.stringToEnum(BuiltinCommand, first)) |cmd| {
        switch (cmd) {
            .compile => try runCompile(io, allocator, init.minimal.environ, &args),
            .config => try runConfig(io, allocator, init.minimal.environ, &args),
            .help => printUsage(),
        }
        return;
    }

    try runDirect(io, allocator, init.minimal.environ, first, &args);
}

fn runDirect(
    io: std.Io,
    allocator: std.mem.Allocator,
    environ: std.process.Environ,
    first: []const u8,
    args: *std.process.Args.Iterator,
) !void {
    var shell_program: ?[]const u8 = null;
    var owned_first: ?[]u8 = null;

    if (std.mem.eql(u8, first, "--shell")) {
        const program = args.next() orelse {
            printUsage();
            std.process.exit(1);
        };
        shell_program = program;

        const next = args.next() orelse {
            printUsage();
            std.process.exit(1);
        };
        owned_first = try allocator.dupe(u8, next);
    } else {
        owned_first = try allocator.dupe(u8, first);
    }
    defer if (owned_first) |value| allocator.free(value);

    var spec: std.ArrayList(u8) = .empty;
    defer spec.deinit(allocator);
    try spec.appendSlice(allocator, owned_first.?);
    while (args.next()) |arg| {
        try spec.append(allocator, ' ');
        try spec.appendSlice(allocator, arg);
    }

    const compiled = try compileSpec(io, allocator, environ, shell_program, spec.items);
    defer allocator.free(compiled);
    try writeLine(io, compiled);
}

fn runCompile(
    io: std.Io,
    allocator: std.mem.Allocator,
    environ: std.process.Environ,
    args: *std.process.Args.Iterator,
) !void {
    var shell_program: ?[]const u8 = null;
    var input: ?[]const u8 = null;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--shell")) {
            shell_program = args.next() orelse {
                printUsage();
                std.process.exit(1);
            };
        } else if (std.mem.eql(u8, arg, "--input")) {
            input = args.next() orelse {
                printUsage();
                std.process.exit(1);
            };
        } else {
            std.debug.print("Unknown flag: {s}\n", .{arg});
            std.process.exit(1);
        }
    }

    const raw_input = input orelse {
        printUsage();
        std.process.exit(1);
    };

    const compiled = try compileSpec(io, allocator, environ, shell_program, raw_input);
    defer allocator.free(compiled);
    try writeLine(io, compiled);
}

fn runConfig(
    io: std.Io,
    allocator: std.mem.Allocator,
    environ: std.process.Environ,
    args: *std.process.Args.Iterator,
) !void {
    const action = args.next();
    if (action == null) {
        const path = cfgmod.configPath(environ, allocator) catch |err| switch (err) {
            error.HomeNotFound => {
                try writeLine(io, "path: (unavailable)");
                try writeLine(io, "source: builtin");
                return;
            },
            else => return err,
        };
        defer allocator.free(path);

        const loaded = try cfgmod.load(io, environ, allocator);
        defer loaded.parsed.deinit();

        try writePrefixedLine(io, "path: ", path);
        try writePrefixedLine(io, "source: ", @tagName(loaded.source));
        return;
    }

    if (std.mem.eql(u8, action.?, "path")) {
        const path = try cfgmod.configPath(environ, allocator);
        defer allocator.free(path);
        try writeLine(io, path);
        return;
    }

    if (std.mem.eql(u8, action.?, "init")) {
        const path = try cfgmod.initUserConfig(io, environ, allocator);
        defer allocator.free(path);
        try writePrefixedLine(io, "initialized: ", path);
        return;
    }

    printUsage();
    std.process.exit(1);
}

fn compileSpec(
    io: std.Io,
    allocator: std.mem.Allocator,
    environ: std.process.Environ,
    shell_program_override: ?[]const u8,
    spec: []const u8,
) ![]u8 {
    const trimmed = std.mem.trim(u8, spec, " \t\r\n");
    if (trimmed.len == 0) {
        return try allocator.dupe(u8, "");
    }

    const shell_program = if (shell_program_override) |explicit|
        explicit
    else blk: {
        const resolved = try shellmod.resolveDefault(io, environ, allocator);
        defer resolved.deinit(allocator);
        break :blk try allocator.dupe(u8, resolved.program);
    };
    defer if (shell_program_override == null) allocator.free(shell_program);

    const loaded = try cfgmod.load(io, environ, allocator);
    defer loaded.parsed.deinit();

    const head_end = firstWordEnd(trimmed);
    const first_word = trimmed[0..head_end];
    const rest = trimLeftSpaces(trimmed[head_end..]);
    const normalized_head = try lowerBasename(allocator, first_word);
    defer allocator.free(normalized_head);
    const normalized_shell = try lowerBasename(allocator, shell_program);
    defer allocator.free(normalized_shell);

    const rules = loaded.parsed.value.object.get("rules") orelse {
        return try allocator.dupe(u8, trimmed);
    };

    for (rules.array.items) |rule| {
        const matches = rule.object.get("matches") orelse continue;
        if (!matchesRule(matches.array, normalized_head)) continue;

        const shells = rule.object.get("shells") orelse break;
        if (findShellTemplate(shells.object, normalized_shell)) |template| {
            return try replaceInputToken(allocator, template, rest);
        }
        if (findShellTemplate(shells.object, "default")) |template| {
            return try replaceInputToken(allocator, template, rest);
        }
        break;
    }

    return try allocator.dupe(u8, trimmed);
}

fn firstWordEnd(spec: []const u8) usize {
    var idx: usize = 0;
    while (idx < spec.len and spec[idx] != ' ' and spec[idx] != '\t') : (idx += 1) {}
    return idx;
}

fn matchesRule(matches: std.json.Array, normalized_head: []const u8) bool {
    for (matches.items) |entry| {
        if (entry != .string) continue;
        var lowered: [128]u8 = undefined;
        const candidate = entry.string;
        if (candidate.len > lowered.len) continue;
        for (candidate, 0..) |ch, idx| {
            lowered[idx] = std.ascii.toLower(ch);
        }
        if (std.mem.eql(u8, lowered[0..candidate.len], normalized_head)) {
            return true;
        }
    }
    return false;
}

fn findShellTemplate(shells: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const entry = shells.get(key) orelse return null;
    return entry.string;
}

fn lowerBasename(allocator: std.mem.Allocator, program: []const u8) ![]u8 {
    var basename = std.fs.path.basename(program);
    if (std.ascii.endsWithIgnoreCase(basename, ".exe")) {
        basename = basename[0 .. basename.len - 4];
    }

    const result = try allocator.dupe(u8, basename);
    for (result) |*ch| {
        ch.* = std.ascii.toLower(ch.*);
    }
    return result;
}

fn replaceInputToken(
    allocator: std.mem.Allocator,
    template: []const u8,
    input: []const u8,
) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);

    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, template, cursor, "${input}")) |idx| {
        try output.appendSlice(allocator, template[cursor..idx]);
        try output.appendSlice(allocator, input);
        cursor = idx + "${input}".len;
    }
    try output.appendSlice(allocator, template[cursor..]);

    return try output.toOwnedSlice(allocator);
}

fn trimLeftSpaces(value: []const u8) []const u8 {
    var idx: usize = 0;
    while (idx < value.len and (value[idx] == ' ' or value[idx] == '\t')) : (idx += 1) {}
    return value[idx..];
}

fn writeLine(io: std.Io, value: []const u8) !void {
    var buffer: [2048]u8 = undefined;
    var writer = std.Io.File.stdout().writer(io, &buffer);
    try writer.interface.writeAll(value);
    try writer.interface.writeAll("\n");
    try writer.flush();
}

fn writePrefixedLine(io: std.Io, prefix: []const u8, value: []const u8) !void {
    var buffer: [2048]u8 = undefined;
    var writer = std.Io.File.stdout().writer(io, &buffer);
    try writer.interface.writeAll(prefix);
    try writer.interface.writeAll(value);
    try writer.interface.writeAll("\n");
    try writer.flush();
}
