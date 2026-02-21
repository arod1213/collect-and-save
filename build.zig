const std = @import("std");

// fn install(target: *std.Build.ResolvedTarget) !void {
// cp for mac
// install into correct locations based on target tag
//
// const location = switch (target.result.os.tag) {
//     .macos => "/usr/loca/bin/cms",
//     .linux => "/home/arod/.local/bin/cms",
//     else => "./shit/cms",
// };
// _ = b.addSystemCommand(&[_][]const u8{
//     "cp",
//     exe.installed_path orelse unreachable,
//     location,
// });
// b.installArtifact(exe);
// }

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const recent_files = b.addModule("recent_files", .{
        .root_source_file = b.path("src/recent_files/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const xml = b.addModule("xml", .{
        .root_source_file = b.path("src/xml/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    xml.linkSystemLibrary("xml2", .{
        .needed = true,
        .use_pkg_config = .yes,
        .preferred_link_mode = .dynamic,
        .weak = false,
        .search_strategy = .paths_first,
    });
    xml.link_libc = true;

    switch (target.result.os.tag) {
        .linux => {
            xml.addSystemIncludePath(.{ .cwd_relative = "/usr/include/libxml2" });
            // xml.addLibraryPath(.{ .cwd_relative = "/usr/lib" });
        },
        .macos => {
            if (target.result.cpu.arch == .x86_64) {
                const sdk = b.sysroot orelse "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk";
                xml.addSystemIncludePath(.{ .cwd_relative = b.pathJoin(&.{ sdk, "/usr/include" }) });
                xml.addLibraryPath(.{ .cwd_relative = b.pathJoin(&.{ sdk, "/usr/lib" }) });
            } else {
                // xml.addIncludePath(.{ .cwd_relative = "/usr/local/include/libxml2" });
                // xml.addIncludePath(.{ .cwd_relative = "/opt/homebrew/include/libxml2" });
            }
        },
        else => {},
    }

    const mod = b.addModule("collect_and_save", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "recent_files", .module = recent_files },
            .{ .name = "xml", .module = xml },
        },
    });

    const zli_dep = b.dependency("zli", .{
        .target = target,
        .optimize = optimize,
    });
    const zli = zli_dep.module("zli");

    const exe = b.addExecutable(.{
        .name = "cns", // maybe change this
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
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
