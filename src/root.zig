const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const collect = @import("./collect.zig");
pub const Color = @import("ascii.zig").Color;

pub const gzip = @import("gzip.zig");
pub const checks = @import("./checks.zig");
pub const xml = @import("xml");
pub const utils = @import("root_utils.zig");

const Node = xml.Node;
const Doc = xml.Doc;

const ableton = @import("ableton.zig");
const PathType = ableton.PathType;

pub const Command = enum { save, xml, check, info, safe };

const CollectFileConfig = struct {
    reader: *std.Io.Reader,
    writer: *std.Io.Writer,
    cmd: Command,
    session_dir: std.fs.Dir,
};

fn collectFile(comptime T: type, alloc: Allocator, f: T, config: CollectFileConfig) !void {
    const sample_path = f.filepath(alloc);
    switch (config.cmd) {
        .check => {
            const collectable = ableton.shouldCollect(alloc, config.session_dir, f.pathType(), sample_path);
            if (!collectable) return error.FileAlreadyFound;
            const exists = checks.fileExists(sample_path);
            utils.writeFileInfo(sample_path, "would save", exists);
        },
        .save => {
            const collectable = ableton.shouldCollect(alloc, config.session_dir, f.pathType(), sample_path);
            if (!collectable) return error.FileAlreadyFound;

            const prefix = "saved";
            utils.resolveFile(alloc, config.session_dir, sample_path) catch |e| {
                utils.writeFileInfo(sample_path, prefix, false);
                return e;
            };
            utils.writeFileInfo(sample_path, prefix, true);
        },
        .info => {
            try config.writer.print("{f}\n", .{f});
            try config.writer.flush();
        },
        .safe => {
            const collectable = ableton.shouldCollect(alloc, config.session_dir, f.pathType(), sample_path);
            if (!collectable) return error.FileAlreadyFound;
            try utils.collectFileSafe(T, alloc, config.reader, config.writer, config.session_dir, f);
        },
        .xml => {},
    }
}

fn processFileRefs(comptime T: type, alloc: Allocator, head: Node, config: CollectFileConfig) !void {
    var map = try xml.getUniqueNodes(T, alloc, head, "FileRef", T.key);
    defer map.deinit();

    var count: usize = 0;
    for (map.values()) |f| {
        collectFile(T, alloc, f, config) catch continue;
        count += 1;
    }
    if (count == 0) {
        try config.writer.print("\tNo files to collect..\n", .{});
        try config.writer.flush();
    }
}

pub fn collectAndSave(alloc: Allocator, reader: *std.Io.Reader, writer: *std.Io.Writer, filepath: []const u8, cmd: Command) !void {
    const tmp_name = "./tmp_ableton_collect_and_save.xml";
    _ = try utils.writeGzipToTmp(alloc, tmp_name, filepath);

    var doc = try xml.Doc.init(tmp_name);
    if (doc.root == null) return error.NoRoot;
    defer doc.deinit();

    var session_dir = try collect.getSessionDir(filepath);
    defer session_dir.close();

    const ableton_version = try utils.getAbletonVersion(alloc, &doc);
    try writer.print("Ableton {d} Session: {s}{s}{s}\n", .{ @intFromEnum(ableton_version), Color.yellow.code(), std.fs.path.basename(filepath), Color.reset.code() });
    try writer.flush();

    const config = CollectFileConfig{
        .reader = reader,
        .writer = writer,
        .session_dir = session_dir,
        .cmd = cmd,
    };
    switch (ableton_version) {
        .nine, .ten => {
            const K = ableton.Ableton10;
            try processFileRefs(K, alloc, doc.root.?, config);
        },
        .eleven, .twelve => {
            const K = ableton.Ableton11;
            try processFileRefs(K, alloc, doc.root.?, config);
        },
    }
}
