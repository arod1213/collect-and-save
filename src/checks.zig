const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const collect = @import("./collect.zig");

// <RelativePath Value="../../../ableton/beautiful guitar thing Project/Samples/Recorded/10-Audio 0005 [2024-02-03 124542].aif" />
pub fn fileExists(filepath: []const u8) bool {
    if (std.fs.path.isAbsolute(filepath)) {
        const source_dirname = std.fs.path.dirname(filepath) orelse "/";
        var source_dir = std.fs.openDirAbsolute(source_dirname, .{}) catch return false;
        defer source_dir.close();

        const filename = std.fs.path.basename(filepath);
        source_dir.access(filename, .{}) catch return false;
    } else {
        std.fs.cwd().access(filepath, .{}) catch return false;
    }
    return true;
}

pub fn validAbleton(filepath: []const u8) bool {
    const ext = std.fs.path.extension(filepath);
    return std.mem.eql(u8, ext, ".als");
}

pub fn isBackup(filepath: []const u8) bool {
    const parent = std.fs.path.dirname(filepath) orelse return false;
    const parent_stem = std.fs.path.basename(parent);
    return std.mem.eql(u8, parent_stem, "Backup");
}
