const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const collect = @import("./collect.zig");
pub const checks = @import("./checks.zig");

pub const gzip = @import("gzip.zig");

pub const xml = @import("xml");

const Node = xml.Node;
const Doc = xml.Doc;
const Color = @import("ascii.zig").Color;

const ableton = @import("ableton_doc.zig");

const FileInfo = ableton.FileInfo;
const PathType = ableton.PathType;

fn resolveFile(alloc: Allocator, session_dir: std.fs.Dir, filepath: []const u8) !void {
    const new_dir = try collect.collectFolder(filepath);

    try session_dir.makePath(new_dir);

    const filename = std.fs.path.basename(filepath);
    const new_path = try std.fs.path.join(alloc, &[_][]const u8{ new_dir, filename });
    defer alloc.free(new_path);

    if (std.fs.path.isAbsolute(filepath)) {
        const source_dirname = std.fs.path.dirname(filepath) orelse "/";
        var source_dir = try std.fs.openDirAbsolute(source_dirname, .{});
        defer source_dir.close();

        try source_dir.copyFile(filename, session_dir, new_path, .{});
        return;
    } else {
        try std.fs.cwd().copyFile(filepath, session_dir, new_path, .{});
    }
}

fn writeFileInfo(f: *const FileInfo, prefix: []const u8, success: bool) void {
    if (success) {
        print("\t{s}: {s}{s}{s}\n", .{ prefix, Color.green.code(), std.fs.path.basename(f.Path), Color.reset.code() });
    } else {
        print("\t{s}: {s}{s}{s}\n", .{ "missing", Color.red.code(), std.fs.path.basename(f.Path), Color.reset.code() });
    }
}

pub fn collectAndSave(alloc: Allocator, filepath: []const u8, dry_run: bool) !void {
    var file = try std.fs.cwd().openFile(filepath, .{});
    defer file.close();

    // TODO: look into real tmp directories
    const tmp_name = "./tmp_ableton_collect_and_save.xml";
    var tmp_file = try std.fs.cwd().createFile(tmp_name, .{ .truncate = true });
    defer {
        tmp_file.close();
        std.fs.cwd().deleteFile(tmp_name) catch {};
    }
    var write_buffer: [4096]u8 = undefined;
    var writer = tmp_file.writer(&write_buffer);
    try gzip.writeChunk(alloc, &file, &writer.interface);

    var doc = try xml.Doc.init(tmp_name);
    if (doc.root == null) return error.NoRoot;
    defer doc.deinit();

    var map = try xml.getUniqueNodes(FileInfo, alloc, doc.root.?, "FileRef", FileInfo.key);
    defer map.deinit();

    var session_dir = try collect.getSessionDir(filepath);
    defer session_dir.close();

    print("Session: {s}{s}{s}\n", .{ Color.yellow.code(), std.fs.path.basename(filepath), Color.reset.code() });

    var count: usize = 0;
    const prefix = if (dry_run) "would save" else "saved";
    for (map.values()) |f| {
        if (!f.shouldCollect(alloc, session_dir)) continue;

        if (dry_run) {
            const exists = checks.fileExists(f.Path);
            writeFileInfo(&f, prefix, exists);
        } else {
            resolveFile(alloc, session_dir, f.Path) catch {
                writeFileInfo(&f, prefix, false);
                continue;
            };
            writeFileInfo(&f, prefix, true);
        }
        count += 1;
    }
    if (count == 0) {
        print("\tNo files to collect..\n", .{});
    }
}

pub fn collectInfo(alloc: Allocator, _: *std.Io.Writer, filepath: []const u8) !void {
    var file = try std.fs.cwd().openFile(filepath, .{});
    defer file.close();

    const xml_buffer = try gzip.unzipXml(alloc, &file);
    const doc = try xml.Doc.initFromBuffer(xml_buffer);
    if (doc.root == null) return error.NoRoot;

    var map = try xml.getUniqueNodes(FileInfo, alloc, doc.root.?, "FileRef", FileInfo.key);
    defer map.deinit();

    var session_dir = try collect.getSessionDir(filepath);
    defer session_dir.close();

    print("Session: {s}{s}{s}\n", .{ Color.yellow.code(), std.fs.path.basename(filepath), Color.reset.code() });

    var count: usize = 0;
    for (map.values()) |f| {
        if (!f.shouldCollect(alloc, session_dir)) continue;

        if (!checks.fileExists(f.Path)) {
            writeFileInfo(&f, "", false);
            continue;
        }
        writeFileInfo(&f, "would save", true);
        count += 1;
    }
    if (count == 0) {
        print("\tNo files to collect..\n", .{});
    }
}
