const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

pub const Color = @import("ascii.zig").Color;
pub const xml = @import("xml");

const lib = @import("lib/main.zig");
pub const collect = lib.collect;
pub const gzip = lib.gzip;
pub const checks = lib.checks;
pub const utils = lib.commands;

const Node = xml.types.Node;
const Doc = xml.types.Doc;

const ableton = lib.ableton;
const PathType = ableton.PathType;

pub const Command = enum { save, xml, check, info, safe };

const CollectFileConfig = struct {
    reader: *std.Io.Reader,
    writer: *std.Io.Writer,
    cmd: Command,
    session_dir: std.fs.Dir,
};

fn collectFile(alloc: Allocator, file: ableton.AbletonFile, config: CollectFileConfig) !void {
    const sample_path = file.file_path;
    switch (config.cmd) {
        .check => {
            const collectable = ableton.shouldCollect(alloc, config.session_dir, file.path_type, sample_path);
            if (!collectable) return error.FileAlreadyFound;
            const exists = checks.fileExists(sample_path);
            utils.writeFileInfo(sample_path, "would save", exists);
        },
        .save => {
            const collectable = ableton.shouldCollect(alloc, config.session_dir, file.path_type, sample_path);
            if (!collectable) return error.FileAlreadyFound;

            const prefix = "saved";
            utils.resolveFile(alloc, config.session_dir, sample_path) catch |e| {
                utils.writeFileInfo(sample_path, prefix, false);
                return e;
            };
            utils.writeFileInfo(sample_path, prefix, true);
        },
        .info => {
            try config.writer.print("{f}\n", .{file});
            try config.writer.flush();
        },
        .safe => {
            const collectable = ableton.shouldCollect(alloc, config.session_dir, file.path_type, sample_path);
            if (!collectable) return error.FileAlreadyFound;
            try utils.collectFileSafe(alloc, config.reader, config.writer, config.session_dir, file);
        },
        .xml => {},
    }
}

fn processFileRefs(comptime T: type, alloc: Allocator, head: Node, config: CollectFileConfig) !void {
    var map = try xml.getUniqueNodes(T, alloc, head, "FileRef", T.key);
    defer map.deinit();

    var count: usize = 0;
    for (map.values()) |f| {
        const ableton_file = f.asAbletonFile(alloc);
        collectFile(alloc, ableton_file, config) catch continue;
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
    defer std.fs.cwd().deleteFile(tmp_name) catch {};

    var doc = try Doc.init(tmp_name);
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
