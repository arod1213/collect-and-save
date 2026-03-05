const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sqlite_dep = b.dependency("sqlzig", .{
        .optimize = optimize,
    });
    const sqlite = sqlite_dep.module("sqlzig");

    const xml_dep = b.dependency("zxml", .{
        .target = target,
        .optimize = optimize,
    });
    const xml = xml_dep.module("zxml");

    const mod = b.addModule("collect_and_save", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "sqlite", .module = sqlite },
            .{ .name = "xml", .module = xml },
        },
    });

    const zli_dep = b.dependency("zli", .{
        .target = target,
        .optimize = optimize,
    });
    const zli = zli_dep.module("zli");

    const exe = b.addExecutable(.{
        .name = "collect_and_save", // maybe change this
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "sqlite", .module = sqlite },
                .{ .name = "zli", .module = zli },
                .{ .name = "collect_and_save", .module = mod },
            },
        }),
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
