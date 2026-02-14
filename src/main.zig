const std = @import("std");
const print = std.debug.print;
const collect_and_save = @import("collect_and_save");

fn collectFiles(file_path: []const u8) !void {
    const session_dir = std.fs.path.dirname(file_path) orelse return error.InvalidDir;
    const cwd = try std.fs.cwd().openDir(session_dir, .{});
    try cwd.setAsCwd();
    const file_name = std.fs.path.basename(file_path);

    // const file_path = "./danny.als";
    var file = try std.fs.cwd().openFile(file_name, .{});
    defer file.close();

    var gpa = std.heap.GeneralPurposeAllocator(.{ .verbose_log = false }){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const alloc = arena.allocator();

    var resolver = try collect_and_save.Resolver.init(alloc, file_name, &file);
    const missing_files = try resolver.getMissingFiles(alloc);
    print("{s}: missing {d} files \n", .{ file_name, missing_files.len });

    var collected: usize = 0;
    for (missing_files) |name| {
        _ = collect_and_save.resolveFile(alloc, cwd, name) catch {
            continue;
        };
        collected += 1;
    }
    print("collected {d} files\n", .{collected});
}

pub fn main() !void {
    const args = std.os.argv;
    if (args.len < 2) {
        std.log.err("please provide a file", .{});
        return;
    }
    const cwd = std.fs.cwd();
    const paths = args[1..];
    for (paths) |path| {
        _ = collectFiles(std.mem.span(path)) catch continue;
        try cwd.setAsCwd();
    }
}

fn copyFile() !void {
    const a = "/home/arod/Documents/Github/collect_and_save/ableton/Samples/Recorded/scratch vox 0001 [2026-02-12 150545]-1.wav";
    const b = "/home/arod/Documents/Github/collect_and_save/ableton/CopiedThatShit/scratch vox 0002 [2026-02-12 161715].wav";
    try std.fs.copyFileAbsolute(a, b, .{});
}
