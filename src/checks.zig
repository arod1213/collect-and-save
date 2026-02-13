const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const collect = @import("./collect.zig");
const Dir = std.Io.Dir;

// <RelativePath Value="../../../ableton/beautiful guitar thing Project/Samples/Recorded/10-Audio 0005 [2024-02-03 124542].aif" />
pub fn fileExists(io: std.Io, filepath: []const u8) bool {
    if (Dir.path.isAbsolute(filepath)) {
        const source_dirname = Dir.path.dirname(filepath) orelse "/";
        var source_dir = Dir.openDirAbsolute(io, source_dirname, .{}) catch return false;
        defer source_dir.close(io);

        const filename = Dir.path.basename(filepath);
        source_dir.access(io, filename, .{}) catch return false;
    } else {
        Dir.cwd().access(io, filepath, .{}) catch return false;
    }
    return true;
}

pub fn validAbleton(filepath: []const u8) bool {
    const ext = Dir.path.extension(filepath);
    return std.mem.eql(u8, ext, ".als");
}

pub fn isBackup(filepath: []const u8) bool {
    const parent = Dir.path.dirname(filepath) orelse return false;
    const parent_stem = Dir.path.basename(parent);
    return std.mem.eql(u8, parent_stem, "Backup");
}
