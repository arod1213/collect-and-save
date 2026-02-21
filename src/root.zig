const std = @import("std");
const builtin = @import("builtin");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const collect = @import("./collect.zig");
pub const Color = @import("ascii.zig").Color;

pub const gzip = @import("gzip.zig");
pub const checks = @import("./checks.zig");
pub const xml = @import("xml");
pub const cli = @import("cli.zig");

const Node = xml.Node;
const Doc = xml.Doc;

const ableton = @import("ableton.zig");
const PathType = ableton.PathType;

pub const Command = enum { save, xml, check, info, safe };

fn collectFile(comptime T: type, alloc: Allocator, f: T, session_dir: std.fs.Dir, cmd: Command) !void {
    const sample_path = f.filepath(alloc);
    switch (cmd) {
        .check => {
            if (!ableton.shouldCollect(alloc, session_dir, f.pathType(), sample_path)) return error.FileAlreadyFound;
            const exists = checks.fileExists(sample_path);
            cli.writeFileInfo(sample_path, "would save", exists);
        },
        .save => {
            if (!ableton.shouldCollect(alloc, session_dir, f.pathType(), sample_path)) return error.FileAlreadyFound;
            const prefix = "saved";
            cli.resolveFile(alloc, session_dir, sample_path) catch |e| {
                cli.writeFileInfo(sample_path, prefix, false);
                return e;
            };
            cli.writeFileInfo(sample_path, prefix, true);
        },
        .info => print("{f}\n", .{f}),
        else => {},
    }
}

fn processFileRefs(comptime T: type, alloc: Allocator, head: Node, session_dir: std.fs.Dir, cmd: Command) !void {
    var map = try xml.getUniqueNodes(T, alloc, head, "FileRef", T.key);
    defer map.deinit();

    var count: usize = 0;
    for (map.values()) |f| {
        collectFile(T, alloc, f, session_dir, cmd) catch continue;
        count += 1;
    }
    if (count == 0) {
        print("\tNo files to collect..\n", .{});
    }
}

pub fn collectAndSave(alloc: Allocator, filepath: []const u8, cmd: Command) !void {
    const tmp_name = "./tmp_ableton_collect_and_save.xml";
    _ = try cli.writeGzipToTmp(alloc, tmp_name, filepath);

    var doc = try xml.Doc.init(tmp_name);
    if (doc.root == null) return error.NoRoot;
    defer doc.deinit();

    var session_dir = try collect.getSessionDir(filepath);
    defer session_dir.close();

    const ableton_version = try cli.getAbletonVersion(alloc, &doc);
    print("Ableton {d} Session: {s}{s}{s}\n", .{ @intFromEnum(ableton_version), Color.yellow.code(), std.fs.path.basename(filepath), Color.reset.code() });

    switch (ableton_version) {
        .nine, .ten => {
            const K = ableton.Ableton10;
            var map = try xml.getUniqueNodes(K, alloc, doc.root.?, "FileRef", K.key);
            defer map.deinit();
            try processFileRefs(K, alloc, doc.root.?, session_dir, cmd);
        },
        .eleven, .twelve => {
            const K = ableton.Ableton11;
            var map = try xml.getUniqueNodes(K, alloc, doc.root.?, "FileRef", K.key);
            defer map.deinit();
            try processFileRefs(K, alloc, doc.root.?, session_dir, cmd);
        },
    }
}
