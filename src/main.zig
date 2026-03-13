const std = @import("std");

const Command = enum {
    init,
    cd,
    ls,
    add,
    delete,
    rename,
    move,
    read,
    @"query-edit",
    help,
};

fn printUsage() void {
    std.debug.print(
        \\Usage: vdir <command> [args]
        \\
        \\Commands:
        \\  init              Initialize a new vdir in current directory
        \\  cd <path>         Change marker to directory
        \\  ls [flags]        List items at current marker
        \\  add <name>        Add folder or query
        \\  add <ref> [name]  Add reference to file/directory
        \\  delete <name>     Delete item
        \\  rename <old> <new> Rename item
        \\  move <name> <dir> Move item to directory
        \\  read <name>       Show item details
        \\  query-edit <name> Edit query definition
        \\  help              Show this help
        \\
        \\Paths:
        \\  ~/      Root of vdir
        \\  ../     Parent directory
        \\  <name>  Relative to current marker
        \\
    , .{});
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var args = std.process.Args.Iterator.init(init.minimal.args);
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
        .cd => try @import("commands/cd.zig").run(io, allocator, &args),
        .ls => try @import("commands/ls.zig").run(io, allocator, &args),
        .add => try @import("commands/add.zig").run(io, allocator, &args),
        .delete => @import("commands/delete.zig").run(&args),
        .rename => @import("commands/rename.zig").run(&args),
        .move => @import("commands/move.zig").run(&args),
        .read => @import("commands/read.zig").run(&args),
        .@"query-edit" => @import("commands/query_edit.zig").run(&args),
        .help => printUsage(),
    }
}
