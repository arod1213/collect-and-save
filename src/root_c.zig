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

pub const FileErr = enum(u8) { none = 0, no_dir, not_found, null_file };
pub const FileRes = extern struct {
    state: FileState,
    err: FileErr,
};

// EXPORTS
pub export fn checkFile(file: [*c]lib.AbletonFile) FileRes {
    if (file == null) {
        return .{
            .state = .collected,
            .err = .null_file,
        };
    }
    // defer std.heap.c_allocator.free(file.*);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var t = std.Io.Threaded.init(alloc, .{});
    defer t.deinit();
    const io = t.io();

    var session_dir = lib.collect.getSessionDir(io, file.*.file_path) catch return .{
        .state = .collected,
        .err = .no_dir,
    };
    defer session_dir.close(io);

    const res = lib.findFile(io, alloc, file.*, session_dir, null) catch return .{
        .state = .collected,
        .err = .not_found,
    };
    return .{
        .state = res.status,
        .err = .none,
    };
}
