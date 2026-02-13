const std = @import("std");
const Allocator = std.mem.Allocator;
const Dir = std.Io.Dir;

// ensure dir was opened with iterate = true
pub fn fileInDir(io: std.Io, alloc: Allocator, dir: std.Io.Dir, filename: []const u8) !bool {
    var iter = try dir.walk(alloc);
    defer iter.deinit();
    while (try iter.next(io)) |entry| {
        if (std.mem.eql(u8, @ptrCast(entry.basename), filename)) {
            return true;
        }
    }
    return false;
}

pub fn getSessionDir(io: std.Io, filepath: []const u8) !std.Io.Dir {
    const dirname = Dir.path.dirname(filepath) orelse ".";

    if (std.Io.Dir.path.isAbsolute(filepath)) {
        return Dir.openDirAbsolute(io, dirname, .{ .iterate = true });
    } else {
        return Dir.cwd().openDir(io, dirname, .{ .iterate = true });
    }
}

const FileExt = enum { wav, mp3, adv, amxd, mp4, m4a, aif };
pub fn collectFolder(filepath: []const u8) ![]const u8 {
    const ext = Dir.path.extension(filepath);
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
