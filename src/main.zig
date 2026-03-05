const std = @import("std");
const span = std.mem.span;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const Reader = std.Io.Reader;

const sqlite = @import("sqlite");
const lib = @import("collect_and_save");
const Color = lib.Color;
const zli = @import("zli");
const termios = @import("termios.zig");

pub fn installPath(alloc: Allocator) ![]const u8 {
    const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
    const path = try std.fs.path.join(alloc, &[_][]const u8{ home, "Documents/CollectAndSave" });

    _ = std.fs.makeDirAbsolute(path) catch |e| {
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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .verbose_log = false }){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const alloc = arena.allocator();

    var stdout = std.fs.File.stdout();
    defer stdout.close();
    var out_buffer: [4096]u8 = undefined;
    var writer = stdout.writer(&out_buffer);

    var stdin = std.fs.File.stdin();
    defer stdin.close();
    var in_buffer: [4096]u8 = undefined;
    var reader = stdin.reader(&in_buffer);

    const install_path = try installPath(alloc);
    const db_path = try std.fs.path.join(alloc, &[_][]const u8{ install_path, "collect.db" });

    var conn = try lib.database.setup(db_path);
    defer conn.deinit();

    termios.setup(stdin.handle) catch {
        std.log.err("failed to setup termios", .{});
    };
    defer _ = termios.restore(stdin.handle) catch {};

    const args = std.os.argv;
    const cmd = std.meta.stringToEnum(Command, std.mem.span(args[1])) orelse {
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
            return try lib.database.scanDir(alloc, &conn, ableton_data.?.filepath);
        },
        .check => {
            ensureNotNull(AbletonData, &writer.interface, ableton_data) catch return;
            try collectAll(&input, ableton_data.?.filepath, .check, ableton_data.?.depth);
        },
        .safe => {
            ensureNotNull(AbletonData, &writer.interface, ableton_data) catch return;
            try collectAll(&input, ableton_data.?.filepath, .safe, ableton_data.?.depth);
        },
        .save => {
            ensureNotNull(AbletonData, &writer.interface, ableton_data) catch return;
            try collectAll(&input, ableton_data.?.filepath, .save, ableton_data.?.depth);
        },
        .xml => {
            ensureNotNull(AbletonData, &writer.interface, ableton_data) catch return;
            var file = try lib.openFile(ableton_data.?.filepath, .{});
            defer file.close();
            try lib.gzip.writeXml(&file, &writer.interface);
        },
    }
}

const CollectInput = struct {
    w: *std.Io.Writer,
    r: *std.Io.Reader,
    db: *sqlite.Conn,
};

pub fn collectAll(input: *const CollectInput, filepath: []const u8, cmd: lib.SaveCommand, mode: Depth) !void {
    const stat = std.fs.cwd().statFile(filepath) catch {
        try input.w.print("{s}failed to find / read: {s}{s}\n", .{ Color.red.code(), filepath, Color.reset.code() });
        try input.w.flush();
        return;
    };

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    switch (stat.kind) {
        .file => try collectSet(alloc, input, filepath, cmd),
        .directory => {
            var dir = if (std.fs.path.isAbsolute(filepath))
                try std.fs.openDirAbsolute(filepath, .{ .iterate = true })
            else
                try std.fs.cwd().openDir(filepath, .{ .iterate = true });
            defer dir.close();

            switch (mode) {
                .none => {
                    var iter = dir.iterate();
                    while (try iter.next()) |entry| {
                        switch (entry.kind) {
                            .file => {},
                            else => continue,
                        }
                        if (!lib.checks.validAbleton(entry.name)) continue;
                        const full_path = try std.fs.path.join(alloc, &[_][]const u8{ filepath, entry.name });

                        defer _ = arena.reset(.free_all);
                        collectSet(alloc, input, full_path, cmd) catch continue;
                    }
                },
                .deep => {
                    var iter = try dir.walk(std.heap.page_allocator);
                    defer iter.deinit();

                    while (try iter.next()) |entry| {
                        switch (entry.kind) {
                            .file => {},
                            else => continue,
                        }
                        if (!lib.checks.validAbleton(entry.basename)) continue;

                        defer _ = arena.reset(.free_all); // free main arena if collecting set
                        collectSet(alloc, input, entry.path, cmd) catch continue;
                    }
                },
            }
        },
        else => {}, // skip invalid entry types
    }
}

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

fn collectSet(alloc: Allocator, input: *const CollectInput, filepath: []const u8, cmd: lib.SaveCommand) !void {
    defer input.w.flush() catch {};
    if (!lib.checks.validAbleton(filepath)) {
        _ = try input.w.print("{s}{s} is not a valid ableton file{s}\n", .{
            Color.red.code(),
            std.fs.path.basename(filepath),
            Color.reset.code(),
        });
        return;
    }

    if (lib.checks.isBackup(filepath)) {
        _ = try input.w.print("skipping backup: {s}\n", .{std.fs.path.basename(filepath)});
        return;
    }
    try lib.collectAndSave(alloc, input.db, input.r, input.w, filepath, cmd);
}
