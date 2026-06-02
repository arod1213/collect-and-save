const std = @import("std");
const span = std.mem.span;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Dir = std.Io.Dir;
const Writer = std.Io.Writer;
const Reader = std.Io.Reader;

const sqlite = @import("sqlite");
const lib = @import("collect_and_save");
const Color = lib.Color;
const zli = @import("zli");
const termios = @import("termios.zig");

pub fn installPath(init: std.process.Init, io: std.Io, alloc: Allocator) ![]const u8 {
    const home = init.environ_map.get("HOME") orelse return error.NoHomeDir;
    const path = try std.fs.path.join(alloc, &[_][]const u8{ home, "Documents/CollectAndSave" });

    _ = Dir.createDirAbsolute(io, path, .default_file) catch |e| {
        switch (e) {
            error.PathAlreadyExists => {},
            else => return e,
        }
    };
    return path;
}

const Depth = enum { none, deep };
const AbletonData = struct { filepath: []const u8, depth: Depth = .none };
const Command = enum {
    // ableton
    check, // safe <file/folder> <depth>
    safe, // safe <file/folder> <depth>
    save, // save <file/folder> <depth>
    xml, // xml <file>
    // db
    scan, // scan <folder>
    reset, // reset
};

pub fn main(init: std.process.Init) !void {
    // const alloc = init.arena.allocator();
    const alloc = init.gpa;
    const io = init.io;

    var stdout = std.Io.File.stdout();
    defer stdout.close(io);
    var out_buffer: [4096]u8 = undefined;
    var writer = stdout.writer(io, &out_buffer);

    var stdin = std.Io.File.stdin();
    defer stdin.close(io);
    var in_buffer: [4096]u8 = undefined;
    var reader = stdin.reader(io, &in_buffer);

    const install_path = try installPath(init, io, alloc);
    defer alloc.free(install_path);
    const db_path = try std.fs.path.join(alloc, &[_][]const u8{ install_path, "collect.db" });
    defer alloc.free(db_path);

    var conn = try lib.database.setup(db_path);
    defer conn.deinit();

    termios.setup(stdin.handle) catch {
        std.log.err("failed to setup termios", .{});
    };
    defer _ = termios.restore(stdin.handle) catch {};

    const args = try init.minimal.args.toSlice(alloc);
    defer alloc.free(args);

    const cmd = std.meta.stringToEnum(Command, args[1]) orelse {
        try enumInfo(Command, &writer.interface);
        return;
    };
    const input = CollectInput{
        .w = &writer.interface,
        .r = &reader.interface,
        .db = &conn,
    };
    const ableton_data: ?AbletonData = if (args.len < 3) null else zli.parseOrdered(AbletonData, args[2..], .offset) catch null;
    switch (cmd) {
        .reset => return try lib.database.reset(&conn),
        .scan => {
            _ = try input.w.print("\rscanning files please wait..\r", .{});
            try input.w.flush();
            ensureNotNull(AbletonData, &writer.interface, ableton_data) catch return;
            return try lib.database.scanDir(io, alloc, &conn, ableton_data.?.filepath);
        },
        .check, .safe, .save => |x| {
            ensureNotNull(AbletonData, &writer.interface, ableton_data) catch |e| {
                std.log.err("err {any}", .{e});
                return;
            };
            const save_cmd: lib.SaveCommand = switch (x) {
                .check => .check,
                .safe => .safe,
                .save => .save,
                else => return error.InvalidCmd,
            };
            try run(io, alloc, &input, ableton_data.?.filepath, save_cmd, ableton_data.?.depth);
        },
        .xml => {
            ensureNotNull(AbletonData, &writer.interface, ableton_data) catch return;
            var file = try lib.openFile(io, ableton_data.?.filepath, .{});
            defer file.close(io);
            lib.gzip.writeXml(io, &file, &writer.interface) catch {
                try writer.interface.print("failed to open file: '{s}'", .{ableton_data.?.filepath});
                try writer.flush();
            };
        },
    }
}

const CollectInput = struct {
    w: *std.Io.Writer,
    r: *std.Io.Reader,
    db: *sqlite.Conn,
};

pub fn run(io: std.Io, gpa: Allocator, input: *const CollectInput, filepath: []const u8, cmd: lib.SaveCommand, mode: Depth) !void {
    const stat = Dir.cwd().statFile(io, filepath, .{ .follow_symlinks = false }) catch {
        try input.w.print("{s}failed to find / read: {s}{s}\n", .{ Color.red.code(), filepath, Color.reset.code() });
        try input.w.flush();
        return;
    };

    var session_dir = try lib.collect.getSessionDir(io, filepath);
    defer session_dir.close(io);
    var config = lib.CollectFileConfig{
        .reader = input.r,
        .writer = input.w,
        .db = input.db,
        .session_dir = session_dir,
        .cmd = cmd,
    };

    // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // defer arena.deinit();
    // const alloc = arena.allocator();
    switch (stat.kind) {
        .file => {
            try lib.verifyAndCollect(io, gpa, &config, filepath);
        },
        .directory => {
            var dir = if (std.fs.path.isAbsolute(filepath))
                try Dir.openDirAbsolute(io, filepath, .{ .iterate = true })
            else
                try Dir.cwd().openDir(io, filepath, .{ .iterate = true });
            defer dir.close(io);

            switch (mode) {
                .none => {
                    var iter = dir.iterate();
                    while (try iter.next(io)) |entry| {
                        switch (entry.kind) {
                            .file => {},
                            else => continue,
                        }
                        const full_path = try std.fs.path.join(gpa, &[_][]const u8{ filepath, entry.name });
                        defer gpa.free(full_path);

                        // defer _ = arena.reset(.free_all);
                        lib.verifyAndCollect(io, gpa, &config, full_path) catch continue;
                    }
                },
                .deep => {
                    var iter = try dir.walk(std.heap.page_allocator);
                    defer iter.deinit();

                    while (try iter.next(io)) |entry| {
                        switch (entry.kind) {
                            .file => {},
                            else => continue,
                        }

                        // reassign session dir to nearest parent folder
                        session_dir = try lib.collect.getSessionDir(io, entry.path);
                        config.session_dir = session_dir;

                        // defer _ = arena.reset(.free_all); // free main arena if collecting set
                        lib.verifyAndCollect(io, gpa, &config, entry.path) catch continue;
                    }
                },
            }
        },
        else => {}, // skip invalid entry types
    }
}

// ---------------
// TEXT RENDERING
// ---------------
fn ensureNotNull(comptime T: type, w: *Writer, filepath: ?T) !void {
    if (filepath == null) {
        _ = try w.print("{s}please provide a folder or file {s}\n", .{
            Color.red.code(),
            Color.reset.code(),
        });
        try w.flush();
        return error.NoFilepath;
    }
    return;
}

fn enumInfo(comptime T: type, w: *std.Io.Writer) !void {
    _ = try w.print("{s}invalid command:{s}\n", .{ Color.red.code(), Color.reset.code() });
    const info = @typeInfo(T);
    assert(info == .@"enum");

    inline for (info.@"enum".fields) |field| {
        _ = try w.print("\t{s}", .{field.name});
    }
    _ = try w.write("\n");
    try w.flush();

    return;
}
