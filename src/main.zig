const std = @import("std");
const Allocator = std.mem.Allocator;
const print = std.debug.print;
const lib = @import("collect_and_save");
const Color = lib.Color;

const Command = enum { save, xml, check, info };
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

fn collectSet(alloc: Allocator, writer: *std.Io.Writer, filepath: []const u8, cmd: *const Command) !void {
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
        .save => try lib.collectAndSave(alloc, filepath, false),
        .check => try lib.collectAndSave(alloc, filepath, true),
        .info => try lib.collectInfo(alloc, writer, filepath),
    }
}

// TODO: remove setAsCwd() calls as it break multiple lookups
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .verbose_log = false }){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const alloc = arena.allocator();

    var stdout = std.fs.File.stdout();
    defer stdout.close();
    var buffer: [4096]u8 = undefined;
    var writer = stdout.writer(&buffer);

    const args = std.os.argv;
    switch (args.len) {
        0 => {
            _ = try writer.interface.print("{s}please provide a command and a file{s}\n", .{ Color.red.code(), Color.reset.code() });
            try writer.interface.flush();
            return;
        },
        1 => return try commandInfo(&writer.interface),
        2 => {
            _ = try writer.interface.print("{s}please provide a file{s}\n", .{ Color.red.code(), Color.reset.code() });
            try writer.interface.flush();
            return;
        },
        else => {},
    }

    const cmd = std.meta.stringToEnum(Command, std.mem.span(args[1])) orelse {
        try commandInfo(&writer.interface);
        return;
    };

    const paths = args[2..];
    for (paths) |path| {
        defer _ = arena.reset(.free_all);
        const filepath = std.mem.span(path);
        collectSet(alloc, &writer.interface, filepath, &cmd) catch continue;
    }
}
