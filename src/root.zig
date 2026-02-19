const std = @import("std");
const builtin = @import("builtin");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const collect = @import("./collect.zig");
pub const Color = @import("ascii.zig").Color;

pub const gzip = @import("gzip.zig");
pub const checks = @import("./checks.zig");
pub const xml = @import("xml");

const Node = xml.Node;
const Doc = xml.Doc;

const ableton = @import("ableton_doc.zig");
const Ableton11 = ableton.Ableton11;
const PathType = ableton.PathType;

fn processFileRefs(comptime T: type, alloc: Allocator, head: Node, session_dir: std.fs.Dir, dry_run: bool) !void {
    var map = try xml.getUniqueNodes(T, alloc, head, "FileRef", T.key);
    defer map.deinit();

    var count: usize = 0;
    const prefix = if (dry_run) "would save" else "saved";
    for (map.values()) |f| {
        const sample_path = f.filepath(alloc);
        if (!ableton.shouldCollect(alloc, session_dir, f.path_type(), sample_path)) continue;
        if (dry_run) {
            const exists = checks.fileExists(sample_path);
            writeFileInfo(sample_path, prefix, exists);
        } else {
            resolveFile(alloc, session_dir, sample_path) catch {
                writeFileInfo(sample_path, prefix, false);
                continue;
            };
            writeFileInfo(sample_path, prefix, true);
        }
        count += 1;
    }
    if (count == 0) {
        print("\tNo files to collect..\n", .{});
    }
}

pub fn collectAndSave(alloc: Allocator, filepath: []const u8, dry_run: bool) !void {
    var file = std.fs.cwd().openFile(filepath, .{}) catch |e| {
        std.log.err("could not find file {s}", .{filepath});
        return e;
    };
    defer file.close();

    const tmp_name = "./tmp_ableton_collect_and_save.xml";
    var tmp_file = try std.fs.cwd().createFile(tmp_name, .{ .truncate = true });
    defer {
        tmp_file.close();
        std.fs.cwd().deleteFile(tmp_name) catch {};
    }

    var write_buffer: [4096]u8 = undefined;
    var writer = tmp_file.writer(&write_buffer);
    switch (builtin.target.os.tag) {
        .macos => try gzip.writeChunk(alloc, &file, &writer.interface),
        else => try gzip.writeXml(&file, &writer.interface),
    }

    var doc = try xml.Doc.init(tmp_name);
    if (doc.root == null) return error.NoRoot;
    defer doc.deinit();

    const ableton_version = blk: {
        const ableton_info = xml.parse.nodeToT(ableton.Header, alloc, doc.root.?) catch {
            print("Unsupported Ableton Version\n", .{});
            return error.UnsupportedVersion;
        };
        break :blk ableton_info.version() orelse {
            print("Unsupported Ableton Version\n", .{});
            return error.UnsupportedVersion;
        };
    };

    var session_dir = try collect.getSessionDir(filepath);
    defer session_dir.close();

    print("Ableton {d} Session: {s}{s}{s}\n", .{ @intFromEnum(ableton_version), Color.yellow.code(), std.fs.path.basename(filepath), Color.reset.code() });

    switch (ableton_version) {
        .ten => {
            const K = ableton.Ableton10;
            var map = try xml.getUniqueNodes(K, alloc, doc.root.?, "FileRef", K.key);
            defer map.deinit();
            try processFileRefs(K, alloc, doc.root.?, session_dir, dry_run);
        },
        else => {
            const K = ableton.Ableton11;
            var map = try xml.getUniqueNodes(K, alloc, doc.root.?, "FileRef", K.key);
            defer map.deinit();
            try processFileRefs(K, alloc, doc.root.?, session_dir, dry_run);
        },
    }
}

pub fn collectInfo(alloc: Allocator, _: *std.Io.Writer, filepath: []const u8) !void {
    var file = try std.fs.cwd().openFile(filepath, .{});
    defer file.close();

    const xml_buffer = try gzip.unzipXml(alloc, &file);
    const doc = try xml.Doc.initFromBuffer(xml_buffer);
    if (doc.root == null) return error.NoRoot;

    // _ = blk: {
    //     const ableton_info = xml.parse.nodeToT(ableton.Header, alloc, doc.root.?) catch {
    //         print("Unsupported Ableton Version\n", .{});
    //         return error.UnsupportedVersion;
    //     };
    //     break :blk ableton_info.version() orelse {
    //         print("Unsupported Ableton Version\n", .{});
    //         return error.UnsupportedVersion;
    //     };
    //     };

    var map = try xml.getUniqueNodes(ableton.Ableton10, alloc, doc.root.?, "FileRef", ableton.Ableton10.key);
    defer map.deinit();

    var session_dir = try collect.getSessionDir(filepath);
    defer session_dir.close();

    print("Session: {s}{s}{s}\n", .{ Color.yellow.code(), std.fs.path.basename(filepath), Color.reset.code() });

    for (map.values()) |f| {
        print("{f}\n", .{f});
    }
}

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

fn writeFileInfo(filepath: []const u8, prefix: []const u8, success: bool) void {
    const path = std.fs.path.basename(filepath);
    if (success) {
        print("\t{s}: {s}{s}{s}\n", .{ prefix, Color.green.code(), path, Color.reset.code() });
    } else {
        print("\t{s}: {s}{s}{s}\n", .{ "missing", Color.red.code(), path, Color.reset.code() });
    }
}
