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
pub const AbletonFile = ableton.AbletonFile;
const PathType = ableton.PathType;

pub const SaveCommand = enum(u8) {
    check = 0,
    save,
    safe,
    info,
    xml,
};
pub const CollectFileConfig = struct {
    reader: *std.Io.Reader,
    writer: *std.Io.Writer,
    cmd: SaveCommand,
    session_dir: std.Io.Dir,
    db: ?*sqlite.Conn,
};

/// TUI Input for Collect And Save
pub fn verifyAndCollect(io: std.Io, gpa: Allocator, config: *const CollectFileConfig, filepath: []const u8) !void {
    defer config.writer.flush() catch {};
    if (!lib.checks.validAbleton(filepath)) {
        _ = try config.writer.print("{s}{s} is not a valid ableton file{s}\n", .{
            Color.red.code(),
            std.fs.path.basename(filepath),
            Color.reset.code(),
        });
        return;
    }

    if (lib.checks.isBackup(filepath)) {
        _ = try config.writer.print("skipping backup: {s}\n", .{std.fs.path.basename(filepath)});
        return;
    }

    try collectSet(io, gpa, config, filepath);
}

pub fn openFile(io: std.Io, path: []const u8, flags: File.OpenFlags) !File {
    if (std.fs.path.isAbsolute(path)) {
        return try Dir.openFileAbsolute(io, path, flags);
    }
    return try Dir.cwd().openFile(io, path, flags);
}

pub const FileState = enum(u8) { missing, found, collected };
pub const FileRes = struct {
    status: FileState,
    path: []const u8,
};

pub fn findFile(io: std.Io, gpa: Allocator, file: ableton.AbletonFile, session_dir: std.Io.Dir, db: ?*const sqlite.Conn) !FileRes {
    const sample_path = file.file_path;
    const should_collect = ableton.shouldCollect(io, gpa, session_dir, file.path_type, sample_path);
    if (!should_collect) return .{ .path = sample_path, .status = .collected };
    var exists = checks.fileExists(io, sample_path);
    if (!exists and db != null) {
        const match = try database.findMatch(gpa, db.?, file.file_name, file.file_size);

        if (match) |m| {
            defer m.deinit(gpa);
            exists = true;
        }
    }
    return .{
        .status = if (exists) .found else .missing,
        .path = sample_path,
    };
}

pub fn collectSet(io: std.Io, gpa: Allocator, config: *const CollectFileConfig, filepath: []const u8) !void {
    const tmp_name = "./tmp_ableton_collect_and_save.xml";
    _ = try commands.writeGzipToTmp(io, gpa, tmp_name, filepath);
    defer Dir.cwd().deleteFile(io, tmp_name) catch {};

    var doc = try Doc.init(tmp_name);
    if (doc.root == null) return error.NoRoot;
    defer doc.deinit();

    const ableton_version = try commands.getAbletonVersion(gpa, &doc);
    try config.writer.print("Ableton {d} Session: {s}{s}{s}\n", .{ @intFromEnum(ableton_version), Color.yellow.code(), std.fs.path.basename(filepath), Color.reset.code() });
    try config.writer.flush();

    switch (ableton_version) {
        .nine, .ten => {
            const K = ableton.Ableton10;
            try processFileRefs(K, io, doc.root.?, config);
        },
        .eleven, .twelve => {
            const K = ableton.Ableton11;
            try processFileRefs(K, io, doc.root.?, config);
        },
    }
}

fn processFileRefs(comptime T: type, io: std.Io, head: Node, config: *const CollectFileConfig) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var map: std.StringHashMap(T) = try xml.find.getNodesUnique(T, gpa, head, "FileRef", T.key);
    defer map.deinit();

    var count: usize = 0;
    var iter = map.valueIterator();
    while (iter.next()) |f| {
        const ableton_file = f.asAbletonFile(gpa);
        collectFile(io, gpa, ableton_file, config) catch continue;
        count += 1;
    }
    if (count == 0) {
        try config.writer.print("\tNo files to collect..\n", .{});
        try config.writer.flush();
    }
}

/// TUI Input for Collect And Save
/// Config.cmd = .check --- Show per file if missing, or found match
/// Config.cmd = .save --- Save all found files
/// Config.cmd = .safe --- Prompt to save each file
pub fn collectFile(io: std.Io, gpa: Allocator, file: ableton.AbletonFile, config: *const CollectFileConfig) !void {
    const sample_path = file.file_path;
    switch (config.cmd) {
        .check => {
            const file_info = try findFile(io, gpa, file, config.session_dir, config.db);
            const valid = switch (file_info.status) {
                .missing => false,
                .collected => return {},
                .found => true,
            };
            commands.writeFileInfo(sample_path, "would save", valid);
        },
        .save => {
            const file_info = try findFile(io, gpa, file, config.session_dir, config.db);
            switch (file_info.status) {
                .missing => return error.MissingFile,
                .collected => return {},
                .found => try saveFile(io, gpa, file, config),
            }
            commands.writeFileInfo(sample_path, "saved", true);
        },
        .info => {
            try config.writer.print("{f}\n", .{file});
            try config.writer.flush();
        },
        .safe => {
            const file_info = try findFile(io, gpa, file, config.session_dir, config.db);
            switch (file_info.status) {
                .collected, .found => return {}, // dont prompt for found files
                .missing => {},
            }
            const save = try commands.askToSave(config.reader, config.writer, sample_path);
            if (save) {
                const succeed = saveFile(io, gpa, file, config) catch null;
                commands.writeFileInfo(sample_path, "saved", succeed != null);
            } else {
                try config.writer.print("\tskipped\n", .{});
                try config.writer.flush();
            }
        },
        .xml => {},
    }
    return {};
}

fn saveFile(io: std.Io, gpa: Allocator, file: ableton.AbletonFile, config: *const CollectFileConfig) !void {
    const sample_path = file.file_path;
    commands.resolveFile(io, gpa, config.session_dir, sample_path) catch |e| {
        if (config.db == null) return e;
        const match = try database.findMatch(gpa, config.db.?, file.file_name, file.file_size);
        if (match) |m| {
            defer m.deinit(gpa);
            try commands.resolveFile(io, gpa, config.session_dir, m.full_path);
        } else {
            return e;
        }
    };
    return {};
}
