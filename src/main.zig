const std = @import("std");
const Allocator = std.mem.Allocator;
const print = std.debug.print;
const lib = @import("collect_and_save");
const zli = @import("zli");
const termios = @import("termios.zig");
const Color = lib.Color;

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

const Input = struct {
    cmd: Command,
    filepath: []const u8,
};

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
    termios.setup(stdin.handle) catch {
        std.log.err("failed to setup termios", .{});
    };

    const input = zli.parseOrdered(Input, std.os.argv) catch {
        _ = try writer.interface.print("{s}please provide a command and a file{s}\n", .{ Color.red.code(), Color.reset.code() });
        try writer.interface.flush();
        try commandInfo(&writer.interface);
        return;
    };

    // const paths = args[2..];
    // for (paths) |path| {
    // defer _ = arena.reset(.free_all);
    collectSet(alloc, &reader.interface, &writer.interface, input.filepath, &input.cmd) catch {};
    // }
}
