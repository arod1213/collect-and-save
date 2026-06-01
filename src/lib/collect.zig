const std = @import("std");
const Dir = std.Io.Dir;
const Allocator = std.mem.Allocator;

// ensure dir was opened with iterate = true
pub fn fileInDir(io: std.Io, alloc: Allocator, dir: Dir, filename: []const u8) !bool {
    var iter = try dir.walk(alloc);
    defer iter.deinit();
    while (try iter.next(io)) |entry| {
        if (std.mem.eql(u8, @ptrCast(entry.basename), filename)) {
            return true;
        }
    }
    return false;
}

pub fn getSessionDir(io: std.Io, filepath: []const u8) !Dir {
    const dirname = std.fs.path.dirname(filepath) orelse ".";

    if (std.fs.path.isAbsolute(filepath)) {
        return Dir.openDirAbsolute(io, dirname, .{ .iterate = true });
    } else {
        return Dir.cwd().openDir(io, dirname, .{ .iterate = true });
    }
}

pub const FileExt = enum {
    // audio
    wav,
    mp3,
    flac,
    ogg,
    mp4,
    m4a,
    aif,
    // presets
    adv,
    amxd,
    adg,
};
pub fn validExtension(filepath: []const u8) bool {
    const ext = std.fs.path.extension(filepath);
    if (ext.len < 2) return false;

    const stem = ext[1..];

    _ = std.meta.stringToEnum(FileExt, stem) orelse return false;
    return true;
}

pub fn collectFolder(filepath: []const u8) ![]const u8 {
    const ext = std.fs.path.extension(filepath);
    if (ext.len < 2) return error.InvalidExtension;

    const stem = ext[1..];

    const ext_type = std.meta.stringToEnum(FileExt, stem) orelse return error.UnsupportedExtension;
    return switch (ext_type) {
        .wav,
        .mp3,
        .mp4,
        .m4a,
        .aif,
        .ogg,
        .flac,
        => "Samples/Collected",
        .adv => "Presets/Audio Effects",
        .adg => "Preset/Audio Effects/Audio Effect Rack",
        .amxd => "Presets/Audio Effects/Max Audio Effect",
    };
}
