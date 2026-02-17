const std = @import("std");
const print = std.debug.print;
const lib = @import("collect_and_save");

const red = "\x1b[31m";
const green = "\x1b[32m";
const reset = "\x1b[0m";

const Mode = enum { save, xml, check };

fn modeInfo(w: *std.Io.Writer) !void {
    _ = try w.print("invalid mode:\n", .{});
    const info = @typeInfo(Mode);

    inline for (info.@"enum".fields) |field| {
        _ = try w.print("\t{s}", .{field.name});
    }
    try w.flush();

    return;
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
            std.log.err("no args found", .{});
            return;
        },
        1 => return try modeInfo(&writer.interface),
        2 => {
            std.log.err("please provide a file", .{});
            return;
        },
        else => {},
    }

    const mode = std.meta.stringToEnum(Mode, std.mem.span(args[1])) orelse {
        try modeInfo(&writer.interface);
        return;
    };

    const paths = args[2..];
    for (paths) |path| {
        defer _ = arena.reset(.free_all);
        const filepath = std.mem.span(path);

        if (lib.isBackup(filepath)) {
            _ = try writer.interface.print("skipping backup: {s}\n", .{std.fs.path.basename(filepath)});
            try writer.interface.flush();
            continue;
        }

        switch (mode) {
            .xml => {
                var file = try std.fs.cwd().openFile(filepath, .{});
                defer file.close();
                try lib.gzip.writeXml(&file, &writer.interface);
            },
            .save => lib.collectAndSave(alloc, filepath, false) catch |e| {
                print("error reading: {any}\n", .{e});
                continue;
            },
            .check => try lib.collectAndSave(alloc, filepath, true),
        }
    }
}
