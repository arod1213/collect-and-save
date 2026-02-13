const std = @import("std");
const Allocator = std.mem.Allocator;
const lib = @import("collect_and_save");

const Dir = std.Io.Dir;
const File = std.Io.File;
const Command = lib.Command;
const Color = lib.Color;

fn collectSet(io: std.Io, alloc: Allocator, writer: *std.Io.Writer, filepath: []const u8, cmd: *const Command) !void {
    if (!lib.checks.validAbleton(filepath)) {
        _ = try writer.print("{s}{s} is not a valid ableton file{s}\n", .{ Color.red.code(), Dir.path.basename(filepath), Color.reset.code() });
        try writer.flush();
        return;
    }

    if (lib.checks.isBackup(filepath)) {
        _ = try writer.print("skipping backup: {s}\n", .{Dir.path.basename(filepath)});
        try writer.flush();
        return;
    }

    switch (cmd.*) {
        .xml => {
            var file = try Dir.cwd().openFile(io, filepath, .{});
            defer file.close(io);
            try lib.gzip.writeXml(io, &file, writer);
        },
        .save, .check, .info => try lib.collectAndSave(io, alloc, filepath, cmd.*),
    }
}

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();

    var io = std.Io.Threaded.init(alloc, .{});
    defer io.deinit();

    var stdout = File.stdout();
    defer stdout.close(io.io());
    var buffer: [4096]u8 = undefined;
    var writer = stdout.writer(io.io(), &buffer);

    const args = try init.minimal.args.toSlice(alloc);
    switch (args.len) {
        0 => {
            _ = try writer.interface.print("{s}please provide a command and a file{s}\n", .{ Color.red.code(), Color.reset.code() });
            try writer.interface.flush();
            return;
        },
        1 => return try Command.showInfo(&writer.interface),
        2 => {
            _ = try writer.interface.print("{s}please provide a file{s}\n", .{ Color.red.code(), Color.reset.code() });
            try writer.interface.flush();
            return;
        },
        else => {},
    }

    const cmd = std.meta.stringToEnum(Command, args[1]) orelse {
        try Command.showInfo(&writer.interface);
        return;
    };

    const paths = args[2..];
    for (paths) |filepath| {
        defer _ = init.arena.reset(.free_all);
        collectSet(io.io(), alloc, &writer.interface, filepath, &cmd) catch continue;
    }
}
