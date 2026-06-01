const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Dir = std.Io.Dir;
const File = std.Io.File;
pub const Color = @import("ascii.zig").Color;

const sqlite = @import("sqlite");
pub const database = @import("./commands/database.zig");

const lib = @import("lib/main.zig");
const commands = lib.commands;
pub const collect = lib.collect;
pub const gzip = lib.gzip;
pub const checks = lib.checks;
pub const xml = lib.xml;
// pub const utils = @import("root_utils.zig");

const Node = xml.types.Node;
const Doc = xml.types.Doc;

const ableton = lib.ableton;
const PathType = ableton.PathType;

pub const SaveCommand = enum { info, xml, check, save, safe };
pub const CollectFileConfig = struct {
    reader: *std.Io.Reader,
    writer: *std.Io.Writer,
    cmd: SaveCommand,
    session_dir: std.Io.Dir,
    db: *sqlite.Conn,
};

/// TUI Input for Collect And Save
/// Config.cmd = .check --- Show per file if missing, or found match
/// Config.cmd = .save --- Save all found files
/// Config.cmd = .safe --- Prompt to save each file
pub fn collectFile(io: std.Io, alloc: Allocator, file: ableton.AbletonFile, config: CollectFileConfig) !void {
    const sample_path = file.file_path;
    switch (config.cmd) {
        .check => {
            const file_info = try findFile(io, alloc, file, config);
            const valid = switch (file_info.status) {
                .missing => false,
                .collected => return {},
                .found => true,
            };
            commands.writeFileInfo(sample_path, "would save", valid);
        },
        .save => {
            const file_info = try findFile(io, alloc, file, config);
            switch (file_info.status) {
                .missing => return error.MissingFile,
                .collected => return {},
                .found => try saveFile(io, alloc, file, config),
            }
            commands.writeFileInfo(sample_path, "saved", true);
        },
        .info => {
            try config.writer.print("{f}\n", .{file});
            try config.writer.flush();
        },
        .safe => {
            const collectable = ableton.shouldCollect(io, alloc, config.session_dir, file.path_type, sample_path);
            if (!collectable) return error.FileAlreadyFound;
            const save = try commands.askToSave(config.reader, config.writer, sample_path);
            if (save) {
                try saveFile(io, alloc, file, config);
                commands.writeFileInfo(sample_path, "saved", true);
            } else {
                try config.writer.print("\tskipped\n", .{});
                try config.writer.flush();
            }
        },
        .xml => {},
    }
    return {};
}

pub fn openFile(io: std.Io, path: []const u8, flags: File.OpenFlags) !File {
    if (std.fs.path.isAbsolute(path)) {
        return try Dir.openFileAbsolute(io, path, flags);
    }
    return try Dir.cwd().openFile(io, path, flags);
}

pub const FileState = enum { missing, found, collected };
pub const FileRes = struct {
    status: FileState,
    path: []const u8,
};

fn findFile(io: std.Io, alloc: Allocator, file: ableton.AbletonFile, config: CollectFileConfig) !FileRes {
    const sample_path = file.file_path;
    const collectable = ableton.shouldCollect(io, alloc, config.session_dir, file.path_type, sample_path);
    if (!collectable) return .{ .path = sample_path, .status = .collected };
    var exists = checks.fileExists(io, sample_path);
    if (!exists) {
        const match = try database.findMatch(alloc, config.db, file.file_name, file.file_size);
        if (match != null) {
            exists = true;
        }
    }
    return .{
        .status = if (exists) .found else .missing,
        .path = sample_path,
    };
}

fn saveFile(io: std.Io, alloc: Allocator, file: ableton.AbletonFile, config: CollectFileConfig) !void {
    const sample_path = file.file_path;
    commands.resolveFile(io, alloc, config.session_dir, sample_path) catch |e| {
        const match = try database.findMatch(alloc, config.db, file.file_name, file.file_size);
        if (match) |m| {
            try commands.resolveFile(io, alloc, config.session_dir, m.full_path);
        } else {
            return e;
        }
    };
    return {};
}

fn processFileRefs(comptime T: type, io: std.Io, alloc: Allocator, head: Node, config: CollectFileConfig) !void {
    var map: std.StringHashMap(T) = try xml.find.getNodesUnique(T, alloc, head, "FileRef", T.key);
    defer map.deinit();

    var count: usize = 0;
    var iter = map.valueIterator();
    while (iter.next()) |f| {
        const ableton_file = f.asAbletonFile(alloc);
        collectFile(io, alloc, ableton_file, config) catch continue;
        count += 1;
    }
    if (count == 0) {
        try config.writer.print("\tNo files to collect..\n", .{});
        try config.writer.flush();
    }
}

pub fn collectAndSave(io: std.Io, alloc: Allocator, config: CollectFileConfig, filepath: []const u8) !void {
    const tmp_name = "./tmp_ableton_collect_and_save.xml";
    _ = try commands.writeGzipToTmp(io, alloc, tmp_name, filepath);
    defer Dir.cwd().deleteFile(io, tmp_name) catch {};

    var doc = try Doc.init(tmp_name);
    if (doc.root == null) return error.NoRoot;
    defer doc.deinit();

    const ableton_version = try commands.getAbletonVersion(alloc, &doc);
    try config.writer.print("Ableton {d} Session: {s}{s}{s}\n", .{ @intFromEnum(ableton_version), Color.yellow.code(), std.fs.path.basename(filepath), Color.reset.code() });
    try config.writer.flush();

    switch (ableton_version) {
        .nine, .ten => {
            const K = ableton.Ableton10;
            try processFileRefs(K, io, alloc, doc.root.?, config);
        },
        .eleven, .twelve => {
            const K = ableton.Ableton11;
            try processFileRefs(K, io, alloc, doc.root.?, config);
        },
    }
}
