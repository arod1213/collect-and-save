const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const collect = @import("./collect.zig");

const Color = enum {
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    reset,

    pub fn code(self: Color) []const u8 {
        return switch (self) {
            .red => "\x1b[31m",
            .green => "\x1b[32m",
            .yellow => "\x1b[33m",
            .blue => "\x1b[34m",
            .magenta => "\x1b[35m",
            .cyan => "\x1b[36m",
            .white => "\x1b[37m",
            .reset => "\x1b[0m",
        };
    }
};

pub const gzip = @import("gzip.zig");

pub const xml = @import("xml");

const Node = xml.Node;
const Doc = xml.Doc;

const ableton = @import("ableton_doc.zig");

const FileInfo = ableton.FileInfo;
const PathType = ableton.PathType;

fn transform(x: Node) !FileInfo {
    return try xml.parseNodeToT(FileInfo, &x, "Value");
}

fn getSessionDir(filepath: []const u8) !std.fs.Dir {
    const dirname = std.fs.path.dirname(filepath) orelse ".";

    if (std.fs.path.isAbsolute(filepath)) {
        return std.fs.openDirAbsolute(dirname, .{ .iterate = true });
    } else {
        return std.fs.cwd().openDir(dirname, .{ .iterate = true });
    }
}

const FileExt = enum { wav, mp3, adv, amxd, mp4, m4a, aif };
fn collectFolder(filepath: []const u8) ![]const u8 {
    const ext = std.fs.path.extension(filepath);
    if (ext.len < 2) return error.InvalidExtension;

    const stem = ext[1..];

    const ext_type = std.meta.stringToEnum(FileExt, stem) orelse return error.UnsupportedExtension;
    return switch (ext_type) {
        .wav,
        .mp3,
        .mp4,
        .m4a,
        .aif,
        => "Samples/Collected",
        .adv => "Presets/Audio Effects",
        .amxd => "Presets/Audio Effects/Max Audio Effect",
    };
}

fn resolveFile(alloc: Allocator, session_dir: std.fs.Dir, filepath: []const u8) !void {
    const new_dir = try collectFolder(filepath);

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
        try std.fs.cwd().copyFile(filename, session_dir, new_path, .{});
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

    const xml_buffer = try gzip.unzipXml(alloc, &file);
    const doc = try xml.Doc.initFromBuffer(xml_buffer);
    if (doc.root == null) return error.NoRoot;

    const files = try xml.nodesByName(FileInfo, alloc, doc.root.?, "FileRef", transform);

    var map = std.StringArrayHashMap(FileInfo).init(alloc);
    defer map.deinit();

    const session_dir = try getSessionDir(filepath);
    // DEDUP
    for (files) |f| {
        if (!f.shouldCollect(alloc, session_dir)) continue;

        const res = try map.getOrPut(f.RelativePath);
        if (res.found_existing) {
            continue;
        }
        res.value_ptr.* = f;
    }

    print("Session: {s}{s}{s}\n", .{ Color.yellow.code(), std.fs.path.basename(filepath), Color.reset.code() });

    var count: usize = 0;
    const prefix = if (dry_run) "would save" else "saved";
    for (map.values()) |f| {
        if (!dry_run) {
            resolveFile(alloc, session_dir, f.Path) catch {
                writeFileInfo(&f, prefix, false);
                continue;
            };
        }
        writeFileInfo(&f, prefix, true);
        count += 1;
    }
    if (count == 0) {
        print("\tNo files to collect..", .{});
    }
}
