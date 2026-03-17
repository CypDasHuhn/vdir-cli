const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const shared_shell = b.createModule(.{
        .root_source_file = b.path("src/shell.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "vdir_cli",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const clap = b.dependency("clap", .{});
    exe.root_module.addImport("clap", clap.module("clap"));
    b.installArtifact(exe);

    const vc_exe = b.addExecutable(.{
        .name = "vc",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/vc/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    vc_exe.root_module.addImport("shared_shell", shared_shell);
    b.installArtifact(vc_exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
