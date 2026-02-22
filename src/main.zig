const std = @import("std");
const Allocator = std.mem.Allocator;
const print = std.debug.print;
const lib = @import("collect_and_save");
const zli = @import("zli");
const termios = @import("termios.zig");
const draw = lib.ascii;
const Color = draw.Color;

const Command = lib.Command;
fn commandInfo(w: *std.Io.Writer) !void {
    _ = try w.print("{s}invalid command:{s}\n", .{ Color.red.code(), Color.reset.code() });
    const info = @typeInfo(Command);

    inline for (info.@"enum".fields) |field| {
        _ = try w.print("\t{s}", .{field.name});
    }
    _ = try w.write("\n");
    try w.flush();

    return;
}

fn collectSet(alloc: Allocator, reader: *std.Io.Reader, writer: *std.Io.Writer, filepath: []const u8, cmd: *const Command) !void {
    if (!lib.checks.validAbleton(filepath)) {
        _ = try writer.print("{s}{s} is not a valid ableton file{s}\n", .{ Color.red.code(), std.fs.path.basename(filepath), Color.reset.code() });
        try writer.flush();
        return;
    }

    if (lib.checks.isBackup(filepath)) {
        _ = try writer.print("skipping backup: {s}\n", .{std.fs.path.basename(filepath)});
        try writer.flush();
        return;
    }

    switch (cmd.*) {
        .xml => {
            var file = try std.fs.cwd().openFile(filepath, .{});
            defer file.close();
            try lib.gzip.writeXml(&file, writer);
        },
        .save, .check, .info, .safe => try lib.collectAndSave(alloc, reader, writer, filepath, cmd.*),
    }
}

pub const Depth = enum { default, deep };
const Input = struct {
    cmd: Command,
    filepath: []const u8,
    depth: Depth = .default,
};

// TODO: dont prompt for depth if filepath is a directory (or if file not found)
pub fn getConfig(stdin: *std.fs.File, r: *std.Io.Reader, w: *std.Io.Writer) !Input {
    const original_termios = try termios.setup(stdin.handle);
    defer termios.restore(stdin.handle, original_termios);

    _ = try draw.clearScreen(w);
    const cmd = try draw.enumOptions(Command, r, w);
    _ = try draw.prompt(w, "default = 1 folder, deep = all sub folders");
    const depth = try draw.enumOptions(Depth, r, w);

    _ = try draw.prompt(w, "please provide a file or a folder\n");
    try termios.enableWrite(stdin.handle);
    const filepath = try draw.readLine(r);

    return .{
        .cmd = cmd,
        .filepath = filepath,
        .depth = depth,
    };
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

    const input = try getConfig(&stdin, &reader.interface, &writer.interface);
    const original_termios = try termios.setup(stdin.handle);
    defer termios.restore(stdin.handle, original_termios);

    const stat = std.fs.cwd().statFile(input.filepath) catch {
        try writer.interface.print("{s}failed to find / read: {s}{s}\n", .{ Color.red.code(), input.filepath, Color.reset.code() });
        try writer.interface.flush();
        return;
    };
    switch (stat.kind) {
        .file => collectSet(alloc, &reader.interface, &writer.interface, input.filepath, &input.cmd) catch {
            try writer.interface.print("{s}failed to collect set: {s}{s}\n", .{ Color.red.code(), input.filepath, Color.reset.code() });
            try writer.interface.flush();
            return;
        },
        .directory => {
            var dir = if (std.fs.path.isAbsolute(input.filepath))
                try std.fs.openDirAbsolute(input.filepath, .{ .iterate = true })
            else
                try std.fs.cwd().openDir(input.filepath, .{ .iterate = true });
            defer dir.close();

            switch (input.depth) {
                .default => {
                    var iter = dir.iterate();
                    while (try iter.next()) |entry| {
                        switch (entry.kind) {
                            .file => {},
                            else => continue,
                        }
                        const full_path = try std.fs.path.join(alloc, &[_][]const u8{ input.filepath, entry.name });
                        defer alloc.free(full_path);
                        defer _ = arena.reset(.free_all); // free main arena if collecting set
                        collectIfValid(alloc, &reader.interface, &writer.interface, full_path, &input.cmd) catch continue;
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
                        collectIfValid(alloc, &reader.interface, &writer.interface, entry.path, &input.cmd) catch continue;
                    }
                },
            }
        },
        else => {
            _ = try writer.interface.print("{s}unsupported file type{s}\n", .{ Color.red.code(), Color.reset.code() });
            try writer.interface.flush();
        },
    }
}

pub fn collectIfValid(alloc: Allocator, reader: *std.Io.Reader, writer: *std.Io.Writer, filepath: []const u8, cmd: *const Command) !void {
    if (!lib.checks.validAbleton(filepath)) return error.Invalid;

    collectSet(alloc, reader, writer, filepath, cmd) catch |e| {
        try writer.print("{s}failed to collect set: {s}{s}\n", .{ Color.red.code(), Color.reset.code(), filepath });
        try writer.flush();
        return e;
    };
}
