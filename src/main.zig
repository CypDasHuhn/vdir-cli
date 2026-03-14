const std = @import("std");

const Command = enum {
    init,
    pwd,
    cd,
    ls,
    mkdir,
    mkq,
    shell,
    ln,
    rm,
    mv,
    info,
    set,
    help,
};

fn printUsage() void {
    std.debug.print(
        \\Usage: vdir <command> [args]
        \\
        \\Commands:
        \\  init             Initialize a new vdir in current directory
        \\  pwd              Print current marker
        \\  cd <path>        Change marker to directory
        \\  ls [-a] [-l] [-r[N]]  List items (-a=hidden, -l=long, -r=recursive)
        \\  mkdir <name>     Create a folder
        \\  mkq <name> [cmd]  Create a query
        \\  shell [...]      Show or configure the command shell
        \\  ln <path> [name] Create a reference to file/directory
        \\  rm <name>        Remove item
        \\  mv <name> <dest> Rename or move item
        \\  info <name>      Show item details
        \\  set <name> <prop> [args]   Set item property
        \\  help             Show this help
        \\
        \\Paths:
        \\  ~       Root of vdir
        \\  ..      Parent directory
        \\  <name>  Relative to current marker
        \\
    , .{});
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var args = try std.process.Args.iterateAllocator(init.minimal.args, allocator);
    defer args.deinit();
    _ = args.next();

    const cmd_str = args.next() orelse {
        printUsage();
        std.process.exit(1);
    };

    const cmd = std.meta.stringToEnum(Command, cmd_str) orelse {
        std.debug.print("Unknown command: {s}\n", .{cmd_str});
        printUsage();
        std.process.exit(1);
    };

    switch (cmd) {
        .init => try @import("commands/init.zig").run(io),
        .pwd => try @import("commands/pwd.zig").run(io, allocator),
        .cd => try @import("commands/cd.zig").run(io, allocator, &args),
        .ls => try @import("commands/ls.zig").run(io, allocator, init.minimal.environ, &args),
        .mkdir => try @import("commands/mkdir.zig").run(io, allocator, &args),
        .mkq => try @import("commands/mkq.zig").run(io, allocator, init.minimal.environ, &args),
        .shell => try @import("commands/shell.zig").run(io, allocator, init.minimal.environ, &args),
        .ln => try @import("commands/ln.zig").run(io, allocator, &args),
        .rm => try @import("commands/rm.zig").run(io, allocator, &args),
        .mv => try @import("commands/mv.zig").run(io, allocator, &args),
        .info => try @import("commands/info.zig").run(io, allocator, &args),
        .set => try @import("commands/set.zig").run(io, allocator, init.minimal.environ, &args),
        .help => printUsage(),
    }
}
