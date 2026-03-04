const std = @import("std");
const span = std.mem.span;
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const Reader = std.Io.Reader;

const lib = @import("collect_and_save");
const Color = lib.Color;
const zli = @import("zli");
const termios = @import("termios.zig");

const Depth = enum { none, deep };
const Command = enum { check, safe, save, scan, reset };
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

    var conn = try lib.database.setup("test.db");
    defer conn.deinit();

    termios.setup(stdin.handle) catch {
        std.log.err("failed to setup termios", .{});
    };
    defer _ = termios.restore(stdin.handle) catch {};

    const args = std.os.argv;
    const cmd = std.meta.stringToEnum(Command, std.mem.span(args[1])) orelse {
        _ = try writer.interface.print("{s}please provide a command {s}\n", .{ Color.red.code(), Color.reset.code() });
        try writer.interface.flush();
        return;
    };

    const filepath = if (args.len > 2) span(args[2]) else null;
    switch (cmd) {
        .reset => return try lib.database.reset(&conn),
        .scan => {
            if (filepath == null) {
                _ = try writer.interface.print("{s}please provide a folder {s}\n", .{
                    Color.red.code(),
                    Color.reset.code(),
                });
                try writer.interface.flush();
                return;
            }
            return try lib.database.scanDir(alloc, &conn, filepath.?);
        },
        .check => {
            if (filepath == null) {
                _ = try writer.interface.print("{s}please provide a folder or file {s}\n", .{
                    Color.red.code(),
                    Color.reset.code(),
                });
                try writer.interface.flush();
                return;
            }
            try collectAll(&reader.interface, &writer.interface, filepath.?, .check, .deep);
        },
        .safe => {
            if (filepath == null) {
                _ = try writer.interface.print("{s}please provide a folder or file {s}\n", .{
                    Color.red.code(),
                    Color.reset.code(),
                });
                try writer.interface.flush();
                return;
            }
            try collectAll(&reader.interface, &writer.interface, filepath.?, .safe, .none);
        },
        .save => {
            if (filepath == null) {
                _ = try writer.interface.print("{s}please provide a folder or file {s}\n", .{
                    Color.red.code(),
                    Color.reset.code(),
                });
                try writer.interface.flush();
                return;
            }
            try collectAll(&reader.interface, &writer.interface, filepath.?, .save, .none);
        },
    }
}

pub fn collectAll(r: *Reader, w: *Writer, filepath: []const u8, cmd: lib.SaveCommand, mode: Depth) !void {
    const stat = std.fs.cwd().statFile(filepath) catch {
        try w.print("{s}failed to find / read: {s}{s}\n", .{ Color.red.code(), filepath, Color.reset.code() });
        try w.flush();
        return;
    };

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    switch (stat.kind) {
        .file => try collectSet(alloc, r, w, filepath, cmd),
        .directory => {
            var dir = if (std.fs.path.isAbsolute(filepath))
                try std.fs.openDirAbsolute(filepath, .{ .iterate = true })
            else
                try std.fs.cwd().openDir(filepath, .{ .iterate = true });
            defer dir.close();
            switch (mode) {
                .deep => {
                    var iter = dir.iterate();
                    while (try iter.next()) |entry| {
                        switch (entry.kind) {
                            .file => {},
                            else => continue,
                        }
                        const full_path = try std.fs.path.join(alloc, &[_][]const u8{ filepath, entry.name });
                        defer alloc.free(full_path);

                        // defer _ = arena.reset(.free_all); // free main arena if collecting set
                        collectSet(alloc, r, w, filepath, cmd) catch continue;
                    }
                },
                .none => {
                    var iter = try dir.walk(std.heap.page_allocator);
                    defer iter.deinit();

                    while (try iter.next()) |entry| {
                        switch (entry.kind) {
                            .file => {},
                            else => continue,
                        }
                        if (!lib.checks.validAbleton(entry.basename)) continue;

                        defer _ = arena.reset(.free_all); // free main arena if collecting set
                        collectSet(alloc, r, w, filepath, cmd) catch continue;
                    }
                },
            }
        },
        else => {},
    }
}

fn collectSet(alloc: Allocator, r: *Reader, w: *Writer, filepath: []const u8, cmd: lib.SaveCommand) !void {
    defer w.flush() catch {};
    if (!lib.checks.validAbleton(filepath)) {
        _ = try w.print("{s}{s} is not a valid ableton file{s}\n", .{
            Color.red.code(),
            std.fs.path.basename(filepath),
            Color.reset.code(),
        });
        return;
    }

    if (lib.checks.isBackup(filepath)) {
        _ = try w.print("skipping backup: {s}\n", .{std.fs.path.basename(filepath)});
        return;
    }
    try lib.collectAndSave(alloc, r, w, filepath, cmd);
}
