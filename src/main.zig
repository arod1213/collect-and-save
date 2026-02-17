const std = @import("std");
const print = std.debug.print;
const lib = @import("collect_and_save");

const red = "\x1b[31m";
const green = "\x1b[32m";
const reset = "\x1b[0m";

const Mode = enum { save, xml };

// TODO: remove setAsCwd() calls as it break multiple lookups
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .verbose_log = false }){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const alloc = arena.allocator();

    const args = std.os.argv;
    if (args.len < 3) {
        std.log.err("please provide a file", .{});
        return;
    }

    const stdout = std.fs.File.stdout();
    var buffer: [4096]u8 = undefined;
    var writer = stdout.writer(&buffer);

    const mode = std.meta.stringToEnum(Mode, std.mem.span(args[1])) orelse {
        _ = try writer.interface.print("invalid mode:\n\t save | xml", .{});
        try writer.interface.flush();
        return;
    };

    const paths = args[2..];
    for (paths) |path| {
        defer {
            _ = arena.reset(.free_all);
        }
        const filepath = std.mem.span(path);
        switch (mode) {
            .xml => {
                var file = try std.fs.cwd().openFile(filepath, .{});
                defer file.close();
                try lib.gzip.writeXml(&file, &writer.interface);
            },
            .save => try lib.collectAndSave(alloc, filepath),
        }
    }
}
