const Allocator = std.mem.Allocator;
const Dir = std.Io.Dir;
const Writer = std.Io.Writer;
const Reader = std.Io.Reader;

const lib = @import("collect_and_save");
const Color = lib.Color;
pub const SaveCommand = lib.SaveCommand;
pub const FileState = lib.FileState;
const sqlite = @import("sqlite");
const zli = @import("zli");

const termios = @import("termios.zig");

const std = @import("std");

pub export fn collectable_files(filepath: [*c]const u8) !void {
    if (filepath == null) {
        return .OK;
    }

    const gpa = std.heap.c_allocator;

    // returns a list of all collectable samples
}

pub export fn save_file(file: [*c]lib.AbletonFile, dry_run: bool) CollectRes {
    if (file == null) {
        return .BAD_FILE;
    }
    const gpa = std.heap.c_allocator;
    var t = std.Io.Threaded.init(gpa, .{});
    defer t.deinit();
    const io = t.io();

    var stdout = std.Io.File.stdout();
    defer stdout.close(io);
    var out_buffer: [4096]u8 = undefined;
    var writer = stdout.writer(io, &out_buffer);

    var stdin = std.Io.File.stdin();
    defer stdin.close(io);
    var in_buffer: [4096]u8 = undefined;
    var reader = stdin.reader(io, &in_buffer);

    var session_dir = lib.collect.getSessionDir(io, file.*.file_path) catch return .BAD_FILE;
    defer session_dir.close(io);

    const config = lib.CollectFileConfig{
        .reader = &reader.interface,
        .writer = &writer.interface,
        .session_dir = session_dir,
        .db = null,
        .cmd = cmd,
    };

    lib.collectFile(io, gpa, file.*, config) catch return .FAIL_COLLECT;
    return .OK;
}

pub export fn is_backup(filepath: [*c]const u8) bool {
    if (filepath == null) {
        return .OK;
    }
    const gpa = std.heap.c_allocator;
    const path = gpa.dupeZ(u8, std.mem.span(filepath)) catch return .BAD_FILE;
    defer gpa.free(path);
    return lib.checks.isBackup(path);
}

pub const CollectRes = enum(u8) { OK, BAD_FILE, FAIL_COLLECT, IS_BACKUP };
pub export fn collect_set(filepath: [*c]const u8, cmd: lib.SaveCommand) CollectRes {
    if (filepath == null) {
        return .OK;
    }

    const gpa = std.heap.c_allocator;
    var t = std.Io.Threaded.init(gpa, .{});
    defer t.deinit();
    const io = t.io();

    const path = gpa.dupeZ(u8, std.mem.span(filepath)) catch return .BAD_FILE;
    defer gpa.free(path);

    var session_dir = lib.collect.getSessionDir(io, path) catch return .BAD_FILE;
    defer session_dir.close(io);

    var stdout = std.Io.File.stdout();
    defer stdout.close(io);
    var out_buffer: [4096]u8 = undefined;
    var writer = stdout.writer(io, &out_buffer);

    var stdin = std.Io.File.stdin();
    defer stdin.close(io);
    var in_buffer: [4096]u8 = undefined;
    var reader = stdin.reader(io, &in_buffer);

    const config = lib.CollectFileConfig{
        .reader = &reader.interface,
        .writer = &writer.interface,
        .session_dir = session_dir,
        .db = null,
        .cmd = cmd,
    };
    lib.collectSet(io, gpa, &config, path) catch return .FAIL_COLLECT;
    return .OK;
}
