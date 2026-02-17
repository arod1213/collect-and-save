const std = @import("std");
const print = std.debug.print;
const lib = @import("collect_and_save");

const red = "\x1b[31m";
const green = "\x1b[32m";
const reset = "\x1b[0m";

// TODO: remove setAsCwd() calls as it break multiple lookups
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .verbose_log = false }){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const alloc = arena.allocator();

    const args = std.os.argv;
    if (args.len < 2) {
        std.log.err("please provide a file", .{});
        return;
    }
    const paths = args[1..];
    for (paths) |path| {
        defer {
            _ = arena.reset(.free_all);
        }
        try lib.collectAndSave(alloc, std.mem.span(path));
    }
    // try cwd.setAsCwd();
    // print("\n", .{});
    // const filepath = "./proj 3/Untitled.2.als";
    // try lib.collectAndSave(alloc, filepath);
}
