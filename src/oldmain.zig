const std = @import("std");
const print = std.debug.print;
const collect_and_save = @import("collect_and_save");

const red = "\x1b[31m";
const green = "\x1b[32m";
const reset = "\x1b[0m";

fn getCwd(path: []const u8) !std.fs.Dir {
    if (std.fs.path.isAbsolute(path)) {
        const dir_path = std.fs.path.dirname(path) orelse return error.InvalidDir;
        return try std.fs.openDirAbsolute(dir_path, .{});
    } else {
        const dir_path = std.fs.path.dirname(path) orelse return error.InvalidDir;
        return try std.fs.cwd().openDir(dir_path, .{});
    }
}

fn collectFiles(file_path: []const u8) !void {
    const cwd = getCwd(file_path) catch |e| {
        std.log.err("fail {any}", .{e});
        return e;
    };
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
    print("{s}: {s}missing {d}{s} files \n", .{ file_name, red, missing_files.len, reset });

    var collected: usize = 0;
    for (missing_files) |name| {
        _ = collect_and_save.resolveFile(alloc, cwd, name) catch {
            continue;
        };
        print("\tsaved: {s}{s}{s}\n", .{ green, std.fs.path.basename(name), reset });
        collected += 1;
    }
    // print("collected {d} files\n", .{collected});
}

// TODO: remove setAsCwd() calls as it break multiple lookups
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .verbose_log = false }){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const alloc = arena.allocator();

    const filepath = "./proj 1/fig - may 15.als";

    var file = try std.fs.cwd().openFile(filepath, .{});
    try collect_and_save.collectAndSave(alloc, &file);

    // const args = std.os.argv;
    // if (args.len < 2) {
    //     std.log.err("please provide a file", .{});
    //     return;
    // }
    // const cwd = std.fs.cwd();
    // const paths = args[1..];
    // for (paths) |path| {
    //     try outputXML(std.mem.span(path));
    // _ = collectFiles(std.mem.span(path)) catch continue;
    // try cwd.setAsCwd();
    // print("\n", .{});
    // }
}

fn outputXML(path: []const u8) !void {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var gpa = std.heap.GeneralPurposeAllocator(.{ .verbose_log = false }){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const alloc = arena.allocator();

    var resolver = try collect_and_save.Resolver.init(alloc, path, &file);

    const stdout = std.fs.File.stdout();
    var buffer: [4096]u8 = undefined;
    var writer = stdout.writer(&buffer);
    while (true) {
        const text = resolver.readGzip() catch |e| {
            switch (e) {
                error.EOF => break,
                else => return e,
            }
        };
        _ = try writer.interface.write(text);
        try writer.interface.flush();
    }
}
