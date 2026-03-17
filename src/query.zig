const std = @import("std");
const shellmod = @import("shell.zig");
const compilermod = @import("compiler_config.zig");

pub const QueryError = error{
    InvalidExpression,
    UnknownSupplier,
    CommandFailed,
    InvalidConfig,
    OutOfMemory,
};

pub const FileSet = struct {
    files: std.StringHashMap(void),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FileSet {
        return .{
            .files = std.StringHashMap(void).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FileSet) void {
        var it = self.files.keyIterator();
        while (it.next()) |key| {
            self.allocator.free(key.*);
        }
        self.files.deinit();
    }

    pub fn add(self: *FileSet, path: []const u8) !void {
        if (!self.files.contains(path)) {
            const owned = try self.allocator.dupe(u8, path);
            try self.files.put(owned, {});
        }
    }

    pub fn contains(self: *const FileSet, path: []const u8) bool {
        return self.files.contains(path);
    }

    pub fn count(self: *const FileSet) usize {
        return self.files.count();
    }

    pub fn intersect(self: *FileSet, other: *const FileSet) !void {
        var to_remove: [4096][]const u8 = undefined;
        var remove_count: usize = 0;

        var it = self.files.keyIterator();
        while (it.next()) |key| {
            if (!other.contains(key.*)) {
                if (remove_count < 4096) {
                    to_remove[remove_count] = key.*;
                    remove_count += 1;
                }
            }
        }

        for (to_remove[0..remove_count]) |key| {
            _ = self.files.remove(key);
            self.allocator.free(key);
        }
    }

    pub fn unite(self: *FileSet, other: *const FileSet) !void {
        var it = other.files.keyIterator();
        while (it.next()) |key| {
            try self.add(key.*);
        }
    }

    pub fn subtract(self: *FileSet, other: *const FileSet) !void {
        var to_remove: [4096][]const u8 = undefined;
        var remove_count: usize = 0;

        var it = self.files.keyIterator();
        while (it.next()) |key| {
            if (other.contains(key.*)) {
                if (remove_count < 4096) {
                    to_remove[remove_count] = key.*;
                    remove_count += 1;
                }
            }
        }

        for (to_remove[0..remove_count]) |key| {
            _ = self.files.remove(key);
            self.allocator.free(key);
        }
    }

    pub fn clone(self: *const FileSet) !FileSet {
        var new_set = FileSet.init(self.allocator);
        var it = self.files.keyIterator();
        while (it.next()) |key| {
            try new_set.add(key.*);
        }
        return new_set;
    }
};

const Token = union(enum) {
    supplier: []const u8,
    @"and",
    @"or",
    not,
    lparen,
    rparen,
};

fn tokenize(allocator: std.mem.Allocator, expr: []const u8) ![]Token {
    var tokens: [64]Token = undefined;
    var count: usize = 0;

    var i: usize = 0;
    while (i < expr.len) {
        while (i < expr.len and (expr[i] == ' ' or expr[i] == '\t')) {
            i += 1;
        }
        if (i >= expr.len) break;

        if (count >= 64) return QueryError.InvalidExpression;

        if (expr[i] == '(') {
            tokens[count] = .lparen;
            count += 1;
            i += 1;
        } else if (expr[i] == ')') {
            tokens[count] = .rparen;
            count += 1;
            i += 1;
        } else if (std.mem.startsWith(u8, expr[i..], "and") and
            (i + 3 >= expr.len or !std.ascii.isAlphanumeric(expr[i + 3])))
        {
            tokens[count] = .@"and";
            count += 1;
            i += 3;
        } else if (std.mem.startsWith(u8, expr[i..], "or") and
            (i + 2 >= expr.len or !std.ascii.isAlphanumeric(expr[i + 2])))
        {
            tokens[count] = .@"or";
            count += 1;
            i += 2;
        } else if (std.mem.startsWith(u8, expr[i..], "not") and
            (i + 3 >= expr.len or !std.ascii.isAlphanumeric(expr[i + 3])))
        {
            tokens[count] = .not;
            count += 1;
            i += 3;
        } else if (std.ascii.isAlphanumeric(expr[i]) or expr[i] == '_') {
            const start = i;
            while (i < expr.len and (std.ascii.isAlphanumeric(expr[i]) or expr[i] == '_' or expr[i] == '-')) {
                i += 1;
            }
            tokens[count] = .{ .supplier = expr[start..i] };
            count += 1;
        } else {
            return QueryError.InvalidExpression;
        }
    }

    const result = try allocator.alloc(Token, count);
    @memcpy(result, tokens[0..count]);
    return result;
}

const ParseError = QueryError || error{OutOfMemory};

const Parser = struct {
    tokens: []const Token,
    pos: usize,
    suppliers: *const std.json.ObjectMap,
    allocator: std.mem.Allocator,
    io: std.Io,
    shell: shellmod.ShellConfig,
    compiler: ?compilermod.CompilerConfig,

    fn parse(self: *Parser) ParseError!FileSet {
        return self.parseOr();
    }

    fn parseOr(self: *Parser) ParseError!FileSet {
        var left = try self.parseAnd();
        errdefer left.deinit();

        while (self.pos < self.tokens.len and self.tokens[self.pos] == .@"or") {
            self.pos += 1;
            var right = try self.parseAnd();
            defer right.deinit();
            try left.unite(&right);
        }

        return left;
    }

    fn parseAnd(self: *Parser) ParseError!FileSet {
        var left = try self.parseNot();
        errdefer left.deinit();

        while (self.pos < self.tokens.len and self.tokens[self.pos] == .@"and") {
            self.pos += 1;
            var right = try self.parseNot();
            defer right.deinit();
            try left.intersect(&right);
        }

        return left;
    }

    fn parseNot(self: *Parser) ParseError!FileSet {
        if (self.pos < self.tokens.len and self.tokens[self.pos] == .not) {
            self.pos += 1;
            var all = try self.getAllFiles();
            errdefer all.deinit();
            var operand = try self.parsePrimary();
            defer operand.deinit();
            try all.subtract(&operand);
            return all;
        }
        return self.parsePrimary();
    }

    fn parsePrimary(self: *Parser) ParseError!FileSet {
        if (self.pos >= self.tokens.len) {
            return QueryError.InvalidExpression;
        }

        const token = self.tokens[self.pos];
        switch (token) {
            .lparen => {
                self.pos += 1;
                var result = try self.parseOr();
                if (self.pos >= self.tokens.len or self.tokens[self.pos] != .rparen) {
                    result.deinit();
                    return QueryError.InvalidExpression;
                }
                self.pos += 1;
                return result;
            },
            .supplier => |name| {
                self.pos += 1;
                return self.runSupplier(name);
            },
            else => return QueryError.InvalidExpression,
        }
    }

    fn runSupplier(self: *Parser, name: []const u8) !FileSet {
        const supplier = self.suppliers.get(name) orelse {
            return QueryError.UnknownSupplier;
        };

        const scope = supplier.object.get("scope").?.string;
        const cmd = supplier.object.get("cmd").?.string;

        if (cmd.len == 0) {
            return FileSet.init(self.allocator);
        }

        const supplier_shell = try shellmod.resolveForSupplier(&supplier, self.shell);
        return executeCommand(self.allocator, self.io, self.compiler, supplier_shell, scope, cmd);
    }

    fn getAllFiles(self: *Parser) !FileSet {
        var result = FileSet.init(self.allocator);
        errdefer result.deinit();

        var it = self.suppliers.iterator();
        while (it.next()) |entry| {
            const supplier = entry.value_ptr.*;
            const scope = supplier.object.get("scope").?.string;
            const cmd = supplier.object.get("cmd").?.string;

            if (cmd.len == 0) continue;

            const supplier_shell = try shellmod.resolveForSupplier(&supplier, self.shell);
            var supplier_files = try executeCommand(self.allocator, self.io, self.compiler, supplier_shell, scope, cmd);
            defer supplier_files.deinit();
            try result.unite(&supplier_files);
        }

        return result;
    }
};

fn executeCommand(
    allocator: std.mem.Allocator,
    io: std.Io,
    compiler: ?compilermod.CompilerConfig,
    shell: shellmod.ShellConfig,
    scope: []const u8,
    cmd: []const u8,
) !FileSet {
    var result = FileSet.init(allocator);
    errdefer result.deinit();

    const cwd: std.process.Child.Cwd = if (scope.len > 0 and !std.mem.eql(u8, scope, "."))
        .{ .path = scope }
    else
        .inherit;

    const compiled_cmd = if (compiler) |active_compiler|
        compilermod.compileCommand(allocator, io, active_compiler, shell.program, cmd) catch
            return QueryError.CommandFailed
    else
        null;
    defer if (compiled_cmd) |owned| allocator.free(owned);

    const run_result = std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ shell.program, shell.execute_arg, compiled_cmd orelse cmd },
        .cwd = cwd,
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(64 * 1024),
    }) catch {
        return result;
    };
    defer allocator.free(run_result.stdout);
    defer allocator.free(run_result.stderr);

    var lines = std.mem.splitScalar(u8, run_result.stdout, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len > 0) {
            try result.add(trimmed);
        }
    }

    return result;
}

pub fn execute(
    allocator: std.mem.Allocator,
    io: std.Io,
    suppliers: *const std.json.ObjectMap,
    expr: []const u8,
    shell: shellmod.ShellConfig,
    compiler: ?compilermod.CompilerConfig,
) !FileSet {
    if (expr.len == 0) {
        var result = FileSet.init(allocator);
        errdefer result.deinit();

        var it = suppliers.iterator();
        while (it.next()) |entry| {
            const supplier = entry.value_ptr.*;
            const scope = supplier.object.get("scope").?.string;
            const cmd = supplier.object.get("cmd").?.string;

            if (cmd.len == 0) continue;

            const supplier_shell = try shellmod.resolveForSupplier(&supplier, shell);
            var supplier_files = try executeCommand(allocator, io, compiler, supplier_shell, scope, cmd);
            defer supplier_files.deinit();
            try result.unite(&supplier_files);
        }

        return result;
    }

    const tokens = try tokenize(allocator, expr);
    defer allocator.free(tokens);

    var parser = Parser{
        .tokens = tokens,
        .pos = 0,
        .suppliers = suppliers,
        .allocator = allocator,
        .io = io,
        .shell = shell,
        .compiler = compiler,
    };

    return parser.parse();
}
