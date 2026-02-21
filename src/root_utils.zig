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

const ableton = @import("ableton.zig");
const PathType = ableton.PathType;

pub fn writeFileInfo(filepath: []const u8, prefix: []const u8, success: bool) void {
    const path = std.fs.path.basename(filepath);
    if (success) {
        print("\t{s}: {s}{s}{s}\n", .{ prefix, Color.green.code(), path, Color.reset.code() });
    } else {
        print("\t{s}: {s}{s}{s}\n", .{ "missing", Color.red.code(), path, Color.reset.code() });
    }
}

pub fn collectFileSafe(comptime T: type, alloc: Allocator, reader: *std.Io.Reader, writer: *std.Io.Writer, session_dir: std.fs.Dir, f: T) !void {
    const sample_path = f.filepath(alloc);
    if (!ableton.shouldCollect(alloc, session_dir, f.pathType(), sample_path)) return error.Uncollectable;
    if (sample_path.len == 0) return error.InvalidFileName; // skip invalid entries

    try writer.print("would you like to save {s}{s}{s}: [y\n]\n", .{ Color.blue.code(), sample_path, Color.reset.code() });
    try writer.flush();
    const byte = try reader.takeByte();
    if (byte == 'y') {
        resolveFile(alloc, session_dir, sample_path) catch |e| {
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
pub fn getAbletonVersion(alloc: Allocator, doc: *xml.Doc) VersionError!ableton.AbletonVersion {
    const ableton_info = xml.parse.nodeToT(ableton.Header, alloc, doc.root.?) catch {
        print("Unsupported Ableton Version\n", .{});
        return VersionError.UnknownVersion;
    };
    return ableton_info.version() orelse {
        print("Unsupported Ableton Version: {s}\n", .{ableton_info.MinorVersion});
        return VersionError.UnsupportedVersion;
    };
}

pub fn writeGzipToTmp(alloc: Allocator, tmp_name: []const u8, filepath: []const u8) !void {
    var file = std.fs.cwd().openFile(filepath, .{}) catch |e| {
        std.log.err("could not find file {s}", .{filepath});
        return e;
    };
    defer file.close();

    var tmp_file = try std.fs.cwd().createFile(tmp_name, .{ .truncate = true });
    defer tmp_file.close();

    var write_buffer: [4096]u8 = undefined;
    var writer = tmp_file.writer(&write_buffer);
    switch (builtin.target.os.tag) {
        .macos => try gzip.writeChunk(alloc, &file, &writer.interface),
        else => try gzip.writeXml(&file, &writer.interface),
    }
}

pub fn resolveFile(alloc: Allocator, session_dir: std.fs.Dir, filepath: []const u8) !void {
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
