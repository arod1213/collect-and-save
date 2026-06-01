const std = @import("std");
const builtin = @import("builtin");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const collect = @import("./collect.zig");
const Dir = std.Io.Dir;
pub const Color = @import("../ascii.zig").Color;

pub const gzip = @import("gzip.zig");
pub const checks = @import("./checks.zig");
pub const xml = @import("xml");

const Node = xml.types.Node;
const Doc = xml.types.Doc;

const ableton = @import("ableton.zig");
const PathType = ableton.PathType;

pub fn openFile(filepath: []const u8, flags: std.fs.File.OpenFlags) !std.fs.File {
    if (std.fs.path.isAbsolute(filepath)) {
        return try std.fs.openFileAbsolute(filepath, flags);
    } else {
        return try std.fs.cwd().openFile(filepath, flags);
    }
}

pub fn writeFileInfo(filepath: []const u8, prefix: []const u8, success: bool) void {
    const path = std.fs.path.basename(filepath);
    if (success) {
        print("\t{s}: {s}{s}{s}\n", .{ prefix, Color.green.code(), path, Color.reset.code() });
    } else {
        print("\t{s}: {s}{s}{s}\n", .{ "missing", Color.red.code(), path, Color.reset.code() });
    }
}

pub fn askToSave(reader: *std.Io.Reader, writer: *std.Io.Writer, filepath: []const u8) !bool {
    if (filepath.len == 0) return error.InvalidFileName; // skip invalid entries

    try writer.print("would you like to save {s}{s}{s}: [y\n]\n", .{ Color.blue.code(), filepath, Color.reset.code() });
    try writer.flush();
    const byte = try reader.takeByte();
    return byte == 'y';
}

pub fn collectFileSafe(io: std.Io, alloc: Allocator, reader: *std.Io.Reader, writer: *std.Io.Writer, session_dir: std.fs.Dir, f: ableton.AbletonFile) !void {
    const sample_path = f.file_path;
    if (sample_path.len == 0) return error.InvalidFileName; // skip invalid entries

    try writer.print("would you like to save {s}{s}{s}: [y\n]\n", .{ Color.blue.code(), sample_path, Color.reset.code() });
    try writer.flush();
    const byte = try reader.takeByte();
    if (byte == 'y') {
        resolveFile(io, alloc, session_dir, sample_path) catch |e| {
            writeFileInfo(sample_path, "saved", false);
            return e;
        };
        writeFileInfo(sample_path, "saved", true);
    } else {
        try writer.print("\tskipped\n", .{});
        try writer.flush();
    }
}

const VersionError = error{ UnknownVersion, UnsupportedVersion };
pub fn getAbletonVersion(alloc: Allocator, doc: *Doc) VersionError!ableton.AbletonVersion {
    const ableton_info = xml.parse.nodeToT(ableton.Header, alloc, doc.root.?) catch {
        print("Unsupported Ableton Version\n", .{});
        return VersionError.UnknownVersion;
    };
    return ableton_info.version() orelse {
        print("Unsupported Ableton Version: {s}\n", .{ableton_info.MinorVersion});
        return VersionError.UnsupportedVersion;
    };
}

pub fn writeGzipToTmp(io: std.Io, alloc: Allocator, tmp_name: []const u8, filepath: []const u8) !void {
    var file = Dir.cwd().openFile(io, filepath, .{}) catch |e| {
        std.log.err("could not find file {s}", .{filepath});
        return e;
    };
    defer file.close(io);

    var tmp_file = try Dir.cwd().createFile(io, tmp_name, .{ .truncate = true });
    defer tmp_file.close(io);

    var write_buffer: [4096]u8 = undefined;
    var writer = tmp_file.writer(io, &write_buffer);
    switch (builtin.target.os.tag) {
        .macos => try gzip.writeChunk(alloc, &file, &writer.interface),
        else => try gzip.writeXml(io, &file, &writer.interface),
    }
}

pub fn resolveFile(io: std.Io, alloc: Allocator, session_dir: Dir, filepath: []const u8) !void {
    const new_dir = try collect.collectFolder(filepath);

    try session_dir.createDirPath(io, new_dir);

    const filename = std.fs.path.basename(filepath);
    const new_path = try std.fs.path.join(alloc, &[_][]const u8{ new_dir, filename });
    defer alloc.free(new_path);

    if (std.fs.path.isAbsolute(filepath)) {
        const source_dirname = std.fs.path.dirname(filepath) orelse "/";
        var source_dir = try Dir.openDirAbsolute(io, source_dirname, .{});
        defer source_dir.close(io);

        try source_dir.copyFile(filename, session_dir, new_path, io, .{});
        return;
    } else {
        try Dir.cwd().copyFile(filepath, session_dir, new_path, io, .{});
    }
}
