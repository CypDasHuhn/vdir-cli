const std = @import("std");
const builtin = @import("builtin");

pub const Shell = enum {
    bash,
    zsh,
    nu,
    powershell,
    cmd,

    pub fn fromString(s: []const u8) ?Shell {
        if (std.mem.eql(u8, s, "bash")) return .bash;
        if (std.mem.eql(u8, s, "zsh")) return .zsh;
        if (std.mem.eql(u8, s, "nu")) return .nu;
        if (std.mem.eql(u8, s, "powershell")) return .powershell;
        if (std.mem.eql(u8, s, "cmd")) return .cmd;
        return null;
    }

    pub fn toString(self: Shell) []const u8 {
        return switch (self) {
            .bash => "bash",
            .zsh => "zsh",
            .nu => "nu",
            .powershell => "powershell",
            .cmd => "cmd",
        };
    }

    /// Returns the executable name for this shell
    pub fn executable(self: Shell) []const u8 {
        return switch (self) {
            .bash => "bash",
            .zsh => "zsh",
            .nu => "nu",
            .powershell => "pwsh",
            .cmd => "cmd",
        };
    }

    /// Returns argv for executing a command with this shell
    pub fn buildArgv(self: Shell, cmd: []const u8) [3][]const u8 {
        return switch (self) {
            .bash => .{ "bash", "-c", cmd },
            .zsh => .{ "zsh", "-c", cmd },
            .nu => .{ "nu", "-c", cmd },
            .powershell => .{ "pwsh", "-Command", cmd },
            .cmd => .{ "cmd", "/c", cmd },
        };
    }
};

/// Get the default shell for the current platform
pub fn getDefaultShell() Shell {
    if (builtin.os.tag == .windows) {
        return .cmd;
    }

    // Try to get $SHELL using libc
    const shell_ptr = std.c.getenv("SHELL") orelse return .bash;
    const shell_path = std.mem.span(shell_ptr);

    // Extract shell name from path (e.g., "/bin/zsh" -> "zsh")
    const shell_name = std.fs.path.basename(shell_path);

    return Shell.fromString(shell_name) orelse .bash;
}

/// Check if a shell is available in PATH
pub fn isInPath(io: std.Io, shell: Shell) bool {
    const exe_name = shell.executable();

    // Use 'which' on Unix, 'where' on Windows
    const check_cmd = if (builtin.os.tag == .windows)
        &[_][]const u8{ "where", exe_name }
    else
        &[_][]const u8{ "which", exe_name };

    var child = std.process.spawn(io, .{
        .argv = check_cmd,
        .stdout = .ignore,
        .stderr = .ignore,
    }) catch return false;

    const term = child.wait(io) catch return false;
    return switch (term) {
        .exited => |code| code == 0,
        else => false,
    };
}

/// All supported shells in order of preference for fallback
pub const all_shells: []const Shell = &.{
    .bash,
    .zsh,
    .nu,
    .powershell,
    .cmd,
};

/// Find the first available shell from a command map
pub fn findAvailableShell(io: std.Io, cmd_map: *const std.json.ObjectMap) ?Shell {
    // First try default shell
    const default = getDefaultShell();
    if (cmd_map.get(default.toString()) != null) {
        return default;
    }

    // Then try each shell in the map that's available
    for (all_shells) |shell| {
        if (cmd_map.get(shell.toString()) != null) {
            if (isInPath(io, shell)) {
                return shell;
            }
        }
    }

    return null;
}
