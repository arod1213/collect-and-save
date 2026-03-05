const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
pub const Color = @import("ascii.zig").Color;

const sqlite = @import("sqlite");
pub const database = @import("./commands/database.zig");

const lib = @import("lib/main.zig");
const commands = lib.commands;
const collect = lib.collect;
pub const gzip = lib.gzip;
pub const checks = lib.checks;
pub const xml = lib.xml;
// pub const utils = @import("root_utils.zig");

const Node = xml.types.Node;
const Doc = xml.types.Doc;

const ableton = lib.ableton;
const PathType = ableton.PathType;

pub const SaveCommand = enum { info, xml, check, save, safe };
const CollectFileConfig = struct {
    reader: *std.Io.Reader,
    writer: *std.Io.Writer,
    cmd: SaveCommand,
    session_dir: std.fs.Dir,
    db: *sqlite.Conn,
};

pub fn openFile(path: []const u8, flags: std.fs.File.OpenFlags) !std.fs.File {
    if (std.fs.path.isAbsolute(path)) {
        return try std.fs.openFileAbsolute(path, flags);
    }
    return try std.fs.cwd().openFile(path, flags);
}

fn collectFile(alloc: Allocator, file: ableton.AbletonFile, config: CollectFileConfig) !void {
    const sample_path = file.file_path;
    switch (config.cmd) {
        .check => {
            const collectable = ableton.shouldCollect(alloc, config.session_dir, file.path_type, sample_path);
            if (!collectable) return error.FileAlreadyFound;
            var exists = checks.fileExists(sample_path);
            if (!exists) {
                const match = try database.findMatch(alloc, config.db, file.file_name, file.file_size);
                if (match != null) {
                    exists = true;
                }
            }
            commands.writeFileInfo(sample_path, "would save", exists);
        },
        .save => {
            const collectable = ableton.shouldCollect(alloc, config.session_dir, file.path_type, sample_path);
            if (!collectable) return error.FileAlreadyFound;

            const prefix = "saved";
            commands.resolveFile(alloc, config.session_dir, sample_path) catch |e| {
                const match = try database.findMatch(alloc, config.db, file.file_name, file.file_size);
                if (match) |m| {
                    try commands.resolveFile(alloc, config.session_dir, m.full_path);
                } else {
                    commands.writeFileInfo(sample_path, prefix, false);
                    return e;
                }
            };
            commands.writeFileInfo(sample_path, prefix, true);
        },
        .info => {
            try config.writer.print("{f}\n", .{file});
            try config.writer.flush();
        },
        .safe => {
            const collectable = ableton.shouldCollect(alloc, config.session_dir, file.path_type, sample_path);
            if (!collectable) return error.FileAlreadyFound;
            try commands.collectFileSafe(alloc, config.reader, config.writer, config.session_dir, file);
        },
        .xml => {},
    }
}

fn processFileRefs(comptime T: type, alloc: Allocator, head: Node, config: CollectFileConfig) !void {
    var map = try xml.find.getNodesUnique(T, alloc, head, "FileRef", T.key);
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

pub fn collectAndSave(alloc: Allocator, conn: *sqlite.Conn, r: *std.Io.Reader, w: *std.Io.Writer, filepath: []const u8, cmd: SaveCommand) !void {
    const tmp_name = "./tmp_ableton_collect_and_save.xml";
    _ = try commands.writeGzipToTmp(alloc, tmp_name, filepath);
    defer std.fs.cwd().deleteFile(tmp_name) catch {};

    var doc = try Doc.init(tmp_name);
    if (doc.root == null) return error.NoRoot;
    defer doc.deinit();

    var session_dir = try collect.getSessionDir(filepath);
    defer session_dir.close();

    const ableton_version = try commands.getAbletonVersion(alloc, &doc);
    try w.print("Ableton {d} Session: {s}{s}{s}\n", .{ @intFromEnum(ableton_version), Color.yellow.code(), std.fs.path.basename(filepath), Color.reset.code() });
    try w.flush();

    const config = CollectFileConfig{
        .reader = r,
        .writer = w,
        .session_dir = session_dir,
        .cmd = cmd,
        .db = conn,
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
