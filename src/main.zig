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

pub fn installPath(env: *const std.process.Environ.Map, io: std.Io, alloc: Allocator) ![]const u8 {
    const home = env.get("HOME") orelse return error.NoHomeDir;
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
    /// check <file/folder> <depth>
    check,
    /// safe <file/folder> <depth>
    safe,
    /// save <file/folder> <depth>
    save,
    /// xml <file>
    xml,
    /// scan <folder>
    scan,
    /// reset
    reset,

    pub fn scanInfo(w: *std.Io.Writer) !void {
        try w.print("{s}\t{s:<5}{s} - {s}\n", .{ Color.magenta.code(), "scan", Color.reset.code(), "add a folder of samples to be checked when searching for missing files" });
        try w.print("{s}\t\tusage: {s} <folder>{s}\n", .{ Color.yellow.code(), "scan", Color.reset.code() });
    }

    pub fn info(w: *std.Io.Writer) !void {
        try w.print("{s}valid command options are:{s}\n", .{ Color.blue.code(), Color.reset.code() });
        try w.print("{s}\t{s:<5}{s} - {s}\n", .{ Color.magenta.code(), "check", Color.reset.code(), "dry-run to visualize which files are missing" });
        try w.print("{s}\t\tusage: {s} <file/folder> <none/deep>{s}\n", .{ Color.yellow.code(), "check", Color.reset.code() });

        try w.print("{s}\t{s:<5}{s} - {s}\n", .{ Color.magenta.code(), "safe", Color.reset.code(), "prompted file by file to [collect/ignore]" });
        try w.print("{s}\t\tusage: {s} <file/folder> <none/deep>{s}\n", .{ Color.yellow.code(), "safe", Color.reset.code() });

        try w.print("{s}\t{s:<5}{s} - {s}\n", .{ Color.magenta.code(), "save", Color.reset.code(), "saves all missing files" });
        try w.print("{s}\t\tusage: {s} <file/folder> <none/deep>{s}\n", .{ Color.yellow.code(), "save", Color.reset.code() });

        try Command.scanInfo(w);

        try w.print("{s}\t{s:<5}{s} - {s}\n", .{ Color.magenta.code(), "xml", Color.reset.code(), "visualize ableton's interal xml structure" });
        try w.print("{s}\t\tusage: {s} <file>{s}\n", .{ Color.yellow.code(), "xml", Color.reset.code() });

        try w.print("{s}\t{s:<5}{s} - {s}\n", .{ Color.magenta.code(), "scan", Color.reset.code(), "add a folder of samples to be checked when searching for missing files" });
        try w.print("{s}\t\tusage: {s} <folder>{s}\n", .{ Color.yellow.code(), "scan", Color.reset.code() });

        try w.print("{s}\t{s:<5}{s} - {s}\n", .{ Color.magenta.code(), "reset", Color.reset.code(), "remove all saved folders of samples" });
        try w.print("{s}\t\tusage: {s}{s}\n", .{ Color.yellow.code(), "reset", Color.reset.code() });
        try w.flush();
    }
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

    const install_path = try installPath(init.environ_map, io, alloc);
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

    if (args.len < 2) {
        try Command.info(&writer.interface);
        return;
    }
    const cmd = std.meta.stringToEnum(Command, args[1]) orelse {
        try Command.info(&writer.interface);
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
            if (ableton_data == null) {
                try input.w.print("{s}please provide a folder of samples to scan{s}\n", .{ Color.red.code(), Color.reset.code() });
                try Command.scanInfo(input.w);
                try input.w.flush();
                return;
            }
            return try lib.database.scanDir(io, alloc, &conn, ableton_data.?.filepath);
        },
        .check, .safe, .save => |x| {
            ensureNotNull(AbletonData, &writer.interface, ableton_data) catch return;
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
        try input.w.print("{s}failed to find / read: {s}'{s}'\n", .{ Color.red.code(), Color.reset.code(), filepath });
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

    switch (stat.kind) {
        .file => {
            _ = try lib.verifyAndCollect(io, gpa, &config, filepath);
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

                        _ = lib.verifyAndCollect(io, gpa, &config, full_path) catch continue;
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

                        _ = lib.verifyAndCollect(io, gpa, &config, entry.path) catch continue;
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
        _ = try w.print("\tformat is: {s}<cmd> <file/folder> <none/deep>{s}\n", .{ Color.blue.code(), Color.reset.code() });
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
